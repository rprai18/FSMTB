# Testing MembershipRenewalReminderBatch

## Quick Test Steps

### Step 1: Update Membership Expiration Date
In Salesforce, update your Membership record's Expiration Date to be exactly **30 days from today**.

For example, if today is January 8, 2026, set Expiration Date to **February 7, 2026**.

### Step 2: Run the Batch Manually

#### Option A: Using Developer Console
1. Go to **Setup** > **Developer Console** (or press `Ctrl+Alt+D` / `Cmd+Alt+D`)
2. Click **Debug** > **Open Execute Anonymous Window**
3. Paste this code:
```apex
MembershipRenewalReminderBatch batch = new MembershipRenewalReminderBatch();
Database.executeBatch(batch, 200);
```
4. Check **"Open Log"** checkbox
5. Click **Execute**
6. Check the debug log for results

#### Option B: Using Anonymous Apex (Setup)
1. Go to **Setup** > **Apex** > **Apex Execute Anonymous**
2. Paste the same code:
```apex
MembershipRenewalReminderBatch batch = new MembershipRenewalReminderBatch();
Database.executeBatch(batch, 200);
```
3. Click **Execute**

### Step 3: Check Results

#### Check Debug Logs:
1. Go to **Setup** > **Debug Logs**
2. Look for logs with "MembershipRenewalReminderBatch"
3. Search for:
   - "Prepared email for Membership"
   - "Sent X emails successfully"
   - Any error messages

#### Check Email Deliverability:
1. Go to **Setup** > **Email Administration** > **Deliverability**
2. Make sure **"Access Level"** is set to **"All Email"** (for testing)
3. If set to "System Email Only", emails won't be sent to users

#### Check Email History:
1. Go to the **Membership** record
2. Check the **Activity History** or **Email History** related list
3. You should see the email sent

#### Check User's Email:
- The email should be sent to:
  1. First priority: Active User linked to Contact on the Account
  2. Second priority: Account Owner

## Alternative: Test with Different Days

If you want to test with your current expiration date (1/15/2026), you can temporarily change the batch to check for a different number of days:

### Temporary Code Change:
In `MembershipRenewalReminderBatch.cls`, change line 8:
```apex
private static final Integer REMINDER_DAYS = 7; // Change from 30 to 7 for testing
```

Then calculate: If expiration is 1/15/2026, and today is 1/8/2026, that's 7 days away.

## Schedule the Batch (Production)

Once testing is complete, schedule it to run daily:

1. Go to **Setup** > **Apex** > **Schedule Apex**
2. Click **Schedule Apex**
3. Select **MembershipRenewalReminderBatch**
4. Set:
   - **Job Name**: "Membership Renewal Reminder Daily"
   - **Frequency**: Daily
   - **Start Time**: 2:00 AM (or your preferred time)
5. Click **Save**

## Troubleshooting

### No emails sent?
1. Check **Deliverability** settings (must be "All Email")
2. Verify the Membership expiration date is exactly 30 days from today
3. Check if Account has a future Membership (renewal already complete - these are excluded)
4. Verify the Account has a valid User or Account Owner with email
5. Check debug logs for error messages

### Email template not found?
- The batch will generate email content automatically if template doesn't exist
- To create a template: Setup > Email Templates > New Template
- Developer Name: `Membership_Renewal_Reminder`

### Batch not finding memberships?
- Verify: `Expiration_Date__c = TODAY + 30 days` (exactly)
- Verify: `Start_Date__c <= TODAY` (membership is current)
- Verify: `Expiration_Date__c >= TODAY` (not expired)
- Verify: `Account__c != null`

