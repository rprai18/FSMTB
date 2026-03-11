public with sharing class CEBannerController {
    
    @AuraEnabled(cacheable=true)
    public static String getAccountStatus(Id recordId, String statusFieldApiName) {
        if (recordId == null) {
            return null;
        }
        
        try {
            // Build dynamic SOQL query to get the status field
            String query = 'SELECT ' + String.escapeSingleQuotes(statusFieldApiName) + 
                          ' FROM Account WHERE Id = :recordId LIMIT 1';
            
            List<Account> accounts = Database.query(query);
            
            if (accounts.isEmpty()) {
                return null;
            }
            
            Account acc = accounts[0];
            // Get the status field value dynamically
            return (String)acc.get(statusFieldApiName);
            
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving account status: ' + e.getMessage());
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static BannerStatusWrapper getAccountBannerStatuses(Id recordId) {
        if (recordId == null) {
            return null;
        }
        
        try {
            Account acc = [
                SELECT Registration_Status__c, Current_Active_Action_Status__c
                FROM Account 
                WHERE Id = :recordId 
                LIMIT 1
            ];
            
            BannerStatusWrapper wrapper = new BannerStatusWrapper();
            wrapper.registrationStatus = acc.Registration_Status__c;
            wrapper.actionStatus = acc.Current_Active_Action_Status__c;
            
            return wrapper;
            
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving account statuses: ' + e.getMessage());
        }
    }
    
    public class BannerStatusWrapper {
        @AuraEnabled public String registrationStatus;
        @AuraEnabled public String actionStatus;
    }
}