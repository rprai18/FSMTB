import { LightningElement, track, api, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import GOOGLE_ANALYTICS from '@salesforce/resourceUrl/GoogleAnalytics';
import portalImages from '@salesforce/resourceUrl/Portal_Images';
import getTermsData from '@salesforce/apex/CeTermsAndConditionsLwcController.getTermsData';
import proceed from '@salesforce/apex/CeTermsAndConditionsLwcController.proceed';

export default class CeTermsAndConditions extends NavigationMixin(LightningElement) {
    @api accountId; // Account ID (for new registration) - can be passed from parent component or URL
    @api contactId; // Contact ID (for new registration) - preserved from registration for User creation
    
    @track termsText = '';
    @track siteName = '';
    @track isLoading = true;
    @track error;
    @track showAcceptButton = true;
    @track hasTerms = false;
    
    // Images
    portalImages = portalImages;
    headerImage = portalImages + '/FSMTB_header0.png';
    
    pageReference;
    @track showAdminRedirect = false;
    gtmInitialized = false;
    @track orderIds = [];
    
    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        if (pageRef) {
            this.pageReference = pageRef;
            
            // Get accountId and contactId from URL parameters if not provided via @api
            if (!this.accountId) {
                // First check page reference state
                if (pageRef.state && pageRef.state.accountId) {
                    this.accountId = pageRef.state.accountId;
                    console.log('[TERMS LWC] Got accountId from pageRef.state:', this.accountId);
                } else {
                    // Check URL parameters
                    const urlParams = new URLSearchParams(window.location.search);
                    const urlAccountId = urlParams.get('accountId');
                    const urlLeadId = urlParams.get('leadId');
                    
                    if (urlAccountId) {
                        this.accountId = urlAccountId;
                        console.log('[TERMS LWC] Got accountId from URL parameter:', this.accountId);
                    } else if (urlLeadId) {
                        // If leadId is in URL, we need to get the Account ID from the Lead
                        // But since we convert Lead immediately, the Lead should be deleted
                        // So this is likely an old URL - we'll handle it in proceed method
                        console.warn('[TERMS LWC] Found leadId in URL (old URL?):', urlLeadId);
                        // For now, set to null and let proceed method handle it
                        this.accountId = null;
                    }
                }
            }
            
            // Get contactId from page reference state (preserved from registration)
            if (!this.contactId && pageRef.state && pageRef.state.contactId) {
                this.contactId = pageRef.state.contactId;
                console.log('[TERMS LWC] Got contactId from pageRef.state:', this.contactId);
            }
            
            console.log('[TERMS LWC] Final accountId:', this.accountId, 'contactId:', this.contactId);
            
            // Load terms data (accountId is optional - may be null for renewal flow)
            this.loadTermsData();
        }
    }
    
    connectedCallback() {
        // Load terms data on connect if not already loading
        if (!this.pageReference) {
            this.loadTermsData();
        }
    }
    
    renderedCallback() {
        if (this.gtmInitialized) {
            // Render terms text if needed
            if (this.termsText) {
                this.renderTermsText();
            }
            return;
        }
        this.gtmInitialized = true;
        
        // Load Google Analytics script - matches VF page
        loadScript(this, GOOGLE_ANALYTICS)
            .then(() => {
                console.log('✅ GTM script loaded successfully');
            })
            .catch(error => {
                console.error('❌ Failed to load GTM script', error);
            });
        
        // Render terms text after script loads
        if (this.termsText) {
            this.renderTermsText();
        }
    }
    
    async loadTermsData() {
        this.isLoading = true;
        this.error = null;
        
        try {
            // For new registration, use accountId. For renewal, get from current user
            let accountIdToUse = this.accountId;
            
            // If no accountId provided (renewal flow), get from current user
            if (!accountIdToUse) {
                // For renewal, accountId will be retrieved in the proceed method
                accountIdToUse = null;
            }
            
            const result = await getTermsData({ accountId: accountIdToUse });
            
            this.termsText = result.termsText || 'T&C\'s have not been configured';
            this.siteName = result.siteName || 'CE Registry';
            this.hasTerms = result.hasTerms || false;
            
            // Show error if present (but still allow acceptance for new registrations)
            if (result.error) {
                this.error = result.error;
                // For new registrations, still show Accept button even if terms are not configured
                // Only hide button for critical errors
                this.showAcceptButton = !result.error.includes('INSUFFICIENT_ACCESS') && !result.error.includes('FIELD_INTEGRITY');
            } else {
                // Always show Accept button - allow acceptance even if terms are not configured
                this.showAcceptButton = true;
            }
            
            this.isLoading = false;
            
            // Render terms text after DOM is updated
            requestAnimationFrame(() => {
                this.renderTermsText();
            });
            
        } catch (error) {
            console.error('[TERMS LWC] Error loading terms data:', error);
            // Don't block acceptance - allow user to proceed even if terms loading fails
            let errorMsg = 'Error loading Terms and Conditions.';
            if (error.body) {
                if (error.body.message) {
                    errorMsg = error.body.message;
                } else if (error.body.pageErrors && error.body.pageErrors.length > 0) {
                    errorMsg = error.body.pageErrors[0].message;
                }
            } else if (error.message) {
                errorMsg = error.message;
            }
            // Only show error for critical issues, still allow acceptance
            if (!errorMsg.includes('INSUFFICIENT_ACCESS') && !errorMsg.includes('FIELD_INTEGRITY')) {
                this.error = null; // Don't show error, allow acceptance
                this.showAcceptButton = true; // Always show Accept button
            } else {
                this.error = errorMsg;
                this.showAcceptButton = false;
            }
            this.isLoading = false;
        }
    }
    
    renderTermsText() {
        if (!this.renderRetryCount) {
            this.renderRetryCount = 0;
        }
        
        setTimeout(() => {
            const termsDiv = this.template.querySelector('[data-id="termsText"]');
            if (termsDiv) {
                if (this.termsText) {
                    termsDiv.innerHTML = this.termsText;
                    termsDiv.style.display = 'block';
                    termsDiv.style.visibility = 'visible';
                } else {
                    termsDiv.innerHTML = '<p>T&C\'s have not been configured</p>';
                }
                this.renderRetryCount = 0;
            } else {
                // Retry up to 5 times
                if (this.renderRetryCount < 5 && this.termsText) {
                    this.renderRetryCount++;
                    setTimeout(() => this.renderTermsText(), 100);
                } else {
                    this.renderRetryCount = 0;
                }
            }
        }, 50);
    }
    
    async handleAccept() {
        // New flow: Create Terms, Acceptance, then Order
        console.log('[TERMS LWC] Accept button clicked. accountId:', this.accountId);
        this.isLoading = true;
        this.showAcceptButton = false;
        
        try {
            // For new registration, use accountId and contactId. For renewal, get from current user
            let accountIdToUse = this.accountId;
            let contactIdToUse = this.contactId; // Preserve contactId from registration
            let leadIdToUse = null;
            
            // If no accountId, check URL for leadId (fallback for old URLs)
            if (!accountIdToUse) {
                const urlParams = new URLSearchParams(window.location.search);
                const urlLeadId = urlParams.get('leadId');
                if (urlLeadId) {
                    leadIdToUse = urlLeadId;
                    console.log('[TERMS LWC] Found leadId in URL (fallback):', leadIdToUse);
                }
            }
            
            console.log('[TERMS LWC] Calling proceed with accountId:', accountIdToUse, 'contactId:', contactIdToUse, 'leadId:', leadIdToUse);
            const result = await proceed({ accountId: accountIdToUse, contactId: contactIdToUse, leadId: leadIdToUse });
            console.log('[TERMS LWC] Proceed result:', JSON.stringify(result, null, 2));
            
            // Handle admin redirect for renewals (if another user completed it)
            if (result.showAdminRedirect) {
                this.showAdminRedirect = true;
                this.isLoading = false;
                return;
            }
            
            if (result.success && result.orderIds && result.orderIds.length > 0) {
                this.orderIds = result.orderIds;
                
                // Navigate to payment page with order IDs, accountId, and contactId - preserve for payment processing
                this.navigateToPayment(this.orderIds, result.accountId, result.contactId);
            } else {
                this.isLoading = false;
                this.showAcceptButton = true;
                this.showError(result.message || 'Error accepting terms and creating order.');
            }
        } catch (error) {
            console.error('[TERMS LWC] Error accepting terms:', error);
            this.isLoading = false;
            this.showAcceptButton = true;
            let errorMessage = 'Unexpected error while accepting terms.';
            if (error.body) {
                if (error.body.message) {
                    errorMessage = error.body.message;
                } else if (error.body.pageErrors && error.body.pageErrors.length > 0) {
                    errorMessage = error.body.pageErrors[0].message;
                } else if (error.body.fieldErrors && Object.keys(error.body.fieldErrors).length > 0) {
                    const firstField = Object.keys(error.body.fieldErrors)[0];
                    errorMessage = error.body.fieldErrors[firstField][0].message;
                }
            } else if (error.message) {
                errorMessage = error.message;
            }
            this.showError(errorMessage);
        }
    }
    
    navigateToPayment(orderIds, accountId, contactId) {
        console.log('[TERMS LWC] Navigating to payment with order IDs:', orderIds, 'accountId:', accountId, 'contactId:', contactId);
        
        if (!orderIds || orderIds.length === 0) {
            console.error('[TERMS LWC] No order IDs provided for payment navigation');
            this.isLoading = false;
            this.showAcceptButton = true;
            this.showError('No order IDs available for payment. Please contact support.');
            return;
        }
        
        // Navigate to payment page - matches VF page Page.CommunityPayment
        // Pass order IDs, accountId, and contactId (preserved from registration for Membership and User creation)
        const pageRef = {
            type: 'comm__namedPage',
            attributes: {
                name: 'Payment__c'
            },
            state: {
                ids: JSON.stringify(orderIds),
                accountId: accountId,  // Preserve AccountId for Membership creation
                contactId: contactId   // Preserve ContactId for User creation
            }
        };
        
        console.log('[TERMS LWC] Navigation page reference:', JSON.stringify(pageRef, null, 2));
        
        try {
            // Safely handle navigation promise - NavigationMixin.Navigate might return undefined
            const navPromise = this[NavigationMixin.Navigate](pageRef);
            
            // Only call .then() if navigation returned a valid promise
            if (navPromise && typeof navPromise === 'object' && typeof navPromise.then === 'function') {
                navPromise
                    .then(() => {
                        console.log('[TERMS LWC] Navigation to payment successful');
                    })
                    .catch(error => {
                        console.error('[TERMS LWC] Navigation error:', error);
                        this.isLoading = false;
                        this.showAcceptButton = true;
                        this.showError('Error navigating to payment page. Please try again.');
                    });
            } else {
                console.warn('[TERMS LWC] Navigation did not return a promise, navigation may have completed synchronously');
                // Navigation might have completed synchronously, or NavigationMixin.Navigate returned undefined
                // In this case, we assume navigation succeeded
            }
        } catch (navError) {
            console.error('[TERMS LWC] Error during navigation:', navError);
            this.isLoading = false;
            this.showAcceptButton = true;
            this.showError('Error navigating to payment page. Please try again.');
        }
    }
    
    handleReturnToAdmin() {
        // Navigate to Account Administration page - matches VF page returnToAdminPage()
        const pageRef = {
            type: 'comm__namedPage',
            attributes: {
                name: 'Account_Administration__c'
            }
        };
        
        try {
            // Safely handle navigation promise
            const navPromise = this[NavigationMixin.Navigate](pageRef);
            
            // Check if navigation returned a promise and handle it safely
            if (navPromise && typeof navPromise === 'object' && typeof navPromise.then === 'function') {
                navPromise.catch(error => {
                    console.error('[TERMS LWC] Navigation error:', error);
                });
            }
        } catch (navError) {
            console.error('[TERMS LWC] Error during navigation:', navError);
        }
    }
    
    showError(message) {
        const evt = new ShowToastEvent({
            title: 'Error',
            message: message,
            variant: 'error'
        });
        this.dispatchEvent(evt);
    }
    
    get displaySiteName() {
        return this.siteName || 'CE Registry';
    }
}
