/**
 * Controller for Access Restricted LWC
 * Handles access restricted page for community users
 */
public with sharing class AccessRestrictedLwcController {
    
    /**
     * Get site and user information for the access restricted page
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getPageInfo() {
        Map<String, String> pageInfo = new Map<String, String>();
        
        try {
            String siteMasterLabel = '';
            String userFirstName = '';
            String userLastName = '';
            String accountName = '';
            
            try {
                siteMasterLabel = Site.getMasterLabel();
            } catch (Exception e) {
                System.debug('Error getting Site.getMasterLabel: ' + e.getMessage());
            }
            
            // Get current user information
            try {
                User currentUser = [
                    SELECT FirstName, LastName, Account_Name__c
                    FROM User
                    WHERE Id = :UserInfo.getUserId()
                    LIMIT 1
                ];
                
                userFirstName = currentUser.FirstName != null ? currentUser.FirstName : '';
                userLastName = currentUser.LastName != null ? currentUser.LastName : '';
                accountName = currentUser.Account_Name__c != null ? currentUser.Account_Name__c : '';
            } catch (Exception e) {
                System.debug('Error getting user info: ' + e.getMessage());
            }
            
            pageInfo.put('siteMasterLabel', siteMasterLabel != null ? siteMasterLabel : '');
            pageInfo.put('userFirstName', userFirstName);
            pageInfo.put('userLastName', userLastName);
            pageInfo.put('accountName', accountName);
            
            // Build email subject
            String emailSubject = 'Under Review Inquiry ICO: ' + userFirstName + ' ' + userLastName;
            if (String.isNotBlank(accountName)) {
                emailSubject += ' of ' + accountName;
            }
            pageInfo.put('emailSubject', EncodingUtil.urlEncode(emailSubject, 'UTF-8'));
            
        } catch (Exception e) {
            System.debug('Error in getPageInfo: ' + e.getMessage());
            pageInfo.put('siteMasterLabel', '');
            pageInfo.put('userFirstName', '');
            pageInfo.put('userLastName', '');
            pageInfo.put('accountName', '');
            pageInfo.put('emailSubject', 'Under Review Inquiry');
        }
        
        return pageInfo;
    }
}

