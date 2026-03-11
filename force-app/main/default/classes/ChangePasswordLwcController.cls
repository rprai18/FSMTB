/**
 * Controller for Change Password LWC
 * Handles password change functionality for community users
 */
public with sharing class ChangePasswordLwcController {
    
    /**
     * Check if the current user's password is expired
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getPasswordStatus() {
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            Boolean isPasswordExpired = Site.isPasswordExpired();
            String siteMasterLabel = Site.getMasterLabel();
            
            result.put('isPasswordExpired', isPasswordExpired);
            result.put('siteMasterLabel', siteMasterLabel != null ? siteMasterLabel : '');
            result.put('success', true);
        } catch (Exception e) {
            System.debug('Error getting password status: ' + e.getMessage());
            result.put('success', false);
            result.put('error', e.getMessage());
            result.put('isPasswordExpired', false);
            result.put('siteMasterLabel', '');
        }
        
        return result;
    }
    
    /**
     * Change the user's password
     * @param newPassword The new password
     * @param verifyNewPassword The verification of the new password
     * @param oldPassword The old password (optional if password is expired)
     * @return PageReference to redirect after password change
     */
    @AuraEnabled
    public static Map<String, Object> changePassword(String newPassword, String verifyNewPassword, String oldPassword) {
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            // Validate inputs
            if (String.isBlank(newPassword)) {
                result.put('success', false);
                result.put('error', 'New password is required.');
                return result;
            }
            
            if (String.isBlank(verifyNewPassword)) {
                result.put('success', false);
                result.put('error', 'Please verify your new password.');
                return result;
            }
            
            if (newPassword != verifyNewPassword) {
                result.put('success', false);
                result.put('error', 'New password and verify password must match.');
                return result;
            }
            
            // Check if password is expired
            Boolean isPasswordExpired = Site.isPasswordExpired();
            
            // If password is not expired, old password is required
            if (!isPasswordExpired && String.isBlank(oldPassword)) {
                result.put('success', false);
                result.put('error', 'Old password is required.');
                return result;
            }
            
            // Call Site.changePassword
            // Note: If password is expired, oldPassword can be null
            PageReference pageRef = Site.changePassword(newPassword, verifyNewPassword, oldPassword);
            
            if (pageRef != null) {
                result.put('success', true);
                result.put('redirectUrl', pageRef.getUrl());
            } else {
                result.put('success', false);
                result.put('error', 'Password change failed. Please try again.');
            }
            
        } catch (Exception e) {
            System.debug('Error changing password: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            result.put('success', false);
            
            // Provide user-friendly error messages
            String errorMessage = e.getMessage();
            if (errorMessage.contains('INVALID_OPERATION')) {
                result.put('error', 'Invalid password. Please ensure your password meets the requirements.');
            } else if (errorMessage.contains('INVALID_OLD_PASSWORD')) {
                result.put('error', 'The old password you entered is incorrect.');
            } else if (errorMessage.contains('PASSWORD_INVALID')) {
                result.put('error', 'Password does not meet the requirements. Passwords must be at least 10 characters long and include a mix of alpha, numeric and special characters.');
            } else {
                result.put('error', errorMessage != null ? errorMessage : 'An error occurred while changing your password. Please try again.');
            }
        }
        
        return result;
    }
}

