# CE Provider Number – Before-Save Flow Setup (Optional)

CE Provider Number is assigned by the **Account trigger** (no Flow required). If you prefer a Before-Save Flow instead, you can call Apex from Flow (see below).

**No Custom Setting or Custom Metadata.** The next number is computed from `MAX(CE_Provider_Number_Sequence__c)` on Account (CE Provider).

## Prerequisites

1. **Account fields**
   - `CE_Provider_Number__c` (Text, 20) – display value, e.g. CERP-0001100.
   - `CE_Provider_Number_Sequence__c` (Number) – numeric part used to compute the next number.
   Set FLS as required (e.g. Read/Edit for admins, Read-only for CE Therapist permission set).
2. **Apex**: `CeProviderNumberService.getNextNumberAndSequence()` is used by the trigger. For Flow, create a separate **Invocable Apex** action (e.g. a small class with @InvocableMethod that calls `CeProviderNumberService.getNextNumberAndSequence()` and returns the two values) so Flow can call it.

## Build the Flow in Flow Builder

1. **Create the flow**
   - Setup → Flows → New Flow → **Record-Triggered Flow** → Create.

2. **Start element**
   - **Object**: Account  
   - **Trigger the Flow When**: A record is created or updated  
   - **Entry Conditions** (all must be true):
     - **RecordType.DeveloperName** | Equals | **CE_Provider**
     - **CE_Provider_Number__c** | Is Null | (checked)
   - **Optimize the Flow for**: Fast Field Updates  
   - **Do you want to execute the flow only when specified conditions are met?** → Yes, use the same entry conditions above (or add them again in the filter).

3. **Add Action**
   - From **+** after the Start node, add **Action**.
   - Search for **Get Next CE Provider Number** (Apex Action from `CeProviderNumberService`).
   - No input parameters.
   - **Store the output** in resources:
     - **CE Provider Number** → e.g. Text variable `varCEProviderNumber`.
     - **Sequence Number** → e.g. Number variable `varSequenceNumber`.

4. **Assign to record**
   - Add **Assignment**.
   - Set the record’s fields:
     - **CE_Provider_Number__c** = `varCEProviderNumber`
     - **CE_Provider_Number_Sequence__c** = `varSequenceNumber`

5. **Save and activate**
   - Label: **CE Provider Number Assignment**
   - API Name: `CE_Provider_Number_Assignment`
   - Save → Activate.

## Flow vs trigger

- **Flow only**: You can remove the CE Provider Number logic from `AccountTriggerHandler` (method `assignCeProviderNumbers` and its calls in `beforeInsert`/`beforeUpdate`) so only the flow assigns the number.
- **Trigger only**: Leave the flow inactive and keep the trigger logic.
- **Both**: Flow runs first (before save). If the flow sets both fields, the trigger sees them and does not assign again. Safe to have both.

## Concurrency

Under very high concurrency (many CE Provider accounts created at the same time), two records could theoretically get the same next number. For typical CE Provider signup volume this is negligible. To guard against it, add a **unique constraint** on `CE_Provider_Number__c` and handle duplicate errors (e.g. retry or alert).

## Backfill existing records

Run a one-time update (e.g. Data Loader, Flow, or batch Apex) on Accounts where RecordType = CE_Provider and CE_Provider_Number__c is null. Each update will fire the flow (or trigger) and assign the next number.
