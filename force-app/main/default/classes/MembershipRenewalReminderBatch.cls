/**
 * Batch class to send reminder emails 30 days before membership expiration
 * Runs daily to check for memberships expiring in 30 days and sends renewal reminder emails
 */
global class MembershipRenewalReminderBatch implements Database.Batchable<sObject>, Schedulable {
    
    // Number of days before expiration to send reminder (default: 30)
    private static final Integer REMINDER_DAYS = 30;
    
    /**
     * Schedulable execute method - allows scheduling via Setup > Apex > Schedule Apex
     */
    global void execute(SchedulableContext ctx) {
        Database.executeBatch(new MembershipRenewalReminderBatch(), 200);
    }
    
    /**
     * Batch start method - queries memberships expiring in exactly 30 days
     */
    global Database.QueryLocator start(Database.BatchableContext bc) {
        Date reminderDate = Date.today().addDays(REMINDER_DAYS);
        
        System.debug('MembershipRenewalReminderBatch: Querying memberships expiring on: ' + reminderDate);
        
        // Query memberships that:
        // 1. Expire in exactly 30 days
        // 2. Are current (Start_Date <= TODAY <= Expiration_Date)
        // 3. Have an associated Account
        // Note: We'll filter out accounts with future memberships in the execute method
        return Database.getQueryLocator([
            SELECT Id, Account__c, Account__r.Name, Account__r.OwnerId, 
                   Start_Date__c, Expiration_Date__c,
                   Account__r.Owner.Email, Account__r.Owner.Name
            FROM Membership__c
            WHERE Expiration_Date__c = :reminderDate
            AND Account__c != null
            AND Start_Date__c <= TODAY
            AND Expiration_Date__c >= TODAY
        ]);
    }
    
    /**
     * Batch execute method - processes each membership and sends reminder email
     */
    global void execute(Database.BatchableContext bc, List<Membership__c> memberships) {
        System.debug('MembershipRenewalReminderBatch.execute: Processing ' + memberships.size() + ' membership(s)');
        
        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        List<Id> accountIds = new List<Id>();
        Set<Id> accountIdsWithFutureMemberships = new Set<Id>();
        
        // Collect account IDs
        for (Membership__c membership : memberships) {
            accountIds.add(membership.Account__c);
            System.debug('Processing Membership: ' + membership.Id + ', Account: ' + membership.Account__c + ', Expiration: ' + membership.Expiration_Date__c);
        }
        
        // Find accounts that have future memberships (renewal already completed)
        // These should be excluded from reminder emails
        for (Membership__c futureMembership : [
            SELECT Account__c
            FROM Membership__c
            WHERE Account__c IN :accountIds
            AND Start_Date__c > TODAY
        ]) {
            accountIdsWithFutureMemberships.add(futureMembership.Account__c);
        }
        
        System.debug('Found ' + accountIdsWithFutureMemberships.size() + ' account(s) with future memberships (will be excluded)');
        
        // Filter out memberships for accounts that already have future memberships
        List<Membership__c> membershipsToProcess = new List<Membership__c>();
        for (Membership__c membership : memberships) {
            if (!accountIdsWithFutureMemberships.contains(membership.Account__c)) {
                membershipsToProcess.add(membership);
            } else {
                System.debug('Skipping Membership ' + membership.Id + ' - Account has future membership (renewal complete)');
            }
        }
        
        System.debug('After filtering, ' + membershipsToProcess.size() + ' membership(s) will be processed');
        
        // Update the loop to use filtered list
        memberships = membershipsToProcess;
        
        if (memberships.isEmpty()) {
            System.debug('No memberships to process after filtering');
            return;
        }
        
        // Get all contacts for these accounts to find users
        Map<Id, List<Contact>> contactsByAccount = new Map<Id, List<Contact>>();
        for (Contact c : [
            SELECT Id, AccountId, Email
            FROM Contact
            WHERE AccountId IN :accountIds
            AND Email != null
        ]) {
            if (!contactsByAccount.containsKey(c.AccountId)) {
                contactsByAccount.put(c.AccountId, new List<Contact>());
            }
            contactsByAccount.get(c.AccountId).add(c);
        }
        
        // Get all users linked to these contacts
        Map<Id, User> usersByContact = new Map<Id, User>();
        Set<Id> contactIds = new Set<Id>();
        for (List<Contact> contacts : contactsByAccount.values()) {
            for (Contact c : contacts) {
                contactIds.add(c.Id);
            }
        }
        
        for (User u : [
            SELECT Id, ContactId, Email, FirstName, LastName, IsActive
            FROM User
            WHERE ContactId IN :contactIds
            AND IsActive = true
            AND Email != null
        ]) {
            usersByContact.put(u.ContactId, u);
        }
        
        // Build renewal URL - construct based on site
        String siteBaseUrl = getSiteBaseUrl();
        
        // Process each membership
        for (Membership__c membership : memberships) {
            try {
                Id targetUserId = null;
                String recipientEmail = null;
                String recipientName = null;
                
                // Priority 1: Find active User linked to Contact on the Account
                if (contactsByAccount.containsKey(membership.Account__c)) {
                    for (Contact c : contactsByAccount.get(membership.Account__c)) {
                        if (usersByContact.containsKey(c.Id)) {
                            User u = usersByContact.get(c.Id);
                            targetUserId = u.Id;
                            recipientEmail = u.Email;
                            recipientName = (u.FirstName != null ? u.FirstName + ' ' : '') + (u.LastName != null ? u.LastName : '');
                            break; // Use first active user found
                        }
                    }
                }
                
                // Priority 2: Use Account Owner if no Contact User found
                if (targetUserId == null && membership.Account__r.OwnerId != null) {
                    try {
                        User owner = [
                            SELECT Id, Email, FirstName, LastName, IsActive
                            FROM User
                            WHERE Id = :membership.Account__r.OwnerId
                            AND IsActive = true
                            AND Email != null
                            LIMIT 1
                        ];
                        if (owner != null) {
                            targetUserId = owner.Id;
                            recipientEmail = owner.Email;
                            recipientName = (owner.FirstName != null ? owner.FirstName + ' ' : '') + (owner.LastName != null ? owner.LastName : '');
                        }
                    } catch (Exception e) {
                        System.debug('Error querying Account Owner: ' + e.getMessage());
                    }
                }
                
                // Skip if no valid recipient found
                if (targetUserId == null || String.isBlank(recipientEmail)) {
                    System.debug('ERROR: No valid recipient found for Membership: ' + membership.Id + ', Account: ' + membership.Account__c);
                    System.debug('  - Contact Users checked: ' + (contactsByAccount.containsKey(membership.Account__c) ? contactsByAccount.get(membership.Account__c).size() : 0));
                    System.debug('  - Account Owner ID: ' + membership.Account__r.OwnerId);
                    continue;
                }
                
                System.debug('Found recipient for Membership ' + membership.Id + ': ' + recipientEmail + ' (User ID: ' + targetUserId + ')');
                
                // Build renewal URL
                String renewalUrl = siteBaseUrl + '/ce-registry?paymentType=renewal';
                
                // Create email message - always generate content directly (no template)
                Messaging.SingleEmailMessage email = new Messaging.SingleEmailMessage();
                email.setTargetObjectId(targetUserId);
                email.setSaveAsActivity(true);
                
                // Generate email content directly
                String subject = 'Membership Renewal Reminder - ' + membership.Account__r.Name;
                String body = generateEmailBody(membership, renewalUrl, recipientName);
                
                email.setSubject(subject);
                email.setHtmlBody(body);
                email.setPlainTextBody(body.stripHtmlTags());
                
                emails.add(email);
                
                System.debug('Prepared email for Membership: ' + membership.Id + 
                           ', Account: ' + membership.Account__r.Name + 
                           ', Recipient: ' + recipientEmail);
                
            } catch (Exception e) {
                System.debug('Error preparing email for Membership ' + membership.Id + ': ' + e.getMessage());
                System.debug('Stack trace: ' + e.getStackTraceString());
            }
        }
        
        // Send emails
        if (!emails.isEmpty()) {
            try {
                Messaging.SendEmailResult[] results = Messaging.sendEmail(emails, false);
                
                Integer successCount = 0;
                Integer failureCount = 0;
                
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        successCount++;
                    } else {
                        failureCount++;
                        System.debug('Email send failed: ' + results[i].getErrors());
                    }
                }
                
                System.debug('MembershipRenewalReminderBatch: Sent ' + successCount + ' emails successfully, ' + failureCount + ' failed');
                
            } catch (Exception e) {
                System.debug('Error sending emails: ' + e.getMessage());
                System.debug('Stack trace: ' + e.getStackTraceString());
            }
        }
    }
    
    /**
     * Batch finish method - called after all batches complete
     */
    global void finish(Database.BatchableContext bc) {
        System.debug('MembershipRenewalReminderBatch: Finished processing all memberships');
        
        // Optionally send a summary email to admins
        AsyncApexJob job = [
            SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems
            FROM AsyncApexJob
            WHERE Id = :bc.getJobId()
        ];
        
        System.debug('Job Status: ' + job.Status + 
                     ', Processed: ' + job.JobItemsProcessed + 
                     '/' + job.TotalJobItems + 
                     ', Errors: ' + job.NumberOfErrors);
    }
    
    /**
     * Get the base URL for the community site
     */
    private static String getSiteBaseUrl() {
        try {
            // Try to get the site URL
            String siteUrl = Site.getBaseUrl();
            if (String.isNotBlank(siteUrl)) {
                return siteUrl;
            }
        } catch (Exception e) {
            System.debug('Error getting Site base URL: ' + e.getMessage());
        }
        
        // Fallback: construct from organization URL
        try {
            Organization org = [SELECT InstanceName FROM Organization LIMIT 1];
            String instance = org.InstanceName.toLowerCase();
            return 'https://' + instance + '.salesforce.com';
        } catch (Exception e) {
            System.debug('Error getting Organization: ' + e.getMessage());
        }
        
        // Final fallback - use System.URL.getOrgDomainUrl() (available from API 58.0+)
        try {
            return System.URL.getOrgDomainUrl().toExternalForm();
        } catch (Exception e) {
            System.debug('Error getting org domain URL: ' + e.getMessage());
            // Last resort fallback
            return 'https://login.salesforce.com';
        }
    }
    
    /**
     * Generate email body content if template is not available
     */
    private static String generateEmailBody(Membership__c membership, String renewalUrl, String recipientName) {
        String greeting = String.isNotBlank(recipientName) ? recipientName : 'Valued Customer';
        String expirationDate = membership.Expiration_Date__c != null 
            ? membership.Expiration_Date__c.format() 
            : 'soon';
        String accountName = membership.Account__r.Name != null 
            ? membership.Account__r.Name 
            : 'your account';
        
        String htmlBody = '<html><body>';
        htmlBody += '<p>Dear ' + greeting + ',</p>';
        htmlBody += '<p>This is a reminder that your CE Provider membership for <strong>' + accountName + '</strong> will expire on <strong>' + expirationDate + '</strong> (30 days from today).</p>';
        htmlBody += '<p>To ensure uninterrupted access to the CE Registry, please renew your membership before the expiration date.</p>';
        htmlBody += '<p><a href="' + renewalUrl + '" style="background-color: #0070D2; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; display: inline-block; margin: 10px 0;">Renew Membership Now</a></p>';
        htmlBody += '<p>If you have any questions, please contact FSMTB at CE@fsmtb.org.</p>';
        htmlBody += '<p>Thank you,<br>FSMTB Service Team</p>';
        htmlBody += '</body></html>';
        
        return htmlBody;
    }
}

