import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { loadStyle } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import forgotPassword from '@salesforce/apex/ForgotPasswordLwcController.forgotPassword';
import getSiteLabels from '@salesforce/apex/ForgotPasswordLwcController.getSiteLabels';
import getSiteInfo from '@salesforce/apex/CommunityLoginLwcController.getSiteInfo';
import portalImages from '@salesforce/resourceUrl/Portal_Images';

export default class CommunityForgotPassword extends NavigationMixin(LightningElement) {
    @track username = '';
    @track isLoading = false;
    @track errorMessage = '';
    @track siteLabels = {
        forgotPassword: 'Forgot Password',
        enterPassword: 'Enter your username to receive a password reset link.',
        username: 'Username',
        submit: 'Submit'
    };
    @track siteInfo = {};
    
    // Static resource for images
    portalImages = portalImages;
    headerImageUrl = '';
    fsmtbLogoUrl = `${portalImages}/FSMTB_logo.png`;
    
    @wire(getSiteLabels)
    wiredSiteLabels({ data, error }) {
        if (data) {
            this.siteLabels = data;
        } else if (error) {
            console.error('Error loading site labels:', error);
            // Keep default labels
        }
    }
    
    @wire(getSiteInfo)
    wiredSiteInfo({ data, error }) {
        if (data) {
            this.siteInfo = data;
            // Set header image URL
            if (data.randomImage) {
                this.headerImageUrl = `${portalImages}/${data.randomImage}`;
            }
        } else if (error) {
            console.error('Error loading site info:', error);
            // Set default header image
            this.headerImageUrl = `${portalImages}/FSMTB_header0.png`;
        }
    }
    
    connectedCallback() {
        // Load portal CSS styles if available
        loadStyle(this, '/resource/FSMTBAssets/FSMTBAssets/css/global.css')
            .catch(error => {
                console.error('Error loading portal styles:', error);
            });
        
        // Set page title
        document.title = this.siteLabels.forgotPassword || 'Forgot Password';
    }
    
    handleUsernameChange(event) {
        this.username = event.target.value;
        this.errorMessage = ''; // Clear error when user types
    }
    
    async handleSubmit(event) {
        event.preventDefault();
        
        // Clear previous errors
        this.errorMessage = '';
        
        // Client-side validation
        if (!this.username || this.username.trim() === '') {
            this.errorMessage = 'Username is required.';
            this.showErrorToast('Validation Error', 'Username is required.');
            return;
        }
        
        this.isLoading = true;
        
        try {
            const result = await forgotPassword({
                username: this.username.trim()
            });
            
            // Log debug information to console
            console.log('%c[FORGOT PASSWORD] ===== PASSWORD RESET RESULT =====', 'background: #006400; color: white; font-weight: bold;');
            console.log('%c[FORGOT PASSWORD] Success:', 'background: #006400; color: white;', result.success);
            console.log('%c[FORGOT PASSWORD] Error:', 'background: #8B0000; color: white;', result.error || '(no error)');
            if (result.debugInfo) {
                console.log('%c[FORGOT PASSWORD] Debug Info:', 'background: #008B8B; color: white;', result.debugInfo);
            }
            console.log('%c[FORGOT PASSWORD] Full Result:', 'background: #008B8B; color: white;', result);
            console.log('%c[FORGOT PASSWORD] ===================================', 'background: #006400; color: white; font-weight: bold;');
            
            if (result.success) {
                // Show success message
                const successMsg = result.debugInfo 
                    ? 'A password reset link has been sent to your email address. ' + result.debugInfo
                    : 'A password reset link has been sent to your email address.';
                this.showSuccessToast('Success', successMsg);
                
                // Navigate to Forgot Password Confirmation page after a short delay
                setTimeout(() => {
                    this.navigateToConfirmationPage();
                }, 1500);
            } else {
                this.errorMessage = result.error || 'An error occurred. Please try again.';
                this.showErrorToast('Error', this.errorMessage);
            }
        } catch (error) {
            console.error('%c[FORGOT PASSWORD] Exception:', 'background: #8B0000; color: white; font-weight: bold;', error);
            console.error('%c[FORGOT PASSWORD] Error body:', 'background: #8B0000; color: white;', error.body);
            console.error('%c[FORGOT PASSWORD] Error message:', 'background: #8B0000; color: white;', error.message);
            const errorMsg = error.body?.message || error.message || 'An error occurred while processing your request. Please try again.';
            this.errorMessage = errorMsg;
            this.showErrorToast('Error', errorMsg);
        } finally {
            this.isLoading = false;
        }
    }
    
    navigateToConfirmationPage() {
        try {
            // Get the current community base URL
            const currentPath = window.location.pathname;
            const sIndex = currentPath.indexOf('/s/');
            
            if (sIndex !== -1) {
                // Construct confirmation URL: communityPath/s/forgotpasswordconfirm
                const communityBase = currentPath.substring(0, sIndex + 3);
                const confirmUrl = `${window.location.origin}${communityBase}forgotpasswordconfirm`;
                console.log('[FORGOT PASSWORD] Navigating to confirmation page:', confirmUrl);
                window.location.href = confirmUrl;
            } else {
                // Fallback: Try NavigationMixin with page API name
                console.log('[FORGOT PASSWORD] Could not determine community path, using NavigationMixin');
                try {
                    const pageRef = {
                        type: 'comm__namedPage',
                        attributes: {
                            name: 'ForgotPasswordConfirm__c'
                        }
                    };
                    
                    const navPromise = this[NavigationMixin.Navigate](pageRef);
                    if (navPromise && typeof navPromise === 'object' && typeof navPromise.then === 'function') {
                        navPromise.catch(error => {
                            console.error('[FORGOT PASSWORD] NavigationMixin failed, using fallback:', error);
                            window.location.href = '/s/forgotpasswordconfirm';
                        });
                    } else {
                        window.location.href = '/s/forgotpasswordconfirm';
                    }
                } catch (navError) {
                    console.error('[FORGOT PASSWORD] Navigation error:', navError);
                    window.location.href = '/s/forgotpasswordconfirm';
                }
            }
        } catch (error) {
            console.error('[FORGOT PASSWORD] Error during navigation:', error);
            // Final fallback
            window.location.href = '/s/forgotpasswordconfirm';
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
    
    handleLogoError(event) {
        // Hide logo if it fails to load
        if (event.target) {
            event.target.style.display = 'none';
        }
    }
}

