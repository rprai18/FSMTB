# How to Make Action Banner Green in Salesforce - Step by Step

## 🎯 Goal
Make the action banner turn **GREEN** when Account Registration Status = "Provisional"

---

## ✅ What I've Done

I've updated the banner component to read both:
1. **Registration_Status__c** - Shows green banner when "Provisional"
2. **Current_Active_Action_Status__c** - Shows orange banner when has action statuses

---

## 📋 Changes Made

### 1. Updated `CEBannerController.cls`
- Added new method `getAccountBannerStatuses()` that returns both Registration Status and Action Status
- Returns a wrapper with both status fields

### 2. Updated `ceActionBanner.js`
- Now reads both `Registration_Status__c` and `Current_Active_Action_Status__c`
- Shows **GREEN banner** when `Registration_Status__c = "Provisional"`
- Shows **ORANGE banner** when `Current_Active_Action_Status__c` has values (Under Review, Restricted, etc.)
- Shows **ORANGE banner** when both Provisional Registration AND Action Status (combined message)

---

## 🎨 Banner Color Logic

### Green Banner (`.banner--green`)
Shows when:
- ✅ `Registration_Status__c = "Provisional"` (hasn't reached 50 favorable surveys)

**Message**: "Your account has not yet received 50 favorable reviews from students."

### Orange Banner (`.banner--orange`)
Shows when:
- ✅ `Current_Active_Action_Status__c = "Under Review"` or other action statuses
- ✅ Both Provisional Registration AND Action Status (combined)

**Message**: 
- "Your account is in the process of taking corrective action in order to comply with FSMTB CE Standards."
- Or combined message if both statuses exist

---

## 🚀 Next Steps

### Step 1: Deploy the Changes
Deploy the updated files to Salesforce:
- `CEBannerController.cls`
- `ceActionBanner.js`

### Step 2: Verify the Banner Shows Green
1. Go to a Community page with the banner component
2. Check an account with `Registration_Status__c = "Provisional"`
3. The banner should show **GREEN** with the Provisional message

### Step 3: Test Different Scenarios

#### Scenario 1: Provisional Registration Only
- `Registration_Status__c = "Provisional"`
- `Current_Active_Action_Status__c = null`
- **Expected**: Green banner with Provisional message

#### Scenario 2: Action Status Only
- `Registration_Status__c = "Registered"` or null
- `Current_Active_Action_Status__c = "Under Review"`
- **Expected**: Orange banner with Action message

#### Scenario 3: Both Statuses
- `Registration_Status__c = "Provisional"`
- `Current_Active_Action_Status__c = "Under Review"`
- **Expected**: Orange banner with combined message

---

## 📂 Files Modified

1. **`force-app/main/default/classes/CEBannerController.cls`**
   - Added `getAccountBannerStatuses()` method
   - Returns both Registration Status and Action Status

2. **`force-app/main/default/lwc/ceActionBanner/ceActionBanner.js`**
   - Updated to read both status fields
   - Updated logic to check `Registration_Status__c` for green banner
   - Updated logic to check `Current_Active_Action_Status__c` for orange banner

---

## ✅ Verification Checklist

- [x] CEBannerController updated to return both statuses
- [x] Banner component updated to read both fields
- [x] Green banner logic updated to check Registration_Status__c
- [x] Orange banner logic updated to check Action Status
- [x] Combined status logic added
- [ ] Deploy to Salesforce
- [ ] Test green banner with Provisional Registration Status
- [ ] Test orange banner with Action Status
- [ ] Test combined banner with both statuses

---

## 🎉 Result

After deploying, the banner will:
- ✅ Show **GREEN** when Registration Status = "Provisional"
- ✅ Show **ORANGE** when Action Status has values
- ✅ Show **ORANGE** when both statuses exist (with combined message)
- ✅ Hide when neither status is set

---

## 🔍 How to Test

### Test 1: Green Banner (Provisional Registration)
```apex
// Query an account with Provisional Registration Status
Account acc = [SELECT Id, Registration_Status__c FROM Account WHERE Registration_Status__c = 'Provisional' LIMIT 1];
// Banner should show GREEN
```

### Test 2: Orange Banner (Action Status)
```apex
// Query an account with Action Status
Account acc = [SELECT Id, Current_Active_Action_Status__c FROM Account WHERE Current_Active_Action_Status__c = 'Under Review' LIMIT 1];
// Banner should show ORANGE
```

### Test 3: Combined Banner
```apex
// Query an account with both statuses
Account acc = [
    SELECT Id, Registration_Status__c, Current_Active_Action_Status__c 
    FROM Account 
    WHERE Registration_Status__c = 'Provisional' 
    AND Current_Active_Action_Status__c = 'Under Review' 
    LIMIT 1
];
// Banner should show ORANGE with combined message
```

---

## 📝 Summary

The banner component now reads both `Registration_Status__c` and `Current_Active_Action_Status__c` fields and shows:
- **GREEN** for Provisional Registration Status
- **ORANGE** for Action Statuses
- **ORANGE** for combined statuses

**Next Step**: Deploy the changes and test! 🚀

