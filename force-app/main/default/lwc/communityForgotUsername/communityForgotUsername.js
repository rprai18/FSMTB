import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { loadStyle } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import emailUsername from '@salesforce/apex/ForgotUsernameLwcController.emailUsername';
import getSiteInfo from '@salesforce/apex/ForgotUsernameLwcController.getSiteInfo';
import SLBAssets from '@salesforce/resourceUrl/SLBAssets';

export default class CommunityForgotUsername extends NavigationMixin(LightningElement) {
    @track email = '';
    @track isLoading = false;
    @track errorMessage = '';
    @track showEmailConfirmation = false;
    @track siteInfo = {
        siteMasterLabel: '',
        siteName: '',
        emailLabel: 'Email'
    };
    
    // Static resource for images
    headerImageUrl = `${SLBAssets}/SLBAssets/img/fsmtb_reach.png`;
    
    @wire(getSiteInfo)
    wiredSiteInfo({ data, error }) {
        if (data) {
            this.siteInfo = data;
        } else if (error) {
            console.error('Error loading site info:', error);
            // Keep default values
        }
    }
    
    connectedCallback() {
        // Load portal CSS styles if available
        loadStyle(this, '/resource/FSMTBAssets/FSMTBAssets/css/global.css')
            .catch(error => {
                console.error('Error loading portal styles:', error);
            });
        
        // Set page title
        document.title = 'Forgot Username';
    }
    
    handleEmailChange(event) {
        this.email = event.target.value;
        this.errorMessage = ''; // Clear error when user types
        this.showEmailConfirmation = false; // Hide confirmation if user types
    }
    
    async handleSubmit(event) {
        event.preventDefault();
        
        // Clear previous errors and confirmation
        this.errorMessage = '';
        this.showEmailConfirmation = false;
        
        // Client-side validation
        if (!this.email || this.email.trim() === '') {
            this.errorMessage = 'Email is required.';
            this.showErrorToast('Validation Error', 'Email is required.');
            return;
        }
        
        // Basic email format validation
        const emailPattern = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailPattern.test(this.email.trim())) {
            this.errorMessage = 'Please enter a valid email address.';
            this.showErrorToast('Validation Error', 'Please enter a valid email address.');
            return;
        }
        
        this.isLoading = true;
        
        try {
            const result = await emailUsername({
                email: this.email.trim()
            });
            
            // Log debug information to console
            console.log('%c[FORGOT USERNAME] ===== EMAIL SEND RESULT =====', 'background: #006400; color: white; font-weight: bold;');
            console.log('%c[FORGOT USERNAME] Success:', 'background: #006400; color: white;', result.success);
            console.log('%c[FORGOT USERNAME] Message:', 'background: #006400; color: white;', result.message || '(no message)');
            console.log('%c[FORGOT USERNAME] Error:', 'background: #8B0000; color: white;', result.error || '(no error)');
            if (result.debugInfo) {
                console.log('%c[FORGOT USERNAME] Debug Info:', 'background: #008B8B; color: white;', result.debugInfo);
            }
            console.log('%c[FORGOT USERNAME] Full Result:', 'background: #008B8B; color: white;', result);
            console.log('%c[FORGOT USERNAME] =============================', 'background: #006400; color: white; font-weight: bold;');
            
            if (result.success) {
                // Show confirmation
                this.showEmailConfirmation = true;
                this.showSuccessToast('Success', result.message || 'An email has been sent to ' + this.email + '.');
            } else {
                this.errorMessage = result.error || 'An error occurred. Please try again.';
                this.showErrorToast('Error', this.errorMessage);
            }
        } catch (error) {
            console.error('%c[FORGOT USERNAME] Exception:', 'background: #8B0000; color: white; font-weight: bold;', error);
            console.error('%c[FORGOT USERNAME] Error body:', 'background: #8B0000; color: white;', error.body);
            console.error('%c[FORGOT USERNAME] Error message:', 'background: #8B0000; color: white;', error.message);
            const errorMsg = error.body?.message || error.message || 'An error occurred while processing your request. Please try again.';
            this.errorMessage = errorMsg;
            this.showErrorToast('Error', errorMsg);
        } finally {
            this.isLoading = false;
        }
    }
    
    navigateToLogin() {
        try {
            // Get the current community base URL
            const currentPath = window.location.pathname;
            const sIndex = currentPath.indexOf('/s/');
            
            if (sIndex !== -1) {
                // Construct login URL: communityPath/s/login
                const communityBase = currentPath.substring(0, sIndex + 3);
                const loginUrl = `${window.location.origin}${communityBase}login`;
                console.log('[FORGOT USERNAME] Navigating to login:', loginUrl);
                window.location.href = loginUrl;
            } else {
                // Fallback: Try NavigationMixin
                console.log('[FORGOT USERNAME] Could not determine community path, using NavigationMixin');
                try {
                    const pageRef = {
                        type: 'comm__namedPage',
                        attributes: {
                            name: 'Login'
                        }
                    };
                    
                    const navPromise = this[NavigationMixin.Navigate](pageRef);
                    if (navPromise && typeof navPromise === 'object' && typeof navPromise.then === 'function') {
                        navPromise.catch(error => {
                            console.error('[FORGOT USERNAME] NavigationMixin failed, using fallback:', error);
                            window.location.href = '/s/login';
                        });
                    } else {
                        window.location.href = '/s/login';
                    }
                } catch (navError) {
                    console.error('[FORGOT USERNAME] Navigation error:', navError);
                    window.location.href = '/s/login';
                }
            }
        } catch (error) {
            console.error('[FORGOT USERNAME] Error during navigation:', error);
            // Final fallback
            window.location.href = '/s/login';
        }
    }
    
    showSuccessToast(title, message) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: 'success',
            mode: 'dismissable'
        });
        this.dispatchEvent(evt);
    }
    
    showErrorToast(title, message) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: 'error',
            mode: 'sticky'
        });
        this.dispatchEvent(evt);
    }
    
    handleImageError(event) {
        // Hide image if it fails to load
        if (event.target) {
            event.target.style.display = 'none';
        }
    }
    
    get pageTitle() {
        return this.siteInfo.siteMasterLabel 
            ? `${this.siteInfo.siteMasterLabel} - Forgot Username` 
            : 'Forgot Username';
    }
}

