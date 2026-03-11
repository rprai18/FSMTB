import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';
import GOOGLE_ANALYTICS from '@salesforce/resourceUrl/GoogleAnalytics';
import portalImages from '@salesforce/resourceUrl/Portal_Images';
import getPaymentConfirmationData from '@salesforce/apex/CePaymentConfirmationLwcController.getPaymentConfirmationData';

export default class CePaymentConfirmation extends NavigationMixin(LightningElement) {
    @track siteName = '';
    @track siteMasterLabel = '';
    @track isUserAdmin = false;
    @track isUserCourseOnly = false;
    @track isUserRosterOnly = false;
    @track isLoading = true;
    @track headerImage = '';
    @track isFirstCourse = false;
    @track hasNavigated = false;
    
    // Images
    portalImages = portalImages;
    
    gtmInitialized = false;
    
    @wire(getPaymentConfirmationData)
    wiredPaymentConfirmationData({ data, error }) {
        if (data) {
            this.siteName = data.siteName || '';
            this.siteMasterLabel = data.siteMasterLabel || 'CE Registry';
            this.isUserAdmin = data.isUserAdmin || false;
            this.isUserCourseOnly = data.isUserCourseOnly || false;
            this.isUserRosterOnly = data.isUserRosterOnly || false;
            this.isFirstCourse = data.isFirstCourse || false;
            this.headerImage = portalImages + '/' + (data.headerImage || 'FSMTB_header0.png');
            this.isLoading = false;
            
            console.log('[PAYMENT CONFIRMATION] Data loaded:', {
                siteName: this.siteName,
                isFirstCourse: this.isFirstCourse,
                hasNavigated: this.hasNavigated
            });
            
            // Navigate based on whether it's the first course
            // Check for course payment - navigate after a short delay
            if (!this.hasNavigated) {
                this.navigateAfterPayment();
            }
        } else if (error) {
            console.error('Error loading payment confirmation data:', error);
            this.isLoading = false;
        }
    }
    
    navigateAfterPayment() {
        // Prevent multiple navigations
        if (this.hasNavigated) {
            console.log('[PAYMENT CONFIRMATION] Navigation already attempted, skipping');
            return;
        }
        this.hasNavigated = true;
        
        console.log('[PAYMENT CONFIRMATION] Starting navigation after payment:', {
            isFirstCourse: this.isFirstCourse
        });
        
        // Wait 5 seconds before navigation (user requested)
        setTimeout(() => {
            try {
                if (this.isFirstCourse) {
                    // Navigate to General Provider Policies page (first course)
                    console.log('[PAYMENT CONFIRMATION] Navigating to CEGeneralProviderPolicies__c (first course)');
                    this[NavigationMixin.Navigate]({
                        type: 'comm__namedPage',
                        attributes: {
                            name: 'CEGeneralProviderPolicies__c'
                        }
                    }, false).catch(navError => {
                        console.error('[PAYMENT CONFIRMATION] Navigation error:', navError);
                    });
                } else {
                    // Navigate to Course Management Overview (not first course)
                    // Navigate to Home page with tab parameter
                    // Home page is at /CERegistryPortal/s/ (root path, not /s/Home)
                    console.log('[PAYMENT CONFIRMATION] Navigating to Home page with courseManagement tab (not first course)');
                    
                    try {
                        // Get current URL to determine community path structure
                        const currentUrl = new URL(window.location.href);
                        const currentPath = currentUrl.pathname;
                        
                        // Extract community base path (e.g., /CERegistryPortal/s/)
                        // Find the '/s/' segment and use everything up to and including '/s/'
                        const sIndex = currentPath.indexOf('/s/');
                        if (sIndex !== -1) {
                            // Construct Home URL: communityPath/s/?tab=courseManagement
                            // Home page is at the root /s/ path, not /s/Home
                            const communityBase = currentPath.substring(0, sIndex + 3);
                            const homeUrl = `${currentUrl.origin}${communityBase}?tab=courseManagement`;
                            console.log('[PAYMENT CONFIRMATION] Navigating to:', homeUrl);
                            window.location.href = homeUrl;
                        } else {
                            // Fallback: try NavigationMixin (default tab is courseManagement)
                            console.log('[PAYMENT CONFIRMATION] Could not determine community path, using NavigationMixin');
                            this[NavigationMixin.Navigate]({
                                type: 'comm__namedPage',
                                attributes: {
                                    name: 'Home'
                                }
                            }, false).catch(navError => {
                                console.error('[PAYMENT CONFIRMATION] Navigation failed:', navError);
                            });
                        }
                    } catch (urlError) {
                        console.error('[PAYMENT CONFIRMATION] URL construction failed:', urlError);
                        // Fallback: use NavigationMixin
                        this[NavigationMixin.Navigate]({
                            type: 'comm__namedPage',
                            attributes: {
                                name: 'Home'
                            }
                        }, false).catch(navError => {
                            console.error('[PAYMENT CONFIRMATION] Navigation to Home also failed:', navError);
                        });
                    }
                }
            } catch (error) {
                console.error('[PAYMENT CONFIRMATION] Error during navigation:', error);
            }
        }, 5000); // 5 second delay to show confirmation message (user requested)
    }
    
    renderedCallback() {
        if (this.gtmInitialized) {
            return;
        }
        this.gtmInitialized = true;
        
        loadScript(this, GOOGLE_ANALYTICS)
            .then(() => {
                console.log('✅ GTM script loaded successfully');
            })
            .catch(error => {
                console.error('❌ Failed to load GTM script', error);
            });
    }
    
    get showAdminMessage() {
        return this.isUserAdmin;
    }
    
    get showNewUserMessage() {
        return !this.isUserAdmin;
    }
    
    get pageHeading() {
        if (this.isUserAdmin) {
            return 'Thank you for your payment';
        } else {
            return `Welcome to ${this.siteMasterLabel}!`;
        }
    }
    
    get isCE_Registry() {
        return this.siteName === 'CE_Registry';
    }
}

