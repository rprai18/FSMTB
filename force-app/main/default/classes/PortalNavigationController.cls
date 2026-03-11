/**
 * Controller for Portal Navigation LWC
 * Provides current user information
 */
public without sharing class PortalNavigationController {
    
    /**
     * Get current user information for navigation header
     */
    @AuraEnabled(cacheable=true)
    public static UserInfoWrapper getUserInfo() {
        UserInfoWrapper wrapper = new UserInfoWrapper();
        
        try {
            Id userId = UserInfo.getUserId();
            
            // Check if user is a guest
            String userType = UserInfo.getUserType();
            wrapper.isGuest = (userType == 'Guest');
            
            if (!wrapper.isGuest && userId != null) {
                // Get user details with Contact relationship
                List<User> users = [
                    SELECT Id, FirstName, LastName, Name, Email, ContactId,
                           Contact.FirstName, Contact.LastName, Contact.Name
                    FROM User
                    WHERE Id = :userId
                    LIMIT 1
                ];
                
                if (!users.isEmpty()) {
                    User u = users[0];
                    wrapper.userId = u.Id;
                    
                    // Try to get name from User record first
                    String firstName = u.FirstName;
                    String lastName = u.LastName;
                    String fullName = u.Name;
                    
                    // If User record doesn't have name, try Contact record (for portal users)
                    if ((String.isBlank(firstName) && String.isBlank(lastName) && String.isBlank(fullName)) 
                        && u.ContactId != null && u.Contact != null) {
                        firstName = u.Contact.FirstName;
                        lastName = u.Contact.LastName;
                        fullName = u.Contact.Name;
                        System.debug('Using Contact name - FirstName: ' + firstName + ', LastName: ' + lastName);
                    }
                    
                    wrapper.firstName = firstName;
                    wrapper.lastName = lastName;
                    
                    // Construct full name
                    if (String.isNotBlank(fullName)) {
                        wrapper.fullName = fullName.trim();
                    } else if (String.isNotBlank(firstName) || String.isNotBlank(lastName)) {
                        String first = String.isNotBlank(firstName) ? firstName.trim() : '';
                        String last = String.isNotBlank(lastName) ? lastName.trim() : '';
                        wrapper.fullName = (first + ' ' + last).trim();
                    } else {
                        wrapper.fullName = 'User';
                        System.debug('No name found in User or Contact record');
                    }
                    
                    wrapper.email = u.Email;
                    System.debug('Final fullName: ' + wrapper.fullName);
                } else {
                    wrapper.fullName = 'User';
                    System.debug('User record not found for userId: ' + userId);
                }
            } else {
                // Guest user - no name available
                wrapper.fullName = 'Guest';
            }
            
        } catch (Exception e) {
            System.debug('Error getting user info: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            wrapper.error = e.getMessage();
            wrapper.fullName = 'User'; // Default fallback
        }
        
        return wrapper;
    }
    
    /**
     * Get logout URL for the current user
     * Returns the proper logout URL that will redirect to login page
     */
    @AuraEnabled
    public static String getLogoutUrl() {
        try {
            // Get the current user's session ID and construct logout URL
            String instanceUrl = URL.getOrgDomainUrl().toExternalForm();
            
            // Get the community login page URL
            // For Experience Cloud sites, login page is typically at /s/login
            // We'll construct it based on the current site
            String loginPageUrl = '/s/login';
            
            // Try to get the site URL if available
            try {
                String siteUrl = Site.getBaseUrl();
                if (String.isNotBlank(siteUrl)) {
                    // Extract the community path from site URL
                    // Site URL format: https://domain.force.com/sitename or https://domain.my.site.com/sitename
                    if (siteUrl.contains('/s/')) {
                        Integer sIndex = siteUrl.indexOf('/s/');
                        String communityPath = siteUrl.substring(sIndex);
                        loginPageUrl = communityPath + 'login';
                    }
                }
            } catch (Exception siteEx) {
                System.debug('Could not get site URL, using default login path: ' + siteEx.getMessage());
            }
            
            String logoutUrl = instanceUrl + '/secur/logout.jsp?retURL=' + EncodingUtil.urlEncode(loginPageUrl, 'UTF-8');
            System.debug('Logout URL with login redirect: ' + logoutUrl);
            return logoutUrl;
        } catch (Exception e) {
            System.debug('Error getting logout URL: ' + e.getMessage());
            // Fallback: construct basic logout URL
            try {
                String instanceUrl = URL.getOrgDomainUrl().toExternalForm();
                return instanceUrl + '/secur/logout.jsp?retURL=' + EncodingUtil.urlEncode('/s/login', 'UTF-8');
            } catch (Exception e2) {
                return '/s/login';
            }
        }
    }
    
    /**
     * Wrapper class for user information
     */
    public class UserInfoWrapper {
        @AuraEnabled public String userId;
        @AuraEnabled public String firstName;
        @AuraEnabled public String lastName;
        @AuraEnabled public String fullName;
        @AuraEnabled public String email;
        @AuraEnabled public Boolean isGuest;
        @AuraEnabled public String error;
    }
}

