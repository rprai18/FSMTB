// ============================================
// QUICK EMAIL RECIPIENT CHECK
// ============================================
// Replace with your Membership ID
String membershipId = 'a08RT00000YAxa3YAD';

// Get Membership
Membership__c m = [
    SELECT Account__c, Account__r.Name, Account__r.OwnerId, 
           Account__r.Owner.Email, Account__r.Owner.IsActive,
           Expiration_Date__c
    FROM Membership__c
    WHERE Id = :membershipId
    LIMIT 1
];

System.debug('=== EMAIL RECIPIENT CHECK ===');
System.debug('Membership: ' + m.Id);
System.debug('Account: ' + m.Account__r.Name);
System.debug('Expiration: ' + m.Expiration_Date__c);
System.debug('Days until expiration: ' + Date.today().daysBetween(m.Expiration_Date__c));
System.debug('');

// Check Contact Users (Priority 1)
List<User> contactUsers = [
    SELECT Id, FirstName, LastName, Email, IsActive
    FROM User
    WHERE ContactId IN (SELECT Id FROM Contact WHERE AccountId = :m.Account__c)
    AND IsActive = true
    AND Email != null
    LIMIT 1
];

if (!contactUsers.isEmpty()) {
    User recipient = contactUsers[0];
    System.debug('EMAIL WILL GO TO: Contact User');
    System.debug('Name: ' + recipient.FirstName + ' ' + recipient.LastName);
    System.debug('Email: ' + recipient.Email);
} else {
    // Check Account Owner (Priority 2)
    if (m.Account__r.OwnerId != null) {
        User owner = [
            SELECT Id, FirstName, LastName, Email, IsActive
            FROM User
            WHERE Id = :m.Account__r.OwnerId
            AND IsActive = true
            AND Email != null
            LIMIT 1
        ];
        
        if (owner != null) {
            System.debug('EMAIL WILL GO TO: Account Owner');
            System.debug('Name: ' + owner.FirstName + ' ' + owner.LastName);
            System.debug('Email: ' + owner.Email);
        } else {
            System.debug('NO RECIPIENT FOUND');
            System.debug('Account Owner is inactive or has no email');
        }
    } else {
        System.debug('NO RECIPIENT FOUND');
        System.debug('No Contact Users and no Account Owner');
    }
}

System.debug('');
System.debug('Check this email inbox for the renewal reminder!');

