/**
 * Controller for System Error LWC
 * Simple controller to get custom labels for error page
 */
public with sharing class SystemErrorLwcController {
    
    /**
     * Get custom label for system error
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getErrorLabels() {
        Map<String, String> labels = new Map<String, String>();
        
        try {
            // Get custom label with fallback
            try {
                labels.put('error2', Label.site.error2);
            } catch (Exception e) {
                labels.put('error2', 'System Error');
            }
            
        } catch (Exception e) {
            System.debug('Error getting error labels: ' + e.getMessage());
            labels.put('error2', 'System Error');
        }
        
        return labels;
    }
}

