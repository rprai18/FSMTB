// ============================================
// CHECK WHY BATCH ISN'T SENDING EMAIL
// ============================================

String membershipId = 'a08RT00000YAxa3YAD';
String accountId = '001RT00000U0InHYAR';

System.debug('=== CHECKING WHY BATCH ISN\'T SENDING EMAIL ===\n');

// Check if membership matches batch criteria
Date targetDate = Date.today().addDays(30);
Membership__c m = [
    SELECT Id, Account__c, Expiration_Date__c, Start_Date__c
    FROM Membership__c
    WHERE Id = :membershipId
];

System.debug('Membership Expiration: ' + m.Expiration_Date__c);
System.debug('Target Date (30 days from today): ' + targetDate);
System.debug('Matches criteria? ' + (m.Expiration_Date__c == targetDate));
System.debug('');

// Check for future memberships (this would exclude it from batch)
List<Membership__c> futureMemberships = [
    SELECT Id, Start_Date__c, Expiration_Date__c
    FROM Membership__c
    WHERE Account__c = :accountId
    AND Start_Date__c > TODAY
    ORDER BY Start_Date__c ASC
];

System.debug('Future Memberships (Start_Date > TODAY): ' + futureMemberships.size());
if (!futureMemberships.isEmpty()) {
    System.debug('WARNING: Account has future membership(s) - Batch will EXCLUDE this membership!');
    for (Membership__c fm : futureMemberships) {
        System.debug('  Future Membership: ' + fm.Id);
        System.debug('    Start Date: ' + fm.Start_Date__c);
        System.debug('    Expiration Date: ' + fm.Expiration_Date__c);
    }
    System.debug('');
    System.debug('SOLUTION: Delete or update the future membership(s) to allow reminder emails');
} else {
    System.debug('No future memberships found - Membership should be processed by batch');
}

System.debug('');
System.debug('=== TESTING BATCH QUERY DIRECTLY ===');
List<Membership__c> batchResults = [
    SELECT Id, Account__c, Expiration_Date__c
    FROM Membership__c
    WHERE Expiration_Date__c = :targetDate
    AND Account__c != null
    AND Start_Date__c <= TODAY
    AND Expiration_Date__c >= TODAY
    AND Id = :membershipId
];

System.debug('Batch query found ' + batchResults.size() + ' membership(s)');
if (batchResults.isEmpty()) {
    System.debug('Membership NOT found by batch query!');
    System.debug('Checking why...');
    System.debug('  Expiration matches? ' + (m.Expiration_Date__c == targetDate));
    System.debug('  Account not null? ' + (m.Account__c != null));
    System.debug('  Start Date <= TODAY? ' + (m.Start_Date__c <= Date.today()));
    System.debug('  Expiration >= TODAY? ' + (m.Expiration_Date__c >= Date.today()));
} else {
    System.debug('Membership WILL be found by batch query');
}

System.debug('');
System.debug('=== RECOMMENDATION ===');
if (!futureMemberships.isEmpty()) {
    System.debug('1. Delete or update future membership(s) to allow emails');
} else if (batchResults.isEmpty()) {
    System.debug('1. Membership doesn\'t match batch criteria - check dates');
} else {
    System.debug('1. Membership should be processed - check Email Deliverability settings');
    System.debug('2. Go to Setup > Email Administration > Deliverability');
    System.debug('3. Set Access Level to "All Email"');
    System.debug('4. Run batch again and check debug logs');
}

