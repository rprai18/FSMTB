# Field Creation Guide - Account Status Splitting

## Analysis of Current Status__c Formula

Based on the formula you provided, here's the breakdown:

### Current Formula Logic:
```
IF(RecordType.DeveloperName == 'CE_Provider',
    IF(Allow_Renewal__c, "Renewal",
        IF(Membership_Expiration_Date__c - today() <= -60, "Expired",
            IF(Membership_Expiration_Date__c - today() <= -30, "Inactive",
                IF(Membership_Expiration_Date__c - today() < 0, "Lapsed",
                    CASE(Current_Active_Action_Status__c,
                        'Revoked','Revoked',
                        'Restricted','Restricted',
                        'Provisional','Provisional',
                        'Under Review','Under Review',
                        'Provisional & Restricted','Provisional & Restricted',
                        'Provisional & Under Review','Provisional & Under Review',
                        'Internal Investigation','Internal Investigation',
                        'Provisional & Internal Investigation','Provisional & Internal Investigation',
                        'Registered'
                    )
                )
            )
        )
    ),
    IF(AND(RecordType.DeveloperName == 'MT_Verify', Membership_Expiration_Date__c - today() < 0), "Renewal", "Registered")
)
```

### Status Mapping:

**Membership Status (from formula logic):**
- **Renewal**: `Allow_Renewal__c = true` OR (MT_Verify AND expired)
- **Expired**: `Membership_Expiration_Date__c - Today() <= -60`
- **Inactive**: `Membership_Expiration_Date__c - Today() <= -30` (and > -60)
- **Lapsed**: `Membership_Expiration_Date__c - Today() < 0` (and > -30)
- **Active**: Default (when membership is current)

**Registration Status (from CASE default):**
- **Registered**: Default in CASE (when no action status)
- **Provisional**: Need to check `Survey_Total_Happy__c < 50`

**Action Status (from Current_Active_Action_Status__c):**
- **Under Review**: From Current_Active_Action_Status__c
- **Restricted**: From Current_Active_Action_Status__c
- **Internal Investigation**: From Current_Active_Action_Status__c
- **Revoked**: From Current_Active_Action_Status__c
- **Remove**: Provisional-related actions

---

## Fields to Create

### Field 1: Membership_Status__c (Picklist)

**Path**: Setup → Object Manager → Account → Fields & Relationships → New

**Field Details:**
- **Data Type**: Picklist
- **Field Label**: `Membership Status`
- **Field Name**: `Membership_Status` (API Name: `Membership_Status__c`)
- **Required**: No
- **Default Value**: Active

**Picklist Values** (Enter one per line):
```
Active
Lapsed
Inactive
Expired
Renewal
```

**Help Text**: `Indicates whether the account is current on payment for membership. Status is determined by membership expiration date and renewal eligibility.`

**Field-Level Security**: Select all profiles that should have access

---

### Field 2: Registration_Status__c (Picklist)

**Path**: Setup → Object Manager → Account → Fields & Relationships → New

**Field Details:**
- **Data Type**: Picklist
- **Field Label**: `Registration Status`
- **Field Name**: `Registration_Status` (API Name: `Registration_Status__c`)
- **Required**: No
- **Default Value**: Provisional

**Picklist Values** (Enter one per line):
```
Provisional
Registered
```

**Help Text**: `Indicates if the account has reached the required number of surveys (50). Provisional = fewer than 50 surveys, Registered = 50 or more surveys.`

**Field-Level Security**: Select all profiles that should have access

---

### Field 3: Registration_Status_Date__c (Date)

**Path**: Setup → Object Manager → Account → Fields & Relationships → New

**Field Details:**
- **Data Type**: Date
- **Field Label**: `Registration Status Date`
- **Field Name**: `Registration_Status_Date` (API Name: `Registration_Status_Date__c`)
- **Required**: No
- **Default Value**: None

**Help Text**: `Date when the account reached the Registered status milestone (when Survey Total Happy reached 50).`

**Field-Level Security**: Select all profiles that should have access

---

### Field 4: Registration_Status_Flag__c (Checkbox)

**Path**: Setup → Object Manager → Account → Fields & Relationships → New

**Field Details:**
- **Data Type**: Checkbox
- **Field Label**: `Registration Status Flag`
- **Field Name**: `Registration_Status_Flag` (API Name: `Registration_Status_Flag__c`)
- **Default Value**: Unchecked (False)

**Help Text**: `Flag to indicate when account has reached Registered status. Automatically set to true when Survey Total Happy = 50.`

**Field-Level Security**: Select all profiles that should have access

---

## Field Updates (Not Creating New Fields)

### Current_Active_Action_Status__c Field

**Path**: Setup → Object Manager → Account → Fields & Relationships → Current_Active_Action_Status__c

**Action**: Update Picklist Values

**Current Values to KEEP:**
- Under Review
- Restricted
- Internal Investigation
- Revoked

**Values to REMOVE** (after code is updated):
- Provisional
- Provisional & Restricted
- Provisional & Under Review
- Provisional & Internal Investigation

**Note**: 
- Keep the field name as `Current_Active_Action_Status__c` (or rename to `Action_Status__c` if preferred)
- Don't remove values yet - remove after code is updated to prevent errors
- Default Value: None (leave blank)

---

## Dependencies and Related Fields

### Fields Already on Account (referenced in logic):
- ✅ `Membership_Expiration_Date__c` - Date field (exists)
- ✅ `Allow_Renewal__c` - Checkbox (exists, referenced in formula)
- ✅ `Current_Active_Action_Status__c` - Picklist (exists)
- ✅ `Survey_Total_Happy__c` - Roll-Up Summary (exists)
- ✅ `RecordType.DeveloperName` - RecordType field (exists)

### Important Notes:
1. **Survey_Total_Happy__c** is a Roll-Up Summary field from Course records
   - This means when Course records update, the Account value updates automatically
   - We'll need a trigger on Course object OR use Platform Events to detect when Account's Survey_Total_Happy__c changes
   - Alternatively, we can use a Process Builder or Flow that triggers on Account field update

2. **Membership_Expiration_Date__c** is referenced in the formula
   - This appears to be a date field directly on Account
   - We'll need logic to calculate membership status based on this date

3. **RecordType** matters
   - CE_Provider record type has different logic than MT_Verify record type
   - Our trigger/handler needs to account for this

---

## Next Steps After Field Creation

### Immediate Next Steps:
1. ✅ **Create all 4 fields** as described above
2. ✅ **Document field creation** (note API names, labels, etc.)
3. ✅ **Verify fields exist** by querying in Developer Console:
   ```sql
   SELECT Id, Name, Membership_Status__c, Registration_Status__c, 
          Registration_Status_Date__c, Registration_Status_Flag__c 
   FROM Account 
   LIMIT 1
   ```

### After Fields Are Created:
1. I'll create the **AccountStatusHandler** class with logic to:
   - Calculate Membership Status based on Membership_Expiration_Date__c
   - Calculate Registration Status based on Survey_Total_Happy__c
   - Auto-update these fields when related data changes

2. I'll create the **AccountStatusTrigger** to:
   - Call the handler on Account insert/update
   - Handle bulk updates efficiently

3. I'll update **CEActionController** to:
   - Remove Provisional actions from available actions
   - Prevent Provisional actions from being created

4. I'll create **migration script** to:
   - Migrate existing Status__c values to new fields
   - Set initial values based on current formula logic

---

## Important Questions to Confirm

Before creating fields, please confirm:

1. **Membership_Expiration_Date__c** - Is this a date field directly on Account, or is it a formula/lookup from Membership__c object?
   - If it's from Membership__c, we need to check Membership__c.Is_Current__c field too

2. **Survey_Total_Happy__c** - Since this is a Roll-Up Summary, when a Course record is updated and this value changes on Account, do we need to:
   - Use a Process Builder/Flow that triggers on Account field update?
   - OR create a trigger on Course object that updates Account?
   - OR use Platform Events?

3. **Registration Status Reversion** - If Survey_Total_Happy__c drops below 50 (after reaching 50), should Registration_Status__c:
   - Stay as "Registered" (once registered, always registered)
   - OR revert to "Provisional" (dynamic)

4. **Membership Status for MT_Verify RecordType** - Based on formula, MT_Verify accounts:
   - Are "Renewal" if expired (Membership_Expiration_Date__c - today() < 0)
   - Are "Registered" if not expired
   - Should MT_Verify accounts have Membership Status, or is it only for CE_Provider?

5. **Default Registration Status** - Should new accounts start with:
   - Registration_Status__c = "Provisional" (even if Survey_Total_Happy__c = 0 or null)
   - OR should it be calculated on first save?

---

## Ready to Create Fields?

Once you confirm the questions above, you can proceed with field creation. Here's the order I recommend:

1. **Create Membership_Status__c** (Picklist)
2. **Create Registration_Status__c** (Picklist) 
3. **Create Registration_Status_Date__c** (Date)
4. **Create Registration_Status_Flag__c** (Checkbox)
5. **Verify Current_Active_Action_Status__c** picklist values (don't remove Provisional values yet)

After fields are created, let me know and I'll help you with:
- Creating the Apex trigger and handler
- Updating the CEActionController
- Creating the migration script
- Testing everything

**Let me know once you've created the fields, or if you need help with any of the field creation steps!**


