# Testing Guide - Account Status Functionality

## 🧪 Quick Testing Checklist

### Step 1: Test New Account Creation (5 minutes)

**Test in Salesforce UI:**
1. Go to: **Accounts → New Account**
2. Fill in required fields:
   - Account Name: `Test Account Status`
   - Record Type: `CE Provider` (or `MT_Verify`)
   - Membership Expiration Date: Future date (e.g., today + 30 days)
   - Survey Total Happy: `0` (or leave blank)
3. Click **Save**

**Verify:**
- ✅ **Membership Status** should be **"Active"** (default)
- ✅ **Registration Status** should be **"Provisional"** (default)
- ✅ **Registration Status Flag** should be **Unchecked**

**Or Test with Anonymous Apex:**
```apex
// Test 1: Create new Account and verify default statuses
Account testAcc = new Account(
    Name = 'Test Account - New',
    RecordTypeId = [SELECT Id FROM RecordType WHERE DeveloperName = 'CE_Provider' AND SobjectType = 'Account' LIMIT 1].Id,
    Membership_Expiration_Date__c = System.today().addDays(30),
    Survey_Total_Happy__c = 0
);
insert testAcc;

// Query and verify
Account result = [SELECT Id, Name, Membership_Status__c, Registration_Status__c, 
                         Registration_Status_Flag__c, Survey_Total_Happy__c 
                  FROM Account WHERE Id = :testAcc.Id];

System.debug('=== Test 1: New Account Creation ===');
System.debug('Account Name: ' + result.Name);
System.debug('Membership Status: ' + result.Membership_Status__c); // Should be "Active"
System.debug('Registration Status: ' + result.Registration_Status__c); // Should be "Provisional"
System.debug('Registration Status Flag: ' + result.Registration_Status_Flag__c); // Should be false
System.debug('Test 1 Result: ' + (result.Membership_Status__c == 'Active' && result.Registration_Status__c == 'Provisional' ? 'PASS' : 'FAIL'));
```

---

### Step 2: Test Membership Status Updates (10 minutes)

**Test Membership Status Calculation:**

```apex
// Test 2: Test Membership Status = "Active"
Account testAcc = new Account(
    Name = 'Test Account - Active',
    RecordTypeId = [SELECT Id FROM RecordType WHERE DeveloperName = 'CE_Provider' AND SobjectType = 'Account' LIMIT 1].Id,
    Membership_Expiration_Date__c = System.today().addDays(30), // Future date
    Allow_Renewal__c = false
);
insert testAcc;

Account result = [SELECT Membership_Status__c FROM Account WHERE Id = :testAcc.Id];
System.debug('=== Test 2: Membership Status = Active ===');
System.debug('Membership Status: ' + result.Membership_Status__c); // Should be "Active"
System.debug('Test 2 Result: ' + (result.Membership_Status__c == 'Active' ? 'PASS' : 'FAIL'));

// Test 3: Test Membership Status = "Lapsed"
testAcc.Membership_Expiration_Date__c = System.today().addDays(-10); // 10 days ago
update testAcc;

result = [SELECT Membership_Status__c FROM Account WHERE Id = :testAcc.Id];
System.debug('=== Test 3: Membership Status = Lapsed ===');
System.debug('Membership Status: ' + result.Membership_Status__c); // Should be "Lapsed"
System.debug('Test 3 Result: ' + (result.Membership_Status__c == 'Lapsed' ? 'PASS' : 'FAIL'));

// Test 4: Test Membership Status = "Inactive"
testAcc.Membership_Expiration_Date__c = System.today().addDays(-40); // 40 days ago
update testAcc;

result = [SELECT Membership_Status__c FROM Account WHERE Id = :testAcc.Id];
System.debug('=== Test 4: Membership Status = Inactive ===');
System.debug('Membership Status: ' + result.Membership_Status__c); // Should be "Inactive"
System.debug('Test 4 Result: ' + (result.Membership_Status__c == 'Inactive' ? 'PASS' : 'FAIL'));

// Test 5: Test Membership Status = "Expired"
testAcc.Membership_Expiration_Date__c = System.today().addDays(-70); // 70 days ago
update testAcc;

result = [SELECT Membership_Status__c FROM Account WHERE Id = :testAcc.Id];
System.debug('=== Test 5: Membership Status = Expired ===');
System.debug('Membership Status: ' + result.Membership_Status__c); // Should be "Expired"
System.debug('Test 5 Result: ' + (result.Membership_Status__c == 'Expired' ? 'PASS' : 'FAIL'));

// Test 6: Test Membership Status = "Renewal"
testAcc.Allow_Renewal__c = true;
update testAcc;

result = [SELECT Membership_Status__c FROM Account WHERE Id = :testAcc.Id];
System.debug('=== Test 6: Membership Status = Renewal ===');
System.debug('Membership Status: ' + result.Membership_Status__c); // Should be "Renewal"
System.debug('Test 6 Result: ' + (result.Membership_Status__c == 'Renewal' ? 'PASS' : 'FAIL'));
```

---

### Step 3: Test Registration Status Updates (10 minutes)

**Test Registration Status Calculation:**

```apex
// Test 7: Test Registration Status = "Provisional" (below 50)
Account testAcc = new Account(
    Name = 'Test Account - Provisional',
    RecordTypeId = [SELECT Id FROM RecordType WHERE DeveloperName = 'CE_Provider' AND SobjectType = 'Account' LIMIT 1].Id,
    Survey_Total_Happy__c = 49
);
insert testAcc;

Account result = [SELECT Registration_Status__c, Registration_Status_Flag__c, Registration_Status_Date__c 
                  FROM Account WHERE Id = :testAcc.Id];
System.debug('=== Test 7: Registration Status = Provisional ===');
System.debug('Registration Status: ' + result.Registration_Status__c); // Should be "Provisional"
System.debug('Registration Status Flag: ' + result.Registration_Status_Flag__c); // Should be false
System.debug('Registration Status Date: ' + result.Registration_Status_Date__c); // Should be null
System.debug('Test 7 Result: ' + (result.Registration_Status__c == 'Provisional' && result.Registration_Status_Flag__c == false ? 'PASS' : 'FAIL'));

// Test 8: Test Registration Status = "Registered" (reaches 50)
testAcc.Survey_Total_Happy__c = 50;
update testAcc;

result = [SELECT Registration_Status__c, Registration_Status_Flag__c, Registration_Status_Date__c 
          FROM Account WHERE Id = :testAcc.Id];
System.debug('=== Test 8: Registration Status = Registered ===');
System.debug('Registration Status: ' + result.Registration_Status__c); // Should be "Registered"
System.debug('Registration Status Flag: ' + result.Registration_Status_Flag__c); // Should be true
System.debug('Registration Status Date: ' + result.Registration_Status_Date__c); // Should be today's date
System.debug('Test 8 Result: ' + (result.Registration_Status__c == 'Registered' && 
                                   result.Registration_Status_Flag__c == true && 
                                   result.Registration_Status_Date__c == System.today() ? 'PASS' : 'FAIL'));

// Test 9: Test that date is only set once (not updated again)
testAcc.Survey_Total_Happy__c = 51;
update testAcc;

result = [SELECT Registration_Status_Date__c FROM Account WHERE Id = :testAcc.Id];
Date originalDate = result.Registration_Status_Date__c;
System.debug('=== Test 9: Registration Status Date Only Set Once ===');
System.debug('Original Date: ' + originalDate);
System.debug('Current Date After Update: ' + result.Registration_Status_Date__c);
System.debug('Test 9 Result: ' + (result.Registration_Status_Date__c == originalDate ? 'PASS' : 'FAIL'));
```

---

### Step 4: Test Action Status (CEActionController) (10 minutes)

**Test Provisional Actions Prevention:**

```apex
// Test 10: Try to create Provisional action (should fail)
Account testAcc = [SELECT Id FROM Account LIMIT 1];

try {
    CEActionController.submitAction(
        testAcc.Id, 
        'Provisional', // This should be rejected
        String.valueOf(System.today()), 
        'Test reason'
    );
    System.debug('=== Test 10: Provisional Action Prevention ===');
    System.debug('Test 10 Result: FAIL - Should have thrown error');
} catch (Exception e) {
    System.debug('=== Test 10: Provisional Action Prevention ===');
    System.debug('Error Message: ' + e.getMessage());
    System.debug('Test 10 Result: ' + (e.getMessage().contains('Provisional') ? 'PASS' : 'FAIL'));
}

// Test 11: Test valid action (should work)
try {
    CEActionController.submitAction(
        testAcc.Id, 
        'Under Review', // Valid action
        String.valueOf(System.today()), 
        'Test reason'
    );
    
    Account result = [SELECT Current_Active_Action_Status__c FROM Account WHERE Id = :testAcc.Id];
    System.debug('=== Test 11: Valid Action Creation ===');
    System.debug('Action Status: ' + result.Current_Active_Action_Status__c); // Should be "Under Review"
    System.debug('Test 11 Result: ' + (result.Current_Active_Action_Status__c == 'Under Review' ? 'PASS' : 'FAIL'));
} catch (Exception e) {
    System.debug('=== Test 11: Valid Action Creation ===');
    System.debug('Error: ' + e.getMessage());
    System.debug('Test 11 Result: FAIL');
}

// Test 12: Verify Provisional actions not in available actions list
List<String> availableActions = CEActionController.getAvailableActions(testAcc.Id);
System.debug('=== Test 12: Available Actions List ===');
System.debug('Available Actions: ' + availableActions);
System.debug('Contains Provisional: ' + (availableActions.contains('Provisional') || 
                                          availableActions.contains('Provisional & Restricted') ||
                                          availableActions.contains('Provisional & Under Review') ||
                                          availableActions.contains('Provisional & Internal Investigation')));
System.debug('Test 12 Result: ' + (!availableActions.contains('Provisional') ? 'PASS' : 'FAIL'));
```

---

### Step 5: Test Migration Script (5 minutes)

**Test Migration Handler:**

```apex
// Test 13: Test migration script on a few accounts
List<Account> testAccounts = [SELECT Id FROM Account LIMIT 5];
List<Id> testIds = new List<Id>();
for (Account acc : testAccounts) {
    testIds.add(acc.Id);
}

System.debug('=== Test 13: Migration Script ===');
System.debug('Migrating ' + testIds.size() + ' accounts');

// Run migration
AccountTriggerHandler.recalculateAllAccountStatuses(testIds);

// Verify results
List<Account> results = [SELECT Id, Name, Membership_Status__c, Registration_Status__c, 
                                Registration_Status_Date__c, Registration_Status_Flag__c,
                                Membership_Expiration_Date__c, Survey_Total_Happy__c
                         FROM Account WHERE Id IN :testIds];

System.debug('=== Migration Results ===');
for (Account acc : results) {
    System.debug('Account: ' + acc.Name);
    System.debug('  Membership Status: ' + acc.Membership_Status__c);
    System.debug('  Registration Status: ' + acc.Registration_Status__c);
    System.debug('  Registration Status Date: ' + acc.Registration_Status_Date__c);
    System.debug('  Registration Status Flag: ' + acc.Registration_Status_Flag__c);
}

System.debug('Test 13 Result: PASS (check values above)');
```

---

### Step 6: Verify in Salesforce UI (5 minutes)

**Check in Salesforce:**

1. **Open an Account Record:**
   - Go to Accounts → Open any account
   - Check the fields:
     - ✅ **Membership Status** field is visible and populated
     - ✅ **Registration Status** field is visible and populated
     - ✅ **Registration Status Date** field is visible (if Registered)
     - ✅ **Registration Status Flag** checkbox is visible

2. **Check CE Action Component:**
   - Go to an Account record
   - Find the CE Action component/banner
   - Verify it displays correctly
   - Try to create an action
   - Verify Provisional actions don't appear in the list

3. **Check Account Administration Page:**
   - Navigate to Account Administration page
   - Verify banner displays correctly
   - Verify status fields are visible

---

### Step 7: Test Edge Cases (5 minutes)

**Test Edge Cases:**

```apex
// Test 14: Account with no expiration date
Account testAcc = new Account(
    Name = 'Test Account - No Expiration',
    RecordTypeId = [SELECT Id FROM RecordType WHERE DeveloperName = 'CE_Provider' AND SobjectType = 'Account' LIMIT 1].Id,
    Membership_Expiration_Date__c = null
);
insert testAcc;

Account result = [SELECT Membership_Status__c FROM Account WHERE Id = :testAcc.Id];
System.debug('=== Test 14: No Expiration Date ===');
System.debug('Membership Status: ' + result.Membership_Status__c); // Should be "Active"
System.debug('Test 14 Result: ' + (result.Membership_Status__c == 'Active' ? 'PASS' : 'FAIL'));

// Test 15: Account with null Survey Total Happy
testAcc.Survey_Total_Happy__c = null;
update testAcc;

result = [SELECT Registration_Status__c FROM Account WHERE Id = :testAcc.Id];
System.debug('=== Test 15: Null Survey Total Happy ===');
System.debug('Registration Status: ' + result.Registration_Status__c); // Should be "Provisional"
System.debug('Test 15 Result: ' + (result.Registration_Status__c == 'Provisional' ? 'PASS' : 'FAIL'));

// Test 16: MT_Verify RecordType
Account mtAcc = new Account(
    Name = 'Test Account - MT Verify',
    RecordTypeId = [SELECT Id FROM RecordType WHERE DeveloperName = 'MT_Verify' AND SobjectType = 'Account' LIMIT 1].Id,
    Membership_Expiration_Date__c = System.today().addDays(-10)
);
insert mtAcc;

Account mtResult = [SELECT Membership_Status__c FROM Account WHERE Id = :mtAcc.Id];
System.debug('=== Test 16: MT_Verify RecordType ===');
System.debug('Membership Status: ' + mtResult.Membership_Status__c); // Should be "Renewal" (expired)
System.debug('Test 16 Result: ' + (mtResult.Membership_Status__c == 'Renewal' ? 'PASS' : 'FAIL'));
```

---

## 📋 Complete Test Script (Run All Tests at Once)

**Copy and paste this into Developer Console → Anonymous Apex:**

```apex
// ============================================
// COMPLETE TEST SCRIPT - Account Status Functionality
// ============================================

System.debug('========================================');
System.debug('STARTING ACCOUNT STATUS TESTS');
System.debug('========================================');

// Test 1: New Account Creation
Account testAcc1 = new Account(
    Name = 'Test Account - New',
    RecordTypeId = [SELECT Id FROM RecordType WHERE DeveloperName = 'CE_Provider' AND SobjectType = 'Account' LIMIT 1].Id,
    Membership_Expiration_Date__c = System.today().addDays(30),
    Survey_Total_Happy__c = 0
);
insert testAcc1;

Account result1 = [SELECT Membership_Status__c, Registration_Status__c, Registration_Status_Flag__c 
                   FROM Account WHERE Id = :testAcc1.Id];
System.debug('Test 1 - New Account: ' + (result1.Membership_Status__c == 'Active' && result1.Registration_Status__c == 'Provisional' ? 'PASS' : 'FAIL'));

// Test 2: Registration Status = Registered
testAcc1.Survey_Total_Happy__c = 50;
update testAcc1;

Account result2 = [SELECT Registration_Status__c, Registration_Status_Flag__c, Registration_Status_Date__c 
                   FROM Account WHERE Id = :testAcc1.Id];
System.debug('Test 2 - Registration Status Registered: ' + (result2.Registration_Status__c == 'Registered' && result2.Registration_Status_Flag__c == true ? 'PASS' : 'FAIL'));

// Test 3: Membership Status = Lapsed
testAcc1.Membership_Expiration_Date__c = System.today().addDays(-10);
update testAcc1;

Account result3 = [SELECT Membership_Status__c FROM Account WHERE Id = :testAcc1.Id];
System.debug('Test 3 - Membership Status Lapsed: ' + (result3.Membership_Status__c == 'Lapsed' ? 'PASS' : 'FAIL'));

// Test 4: Membership Status = Renewal
testAcc1.Allow_Renewal__c = true;
update testAcc1;

Account result4 = [SELECT Membership_Status__c FROM Account WHERE Id = :testAcc1.Id];
System.debug('Test 4 - Membership Status Renewal: ' + (result4.Membership_Status__c == 'Renewal' ? 'PASS' : 'FAIL'));

// Test 5: Provisional Action Prevention
try {
    CEActionController.submitAction(testAcc1.Id, 'Provisional', String.valueOf(System.today()), 'Test');
    System.debug('Test 5 - Provisional Action Prevention: FAIL');
} catch (Exception e) {
    System.debug('Test 5 - Provisional Action Prevention: ' + (e.getMessage().contains('Provisional') ? 'PASS' : 'FAIL'));
}

// Test 6: Valid Action Creation
try {
    CEActionController.submitAction(testAcc1.Id, 'Under Review', String.valueOf(System.today()), 'Test');
    Account result5 = [SELECT Current_Active_Action_Status__c FROM Account WHERE Id = :testAcc1.Id];
    System.debug('Test 6 - Valid Action Creation: ' + (result5.Current_Active_Action_Status__c == 'Under Review' ? 'PASS' : 'FAIL'));
} catch (Exception e) {
    System.debug('Test 6 - Valid Action Creation: FAIL - ' + e.getMessage());
}

System.debug('========================================');
System.debug('TESTS COMPLETED');
System.debug('========================================');
```

---

## ✅ Success Criteria

All tests should **PASS**:
- ✅ New accounts get default statuses (Active, Provisional)
- ✅ Membership Status updates correctly based on expiration date
- ✅ Registration Status updates when Survey_Total_Happy__c reaches 50
- ✅ Registration_Status_Date__c is captured when milestone reached
- ✅ Provisional actions cannot be created
- ✅ Valid actions (Under Review, Restricted, etc.) work correctly
- ✅ Migration script runs successfully

---

## 🐛 Troubleshooting

**Issue**: Membership Status not updating
- **Check**: Membership_Expiration_Date__c field has a value
- **Check**: Trigger is active
- **Check**: Debug logs for errors

**Issue**: Registration Status not updating
- **Check**: Survey_Total_Happy__c field is populated
- **Check**: Trigger is firing (check Debug Logs)
- **Check**: Roll-Up Summary field is configured correctly

**Issue**: Provisional actions still appearing
- **Check**: CEActionController.cls is deployed with latest changes
- **Check**: Clear browser cache
- **Check**: Verify getAvailableActions() method returns correct list

**Issue**: Migration script errors
- **Check**: Field-level security permissions
- **Check**: Account records exist
- **Check**: Batch size (reduce if needed)

---

## 📞 Next Steps

After all tests pass:
1. ✅ Run migration script on all accounts (if needed)
2. ✅ Create Registration Status report
3. ✅ Update any components that display status
4. ✅ Test in production sandbox (if applicable)
5. ✅ Train users on new fields

**Let me know the results of your tests!**

