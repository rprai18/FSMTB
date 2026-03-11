# Account Status Splitting Implementation Plan

## Overview
This document outlines the steps required to split the Account Status field into three separate status fields: Membership Status, Registration Status, and Action Status.

---

## Phase 1: Field Creation on Account Object

### Step 1.1: Create Membership_Status__c Field
- **Type**: Picklist
- **Field Label**: Membership Status
- **API Name**: Membership_Status__c
- **Values**: 
  - Active (Default)
  - Lapsed
  - Inactive
  - Expired
  - Renewal
- **Default Value**: Active
- **Required**: No
- **Help Text**: Indicates whether the account is current on payment for membership

### Step 1.2: Create Registration_Status__c Field
- **Type**: Picklist
- **Field Label**: Registration Status
- **API Name**: Registration_Status__c
- **Values**:
  - Provisional (Default)
  - Registered
- **Default Value**: Provisional
- **Required**: No
- **Help Text**: Indicates if the account has reached the required number of surveys (50)

### Step 1.3: Create Registration_Status_Date__c Field
- **Type**: Date
- **Field Label**: Registration Status Date
- **API Name**: Registration_Status_Date__c
- **Required**: No
- **Help Text**: Date when Registration Status milestone was reached (when Survey_Total_Happy__c = 50)

### Step 1.4: Create Registration_Status_Flag__c Field
- **Type**: Checkbox
- **Field Label**: Registration Status Flag
- **API Name**: Registration_Status_Flag__c
- **Default Value**: False
- **Help Text**: Flag to indicate registration status on the account

### Step 1.5: Update/Rename Current_Active_Action_Status__c Field
- **Option A**: Keep existing field but update values
- **Option B**: Create new Action_Status__c field and migrate data
- **Field Label**: Action Status
- **API Name**: Action_Status__c (or keep Current_Active_Action_Status__c)
- **Values**:
  - Under Review
  - Restricted
  - Internal Investigation
  - Revoked
- **Default Value**: None (leave blank)
- **Help Text**: Shows any action that is currently being taken or has been taken against the account

---

## Phase 2: Create Apex Trigger for Status Updates

### Step 2.1: Create AccountStatusHandler Trigger Handler
**File**: `force-app/main/default/classes/AccountStatusHandler.cls`

**Responsibilities**:
1. **Membership Status Logic**: 
   - Evaluate Membership__c records for the Account
   - Set Membership_Status__c based on:
     - Active: If Is_Current__c = true and Expiration_Date__c >= Today
     - Expired: If Expiration_Date__c < Today
     - Lapsed: If membership expired and no new membership created within grace period
     - Renewal: If new membership created but old one not expired yet
     - Inactive: If no current membership

2. **Registration Status Logic**:
   - Monitor Survey_Total_Happy__c field (or related survey count)
   - When Survey_Total_Happy__c >= 50:
     - Set Registration_Status__c = 'Registered'
     - Set Registration_Status_Date__c = Today
     - Set Registration_Status_Flag__c = true
   - When Survey_Total_Happy__c < 50:
     - Set Registration_Status__c = 'Provisional'
     - Clear Registration_Status_Date__c (or keep historical date)

**Trigger**: `AccountStatusTrigger.trigger`
- **Object**: Account
- **Events**: Before Insert, Before Update
- Calls AccountStatusHandler methods

---

## Phase 3: Update CEActionController Class

### Step 3.1: Remove Provisional-Related Actions
**File**: `force-app/main/default/classes/CEActionController.cls`

**Changes Needed**:
1. In `getAvailableActions()` method:
   - Remove: 'Provisional'
   - Remove: 'Provisional & Restricted'
   - Remove: 'Provisional & Under Review'
   - Remove: 'Provisional & Internal Investigation'
   - Keep only: Under Review, Restricted, Internal Investigation, Revoked

2. Update `submitAction()` method:
   - Ensure Provisional actions don't generate CE_Action__c records
   - Prevent setting Action_Status__c when action is Provisional-related

3. Update `updateParentRecord()` method:
   - Use new Action_Status__c field name (if renamed)
   - Don't set action status for Provisional actions

4. Update action ending logic:
   - When ending actions, don't reset if new Provisional action is being set

### Step 3.2: Prevent Provisional Actions on Signup
- Add logic to prevent automatic Provisional action creation upon account signup
- This may be in a trigger or registration flow

---

## Phase 4: Update Visualforce Pages and LWC Components

### Step 4.1: Update CEBannerController
**File**: `force-app/main/default/classes/CEBannerController.cls`

**Changes Needed**:
- Update `getAccountStatus()` to support new field names
- Optionally create separate methods for each status type
- Return combined status information if needed for banner display

### Step 4.2: Update ceActionBanner LWC
**File**: `force-app/main/default/lwc/ceActionBanner/ceActionBanner.js`

**Changes Needed**:
- Update to use Action_Status__c instead of Current_Active_Action_Status__c
- Add support for displaying Membership Status and Registration Status
- Update banner logic to show appropriate messages based on new statuses

### Step 4.3: Update PCEAction Visualforce Page (if exists)
- Update to use new field names
- Remove Provisional-related options from UI
- Update action selection logic

### Step 4.4: Update Other Components
- Update ceAccountAdministration LWC to display new statuses
- Update courseManagementOverview if it references Account Status
- Update any other components that display account status

---

## Phase 5: Create Migration Logic

### Step 5.1: Create Data Migration Script
**File**: `force-app/main/default/classes/AccountStatusMigrationHandler.cls`

**Purpose**: Migrate existing Status formula field values to new fields

**Logic**:
1. Query all Accounts with existing Status values
2. Parse Status formula logic (you'll need to reverse-engineer the formula)
3. Map values to new fields:
   - Membership-related statuses → Membership_Status__c
   - Provisional/Registered → Registration_Status__c
   - Action-related statuses → Action_Status__c
4. Update accounts in batches

**Execution**:
- Create Anonymous Apex script or scheduled job
- Run during maintenance window
- Validate results before full deployment

---

## Phase 6: Update Reports and Dashboards

### Step 6.1: Create Registration Status Report
**Report Type**: Accounts with Contacts
**Fields**:
- Account Name
- Registration Status
- Registration Status Date
- Survey Total Happy (or related field)
- Contact Name (if needed)

**Sort**: Registration Status Date (Most Recent First)
**Filters**: 
- Registration Status = Registered (optional)
- Registration Status Date is not null

### Step 6.2: Update Existing Reports
- Update any reports that use Account Status formula field
- Replace with appropriate new status fields

---

## Phase 7: Testing Checklist

### Step 7.1: Unit Tests
- Test AccountStatusHandler trigger logic
- Test CEActionController updates
- Test Registration Status milestone logic
- Test Membership Status calculation
- Test Action Status updates

### Step 7.2: Integration Tests
- Test account creation with new statuses
- Test membership renewal flow
- Test survey milestone achievement
- Test CE Action creation/ending
- Test banner display logic

### Step 7.3: User Acceptance Testing
- Verify Provisional actions don't appear in action list
- Verify Registration Status updates when survey count reaches 50
- Verify Membership Status updates correctly
- Verify Action Status works as expected
- Verify reports display correctly

---

## Phase 8: Deployment Steps

### Step 8.1: Pre-Deployment
1. Backup all Account records
2. Document current Status formula logic
3. Review all components that use Status field
4. Create sandbox/test environment changes

### Step 8.2: Deployment Order
1. Deploy new fields (membership, registration, action status)
2. Deploy trigger and handler class
3. Run data migration script
4. Deploy updated CEActionController
5. Deploy updated components/Visualforce pages
6. Create/update reports

### Step 8.3: Post-Deployment
1. Verify all accounts have correct status values
2. Monitor for errors in trigger execution
3. Validate report data
4. Update user documentation
5. Train administrators on new status fields

---

## Files That Need to be Created/Updated

### New Files:
1. `force-app/main/default/classes/AccountStatusHandler.cls`
2. `force-app/main/default/triggers/AccountStatusTrigger.trigger`
3. `force-app/main/default/classes/AccountStatusMigrationHandler.cls`
4. `force-app/main/default/classes/AccountStatusHandler.cls-meta.xml`
5. `force-app/main/default/triggers/AccountStatusTrigger.trigger-meta.xml`
6. `force-app/main/default/classes/AccountStatusMigrationHandler.cls-meta.xml`

### Updated Files:
1. `force-app/main/default/classes/CEActionController.cls`
2. `force-app/main/default/classes/CEBannerController.cls`
3. `force-app/main/default/lwc/ceActionBanner/ceActionBanner.js`
4. `force-app/main/default/lwc/ceAccountAdministration/ceAccountAdministration.js` (if statuses displayed)
5. Any Visualforce pages that reference account status

### Field Metadata (Need to be created in Salesforce UI or via Metadata API):
- Account.Membership_Status__c
- Account.Registration_Status__c
- Account.Registration_Status_Date__c
- Account.Registration_Status_Flag__c
- Account.Action_Status__c (or update Current_Active_Action_Status__c)

---

## Important Notes

1. **Survey Field**: You mentioned `Survey_Total_Happy__c` - verify this field exists on Account. If it doesn't, you may need to:
   - Create a rollup summary field
   - Create a formula field
   - Use a trigger to calculate it from related records

2. **Status Formula Logic**: You'll need to:
   - Review the current Status formula field
   - Document all conditions and logic
   - Map each condition to the appropriate new status field

3. **Backward Compatibility**: Consider:
   - Keeping old Status field temporarily (as formula or text)
   - Creating a validation rule to ensure consistency
   - Phased rollout approach

4. **Performance**: 
   - Ensure trigger is bulkified
   - Consider using Future methods or Queueable for complex logic
   - Add appropriate error handling

---

## Questions to Verify Before Implementation

1. What is the exact API name of the survey field? (Survey_Total_Happy__c or different?)
2. What is the current Status formula field logic?
3. What are the exact Membership status calculation rules?
4. Should Provisional action records be deleted or just prevented from creation?
5. What happens to existing CE_Action__c records with Provisional actions?
6. Should Registration Status revert to Provisional if survey count drops below 50?

---

## Timeline Estimate

- **Phase 1**: Field Creation - 2-4 hours
- **Phase 2**: Trigger Development - 4-6 hours
- **Phase 3**: CEActionController Updates - 2-3 hours
- **Phase 4**: Component Updates - 4-6 hours
- **Phase 5**: Migration Logic - 2-4 hours
- **Phase 6**: Reports - 1-2 hours
- **Phase 7**: Testing - 4-8 hours
- **Phase 8**: Deployment - 2-4 hours

**Total Estimated Time**: 21-37 hours

---

## Next Steps

1. Review this plan with stakeholders
2. Verify all field names and logic requirements
3. Create fields in a sandbox environment
4. Start with Phase 2 (Trigger Development)
5. Test thoroughly before production deployment


