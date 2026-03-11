/**
 * Controller for Forgot Password LWC
 * Handles forgot password functionality for community users
 */
public with sharing class ForgotPasswordLwcController {
    
    // Must match CE provider username domain used during initial registration
    private static final String CE_USERNAME_SUFFIX = '@ceprovider.fsmtb.org';
    
    /**
     * Process forgot password request
     * @param username The username to reset password for
     * @return Map with success status and redirect URL or error message
     */
    @AuraEnabled
    public static Map<String, Object> forgotPassword(String username) {
        Map<String, Object> result = new Map<String, Object>();
        
        System.debug('===== FORGOT PASSWORD DEBUG =====');
        System.debug('Input username: ' + username);
        
        try {
            // Validate input
            if (String.isBlank(username)) {
                result.put('success', false);
                result.put('error', 'Username is required.');
                result.put('debugInfo', 'Username is blank');
                return result;
            }
            
            // Add CE username suffix if username doesn't contain '@'
            String processedUsername = username;
            if (!username.contains('@')) {
                processedUsername = username + CE_USERNAME_SUFFIX;
            }
            
            System.debug('Processed username: ' + processedUsername);
            
            // Check if user exists before calling Site.forgotPassword
            List<User> users = [
                SELECT Id, Username, Email, IsActive, ContactId, Contact.Email
                FROM User 
                WHERE Username = :processedUsername 
                LIMIT 1
            ];
            
            if (users.isEmpty()) {
                System.debug('✗ User not found with username: ' + processedUsername);
                result.put('success', false);
                result.put('error', 'The username you entered is not valid. Please check and try again.');
                result.put('debugInfo', 'User not found with username: ' + processedUsername);
                return result;
            }
            
            User foundUser = users[0];
            System.debug('✓ User found:');
            System.debug('  User ID: ' + foundUser.Id);
            System.debug('  Username: ' + foundUser.Username);
            System.debug('  Email: ' + foundUser.Email);
            System.debug('  IsActive: ' + foundUser.IsActive);
            System.debug('  ContactId: ' + foundUser.ContactId);
            if (foundUser.Contact != null) {
                System.debug('  Contact Email: ' + foundUser.Contact.Email);
            }
            
            if (!foundUser.IsActive) {
                System.debug('✗ User is not active');
                result.put('success', false);
                result.put('error', 'The username you entered is not active. Please contact support.');
                result.put('debugInfo', 'User is not active');
                return result;
            }
            
            // Check if user has an email
            String userEmail = foundUser.Email;
            if (String.isBlank(userEmail) && foundUser.Contact != null) {
                userEmail = foundUser.Contact.Email;
            }
            
            if (String.isBlank(userEmail)) {
                System.debug('✗ User has no email address');
                result.put('success', false);
                result.put('error', 'No email address is associated with this username. Please contact support.');
                result.put('debugInfo', 'User has no email address');
                return result;
            }
            
            System.debug('User email: ' + userEmail);
            System.debug('Calling Site.forgotPassword for username: ' + processedUsername);
            
            // Call Site.forgotPassword
            try {
                Site.forgotPassword(processedUsername);
                System.debug('✓ Site.forgotPassword() called successfully');
                result.put('debugInfo', 'Password reset email sent to: ' + userEmail);
            } catch (Exception siteEx) {
                System.debug('✗ Site.forgotPassword() failed: ' + siteEx.getMessage());
                System.debug('Stack trace: ' + siteEx.getStackTraceString());
                result.put('success', false);
                result.put('error', 'Failed to send password reset email. Please try again later.');
                result.put('debugInfo', 'Site.forgotPassword exception: ' + siteEx.getMessage());
                return result;
            }
            
            // Get the ForgotPasswordConfirmation page URL
            try {
                PageReference confirmationPage = Page.ForgotPasswordConfirmation;
                result.put('success', true);
                result.put('redirectUrl', confirmationPage.getUrl());
            } catch (Exception e) {
                System.debug('Error getting ForgotPasswordConfirmation page: ' + e.getMessage());
                // Fallback: return success but let LWC handle navigation
                result.put('success', true);
                result.put('redirectUrl', '/ForgotPasswordConfirmation');
            }
            
        } catch (Exception e) {
            System.debug('✗ Exception in forgotPassword: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            result.put('success', false);
            
            // Provide user-friendly error messages
            String errorMessage = e.getMessage();
            if (errorMessage.contains('INVALID_USERNAME')) {
                result.put('error', 'The username you entered is not valid. Please check and try again.');
            } else if (errorMessage.contains('INVALID_EMAIL')) {
                result.put('error', 'The email address associated with this username is not valid.');
            } else {
                result.put('error', errorMessage != null ? errorMessage : 'An error occurred while processing your request. Please try again.');
            }
            result.put('debugInfo', 'Exception: ' + e.getTypeName() + ' - ' + errorMessage);
        }
        
        System.debug('===============================');
        return result;
    }
    
    /**
     * Get site labels for forgot password page
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getSiteLabels() {
        Map<String, String> labels = new Map<String, String>();
        
        try {
            // Get custom labels with fallbacks
            try {
                labels.put('forgotPassword', Label.site.forgot_password);
            } catch (Exception e) {
                labels.put('forgotPassword', 'Forgot Password');
            }
            
            try {
                labels.put('enterPassword', Label.site.enter_password);
            } catch (Exception e) {
                labels.put('enterPassword', 'Enter your username to receive a password reset link.');
            }
            
            try {
                labels.put('username', Label.site.username);
            } catch (Exception e) {
                labels.put('username', 'Username');
            }
            
            try {
                labels.put('submit', Label.site.submit);
            } catch (Exception e) {
                labels.put('submit', 'Submit');
            }
            
            try {
                labels.put('tempPasswordSent', Label.site.temp_password_sent);
            } catch (Exception e) {
                labels.put('tempPasswordSent', 'Temporary password sent');
            }
            
            try {
                labels.put('goToLoginPage', Label.site.go_to_login_page);
            } catch (Exception e) {
                labels.put('goToLoginPage', 'Go to login page');
            }
            
        } catch (Exception e) {
            System.debug('Error getting site labels: ' + e.getMessage());
            // Set defaults
            labels.put('forgotPassword', 'Forgot Password');
            labels.put('enterPassword', 'Enter your username to receive a password reset link.');
            labels.put('username', 'Username');
            labels.put('submit', 'Submit');
            labels.put('tempPasswordSent', 'Temporary password sent');
            labels.put('goToLoginPage', 'Go to login page');
        }
        
        return labels;
    }
}

