# How to Make the Action Banner Green in Salesforce

## 🎯 Goal
Make the action banner turn **GREEN** when Registration Status = "Provisional"

## 📋 Current Situation
- Banner currently reads from `Current_Active_Action_Status__c` field
- Banner shows green when status contains "Provisional"
- But now "Provisional" is in `Registration_Status__c` field (not in Action Status)
- Banner won't show green anymore because Action Status doesn't have "Provisional"

## ✅ Solution
Update the banner component to read `Registration_Status__c` field and show green banner when status is "Provisional"

---

## 📝 Steps to Make Banner Green

### Step 1: Update CEBannerController to Return Both Statuses

The controller needs to return both Registration Status and Action Status so the banner can decide which color to show.

### Step 2: Update ceActionBanner Component

The component needs to:
- Read `Registration_Status__c` field
- Show **GREEN banner** when `Registration_Status__c = "Provisional"`
- Show **ORANGE banner** when Action Status has values (Under Review, Restricted, etc.)
- Show **GREEN banner** when both Provisional Registration AND action status

### Step 3: Deploy the Changes

Deploy the updated component to Salesforce.

---

## 🎨 Banner Color Logic

**Green Banner** shows when:
- `Registration_Status__c = "Provisional"` (hasn't reached 50 surveys)

**Orange Banner** shows when:
- `Current_Active_Action_Status__c = "Under Review"` or other action statuses

**Green Banner with Orange** shows when:
- Both Provisional Registration AND Action Status

---

## 📂 Files to Update

1. **CEBannerController.cls** - Update to return both Registration Status and Action Status
2. **ceActionBanner.js** - Update to check Registration_Status__c field
3. **ceActionBanner.html** - No changes needed (already uses bannerClass)

---

## 🚀 Quick Fix Options

### Option 1: Update Banner to Use Registration_Status__c
Update the component to read `Registration_Status__c` instead of `Current_Active_Action_Status__c` for Provisional status.

### Option 2: Pass Both Fields
Update the component to accept both fields and check Registration_Status__c for green banner.

---

## ✅ Recommended Approach

Update `ceActionBanner` to:
1. Read `Registration_Status__c` field
2. Read `Current_Active_Action_Status__c` field  
3. Show green when `Registration_Status__c = "Provisional"`
4. Show orange when Action Status has values

This way:
- ✅ Green banner shows for Provisional Registration Status
- ✅ Orange banner shows for Action Statuses
- ✅ Both can work together

