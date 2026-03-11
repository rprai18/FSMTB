/**
 * Controller for Forgot Username LWC
 * Handles forgot username functionality for community users
 */
public with sharing class ForgotUsernameLwcController {
    
    /**
     * Get site information for the forgot username page
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getSiteInfo() {
        Map<String, String> siteInfo = new Map<String, String>();
        
        try {
            String siteMasterLabel = '';
            String siteName = '';
            
            try {
                siteMasterLabel = Site.getMasterLabel();
            } catch (Exception e) {
                System.debug('Error getting Site.getMasterLabel: ' + e.getMessage());
            }
            
            try {
                siteName = Site.getName();
            } catch (Exception e) {
                System.debug('Error getting Site.getName: ' + e.getMessage());
            }
            
            siteInfo.put('siteMasterLabel', siteMasterLabel != null ? siteMasterLabel : '');
            siteInfo.put('siteName', siteName != null ? siteName : '');
            
            // Get custom labels with fallbacks
            try {
                siteInfo.put('emailLabel', Label.site.email);
            } catch (Exception e) {
                siteInfo.put('emailLabel', 'Email');
            }
            
        } catch (Exception e) {
            System.debug('Error in getSiteInfo: ' + e.getMessage());
            siteInfo.put('siteMasterLabel', '');
            siteInfo.put('siteName', '');
            siteInfo.put('emailLabel', 'Email');
        }
        
        return siteInfo;
    }
    
    /**
     * Send username information to the provided email address
     * @param email The email address to send usernames to
     * @return Map with success status and message
     */
    @AuraEnabled
    public static Map<String, Object> emailUsername(String email) {
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            // Validate input
            if (String.isBlank(email)) {
                result.put('success', false);
                result.put('error', 'Email is required.');
                return result;
            }
            
            // Validate email format
            String emailPattern = '^[a-zA-Z0-9._|\\\\%#~`=?&/$^*!}{+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,4}$';
            Pattern emailRegex = Pattern.compile(emailPattern);
            if (!emailRegex.matcher(email).matches()) {
                result.put('success', false);
                result.put('error', 'Please enter a valid email address.');
                return result;
            }
            
            String siteName = Site.getName();
            System.debug('===== FORGOT USERNAME EMAIL DEBUG =====');
            System.debug('Site Name: ' + siteName);
            System.debug('Email: ' + email);
            
            Map<String, String> usernames = new Map<String, String>();
            
            // Query users for CE_Registry site (case-insensitive check)
            if (siteName != null && siteName.equalsIgnoreCase('CE_Registry')) {
                System.debug('Site is CE_Registry, querying users...');
                
                // Get CE_Provider_User RecordType ID
                List<RecordType> recordTypes = [
                    SELECT Id 
                    FROM RecordType 
                    WHERE DeveloperName = 'CE_Provider_User' 
                    AND SObjectType = 'Contact'
                    LIMIT 1
                ];
                
                System.debug('RecordType query result: ' + (recordTypes.isEmpty() ? 'NOT FOUND' : 'Found: ' + recordTypes[0].Id));
                
                if (!recordTypes.isEmpty()) {
                    Id ceProviderRecordTypeId = recordTypes[0].Id;
                    
                    // Query users with matching email
                    // Note: We query Contact separately to get RecordType, then match to User
                    List<Contact> contacts = [
                        SELECT Id, AccountId, Account.Name
                        FROM Contact 
                        WHERE Email = :email 
                        AND RecordTypeId = :ceProviderRecordTypeId
                        LIMIT 50
                    ];
                    
                    System.debug('Found ' + contacts.size() + ' Contacts with email: ' + email);
                    
                    if (!contacts.isEmpty()) {
                        Set<Id> contactIds = new Set<Id>();
                        for (Contact con : contacts) {
                            contactIds.add(con.Id);
                        }
                        
                        // Query users linked to these contacts
                        List<User> users = [
                            SELECT Id, Username, Email, ContactId, AccountId, Account.Name, IsActive
                            FROM User 
                            WHERE ContactId IN :contactIds
                            AND IsActive = true
                            ORDER BY Account.Name ASC, Username ASC
                        ];
                        
                        System.debug('Found ' + users.size() + ' active Users for these Contacts');
                        
                        for (User user : users) {
                            String accountName = user.Account != null ? user.Account.Name : 'Unknown Account';
                            usernames.put(user.Username, accountName);
                            System.debug('  - Username: ' + user.Username + ', Account: ' + accountName);
                        }
                    }
                } else {
                    System.debug('⚠️ WARNING: CE_Provider_User RecordType not found');
                }
            } else {
                System.debug('Site is not CE_Registry (siteName: ' + siteName + '), skipping user query');
            }
            
            System.debug('Total usernames found: ' + usernames.size());
            
            // Build and send email (always send, even if no usernames found)
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new List<String> {email});
            mail.setInReplyTo('ce@fsmtb.org');
            mail.setSubject('CE Provider forgot username notification');
            mail.setBccAddresses(new List<String> { 'errors@fsmtb.org' });
            mail.setHtmlBody(buildEmailBody(usernames));
            
            // Get OrgWideEmailAddress
            List<OrgWideEmailAddress> orgWideEmails = [
                SELECT Id, DisplayName, Address
                FROM OrgWideEmailAddress 
                WHERE DisplayName = 'CE Registry' 
                LIMIT 1
            ];
            
            if (!orgWideEmails.isEmpty()) {
                mail.setOrgWideEmailAddressId(orgWideEmails[0].Id);
                System.debug('Using OrgWideEmailAddress: ' + orgWideEmails[0].DisplayName + ' (' + orgWideEmails[0].Address + ')');
            } else {
                System.debug('⚠️ WARNING: OrgWideEmailAddress "CE Registry" not found');
            }
            
            // Always send email (even if no usernames found, to prevent email enumeration)
            try {
                System.debug('Attempting to send email to: ' + email);
                Messaging.SendEmailResult[] results = Messaging.sendEmail(new Messaging.SingleEmailMessage[] {mail});
                
                if (results != null && !results.isEmpty()) {
                    Messaging.SendEmailResult sendResult = results[0];
                    if (sendResult.isSuccess()) {
                        System.debug('✓ Email sent successfully');
                        result.put('success', true);
                        result.put('message', 'An email has been sent to ' + email + '.');
                        result.put('debugInfo', 'Email sent successfully to ' + email);
                    } else {
                        String errorDetails = '';
                        if (sendResult.getErrors() != null && !sendResult.getErrors().isEmpty()) {
                            for (Messaging.SendEmailError err : sendResult.getErrors()) {
                                errorDetails += err.getMessage() + ' (Status: ' + err.getStatusCode() + '); ';
                            }
                        }
                        System.debug('✗ Email send failed: ' + errorDetails);
                        result.put('success', false);
                        result.put('error', 'Failed to send email. Please try again later.');
                        result.put('debugInfo', 'Email send failed: ' + errorDetails);
                    }
                } else {
                    System.debug('✗ Email send returned no results');
                    result.put('success', false);
                    result.put('error', 'Failed to send email. Please try again later.');
                    result.put('debugInfo', 'Email send returned no results');
                }
            } catch (Exception emailEx) {
                System.debug('✗ Exception sending email: ' + emailEx.getMessage());
                System.debug('Stack trace: ' + emailEx.getStackTraceString());
                result.put('success', false);
                result.put('error', 'An error occurred while sending the email. Please try again later.');
                result.put('debugInfo', 'Exception: ' + emailEx.getTypeName() + ' - ' + emailEx.getMessage());
            }
            
            System.debug('===============================');
            
        } catch (Exception e) {
            System.debug('Error in emailUsername: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            result.put('success', false);
            
            // Provide user-friendly error messages
            String errorMessage = e.getMessage();
            if (errorMessage.contains('INVALID_EMAIL')) {
                result.put('error', 'The email address you entered is not valid.');
            } else if (errorMessage.contains('EMAIL_EXCEPTION')) {
                result.put('error', 'An error occurred while sending the email. Please try again later.');
            } else {
                result.put('error', errorMessage != null ? errorMessage : 'An error occurred while processing your request. Please try again.');
            }
        }
        
        return result;
    }
    
    /**
     * Build the HTML email body with username information
     * @param usernames Map of username to account name
     * @return HTML email body string
     */
    private static String buildEmailBody(Map<String, String> usernames) {
        String body = '';
        String siteMasterLabel = '';
        
        try {
            siteMasterLabel = Site.getMasterLabel();
        } catch (Exception e) {
            System.debug('Error getting Site.getMasterLabel in buildEmailBody: ' + e.getMessage());
            siteMasterLabel = 'CE Registry';
        }
        
        body += 'Hi ' + (siteMasterLabel != null ? siteMasterLabel : 'CE Registry') + ' User,<br><br>';
        
        body += 'FSMTB received a "forgot username" request from you. Below are any usernames associated with this email address,';
        body += ' along with the provider each username is associated with.<br><br>';
        
        if (usernames.size() > 0) {
            for (String key : usernames.keySet()) {
                body += 'Account: ' + usernames.get(key) + '; Username: ' + key + '<br>';
            }
        } else {
            body += 'No usernames were found associated with this email address.<br>';
        }
        
        body += '<br>';
        
        body += 'If you did not request your username, you can ignore this email. If you have any questions, please call FSMTB at 913.681.0380, ';
        body += 'email CE@fsmtb.org or learn more on www.fsmtb.org.<br><br>';
        
        body += 'Thanks,<br>';
        body += 'FSMTB Service Team';
        
        return body;
    }
}

