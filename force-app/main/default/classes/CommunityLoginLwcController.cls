public with sharing class CommunityLoginLwcController {
    
    /**
     * Get site information for the login page
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getSiteInfo() {
        Map<String, String> siteInfo = new Map<String, String>();
        
        try {
            String siteName = '';
            String siteMasterLabel = '';
            
            // Safely get site information
            try {
                siteName = Site.getName();
            } catch (Exception e) {
                System.debug('Error getting Site.getName: ' + e.getMessage());
            }
            
            try {
                siteMasterLabel = Site.getMasterLabel();
            } catch (Exception e) {
                System.debug('Error getting Site.getMasterLabel: ' + e.getMessage());
            }
            
            siteInfo.put('siteName', siteName != null ? siteName : '');
            siteInfo.put('siteMasterLabel', siteMasterLabel != null ? siteMasterLabel : '');
            
            // Get custom labels with fallbacks
            try {
                siteInfo.put('usernameLabel', Label.site.username);
            } catch (Exception e) {
                siteInfo.put('usernameLabel', 'Username');
            }
            
            try {
                siteInfo.put('passwordLabel', Label.site.password);
            } catch (Exception e) {
                siteInfo.put('passwordLabel', 'Password');
            }
            
            try {
                siteInfo.put('loginButtonLabel', Label.site.login_button);
            } catch (Exception e) {
                siteInfo.put('loginButtonLabel', 'Login');
            }
            
            try {
                siteInfo.put('forgotPasswordLabel', Label.site.forgot_your_password_q);
            } catch (Exception e) {
                siteInfo.put('forgotPasswordLabel', 'Forgot Your Password?');
            }
            
            // Determine display name based on site
            String displayName = '';
            if (String.isNotBlank(siteName) && siteName.equalsIgnoreCase('SLB')) {
                displayName = 'Massage Therapy Licensing Database';
            } else if (String.isNotBlank(siteMasterLabel)) {
                displayName = siteMasterLabel;
            } else {
                displayName = 'FSMTB';
            }
            siteInfo.put('displayName', displayName);
            
            // Get random header image
            siteInfo.put('randomImage', getRandomHeaderImage());
            
        } catch (Exception e) {
            System.debug('Error in getSiteInfo: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            // Return defaults
            siteInfo.put('siteName', '');
            siteInfo.put('siteMasterLabel', '');
            siteInfo.put('displayName', 'FSMTB');
            siteInfo.put('usernameLabel', 'Username');
            siteInfo.put('passwordLabel', 'Password');
            siteInfo.put('loginButtonLabel', 'Login');
            siteInfo.put('forgotPasswordLabel', 'Forgot Your Password?');
            siteInfo.put('randomImage', 'FSMTB_header0.png');
        }
        
        return siteInfo;
    }
    
    /**
     * Get random header image from Portal_Images static resource
     * This mimics the VF page's RandomImage property
     */
    private static String getRandomHeaderImage() {
        // List of available header images (adjust based on your static resource)
        List<String> headerImages = new List<String>{
            'FSMTB_header0.png',
            'FSMTB_header1.png',
            'FSMTB_header2.png'
        };
        
        // Use a simple randomization based on current time
        Integer randomIndex = Math.mod(Integer.valueOf(System.now().getTime()), headerImages.size());
        return headerImages[randomIndex];
    }
    
    /**
     * Perform login for community users
     */
    @AuraEnabled
    public static Map<String, Object> performLogin(String username, String password, String startURL) {
        Map<String, Object> result = new Map<String, Object>();
        
        try {
            String siteName = Site.getName();
            PageReference pageRef;
            
            // Handle login based on site name
            // Redirect to Home page (/) after successful login
            String homePageUrl = '/s/'; // Home page is at root /s/ path
            
            if (siteName != null && siteName.equalsIgnoreCase('SLB')) {
                // Use startURL if provided, otherwise go to Home
                String redirectURL = (startURL != null && String.isNotBlank(startURL)) 
                    ? startURL 
                    : homePageUrl;
                pageRef = Site.login(username, password, redirectURL);
            } else if (siteName != null && siteName.equalsIgnoreCase('CE_Registry')) {
                // Use startURL if provided, otherwise go to Home
                String redirectURL = (startURL != null && String.isNotBlank(startURL)) 
                    ? startURL 
                    : homePageUrl;
                pageRef = Site.login(username, password, redirectURL);
            } else if (siteName != null && siteName.equalsIgnoreCase('Massage_License_Verification_Center')) {
                // Use startURL if provided, otherwise go to Home
                String redirectURL = (startURL != null && String.isNotBlank(startURL)) 
                    ? startURL 
                    : homePageUrl;
                pageRef = Site.login(username, password, redirectURL);
            } else {
                // Default behavior - redirect to Home
                String redirectURL = (startURL != null && String.isNotBlank(startURL)) 
                    ? startURL 
                    : homePageUrl;
                pageRef = Site.login(username, password, redirectURL);
            }
            
            if (pageRef != null) {
                result.put('success', true);
                result.put('redirectUrl', pageRef.getUrl());
            } else {
                result.put('success', false);
                result.put('error', 'Login failed. Please check your credentials.');
            }
            
        } catch (Exception e) {
            System.debug('Error in performLogin: ' + e.getMessage());
            result.put('success', false);
            result.put('error', e.getMessage());
        }
        
        return result;
    }
    
    /**
     * Get page URLs for forgot password, forgot username, and registration
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getPageUrls() {
        Map<String, String> urls = new Map<String, String>();
        
        try {
            String siteName = '';
            try {
                siteName = Site.getName();
            } catch (Exception e) {
                System.debug('Error getting Site.getName in getPageUrls: ' + e.getMessage());
            }
            
            // Forgot Password URL
            try {
                PageReference forgotPasswordPage = Page.ForgotPassword;
                urls.put('forgotPasswordUrl', forgotPasswordPage.getUrl());
            } catch (Exception e) {
                System.debug('Error getting ForgotPassword page: ' + e.getMessage());
                urls.put('forgotPasswordUrl', '/ForgotPassword');
            }
            
            // Forgot Username URL (primarily for CE_Registry, but try to get it for all sites)
            try {
                PageReference forgotUsernamePage = Page.ForgotUsername;
                urls.put('forgotUsernameUrl', forgotUsernamePage.getUrl());
            } catch (Exception e) {
                System.debug('Error getting ForgotUsername page: ' + e.getMessage());
                // Only set URL if it's CE_Registry or if site name is not available (fallback)
                if (String.isBlank(siteName) || siteName.equalsIgnoreCase('CE_Registry')) {
                    urls.put('forgotUsernameUrl', '/ForgotUsername');
                }
            }
            
            // Registration URLs
            if (String.isNotBlank(siteName) && siteName.equalsIgnoreCase('CE_Registry')) {
                try {
                    PageReference registrationPage = Page.CEProviderRegistration;
                    urls.put('registrationUrl', registrationPage.getUrl());
                } catch (Exception e) {
                    System.debug('Error getting CEProviderRegistration page: ' + e.getMessage());
                    urls.put('registrationUrl', '/CEProviderRegistration');
                }
            } else if (String.isNotBlank(siteName) && siteName.equalsIgnoreCase('Massage_License_Verification_Center')) {
                try {
                    PageReference registrationPage = Page.MTRegistration;
                    urls.put('registrationUrl', registrationPage.getUrl());
                } catch (Exception e) {
                    System.debug('Error getting MTRegistration page: ' + e.getMessage());
                    urls.put('registrationUrl', '/MTRegistration');
                }
            } else {
                // Fallback: try to get CEProviderRegistration if site name is not available
                try {
                    PageReference registrationPage = Page.CEProviderRegistration;
                    urls.put('registrationUrl', registrationPage.getUrl());
                } catch (Exception e) {
                    System.debug('Error getting CEProviderRegistration page (fallback): ' + e.getMessage());
                    urls.put('registrationUrl', '/CEProviderRegistration');
                }
            }
            
            urls.put('siteName', siteName != null ? siteName : '');
            
        } catch (Exception e) {
            System.debug('Error in getPageUrls: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            // Return empty map with defaults
            urls.put('siteName', '');
        }
        
        return urls;
    }
}

