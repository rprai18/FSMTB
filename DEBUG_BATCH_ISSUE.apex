// ============================================
// COMPREHENSIVE BATCH DEBUGGING SCRIPT
// ============================================
// This will help identify why the batch isn't sending emails

System.debug('=== BATCH DEBUGGING START ===\n');

// Step 1: Check if any memberships match the criteria
Date targetDate = Date.today().addDays(30);
System.debug('Step 1: Looking for memberships expiring on: ' + targetDate);
System.debug('Today is: ' + Date.today());
System.debug('');

List<Membership__c> matchingMemberships = [
    SELECT Id, Account__c, Account__r.Name, Account__r.OwnerId,
           Start_Date__c, Expiration_Date__c
    FROM Membership__c
    WHERE Expiration_Date__c = :targetDate
    AND Account__c != null
    AND Start_Date__c <= TODAY
    AND Expiration_Date__c >= TODAY
];

System.debug('Found ' + matchingMemberships.size() + ' membership(s) matching criteria');
if (matchingMemberships.isEmpty()) {
    System.debug('NO MEMBERSHIPS FOUND - This is why no emails were sent!');
    System.debug('');
    System.debug('Checking all memberships to see what dates exist:');
    List<Membership__c> allMemberships = [
        SELECT Id, Account__c, Expiration_Date__c, Start_Date__c
        FROM Membership__c
        WHERE Account__c != null
        ORDER BY Expiration_Date__c DESC
        LIMIT 10
    ];
    for (Membership__c m : allMemberships) {
        Integer daysUntil = Date.today().daysBetween(m.Expiration_Date__c);
        System.debug('  Membership ' + m.Id + ': Expires ' + m.Expiration_Date__c + ' (' + daysUntil + ' days from today)');
    }
    System.debug('');
    System.debug('SOLUTION: Update a membership expiration date to be exactly 30 days from today: ' + targetDate);
} else {
    System.debug('Memberships found:');
    for (Membership__c m : matchingMemberships) {
        System.debug('  Membership: ' + m.Id);
        System.debug('  Account: ' + m.Account__r.Name + ' (' + m.Account__c + ')');
        System.debug('  Expiration: ' + m.Expiration_Date__c);
        System.debug('');
        
        // Check for future memberships (renewal already complete)
        List<Membership__c> futureMemberships = [
            SELECT Id, Start_Date__c
            FROM Membership__c
            WHERE Account__c = :m.Account__c
            AND Start_Date__c > TODAY
        ];
        
        if (!futureMemberships.isEmpty()) {
            System.debug('  WARNING: Account has ' + futureMemberships.size() + ' future membership(s) - will be EXCLUDED from emails');
            System.debug('  Future membership start dates:');
            for (Membership__c fm : futureMemberships) {
                System.debug('    ' + fm.Start_Date__c);
            }
        } else {
            System.debug('  No future memberships - this membership WILL be processed');
            
            // Check recipients
            System.debug('  Checking recipients...');
            
            // Check Contact Users
            List<User> contactUsers = [
                SELECT Id, FirstName, LastName, Email, IsActive
                FROM User
                WHERE ContactId IN (SELECT Id FROM Contact WHERE AccountId = :m.Account__c)
                AND IsActive = true
                AND Email != null
                LIMIT 1
            ];
            
            if (!contactUsers.isEmpty()) {
                System.debug('    Recipient: Contact User - ' + contactUsers[0].Email);
            } else {
                // Check Account Owner
                if (m.Account__r.OwnerId != null) {
                    List<User> owner = [
                        SELECT Id, Email, IsActive
                        FROM User
                        WHERE Id = :m.Account__r.OwnerId
                        AND IsActive = true
                        AND Email != null
                        LIMIT 1
                    ];
                    if (!owner.isEmpty()) {
                        System.debug('    Recipient: Account Owner - ' + owner[0].Email);
                    } else {
                        System.debug('    ERROR: Account Owner is inactive or has no email');
                    }
                } else {
                    System.debug('    ERROR: Account has no Owner');
                }
            }
        }
        System.debug('');
    }
}

System.debug('');
System.debug('=== EMAIL DELIVERABILITY CHECK ===');
System.debug('IMPORTANT: Go to Setup > Email Administration > Deliverability');
System.debug('Make sure "Access Level" is set to "All Email"');
System.debug('If it\'s "System Email Only", emails won\'t be sent to users');

System.debug('');
System.debug('=== BATCH JOB STATUS ===');
List<AsyncApexJob> recentJobs = [
    SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems, CreatedDate
    FROM AsyncApexJob
    WHERE ApexClass.Name = 'MembershipRenewalReminderBatch'
    ORDER BY CreatedDate DESC
    LIMIT 5
];

System.debug('Recent batch jobs: ' + recentJobs.size());
for (AsyncApexJob job : recentJobs) {
    System.debug('  Job ' + job.Id + ':');
    System.debug('    Status: ' + job.Status);
    System.debug('    Processed: ' + job.JobItemsProcessed + '/' + job.TotalJobItems);
    System.debug('    Errors: ' + job.NumberOfErrors);
    System.debug('    Created: ' + job.CreatedDate);
}

System.debug('');
System.debug('=== DEBUG COMPLETE ===');

