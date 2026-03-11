/**
 * Controller for Forgot Password Visualforce Page
 * Handles forgot password functionality for community users
 */
public class ForgotPasswordController {
    
    public String username { get; set; }
    
    // Must match CE provider username domain used during initial registration
    private static final String CE_USERNAME_SUFFIX = '@ceprovider.fsmtb.org';
    
    /**
     * Process forgot password request
     * @return PageReference to confirmation page or null if error
     */
    public PageReference forgotPassword() {
        try {
            // Validate input
            if (String.isBlank(username)) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'Username is required.'));
                return null;
            }
            
            // Add CE username suffix if username doesn't contain '@'
            String processedUsername = username;
            if (!username.contains('@')) {
                processedUsername = username + CE_USERNAME_SUFFIX;
            }
            
            // Check if user exists before calling Site.forgotPassword
            List<User> users = [
                SELECT Id, Username, Email, IsActive, ContactId, Contact.Email
                FROM User 
                WHERE Username = :processedUsername 
                LIMIT 1
            ];
            
            if (users.isEmpty()) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'The username you entered is not valid. Please check and try again.'));
                return null;
            }
            
            User foundUser = users[0];
            
            if (!foundUser.IsActive) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'The username you entered is not active. Please contact support.'));
                return null;
            }
            
            // Check if user has an email
            String userEmail = foundUser.Email;
            if (String.isBlank(userEmail) && foundUser.Contact != null) {
                userEmail = foundUser.Contact.Email;
            }
            
            if (String.isBlank(userEmail)) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'No email address is associated with this username. Please contact support.'));
                return null;
            }
            
            // Call Site.forgotPassword
            Site.forgotPassword(processedUsername);
            
            // Redirect to ForgotPasswordConfirmation page
            return Page.ForgotPasswordConfirmation;
            
        } catch (Exception e) {
            System.debug('Error in forgotPassword: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            
            // Provide user-friendly error messages
            String errorMessage = e.getMessage();
            if (errorMessage.contains('INVALID_USERNAME')) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'The username you entered is not valid. Please check and try again.'));
            } else if (errorMessage.contains('INVALID_EMAIL')) {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, 'The email address associated with this username is not valid.'));
            } else {
                ApexPages.addMessage(new ApexPages.Message(ApexPages.Severity.ERROR, errorMessage != null ? errorMessage : 'An error occurred while processing your request. Please try again.'));
            }
            return null;
        }
    }
}

