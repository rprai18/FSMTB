# How to Make the Banner Green (See Green Color)

## 🎯 Why Banner is Orange Right Now

The banner shows **ORANGE** when:
- ✅ Account has an **Action Status** (Under Review, Restricted, Internal Investigation, Revoked)

The banner shows **GREEN** when:
- ✅ Account has **Registration Status = "Provisional"** 
- ✅ AND **NO Action Status** (Action Status = null)

---

## ✅ Quick Fix: Make Banner Green

### Option 1: Clear Action Status (Recommended)

If your account has an Action Status, clear it to see green:

```apex
// Get your account
Account acc = [SELECT Id, Current_Active_Action_Status__c FROM Account WHERE Id = 'YOUR_ACCOUNT_ID' LIMIT 1];

// Clear Action Status
acc.Current_Active_Action_Status__c = null;
update acc;
```

**Result**: Banner will turn GREEN if Registration Status = "Provisional"

---

### Option 2: Use the Script

Run the script I created: `MAKE_BANNER_GREEN.txt`

This script will:
1. ✅ Check your current account statuses
2. ✅ Clear Action Status if it exists
3. ✅ Set Registration Status to "Provisional" if needed
4. ✅ Make banner green

---

## 📋 Step-by-Step Instructions

### Step 1: Check Current Statuses

Run this in Developer Console:

```apex
// Get current user's account
User currentUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
Account acc = [SELECT Id, Name, Registration_Status__c, Current_Active_Action_Status__c FROM Account WHERE Id = :currentUser.AccountId LIMIT 1];

System.debug('Registration Status: ' + acc.Registration_Status__c);
System.debug('Action Status: ' + acc.Current_Active_Action_Status__c);
```

### Step 2: Make Banner Green

**If Action Status exists:**
```apex
Account accUpdate = new Account(Id = acc.Id);
accUpdate.Current_Active_Action_Status__c = null;
update accUpdate;
```

**If Registration Status is not "Provisional":**
```apex
Account accUpdate = new Account(Id = acc.Id);
accUpdate.Registration_Status__c = 'Provisional';
update accUpdate;
```

### Step 3: Refresh the Page

After updating:
1. ✅ Go to the Community page with the banner
2. ✅ Refresh the page (F5 or Ctrl+R)
3. ✅ Banner should now be GREEN

---

## 🎨 Banner Color Logic

| Registration Status | Action Status | Banner Color |
|-------------------|--------------|--------------|
| "Provisional" | null | ✅ **GREEN** |
| "Provisional" | "Under Review" | ❌ Orange |
| "Provisional" | "Restricted" | ❌ Orange |
| "Registered" | null | Hidden |
| "Registered" | "Under Review" | ❌ Orange |

---

## ✅ Quick Test Script

Copy and paste this into Developer Console:

```apex
// Quick script to make banner green
User currentUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];

if (currentUser.AccountId != null) {
    Account acc = [SELECT Id, Registration_Status__c, Current_Active_Action_Status__c FROM Account WHERE Id = :currentUser.AccountId LIMIT 1];
    
    Account accUpdate = new Account(Id = acc.Id);
    
    // Clear Action Status to see green
    accUpdate.Current_Active_Action_Status__c = null;
    
    // Ensure Registration Status is Provisional
    if (acc.Registration_Status__c != 'Provisional') {
        accUpdate.Registration_Status__c = 'Provisional';
    }
    
    update accUpdate;
    
    System.debug('✅ Account updated! Banner should be GREEN now.');
    System.debug('Registration Status: ' + accUpdate.Registration_Status__c);
    System.debug('Action Status: null');
}
```

---

## 🔍 Why It's Orange

The banner shows **ORANGE** because:

1. **Priority Logic**: Action Statuses take priority over Registration Status
   - If Action Status exists → Orange
   - If only Registration Status = "Provisional" → Green

2. **Combined Status**: If both statuses exist, banner shows Orange with combined message

---

## ✅ Solution

To see **GREEN** banner:

1. ✅ Ensure `Registration_Status__c = "Provisional"`
2. ✅ Clear `Current_Active_Action_Status__c = null`
3. ✅ Refresh the page
4. ✅ Banner will be GREEN

---

## 🚀 After Making Changes

1. **Refresh the page** in your browser
2. **Check the banner** - it should be GREEN
3. **Check browser console** - look for "Banner Status Result" logs

The banner will automatically update when you refresh the page!

---

## 📝 Notes

- **Action Status** takes priority - if it exists, banner is orange
- **Registration Status** shows green only when Action Status is null
- **Refresh page** after updating statuses to see changes

---

**To see GREEN banner right now:**
1. Run the script above
2. Refresh the page
3. Banner should be GREEN! ✅

