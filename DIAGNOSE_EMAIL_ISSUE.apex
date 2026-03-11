// ============================================
// DIAGNOSTIC SCRIPT - Check Why Email Wasn't Sent
// ============================================
// Copy and paste this into Developer Console > Execute Anonymous Window
// This will help identify why you didn't receive the email

// Replace with your Membership ID or Account ID
String membershipId = 'a08RT00000YAxa3YAD'; // Your Membership ID from the URL
// OR use Account ID:
// String accountId = 'YOUR_ACCOUNT_ID_HERE';

System.debug('=== EMAIL RECIPIENT DIAGNOSTIC ===\n');

// Get the Membership record
Membership__c membership = [
    SELECT Id, Account__c, Account__r.Name, Account__r.OwnerId, 
           Account__r.Owner.Name, Account__r.Owner.Email, Account__r.Owner.IsActive,
           Start_Date__c, Expiration_Date__c
    FROM Membership__c
    WHERE Id = :membershipId
    LIMIT 1
];

System.debug('Membership: ' + membership.Id);
System.debug('Account: ' + membership.Account__r.Name + ' (' + membership.Account__c + ')');
System.debug('Expiration Date: ' + membership.Expiration_Date__c);
System.debug('Days until expiration: ' + Date.today().daysBetween(membership.Expiration_Date__c));
System.debug('');

// Check Priority 1: Contact Users
System.debug('=== PRIORITY 1: Contact Users ===');
List<Contact> contacts = [
    SELECT Id, FirstName, LastName, Email, AccountId
    FROM Contact
    WHERE AccountId = :membership.Account__c
    AND Email != null
];

System.debug('Found ' + contacts.size() + ' Contact(s) on Account');
if (contacts.isEmpty()) {
    System.debug('NO CONTACTS FOUND - Will use Account Owner instead');
} else {
    for (Contact c : contacts) {
        System.debug('  Contact: ' + c.FirstName + ' ' + c.LastName + ' (' + c.Email + ')');
        
        // Check if Contact has a User
        List<User> contactUsers = [
            SELECT Id, FirstName, LastName, Email, IsActive, ContactId
            FROM User
            WHERE ContactId = :c.Id
            AND IsActive = true
            AND Email != null
        ];
        
        if (contactUsers.isEmpty()) {
            System.debug('    No active User linked to this Contact');
        } else {
            for (User u : contactUsers) {
                System.debug('    User found: ' + u.FirstName + ' ' + u.LastName + ' (' + u.Email + ') - ACTIVE');
                System.debug('       THIS USER WILL RECEIVE THE EMAIL');
            }
        }
    }
}

System.debug('');

// Check Priority 2: Account Owner
System.debug('=== PRIORITY 2: Account Owner ===');
if (membership.Account__r.OwnerId == null) {
    System.debug('Account Owner is NULL');
} else {
    System.debug('Account Owner ID: ' + membership.Account__r.OwnerId);
    System.debug('Account Owner Name: ' + membership.Account__r.Owner.Name);
    System.debug('Account Owner Email: ' + membership.Account__r.Owner.Email);
    System.debug('Account Owner IsActive: ' + membership.Account__r.Owner.IsActive);
    
    if (!membership.Account__r.Owner.IsActive) {
        System.debug('Account Owner is NOT ACTIVE');
    } else if (String.isBlank(membership.Account__r.Owner.Email)) {
        System.debug('Account Owner has NO EMAIL');
    } else {
        System.debug('Account Owner is valid - WILL RECEIVE EMAIL if no Contact User found');
    }
}

System.debug('');

// Check if email was actually sent (check EmailMessage or Task records)
System.debug('=== EMAIL HISTORY CHECK ===');
List<EmailMessage> emailMessages = [
    SELECT Id, ToAddress, Subject, CreatedDate, Status
    FROM EmailMessage
    WHERE RelatedToId = :membership.Id
    AND CreatedDate = TODAY
    ORDER BY CreatedDate DESC
    LIMIT 5
];

System.debug('Found ' + emailMessages.size() + ' email(s) sent today for this Membership');
if (emailMessages.isEmpty()) {
    System.debug('NO EMAILS FOUND - Email was not sent');
} else {
    for (EmailMessage em : emailMessages) {
        System.debug('  Email sent to: ' + em.ToAddress);
        System.debug('  Subject: ' + em.Subject);
        System.debug('  Status: ' + em.Status);
        System.debug('  Date: ' + em.CreatedDate);
    }
}

// Check Tasks (if SaveAsActivity = true)
List<Task> tasks = [
    SELECT Id, Subject, WhoId, WhatId, CreatedDate, Status
    FROM Task
    WHERE WhatId = :membership.Id
    AND CreatedDate = TODAY
    AND Subject LIKE '%Renewal%'
    ORDER BY CreatedDate DESC
    LIMIT 5
];

System.debug('Found ' + tasks.size() + ' Task(s) created today for this Membership');
if (!tasks.isEmpty()) {
    for (Task t : tasks) {
        System.debug('  Task: ' + t.Subject + ' - Status: ' + t.Status);
    }
}

System.debug('');

// Check Email Deliverability Settings
System.debug('=== EMAIL DELIVERABILITY CHECK ===');
System.debug('IMPORTANT: Go to Setup > Email Administration > Deliverability');
System.debug('   Make sure "Access Level" is set to "All Email" for testing');
System.debug('   If it\'s "System Email Only", emails won\'t be sent to users');

System.debug('');
System.debug('=== SUMMARY ===');
System.debug('Based on the batch logic:');
System.debug('1. If Contact Users exist → First active Contact User receives email');
System.debug('2. If NO Contact Users → Account Owner receives email');
System.debug('3. If NEITHER exists → Email is NOT sent (logged in debug)');

