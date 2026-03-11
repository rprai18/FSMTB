import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { loadStyle } from 'lightning/platformResourceLoader';
import getSiteLabels from '@salesforce/apex/ForgotPasswordLwcController.getSiteLabels';
import portalImages from '@salesforce/resourceUrl/Portal_Images';

export default class CommunityForgotPasswordConfirm extends NavigationMixin(LightningElement) {
    @track siteLabels = {
        tempPasswordSent: 'Temporary password sent',
        goToLoginPage: 'Go to login page'
    };
    
    // Static resource for images
    clockImageUrl = `${portalImages}/clock.png`;
    
    @wire(getSiteLabels)
    wiredSiteLabels({ data, error }) {
        if (data) {
            this.siteLabels = data;
        } else if (error) {
            console.error('Error loading site labels:', error);
            // Keep default labels
        }
    }
    
    connectedCallback() {
        // Load portal CSS styles if available
        loadStyle(this, '/resource/FSMTBAssets/FSMTBAssets/css/global.css')
            .catch(error => {
                console.error('Error loading portal styles:', error);
            });
        
        // Set page title
        document.title = this.siteLabels.tempPasswordSent || 'Forgot Password Confirmation';
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
                console.log('[FORGOT PASSWORD CONFIRM] Navigating to login:', loginUrl);
                window.location.href = loginUrl;
            } else {
                // Fallback: Try NavigationMixin
                console.log('[FORGOT PASSWORD CONFIRM] Could not determine community path, using NavigationMixin');
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
                            console.error('[FORGOT PASSWORD CONFIRM] NavigationMixin failed, using fallback:', error);
                            window.location.href = '/s/login';
                        });
                    } else {
                        window.location.href = '/s/login';
                    }
                } catch (navError) {
                    console.error('[FORGOT PASSWORD CONFIRM] Navigation error:', navError);
                    window.location.href = '/s/login';
                }
            }
        } catch (error) {
            console.error('[FORGOT PASSWORD CONFIRM] Error during navigation:', error);
            // Final fallback
            window.location.href = '/s/login';
        }
    }
    
    handleImageError(event) {
        // Hide image if it fails to load
        if (event.target) {
            event.target.style.display = 'none';
        }
    }
}

