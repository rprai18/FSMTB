# Quick Test Data Checklist for ceSlbTherapistSearch

## Step-by-Step Manual Data Creation

### Step 1: Create SLB Accounts (Participating States)
1. Go to **Accounts** → **New**
2. Record Type: **SLB**
3. Fill in:
   - Account Name: "California SLB"
   - Billing State: California (or any state)
   - ✅ Check **Participating** checkbox
4. Save
5. Repeat for 2-3 more states (e.g., New York, Texas)

### Step 2: Create Therapist Contacts
1. Go to **Contacts** → **New**
2. Record Type: **TherapistRecord**
3. Fill in:
   - First Name: "John"
   - Last Name: "Smith"
   - SSN Last 4 Digits: "1234"
4. Save
5. Repeat for 2-3 more therapists with different names

### Step 3: Create State Licensing Records
1. Go to **State Licensing** tab → **New**
2. Fill in:
   - Contact: Select a therapist (e.g., John Smith)
   - Account: Select an SLB Account (e.g., California SLB)
   - Number: "CA12345"
3. Save
4. Repeat to link therapists to states

### Step 4: Create Exam Record (Optional - for Exam Candidates)
1. Go to **Exams** tab → **New**
2. Fill in:
   - Contact: Select a therapist WITHOUT any State Licensing records
   - Source: "FSMTB"
3. Save

## Quick Test Scenarios

| Test | Search Term | Last 4 SSN | State | Expected Result |
|------|-------------|------------|-------|------------------|
| Name Search | "John" | - | - | Returns John Smith |
| SSN Search | - | "1234" | - | Returns John Smith |
| State Filter | - | - | CA | Returns only CA therapists |
| Combined | "John" | "1234" | CA | Returns John Smith if licensed in CA |
| Exam Candidate | "Robert" | - | - | Returns with blank license fields |

## Minimum Test Data Needed

- ✅ 2-3 SLB Accounts (different states)
- ✅ 3-5 Therapist Contacts
- ✅ 3-5 State Licensing records
- ✅ 1 Exam record (for exam candidate test)

## Common Issues

- **No results?** → Check Record Types are correct
- **State filter empty?** → Verify Account has Participating = true
- **SSN not working?** → Ensure SSN_Last_4_Digits__c is exactly 4 digits
- **Search term error?** → Must be 3+ characters, cannot be '***'
