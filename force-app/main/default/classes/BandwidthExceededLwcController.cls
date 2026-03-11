/**
 * Controller for Bandwidth Exceeded LWC
 * Simple controller to get custom labels for error page
 */
public with sharing class BandwidthExceededLwcController {
    
    /**
     * Get custom label for bandwidth limit exceeded
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getErrorLabels() {
        Map<String, String> labels = new Map<String, String>();
        
        try {
            // Get custom label with fallback
            try {
                labels.put('bandwidthLimitExceeded', Label.site.bandwidth_limit_exceeded);
            } catch (Exception e) {
                labels.put('bandwidthLimitExceeded', 'Bandwidth Exceeded');
            }
            
        } catch (Exception e) {
            System.debug('Error getting error labels: ' + e.getMessage());
            labels.put('bandwidthLimitExceeded', 'Bandwidth Exceeded');
        }
        
        return labels;
    }
}

