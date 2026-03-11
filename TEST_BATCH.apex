// ============================================
// TEST SCRIPT FOR MembershipRenewalReminderBatch
// ============================================
// Copy and paste this into Developer Console > Execute Anonymous Window
// OR Setup > Apex > Apex Execute Anonymous

// OPTION 1: Run the batch as-is (will only find memberships expiring in exactly 30 days)
System.debug('=== Starting MembershipRenewalReminderBatch Test ===');
MembershipRenewalReminderBatch batch = new MembershipRenewalReminderBatch();
Id jobId = Database.executeBatch(batch, 200);
System.debug('Batch job started with ID: ' + jobId);
System.debug('Check Setup > Apex Jobs to see the job status');

// OPTION 2: Test with your current membership (1/15/2026 expiration)
// First, update the membership expiration to be exactly 30 days from today
Date today = Date.today();
Date targetExpiration = today.addDays(30);

System.debug('Today: ' + today);
System.debug('Target expiration for batch (30 days from today): ' + targetExpiration);

// Find your membership record
List<Membership__c> memberships = [
    SELECT Id, Account__c, Expiration_Date__c, Start_Date__c
    FROM Membership__c
    WHERE Expiration_Date__c = Date.valueOf('2026-01-15')
    LIMIT 1
];

if (!memberships.isEmpty()) {
    Membership__c m = memberships[0];
    System.debug('Found membership: ' + m.Id);
    System.debug('Current expiration: ' + m.Expiration_Date__c);
    System.debug('Days until expiration: ' + today.daysBetween(m.Expiration_Date__c));
    
    // Uncomment the next 3 lines to update expiration to 30 days from today
    // m.Expiration_Date__c = targetExpiration;
    // update m;
    // System.debug('Updated expiration to: ' + targetExpiration);
    
    // Now run the batch
    // MembershipRenewalReminderBatch batch = new MembershipRenewalReminderBatch();
    // Database.executeBatch(batch, 200);
}

System.debug('=== Test Complete ===');

