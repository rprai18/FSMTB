# Step-by-Step Implementation Guide: Account Status Splitting

This guide provides detailed steps to split Account Status into three separate statuses.

---

## 🔍 STEP 1: Discovery and Analysis (30-60 minutes)

### Step 1.1: Verify Current Status Field Logic
**Where to Look:**
- Go to: **Setup → Object Manager → Account → Fields & Relationships → Status**
- Check if Status is a formula field or standard field
- **Document the formula logic** (if it's a formula field)
- **Note down** all possible values currently used

**What to Document:**
- Current Status field API name: `Status__c` or `Status`?
- Is it a formula field? If yes, what's the formula?
- What values does it currently contain?
- Which values indicate membership status? (Active, Lapsed, etc.)
- Which values indicate registration status? (Provisional, Registered, etc.)
- Which values indicate action status? (Under Review, Restricted, etc.)

### Step 1.2: Verify Survey Field
**Where to Look:**
- Go to: **Setup → Object Manager → Account → Fields & Relationships**
- Search for survey-related fields

**What to Find:**
- Field API name that tracks survey count (e.g., `Survey_Total_Happy__c`)
- Current field type (Number, Formula, Roll-Up Summary)
- Current values in existing accounts

**If field doesn't exist:**
- You'll need to create it or identify the correct field name
- Ask stakeholders: "What field tracks the number of surveys/happy responses?"

### Step 1.3: Review Membership__c Object
**Where to Look:**
- Go to: **Setup → Object Manager → Membership__c**
- Review fields: `Is_Current__c`, `Expiration_Date__c`, `Start_Date__c`, `Account__c`

**What to Understand:**
- How membership status is currently determined
- What makes a membership "Active" vs "Expired" vs "Lapsed"
- Grace period for membership renewal (if any)

### Step 1.4: Review CE_Action__c Object
**Where to Look:**
- Go to: **Setup → Object Manager → CE_Action__c → Fields & Relationships → Action__c**
- Review picklist values

**What to Document:**
- Current picklist values for Action__c
- Which ones contain "Provisional" that need to be removed:
  - `Provisional`
  - `Provisional & Restricted`
  - `Provisional & Under Review`
  - `Provisional & Internal Investigation`

---

## 📋 STEP 2: Create Account Fields (30-60 minutes)

### Step 2.1: Create Membership_Status__c Field
**Action:**
1. Go to: **Setup → Object Manager → Account → Fields & Relationships**
2. Click **New**
3. Select **Picklist** → Click **Next**
4. Fill in:
   - **Field Label**: `Membership Status`
   - **Field Name**: `Membership_Status` (API name will be `Membership_Status__c`)
   - Click **Next**
5. **Enter Values** (one per line):
   ```
   Active
   Lapsed
   Inactive
   Expired
   Renewal
   ```
6. Click **Next**
7. Select **Make this field required** = NO (unchecked)
8. Select **Default Value** = `Active`
9. Click **Next**
10. Select profiles that should have access (usually all)
11. Click **Save**

### Step 2.2: Create Registration_Status__c Field
**Action:**
1. Go to: **Setup → Object Manager → Account → Fields & Relationships**
2. Click **New**
3. Select **Picklist** → Click **Next**
4. Fill in:
   - **Field Label**: `Registration Status`
   - **Field Name**: `Registration_Status` (API name will be `Registration_Status__c`)
   - Click **Next**
5. **Enter Values** (one per line):
   ```
   Provisional
   Registered
   ```
6. Click **Next**
7. Select **Make this field required** = NO (unchecked)
8. Select **Default Value** = `Provisional`
9. Click **Next**
10. Select profiles that should have access (usually all)
11. Click **Save**

### Step 2.3: Create Registration_Status_Date__c Field
**Action:**
1. Go to: **Setup → Object Manager → Account → Fields & Relationships**
2. Click **New**
3. Select **Date** → Click **Next**
4. Fill in:
   - **Field Label**: `Registration Status Date`
   - **Field Name**: `Registration_Status_Date` (API name will be `Registration_Status_Date__c`)
   - Click **Next**
5. Select **Make this field required** = NO (unchecked)
6. Click **Next**
7. Select profiles that should have access (usually all)
8. Click **Save**

### Step 2.4: Create Registration_Status_Flag__c Field
**Action:**
1. Go to: **Setup → Object Manager → Account → Fields & Relationships**
2. Click **New**
3. Select **Checkbox** → Click **Next**
4. Fill in:
   - **Field Label**: `Registration Status Flag`
   - **Field Name**: `Registration_Status_Flag` (API name will be `Registration_Status_Flag__c`)
   - **Default Value** = Unchecked (false)
   - Click **Next**
5. Select profiles that should have access (usually all)
6. Click **Save**

### Step 2.5: Verify/Update Current_Active_Action_Status__c Field
**Action:**
1. Go to: **Setup → Object Manager → Account → Fields & Relationships → Current_Active_Action_Status__c**
2. **Review picklist values** - ensure it only contains:
   - Under Review
   - Restricted
   - Internal Investigation
   - Revoked
3. **Remove** if present (will remove in later step):
   - Provisional
   - Provisional & Restricted
   - Provisional & Under Review
   - Provisional & Internal Investigation
4. **Optional**: Rename to `Action_Status__c` if desired (requires updating code)

---

## 🗄️ STEP 3: Create Apex Trigger and Handler (2-4 hours)

### Step 3.1: Create AccountStatusHandler Class
**File to Create**: `force-app/main/default/classes/AccountStatusHandler.cls`

**Purpose**: Contains logic to automatically update Membership Status and Registration Status based on business rules.

**Key Methods Needed:**
1. `calculateMembershipStatus(Account acc)` - Determines membership status from Membership__c records
2. `calculateRegistrationStatus(Account acc)` - Determines registration status from survey count
3. `handleBeforeInsert(List<Account> accounts)` - Trigger handler for before insert
4. `handleBeforeUpdate(List<Account> accounts, Map<Id, Account> oldMap)` - Trigger handler for before update

**Logic for Membership Status:**
- **Active**: Has Membership__c with `Is_Current__c = true` AND `Expiration_Date__c >= Today`
- **Expired**: Has Membership__c with `Expiration_Date__c < Today` and no current membership
- **Lapsed**: Expired membership with no renewal within X days (define grace period)
- **Renewal**: New membership created but old one hasn't expired yet
- **Inactive**: No membership records exist

**Logic for Registration Status:**
- **Registered**: When `Survey_Total_Happy__c >= 50`
  - Set `Registration_Status__c = 'Registered'`
  - Set `Registration_Status_Date__c = Today` (if not already set)
  - Set `Registration_Status_Flag__c = true`
- **Provisional**: When `Survey_Total_Happy__c < 50`
  - Set `Registration_Status__c = 'Provisional'`
  - Keep `Registration_Status_Date__c` (don't clear historical date)
  - Set `Registration_Status_Flag__c = false`

### Step 3.2: Create AccountStatusTrigger
**File to Create**: `force-app/main/default/triggers/AccountStatusTrigger.trigger`

**Purpose**: Trigger on Account object that calls handler methods.

**Events**: `Before Insert, Before Update`

**What it should do:**
- Call `AccountStatusHandler.handleBeforeInsert()` on insert
- Call `AccountStatusHandler.handleBeforeUpdate()` on update
- Ensure bulkification (handle multiple records)

### Step 3.3: Create Trigger Handler for Survey Updates
**Note**: If survey count is on a related object, you may need a trigger on that object as well to update Account when survey count changes.

---

## 🔧 STEP 4: Update CEActionController (1-2 hours)

### Step 4.1: Remove Provisional Actions from getAvailableActions()
**File to Update**: `force-app/main/default/classes/CEActionController.cls`

**Line to Modify**: Lines 14-24 (the Account section)

**Current Code** (remove these lines):
```apex
if (ple.getValue().equals('Provisional')) options.add(ple.getValue());
if (ple.getValue().equals('Provisional & Restricted')) options.add(ple.getValue());
if (ple.getValue().equals('Provisional & Under Review')) options.add(ple.getValue());
if (ple.getValue().equals('Provisional & Internal Investigation')) options.add(ple.getValue());
```

**New Code** (keep only these):
```apex
if (ple.getValue().equals('Revoked') && adminIds.contains(UserInfo.getProfileId())) options.add(ple.getValue());
if (ple.getValue().equals('Restricted')) options.add(ple.getValue());
if (ple.getValue().equals('Under Review')) options.add(ple.getValue());
if (ple.getValue().equals('Internal Investigation')) options.add(ple.getValue());
```

### Step 4.2: Update submitAction() Method
**Purpose**: Prevent Provisional actions from being created

**Add Validation**: 
- If actionTaken contains "Provisional", throw an error or skip creation
- Add check: `if (actionTaken.contains('Provisional')) { throw new AuraHandledException('Provisional actions are no longer allowed'); }`

### Step 4.3: Update updateParentRecord() Method
**File to Update**: `force-app/main/default/classes/CEActionController.cls`

**Line to Modify**: Line 175

**Ensure**: Action_Status__c is only set for non-Provisional actions

---

## 🎨 STEP 5: Update LWC Components (1-2 hours)

### Step 5.1: Update ceActionBanner Component
**File to Update**: `force-app/main/default/lwc/ceActionBanner/ceActionBanner.js`

**Change**: 
- Line 6: Verify it uses `Current_Active_Action_Status__c` or update to `Action_Status__c` if renamed
- No other changes needed if field name stays the same

**File to Update**: `force-app/main/default/lwc/ceActionBanner/ceActionBanner.html`
- Verify it displays the correct status field

### Step 5.2: Update ceAccountAdministration Component (if needed)
**File to Update**: `force-app/main/default/lwc/ceAccountAdministration/ceAccountAdministration.js`

**Purpose**: Add display of new status fields if needed on Account Administration page

**What to Add**:
- Query new status fields in `getAdministrationData()` method
- Add properties to wrapper: `membershipStatus`, `registrationStatus`, `actionStatus`
- Display in HTML template if required

---

## 🔄 STEP 6: Data Migration (1-2 hours)

### Step 6.1: Create Migration Script
**File to Create**: `force-app/main/default/classes/AccountStatusMigrationHandler.cls`

**Purpose**: Migrate existing Account Status formula values to new fields

### Step 6.2: Understand Current Status Values
**Action**: 
1. Run SOQL query in Developer Console:
   ```sql
   SELECT Id, Status__c, Name FROM Account WHERE Status__c != NULL LIMIT 100
   ```
2. Review actual values in Status__c field
3. Document mapping:
   - Which values → Membership_Status__c
   - Which values → Registration_Status__c
   - Which values → Action_Status__c

### Step 6.3: Write Migration Logic
**Steps**:
1. Query all Accounts with Status values
2. Parse Status formula or values
3. Map to appropriate new fields
4. Update Accounts in batches of 200

### Step 6.4: Execute Migration
**Action**:
1. Run in Developer Console (Anonymous Apex) or create a scheduled job
2. Execute in test mode first with a few records
3. Validate results
4. Run full migration

---

## 📊 STEP 7: Create Reports (30-60 minutes)

### Step 7.1: Create Registration Status Report
**Action**:
1. Go to: **Reports & Dashboards → New Report**
2. Select **Report Type**: `Accounts with Contacts` or `Accounts`
3. Click **Create**
4. **Add Columns**:
   - Account Name
   - Registration Status
   - Registration Status Date
   - Survey Total Happy (or survey field name)
   - Contact Name (if Accounts with Contacts)
5. **Add Filters** (optional):
   - Registration Status = Registered
   - Registration Status Date is not null
6. **Sort By**: Registration Status Date (Descending - Most Recent First)
7. **Save** report as "Registration Status - Most Recent First"

---

## 🧪 STEP 8: Testing (2-4 hours)

### Step 8.1: Test Membership Status Updates
**Test Cases**:
1. **Create new Account** → Should default to `Membership Status = Active`
2. **Create Membership__c** with `Is_Current__c = true`, `Expiration_Date__c = Future date` → Should set `Membership Status = Active`
3. **Update Membership__c** with `Expiration_Date__c = Past date` → Should set `Membership Status = Expired`
4. **Create new Membership** while old one not expired → Should set `Membership Status = Renewal`
5. **Delete all Memberships** → Should set `Membership Status = Inactive`

### Step 8.2: Test Registration Status Updates
**Test Cases**:
1. **Create new Account** → Should default to `Registration Status = Provisional`
2. **Update Survey_Total_Happy__c to 50** → Should:
   - Set `Registration Status = Registered`
   - Set `Registration Status_Date__c = Today`
   - Set `Registration_Status_Flag__c = true`
3. **Update Survey_Total_Happy__c to 49** → Should:
   - Keep `Registration Status = Registered` (once registered, doesn't revert)
   - OR set back to `Provisional` (clarify requirement)
4. **Update Survey_Total_Happy__c from 49 to 50** → Should capture the date when it reaches 50

### Step 8.3: Test Action Status
**Test Cases**:
1. **Create CE_Action__c** with `Action__c = 'Under Review'` → Should update Account `Action_Status__c = 'Under Review'`
2. **Verify Provisional actions cannot be created** → Should throw error or be prevented
3. **End an action** → Should clear `Action_Status__c = null`
4. **Verify banner displays** action status correctly

### Step 8.4: Test Component Updates
**Test Cases**:
1. Verify `ceActionBanner` displays action status correctly
2. Verify Provisional actions don't appear in action selection UI
3. Verify account administration page shows new status fields correctly

---

## 🚀 STEP 9: Deployment (1-2 hours)

### Step 9.1: Pre-Deployment Checklist
- [ ] All fields created and tested in sandbox
- [ ] Trigger code written and tested
- [ ] CEActionController updated
- [ ] Components updated and tested
- [ ] Migration script tested on sample data
- [ ] Reports created and verified
- [ ] Unit tests written and passing

### Step 9.2: Deployment Order
1. **Deploy Fields** (via Change Sets or Metadata API)
   - Membership_Status__c
   - Registration_Status__c
   - Registration_Status_Date__c
   - Registration_Status_Flag__c
   - Update Current_Active_Action_Status__c picklist (remove Provisional values)

2. **Deploy Apex Code** (via Change Sets or Metadata API)
   - AccountStatusHandler.cls
   - AccountStatusTrigger.trigger
   - Updated CEActionController.cls
   - Updated CEBannerController.cls (if needed)
   - Updated components (ceActionBanner, etc.)

3. **Run Data Migration**
   - Execute AccountStatusMigrationHandler in production
   - Verify records updated correctly

4. **Deploy Reports**
   - Export report from sandbox
   - Import to production

5. **Update CE_Action__c Picklist**
   - Go to: **Setup → Object Manager → CE_Action__c → Fields & Relationships → Action__c**
   - Remove Provisional-related values from picklist

---

## ✅ STEP 10: Post-Deployment Verification (30-60 minutes)

### Step 10.1: Verify Field Values
**Action**: Run SOQL queries to verify:
```sql
SELECT Id, Name, Membership_Status__c, Registration_Status__c, Registration_Status_Date__c, 
       Registration_Status_Flag__c, Current_Active_Action_Status__c 
FROM Account 
LIMIT 20
```

### Step 10.2: Verify Trigger Functionality
**Action**: 
1. Create a test Account
2. Create a Membership__c record
3. Verify Membership_Status__c updates correctly
4. Update Survey_Total_Happy__c to 50
5. Verify Registration_Status__c updates correctly

### Step 10.3: Verify Component Functionality
**Action**:
1. Navigate to account administration page
2. Verify banner displays correctly
3. Verify action status updates correctly
4. Verify Provisional actions don't appear in UI

### Step 10.4: Verify Reports
**Action**:
1. Open Registration Status report
2. Verify data displays correctly
3. Verify sorting works (most recent first)
4. Verify filters work correctly

---

## 📝 Quick Reference: File Checklist

### Files to Create:
- [ ] `force-app/main/default/classes/AccountStatusHandler.cls`
- [ ] `force-app/main/default/classes/AccountStatusHandler.cls-meta.xml`
- [ ] `force-app/main/default/triggers/AccountStatusTrigger.trigger`
- [ ] `force-app/main/default/triggers/AccountStatusTrigger.trigger-meta.xml`
- [ ] `force-app/main/default/classes/AccountStatusMigrationHandler.cls`
- [ ] `force-app/main/default/classes/AccountStatusMigrationHandler.cls-meta.xml`

### Files to Update:
- [ ] `force-app/main/default/classes/CEActionController.cls`
- [ ] `force-app/main/default/classes/CEBannerController.cls` (if needed)
- [ ] `force-app/main/default/lwc/ceActionBanner/ceActionBanner.js` (verify)
- [ ] `force-app/main/default/lwc/ceAccountAdministration/ceAccountAdministration.js` (if needed)

### Fields to Create (in Salesforce UI):
- [ ] Account.Membership_Status__c (Picklist)
- [ ] Account.Registration_Status__c (Picklist)
- [ ] Account.Registration_Status_Date__c (Date)
- [ ] Account.Registration_Status_Flag__c (Checkbox)
- [ ] Update Account.Current_Active_Action_Status__c (remove Provisional values)

---

## ⚠️ Important Notes

1. **Backup First**: Always backup Account records before running migration
2. **Test in Sandbox**: Test everything thoroughly in sandbox before production
3. **Phased Rollout**: Consider deploying to a subset of accounts first
4. **Monitor Errors**: Check trigger execution logs after deployment
5. **Document Changes**: Keep track of what was changed and why

---

## 🆘 Troubleshooting

**Issue**: Trigger not firing
- **Check**: Trigger is active, bulkification is correct, no DML in loop

**Issue**: Status not updating
- **Check**: Trigger logic, field permissions, validation rules

**Issue**: Migration script errors
- **Check**: Batch size, field access, data quality

**Issue**: Components not showing status
- **Check**: Field API names, SOQL queries, component properties

---

## 📞 Questions to Ask Before Starting

1. What is the exact API name of the survey field? (`Survey_Total_Happy__c`?)
2. What is the current Status formula field logic?
3. Should Registration Status revert to Provisional if survey count drops below 50?
4. What is the grace period for "Lapsed" membership status?
5. Should existing CE_Action__c records with Provisional actions be deleted or just ignored?
6. Can an account have multiple statuses active at once? (e.g., Membership Status = Active AND Action Status = Under Review)

---

## 🎯 Estimated Timeline

- **Discovery & Analysis**: 1-2 hours
- **Field Creation**: 1 hour
- **Apex Development**: 4-6 hours
- **Component Updates**: 1-2 hours
- **Data Migration**: 2-4 hours
- **Testing**: 2-4 hours
- **Deployment**: 1-2 hours
- **Total**: 12-21 hours

---

**Start with Step 1 (Discovery) and work through each step sequentially. If you get stuck on any step, let me know and I can help you with that specific part!**

