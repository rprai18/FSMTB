public without sharing class CePaymentConfirmationLwcController {
    
    // Wrapper for payment confirmation data
    public class PaymentConfirmationData {
        @AuraEnabled public String siteName { get; set; }
        @AuraEnabled public String siteMasterLabel { get; set; }
        @AuraEnabled public Boolean isUserAdmin { get; set; }
        @AuraEnabled public Boolean isUserCourseOnly { get; set; }
        @AuraEnabled public Boolean isUserRosterOnly { get; set; }
        @AuraEnabled public Boolean isUserSearchOnly { get; set; }
        @AuraEnabled public Boolean allowFeedbackAccess { get; set; }
        @AuraEnabled public String headerImage { get; set; }
        @AuraEnabled public Boolean isFirstCourse { get; set; }
    }
    
    /**
     * Get payment confirmation data
     */
    @AuraEnabled(cacheable=true)
    public static PaymentConfirmationData getPaymentConfirmationData() {
        PaymentConfirmationData data = new PaymentConfirmationData();
        
        try {
            // Get site information
            data.siteName = Site.getName();
            data.siteMasterLabel = Site.getMasterLabel();
            
            // Get user profile information
            String profileName = [SELECT Profile.Name FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1].Profile.Name;
            
            // Define user visibility
            data.isUserAdmin = (profileName == 'CE Provider Administrator' || profileName == 'MT Verify Administrator');
            data.isUserCourseOnly = (profileName == 'CE Courses Only');
            data.isUserRosterOnly = (profileName == 'CE Rosters Only');
            data.isUserSearchOnly = (profileName == 'MT Verify Search Only');
            
            // Get allowFeedbackAccess - currently set to true for all users (as per comment in VF controller)
            data.allowFeedbackAccess = true;
            
            // Check if this is the first course for the account
            data.isFirstCourse = checkIfFirstCourse();
            
            // Get random header image
            data.headerImage = getRandomImage();
            
        } catch (Exception e) {
            System.debug('Error loading payment confirmation data: ' + e.getMessage());
            // Set defaults
            data.siteName = 'CE_Registry';
            data.siteMasterLabel = 'CE Registry';
            data.isUserAdmin = false;
            data.allowFeedbackAccess = true;
            data.headerImage = 'FSMTB_header0.png';
        }
        
        return data;
    }
    
    /**
     * Get random header image (0-3)
     */
    private static String getRandomImage() {
        Integer randomNum = (Integer)(Math.random() * 4);
        return 'FSMTB_header' + randomNum + '.png';
    }
    
    /**
     * Check if this is the first course for the account
     * Returns true if the account has exactly 1 course (including the one just paid for)
     * Uses same query pattern as CeCourseManagementLwcController for consistency
     */
    private static Boolean checkIfFirstCourse() {
        try {
            // Get account ID from current user
            User currentUser = [SELECT AccountId FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
            
            if (currentUser.AccountId == null) {
                System.debug('User has no AccountId, returning false for isFirstCourse');
                return false;
            }
            
            // Count total courses for this account
            // Match the query pattern used in CeCourseManagementLwcController
            // This will include any course that was just created/paid for
            Integer courseCount = [
                SELECT COUNT() 
                FROM Course__c 
                WHERE Contact__r.AccountId = :currentUser.AccountId 
                AND Status__c != NULL
            ];
            
            System.debug('Course count for account ' + currentUser.AccountId + ': ' + courseCount);
            
            // If there's exactly 1 course, this is the first one
            Boolean isFirst = (courseCount == 1);
            System.debug('Is first course: ' + isFirst);
            return isFirst;
            
        } catch (Exception e) {
            System.debug('Error checking if first course: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            // If we can't determine, default to false (navigate to course management)
            return false;
        }
    }
}

