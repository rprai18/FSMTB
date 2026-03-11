# Test Data Guide for ceSlbTherapistSearch LWC Component

This guide explains how to manually create test data in Salesforce to test the `ceSlbTherapistSearch` Lightning Web Component.

## Overview

The component searches for therapists (Contacts) with the following search criteria:
- **Search Term**: Name or license number (minimum 3 characters)
- **Last Four SSN**: Last 4 digits of SSN (4 digits)
- **State Filter**: Filter by participating states (optional)

## Required Objects and Fields

### 1. Account (SLB Record Type)
**Purpose**: Represents participating states/territories

**Required Fields:**
- **RecordType**: Must be `SLB` (DeveloperName = 'SLB')
- **BillingStateCode**: State code (e.g., 'CA', 'NY', 'TX', 'FL')
- **Participating__c**: Must be `true`

**Steps to Create:**
1. Go to **Accounts** tab
2. Click **New**
3. Select Record Type: **SLB** (if prompted)
4. Fill in:
   - **Account Name**: e.g., "California State Licensing Board"
   - **Billing State/Province**: Select a state (e.g., California)
   - **Participating**: Check the checkbox
5. Click **Save**

**Example Test Data:**
- Account Name: "California SLB", BillingStateCode: "CA", Participating: ✓
- Account Name: "New York SLB", BillingStateCode: "NY", Participating: ✓
- Account Name: "Texas SLB", BillingStateCode: "TX", Participating: ✓

---

### 2. Contact (TherapistRecord Record Type)
**Purpose**: Represents therapists that can be searched

**Required Fields:**
- **RecordType**: Must be `TherapistRecord` (DeveloperName = 'TherapistRecord')
- **FirstName**: First name
- **LastName**: Last name (required)
- **Middle_Name__c**: Middle name (optional)
- **Previously_Known_As__c**: Also known as / AKA (optional)
- **SSN_Last_4_Digits__c**: Last 4 digits of SSN (for SSN search)

**Optional Fields:**
- **Display_State_Participation_Dialog__c**: Controls whether state participation dialog shows (default: true)

**Steps to Create:**
1. Go to **Contacts** tab
2. Click **New**
3. Select Record Type: **TherapistRecord** (if prompted)
4. Fill in:
   - **First Name**: e.g., "John"
   - **Last Name**: e.g., "Smith" (required)
   - **Middle Name**: e.g., "Michael" (optional)
   - **Previously Known As**: e.g., "Johnny Smith" (optional)
   - **SSN Last 4 Digits**: e.g., "1234" (4 digits, for testing SSN search)
5. Click **Save**

**Example Test Data:**
- FirstName: "John", LastName: "Smith", Middle_Name__c: "Michael", SSN_Last_4_Digits__c: "1234"
- FirstName: "Jane", LastName: "Doe", Previously_Known_As__c: "Jane Smith", SSN_Last_4_Digits__c: "5678"
- FirstName: "Robert", LastName: "Johnson", SSN_Last_4_Digits__c: "9012"

---

### 3. State_Licensing__c (Custom Object)
**Purpose**: Links therapists to their state licenses

**Required Fields:**
- **Contact__c**: Lookup to Contact (the therapist)
- **Account__c**: Lookup to Account (the SLB Account for the state)
- **Number__c**: License number (e.g., "CA12345")

**Steps to Create:**
1. Go to **State Licensing** tab (or use Object Manager if tab doesn't exist)
2. Click **New**
3. Fill in:
   - **Contact**: Select a Contact with TherapistRecord record type
   - **Account**: Select an SLB Account (e.g., California SLB)
   - **Number**: Enter a license number (e.g., "CA12345")
4. Click **Save**

**Example Test Data:**
- Contact: John Smith, Account: California SLB, Number: "CA12345"
- Contact: Jane Doe, Account: New York SLB, Number: "NY67890"
- Contact: John Smith, Account: Texas SLB, Number: "TX11111" (same therapist, multiple licenses)

**Note**: A therapist can have multiple State_Licensing__c records (one per state), and each will appear as a separate row in search results.

---

### 4. Exam__c (Custom Object - for Exam Candidates)
**Purpose**: Represents exam candidates (therapists without state licenses but with FSMTB exams)

**Required Fields:**
- **Contact__c**: Lookup to Contact (the therapist)
- **Source__c**: Must be `FSMTB`

**Steps to Create:**
1. Go to **Exams** tab (or use Object Manager if tab doesn't exist)
2. Click **New**
3. Fill in:
   - **Contact**: Select a Contact with TherapistRecord record type
   - **Source**: Select "FSMTB"
4. Click **Save**

**Example Test Data:**
- Contact: Robert Johnson, Source: "FSMTB"
  - This therapist will appear in search results with blank License State and License Number fields

**Note**: Exam candidates are therapists who have Exam records with Source = 'FSMTB' but NO State_Licensing__c records.

---

## Test Scenarios

### Scenario 1: Search by Name
**Setup:**
- Create Contact: FirstName="John", LastName="Smith"
- Create State_Licensing__c linking to an SLB Account

**Test:**
- Enter "John" or "Smith" in Search Term field
- Click Search
- Should return results matching the name

---

### Scenario 2: Search by Last Four SSN
**Setup:**
- Create Contact: LastName="Doe", SSN_Last_4_Digits__c="5678"
- Create State_Licensing__c linking to an SLB Account

**Test:**
- Enter "5678" in Last Four SSN field
- Click Search
- Should return results matching the SSN

---

### Scenario 3: Search by State Filter
**Setup:**
- Create Account: BillingStateCode="CA", Participating=true
- Create Contact: LastName="Smith"
- Create State_Licensing__c: Contact=Smith, Account=CA Account

**Test:**
- Select "CA" in the state multi-select
- Click Search
- Should return only therapists licensed in California

---

### Scenario 4: Multiple Licenses per Therapist
**Setup:**
- Create Contact: LastName="Smith"
- Create State_Licensing__c: Contact=Smith, Account=CA Account, Number="CA123"
- Create State_Licensing__c: Contact=Smith, Account=NY Account, Number="NY456"

**Test:**
- Search for "Smith"
- Should return 2 rows (one for each license)

---

### Scenario 5: Exam Candidate (No License)
**Setup:**
- Create Contact: LastName="Johnson"
- Create Exam__c: Contact=Johnson, Source="FSMTB"
- Do NOT create any State_Licensing__c records

**Test:**
- Search for "Johnson"
- Should return 1 row with blank License State and License Number
- Row should be visually distinct (exam-candidate-row class)

---

### Scenario 6: Combined Search (Name + SSN + State)
**Setup:**
- Create Account: BillingStateCode="CA", Participating=true
- Create Contact: FirstName="John", LastName="Smith", SSN_Last_4_Digits__c="1234"
- Create State_Licensing__c: Contact=Smith, Account=CA Account

**Test:**
- Enter "John" in Search Term
- Enter "1234" in Last Four SSN
- Select "CA" in states
- Click Search
- Should return matching results

---

## Quick Setup Script (Developer Console)

You can also use this Apex script in Developer Console to quickly create test data:

```apex
// Run this in Developer Console > Execute Anonymous

// 1. Get Record Types
Id slbRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND DeveloperName = 'SLB' LIMIT 1].Id;
Id therapistRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Contact' AND DeveloperName = 'TherapistRecord' LIMIT 1].Id;

// 2. Create SLB Accounts
List<Account> slbAccounts = new List<Account>();
slbAccounts.add(new Account(
    Name = 'California SLB',
    RecordTypeId = slbRecordTypeId,
    BillingStateCode = 'CA',
    Participating__c = true
));
slbAccounts.add(new Account(
    Name = 'New York SLB',
    RecordTypeId = slbRecordTypeId,
    BillingStateCode = 'NY',
    Participating__c = true
));
insert slbAccounts;

// 3. Create Therapist Contacts
List<Contact> therapists = new List<Contact>();
therapists.add(new Contact(
    FirstName = 'John',
    LastName = 'Smith',
    Middle_Name__c = 'Michael',
    RecordTypeId = therapistRecordTypeId,
    SSN_Last_4_Digits__c = '1234'
));
therapists.add(new Contact(
    FirstName = 'Jane',
    LastName = 'Doe',
    Previously_Known_As__c = 'Jane Smith',
    RecordTypeId = therapistRecordTypeId,
    SSN_Last_4_Digits__c = '5678'
));
therapists.add(new Contact(
    FirstName = 'Robert',
    LastName = 'Johnson',
    RecordTypeId = therapistRecordTypeId,
    SSN_Last_4_Digits__c = '9012'
));
insert therapists;

// 4. Create State Licensing Records
List<State_Licensing__c> licenses = new List<State_Licensing__c>();
licenses.add(new State_Licensing__c(
    Contact__c = therapists[0].Id,
    Account__c = slbAccounts[0].Id,
    Number__c = 'CA12345'
));
licenses.add(new State_Licensing__c(
    Contact__c = therapists[0].Id,
    Account__c = slbAccounts[1].Id,
    Number__c = 'NY67890'
));
licenses.add(new State_Licensing__c(
    Contact__c = therapists[1].Id,
    Account__c = slbAccounts[0].Id,
    Number__c = 'CA11111'
));
insert licenses;

// 5. Create Exam Record (for exam candidate)
List<Exam__c> exams = new List<Exam__c>();
exams.add(new Exam__c(
    Contact__c = therapists[2].Id,
    Source__c = 'FSMTB'
));
insert exams;

System.debug('Test data created successfully!');
System.debug('SLB Accounts: ' + slbAccounts.size());
System.debug('Therapists: ' + therapists.size());
System.debug('Licenses: ' + licenses.size());
System.debug('Exams: ' + exams.size());
```

---

## Important Notes

1. **Record Types**: Ensure the Record Types `SLB` (Account) and `TherapistRecord` (Contact) exist in your org.

2. **Field-Level Security**: Make sure your user profile has access to:
   - Contact fields: FirstName, LastName, Middle_Name__c, Previously_Known_As__c, SSN_Last_4_Digits__c
   - State_Licensing__c fields: Contact__c, Account__c, Number__c
   - Exam__c fields: Contact__c, Source__c
   - Account fields: BillingStateCode, Participating__c

3. **Search Functionality**:
   - Search uses SOSL (Salesforce Object Search Language) to find matches in State_Licensing__c records
   - SSN search uses encrypted/hashed SSN values (SHA256 digest)
   - Minimum 3 characters required for search term (cannot be '***')

4. **Geographical Regions**: The component displays participating states from Accounts where `Participating__c = true` and `RecordTypeId = SLB`.

5. **Custom Metadata**: The component may also use `SLB_Community_Content__mdt` for displaying content. This is optional and won't prevent testing if missing.

---

## Testing Checklist

- [ ] Create at least 2-3 SLB Accounts with different states
- [ ] Create at least 3-5 Therapist Contacts with various names
- [ ] Create State_Licensing__c records linking therapists to states
- [ ] Create at least 1 Exam__c record for an exam candidate
- [ ] Test search by name
- [ ] Test search by SSN
- [ ] Test search by state filter
- [ ] Test combined search criteria
- [ ] Verify multiple licenses show as separate rows
- [ ] Verify exam candidates show with blank license fields
- [ ] Test sorting functionality
- [ ] Test infinite scroll (if results > 25)
- [ ] Test "View" button navigation

---

## Troubleshooting

**No results appearing:**
- Check that Contacts have the correct RecordType (`TherapistRecord`)
- Verify State_Licensing__c records are linked correctly
- Ensure search term is at least 3 characters
- Check field-level security permissions

**State filter not working:**
- Verify Account has `Participating__c = true`
- Check Account RecordType is `SLB`
- Ensure BillingStateCode is populated

**Exam candidates not showing:**
- Verify Exam__c record has `Source__c = 'FSMTB'`
- Ensure Contact has NO State_Licensing__c records
- Check Contact RecordType is `TherapistRecord`
