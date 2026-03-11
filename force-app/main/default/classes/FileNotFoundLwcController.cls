/**
 * Controller for File Not Found LWC
 * Simple controller to get custom labels for 404 error page
 */
public with sharing class FileNotFoundLwcController {
    
    /**
     * Get custom label for file not found
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, String> getErrorLabels() {
        Map<String, String> labels = new Map<String, String>();
        
        try {
            // Get custom label with fallback
            try {
                labels.put('fileNotFound', Label.site.file_not_found);
            } catch (Exception e) {
                labels.put('fileNotFound', 'File Not Found');
            }
            
        } catch (Exception e) {
            System.debug('Error getting error labels: ' + e.getMessage());
            labels.put('fileNotFound', 'File Not Found');
        }
        
        return labels;
    }
}

