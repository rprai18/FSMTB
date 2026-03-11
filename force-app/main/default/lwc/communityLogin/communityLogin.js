import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { loadStyle } from 'lightning/platformResourceLoader';
import portalImages from '@salesforce/resourceUrl/Portal_Images';
import getSiteInfo from '@salesforce/apex/CommunityLoginLwcController.getSiteInfo';
import getPageUrls from '@salesforce/apex/CommunityLoginLwcController.getPageUrls';
import performLogin from '@salesforce/apex/CommunityLoginLwcController.performLogin';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class CommunityLogin extends NavigationMixin(LightningElement) {
    @track username = '';
    @track password = '';
    @track siteInfo = {};
    @track pageUrls = {};
    @track isLoading = false;
    @track errorMessage = '';
    
    // Static resource for images
    portalImages = portalImages;
    headerImageUrl = '';
    fsmtbLogoUrl = `${portalImages}/FSMTB_logo.png`;
    bannerImageUrl = `${portalImages}/massage_background.png`;
    
    @wire(getSiteInfo)
    wiredSiteInfo({ data, error }) {
        if (data) {
            this.siteInfo = data;
            // Set header image URL
            if (data.randomImage) {
                this.headerImageUrl = `${portalImages}/${data.randomImage}`;
            }
            // Set default values if missing
            if (!this.siteInfo.usernameLabel) {
                this.siteInfo.usernameLabel = 'Username';
            }
            if (!this.siteInfo.passwordLabel) {
                this.siteInfo.passwordLabel = 'Password';
            }
            if (!this.siteInfo.loginButtonLabel) {
                this.siteInfo.loginButtonLabel = 'Login';
            }
            if (!this.siteInfo.forgotPasswordLabel) {
                this.siteInfo.forgotPasswordLabel = 'Forgot Your Password?';
            }
            if (!this.siteInfo.displayName) {
                this.siteInfo.displayName = 'FSMTB';
            }
        } else if (error) {
            console.error('Error loading site info:', error);
            // Set defaults on error
            this.siteInfo = {
                siteName: '',
                siteMasterLabel: '',
                displayName: 'FSMTB',
                usernameLabel: 'Username',
                passwordLabel: 'Password',
                loginButtonLabel: 'Login',
                forgotPasswordLabel: 'Forgot Your Password?',
                randomImage: 'FSMTB_header0.png'
            };
            this.headerImageUrl = `${portalImages}/FSMTB_header0.png`;
        }
    }
    
    @wire(getPageUrls)
    wiredPageUrls({ data, error }) {
        if (data) {
            this.pageUrls = data;
        } else if (error) {
            console.error('Error loading page URLs:', error);
            // Set defaults on error
            this.pageUrls = {
                siteName: '',
                forgotPasswordUrl: '/ForgotPassword'
            };
        }
    }
    
    @wire(CurrentPageReference)
    getPageRef(pageRef) {
        if (pageRef && pageRef.state && pageRef.state.startURL) {
            // Store startURL for redirect after login
            this.startURL = pageRef.state.startURL;
        }
    }
    
    startURL = '';
    
    connectedCallback() {
        // Load portal CSS styles
        loadStyle(this, '/resource/FSMTBAssets/FSMTBAssets/css/global.css')
            .catch(error => {
                console.error('Error loading portal styles:', error);
            });
        
        // Set page title
        if (this.siteInfo && this.siteInfo.displayName) {
            document.title = `${this.siteInfo.displayName} Login`;
        }
    }
    
    handleUsernameChange(event) {
        this.username = event.target.value;
        this.errorMessage = ''; // Clear error when user types
    }
    
    handlePasswordChange(event) {
        this.password = event.target.value;
        this.errorMessage = ''; // Clear error when user types
    }
    
    async handleLogin(event) {
        event.preventDefault();
        
        // Validate inputs
        if (!this.username || !this.password) {
            this.errorMessage = 'Please enter both username and password.';
            this.showErrorToast('Login Error', 'Please enter both username and password.');
            return;
        }
        
        this.isLoading = true;
        this.errorMessage = '';
        
        try {
            const result = await performLogin({
                username: this.username,
                password: this.password,
                startURL: this.startURL
            });
            
            if (result.success) {
                // Site.login() performs a server-side redirect, so the redirectUrl from Apex
                // should already point to the Home page (/s/)
                // However, if for some reason we need to handle it client-side, use the redirectUrl
                console.log('[LOGIN LWC] Login successful. Redirect URL:', result.redirectUrl);
                
                // Site.login() already redirects, but if we're still here, use the redirect URL
                // or navigate to Home page directly
                if (result.redirectUrl) {
                    // Use the redirect URL from Apex (should be /s/ for Home page)
                    console.log('[LOGIN LWC] Using redirect URL from Apex:', result.redirectUrl);
                    window.location.href = result.redirectUrl;
                } else {
                    // Fallback: navigate to Home page using NavigationMixin
                    console.log('[LOGIN LWC] No redirect URL, navigating to Home using NavigationMixin');
                    try {
                        const pageRef = {
                            type: 'comm__namedPage',
                            attributes: {
                                name: 'Home'
                            }
                        };
                        
                        const navPromise = this[NavigationMixin.Navigate](pageRef);
                        
                        if (navPromise && typeof navPromise === 'object' && typeof navPromise.then === 'function') {
                            navPromise.catch(error => {
                                console.error('[LOGIN LWC] NavigationMixin failed, using fallback:', error);
                                // Fallback to /s/
                                window.location.href = '/s/';
                            });
                        } else {
                            // NavigationMixin didn't return a promise, use fallback
                            window.location.href = '/s/';
                        }
                    } catch (navError) {
                        console.error('[LOGIN LWC] Error during navigation to Home:', navError);
                        // Final fallback
                        window.location.href = '/s/';
                    }
                }
            } else {
                this.errorMessage = result.error || 'Invalid username or password. Please try again.';
                this.showErrorToast('Login Failed', this.errorMessage);
            }
        } catch (error) {
            console.error('Login error:', error);
            const errorMsg = error.body?.message || error.message || 'An error occurred during login. Please try again.';
            this.errorMessage = errorMsg;
            this.showErrorToast('Login Error', errorMsg);
        } finally {
            this.isLoading = false;
        }
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
    
    get welcomeMessage() {
        const siteName = this.siteInfo.siteName;
        if (siteName === 'SLB') {
            return 'Welcome to the Massage Therapy Licensing Database!';
        }
        return `Welcome to ${this.siteInfo.displayName || 'FSMTB'}!`;
    }
    
    get showForgotPassword() {
        return this.pageUrls.forgotPasswordUrl;
    }
    
    // Navigation handlers
    handleForgotUsername(event) {
        event.preventDefault();
        event.stopPropagation();
        this.navigateToForgotUsername();
    }
    
    handleForgotPassword(event) {
        event.preventDefault();
        event.stopPropagation();
        this.navigateToForgotPassword();
    }
    
    handleRegisterAsProvider(event) {
        event.preventDefault();
        event.stopPropagation();
        this.navigateToRegister();
    }
    
    navigateToForgotUsername() {
        try {
            // First try NavigationMixin with page API name
            const pageRef = {
                type: 'comm__namedPage',
                attributes: {
                    name: 'Forgot_Your_Username__c'
                }
            };
            
            const navPromise = this[NavigationMixin.Navigate](pageRef);
            
            if (navPromise && typeof navPromise === 'object' && typeof navPromise.then === 'function') {
                navPromise.catch(error => {
                    console.error('[LOGIN LWC] NavigationMixin failed, using URL fallback:', error);
                    this.navigateToForgotUsernameUrl();
                });
            } else {
                // NavigationMixin didn't return a promise, use URL fallback
                this.navigateToForgotUsernameUrl();
            }
        } catch (navError) {
            console.error('[LOGIN LWC] Navigation error, using URL fallback:', navError);
            this.navigateToForgotUsernameUrl();
        }
    }
    
    navigateToForgotUsernameUrl() {
        try {
            const currentPath = window.location.pathname;
            const sIndex = currentPath.indexOf('/s/');
            
            if (sIndex !== -1) {
                const communityBase = currentPath.substring(0, sIndex + 3);
                const fullUrl = `${window.location.origin}${communityBase}forgot-your-username`;
                console.log('[LOGIN LWC] Navigating to Forgot Username URL:', fullUrl);
                window.location.href = fullUrl;
            } else {
                window.location.href = '/s/forgot-your-username';
            }
        } catch (urlError) {
            console.error('[LOGIN LWC] Error constructing URL:', urlError);
            window.location.href = '/s/forgot-your-username';
        }
    }
    
    navigateToForgotPassword() {
        try {
            const pageRef = {
                type: 'comm__namedPage',
                attributes: {
                    name: 'Forgot_Password'
                }
            };
            
            const navPromise = this[NavigationMixin.Navigate](pageRef);
            
            if (navPromise && typeof navPromise === 'object' && typeof navPromise.then === 'function') {
                navPromise.catch(error => {
                    console.error('[LOGIN LWC] NavigationMixin failed, using URL fallback:', error);
                    const currentPath = window.location.pathname;
                    const sIndex = currentPath.indexOf('/s/');
                    if (sIndex !== -1) {
                        const communityBase = currentPath.substring(0, sIndex + 3);
                        window.location.href = `${window.location.origin}${communityBase}login/ForgotPassword`;
                    } else {
                        window.location.href = '/s/login/ForgotPassword';
                    }
                });
            } else {
                const currentPath = window.location.pathname;
                const sIndex = currentPath.indexOf('/s/');
                if (sIndex !== -1) {
                    const communityBase = currentPath.substring(0, sIndex + 3);
                    window.location.href = `${window.location.origin}${communityBase}login/ForgotPassword`;
                } else {
                    window.location.href = '/s/login/ForgotPassword';
                }
            }
        } catch (navError) {
            console.error('[LOGIN LWC] Navigation error:', navError);
            window.location.href = '/s/login/ForgotPassword';
        }
    }
    
    navigateToRegister() {
        try {
            const pageRef = {
                type: 'comm__namedPage',
                attributes: {
                    name: 'CE_Registry__c'
                }
            };
            
            const navPromise = this[NavigationMixin.Navigate](pageRef);
            
            if (navPromise && typeof navPromise === 'object' && typeof navPromise.then === 'function') {
                navPromise.catch(error => {
                    console.error('[LOGIN LWC] NavigationMixin failed, using URL fallback:', error);
                    const currentPath = window.location.pathname;
                    const sIndex = currentPath.indexOf('/s/');
                    if (sIndex !== -1) {
                        const communityBase = currentPath.substring(0, sIndex + 3);
                        window.location.href = `${window.location.origin}${communityBase}ce-registry`;
                    } else {
                        window.location.href = '/s/ce-registry';
                    }
                });
            } else {
                const currentPath = window.location.pathname;
                const sIndex = currentPath.indexOf('/s/');
                if (sIndex !== -1) {
                    const communityBase = currentPath.substring(0, sIndex + 3);
                    window.location.href = `${window.location.origin}${communityBase}ce-registry`;
                } else {
                    window.location.href = '/s/ce-registry';
                }
            }
        } catch (navError) {
            console.error('[LOGIN LWC] Navigation error:', navError);
            window.location.href = '/s/ce-registry';
        }
    }
    
    handleLogoError(event) {
        // Hide logo if it fails to load
        if (event.target) {
            event.target.style.display = 'none';
        }
    }
    
    handleBannerImageError(event) {
        // Hide banner image if it fails to load
        if (event.target) {
            event.target.style.display = 'none';
        }
    }
}

