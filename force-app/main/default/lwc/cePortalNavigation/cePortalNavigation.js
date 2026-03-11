import { LightningElement, track, wire } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import { NavigationMixin } from 'lightning/navigation';
import FSMTBAssets from '@salesforce/resourceUrl/FSMTBAssets';
import SchibstedGroteskFont from '@salesforce/resourceUrl/Schibsted_Grotesk_Font';
import getUserInfo from '@salesforce/apex/PortalNavigationController.getUserInfo';
import getLogoutUrl from '@salesforce/apex/PortalNavigationController.getLogoutUrl';

export default class CePortalNavigation extends NavigationMixin(LightningElement) {
    @track activeTab = 'courseManagement';
    @track userName = '';
    @track isGuest = false;
    @track showUserMenu = false;
    @track showMobileMenu = false; // For hamburger menu
    
    // Logo path from static resource
    logoUrl = `${FSMTBAssets}/FSMTBAssets/images/logo.svg`;
    
    // Font path from static resource
    fontUrl = SchibstedGroteskFont;

    connectedCallback() {
        // Check if logout is in progress - if so, redirect immediately to login page
        if (sessionStorage.getItem('logoutInProgress') === 'true') {
            sessionStorage.removeItem('logoutInProgress');
            // Redirect to login page
            const currentPath = window.location.pathname;
            const sIndex = currentPath.indexOf('/s/');
            if (sIndex !== -1) {
                const communityBase = currentPath.substring(0, sIndex + 3);
                const loginUrl = `${window.location.origin}${communityBase}login`;
                window.location.replace(loginUrl);
            } else {
                window.location.replace('/s/login');
            }
            return;
        }
        
        // Set default tab based on URL or default to Course Management
        const urlParams = new URLSearchParams(window.location.search);
        const tab = urlParams.get('tab');
        if (tab) {
            this.activeTab = tab;
        }
        
        // Listen for browser back/forward button to update tab
        this.handlePopState = (event) => {
            if (event.state && event.state.tab) {
                this.activeTab = event.state.tab;
            } else {
                // If no state, check URL params
                const urlParams = new URLSearchParams(window.location.search);
                const tab = urlParams.get('tab');
                if (tab) {
                    this.activeTab = tab;
                }
            }
        };
        window.addEventListener('popstate', this.handlePopState);
        
        // Load font CSS if available
        this.loadFont();
        
        // Close user menu when clicking outside
        this.handleClickOutside = this.handleClickOutside.bind(this);
        document.addEventListener('click', this.handleClickOutside);
        
        // Add beforeunload listener to clear session on page unload
        this.boundBeforeUnload = () => {
            if (sessionStorage.getItem('logoutInProgress') === 'true') {
                // Clear everything on page unload
                try {
                    localStorage.clear();
                    sessionStorage.clear();
                } catch (e) {
                    // Ignore errors
                }
            }
        };
        window.addEventListener('beforeunload', this.boundBeforeUnload);
    }
    
    disconnectedCallback() {
        // Clean up event listeners
        document.removeEventListener('click', this.handleClickOutside);
        if (this.boundBeforeUnload) {
            window.removeEventListener('beforeunload', this.boundBeforeUnload);
        }
        if (this.handlePopState) {
            window.removeEventListener('popstate', this.handlePopState);
        }
    }
    
    // Wire user info
    @wire(getUserInfo)
    wiredUserInfo({ data, error }) {
        if (data) {
            console.log('[PORTAL NAV] User info data:', data);
            // Use full name
            this.userName = data.fullName || data.firstName || 'User';
            this.isGuest = data.isGuest || false;
            if (!this.userName || this.userName === 'User') {
                console.warn('[PORTAL NAV] User name not properly set, data:', data);
            }
        } else if (error) {
            console.error('[PORTAL NAV] Error fetching user info:', error);
            console.error('[PORTAL NAV] Error details:', JSON.stringify(error));
            // Try to get name from error body if available
            if (error.body && error.body.message) {
                console.error('[PORTAL NAV] Error message:', error.body.message);
            }
            this.userName = 'User';
            this.isGuest = false;
        }
    }
    
    loadFont() {
        // Inject @font-face rules dynamically using the static resource URL
        // Adjust font file names based on your actual static resource structure
        const style = document.createElement('style');
        style.textContent = `
            @font-face {
                font-family: 'Schibsted Grotesk';
                src: url('${this.fontUrl}/SchibstedGrotesk-Regular.woff2') format('woff2'),
                     url('${this.fontUrl}/SchibstedGrotesk-Regular.woff') format('woff'),
                     url('${this.fontUrl}/SchibstedGrotesk-Regular.ttf') format('truetype'),
                     url('${this.fontUrl}/Regular.woff2') format('woff2'),
                     url('${this.fontUrl}/Regular.woff') format('woff'),
                     url('${this.fontUrl}/Regular.ttf') format('truetype');
                font-weight: 400;
                font-style: normal;
                font-display: swap;
            }
            @font-face {
                font-family: 'Schibsted Grotesk';
                src: url('${this.fontUrl}/SchibstedGrotesk-Medium.woff2') format('woff2'),
                     url('${this.fontUrl}/SchibstedGrotesk-Medium.woff') format('woff'),
                     url('${this.fontUrl}/SchibstedGrotesk-Medium.ttf') format('truetype'),
                     url('${this.fontUrl}/Medium.woff2') format('woff2'),
                     url('${this.fontUrl}/Medium.woff') format('woff'),
                     url('${this.fontUrl}/Medium.ttf') format('truetype');
                font-weight: 500;
                font-style: normal;
                font-display: swap;
            }
            @font-face {
                font-family: 'Schibsted Grotesk';
                src: url('${this.fontUrl}/SchibstedGrotesk-Bold.woff2') format('woff2'),
                     url('${this.fontUrl}/SchibstedGrotesk-Bold.woff') format('woff'),
                     url('${this.fontUrl}/SchibstedGrotesk-Bold.ttf') format('truetype'),
                     url('${this.fontUrl}/Bold.woff2') format('woff2'),
                     url('${this.fontUrl}/Bold.woff') format('woff'),
                     url('${this.fontUrl}/Bold.ttf') format('truetype');
                font-weight: 700;
                font-style: normal;
                font-display: swap;
            }
        `;
        document.head.appendChild(style);
    }

    // handleTabClick(event) {
    //     event.preventDefault();
    //     event.stopPropagation();
        
    //     // Handle both click and keyboard events (Enter/Space)
    //     if (event.type === 'keydown') {
    //         if (event.key !== 'Enter' && event.key !== ' ') {
    //             return;
    //         }
    //     }
        
    //     const tab = event.currentTarget.dataset.tab;
    //     if (tab) {
    //         this.activeTab = tab;
    //         // Update URL without page reload
    //         const url = new URL(window.location);
    //         url.searchParams.set('tab', tab);
    //         window.history.pushState({}, '', url);
    //     }
    // }
    handleTabClick(event) {
        event.preventDefault();
        event.stopPropagation();
        
        // Handle keyboard accessibility
        if (event.type === 'keydown') {
            if (event.key !== 'Enter' && event.key !== ' ') {
                return;
            }
        }
    
        const tab = event.currentTarget.dataset.tab;
        if (tab) {
            // Only update if different tab to avoid unnecessary re-renders
            if (tab !== this.activeTab) {
                // Update active tab immediately (no page reload)
                this.activeTab = tab;
                
                // Update URL without page reload using history API
                const url = new URL(window.location);
                url.searchParams.set('tab', tab);
                window.history.pushState({ tab: tab }, '', url);
            }
        }
    }
    

    get showCourseManagement() {
        return this.activeTab === 'courseManagement';
    }

    get showRosterUpload() {
        return this.activeTab === 'rosterUpload';
    }

    get showSurveyFeedback() {
        return this.activeTab === 'surveyFeedback';
    }

    get showInstructorManagement() {
        return this.activeTab === 'instructorManagement';
    }

    get showAccountAdministration() {
        return this.activeTab === 'accountAdministration';
    }
    
    // CSS classes to show/hide components instead of destroying/recreating them
    get showCourseManagementClass() {
        return this.activeTab === 'courseManagement' ? 'tab-content tab-content--active' : 'tab-content tab-content--hidden';
    }

    get showRosterUploadClass() {
        return this.activeTab === 'rosterUpload' ? 'tab-content tab-content--active' : 'tab-content tab-content--hidden';
    }

    get showSurveyFeedbackClass() {
        return this.activeTab === 'surveyFeedback' ? 'tab-content tab-content--active' : 'tab-content tab-content--hidden';
    }

    get showInstructorManagementClass() {
        return this.activeTab === 'instructorManagement' ? 'tab-content tab-content--active' : 'tab-content tab-content--hidden';
    }

    get showAccountAdministrationClass() {
        return this.activeTab === 'accountAdministration' ? 'tab-content tab-content--active' : 'tab-content tab-content--hidden';
    }

    get tabClassCourseManagement() {
        return this.activeTab === 'courseManagement' ? 'nav-link nav-link--active' : 'nav-link';
    }

    get tabClassRosterUpload() {
        return this.activeTab === 'rosterUpload' ? 'nav-link nav-link--active' : 'nav-link';
    }

    get tabClassSurveyFeedback() {
        return this.activeTab === 'surveyFeedback' ? 'nav-link nav-link--active' : 'nav-link';
    }

    get tabClassInstructorManagement() {
        return this.activeTab === 'instructorManagement' ? 'nav-link nav-link--active' : 'nav-link';
    }
    
    get hamburgerIconName() {
        return this.showMobileMenu ? 'utility:close' : 'utility:menu';
    }
    
    // Handle gear icon click - navigate to Account Administration
    handleGearClick(event) {
        event.preventDefault();
        event.stopPropagation();
        
        try {
            // Update active tab immediately (no page reload)
            this.activeTab = 'accountAdministration';
            
            // Update URL without page reload using history API
            const url = new URL(window.location);
            url.searchParams.set('tab', 'accountAdministration');
            window.history.pushState({ tab: 'accountAdministration' }, '', url);
        } catch (error) {
            console.error('Error navigating to Account Administration:', error);
        }
    }
    
    // Handle user name click - toggle dropdown menu
    handleUserNameClick(event) {
        event.preventDefault();
        event.stopPropagation();
        // Use setTimeout to ensure the menu renders after state change
        this.showUserMenu = !this.showUserMenu;
        if (this.showUserMenu) {
            // Force re-render to ensure menu is visible and positioned correctly
            setTimeout(() => {
                const userMenu = this.template.querySelector('.user-menu');
                const userNameButton = this.template.querySelector('.user-name-button');
                if (userMenu && userNameButton) {
                    // Get button position relative to viewport
                    const buttonRect = userNameButton.getBoundingClientRect();
                    // Position menu below button using fixed positioning
                    userMenu.style.position = 'fixed';
                    userMenu.style.top = (buttonRect.bottom + 4) + 'px';
                    userMenu.style.right = (window.innerWidth - buttonRect.right) + 'px';
                    userMenu.style.left = 'auto';
                    userMenu.style.bottom = 'auto';
                    userMenu.style.display = 'block';
                    userMenu.style.visibility = 'visible';
                    userMenu.style.opacity = '1';
                    userMenu.style.zIndex = '99999';
                }
            }, 0);
        }
    }
    
    // Handle logout click
    async handleLogout(event) {
        event.preventDefault();
        event.stopPropagation();
        this.showUserMenu = false; // Close menu
        
        // Mark that logout is in progress to prevent any further actions
        sessionStorage.setItem('logoutInProgress', 'true');
        
        // Clear any local storage or session data to kill session
        try {
            // Clear all cookies more aggressively
            const cookies = document.cookie.split(";");
            for (let i = 0; i < cookies.length; i++) {
                const cookie = cookies[i];
                const eqPos = cookie.indexOf("=");
                const name = eqPos > -1 ? cookie.substr(0, eqPos).trim() : cookie.trim();
                // Clear cookie for current path
                document.cookie = name + "=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/";
                // Clear cookie for root path
                document.cookie = name + "=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/;domain=" + window.location.hostname;
                // Clear cookie for parent domain
                const domainParts = window.location.hostname.split('.');
                if (domainParts.length > 2) {
                    const parentDomain = '.' + domainParts.slice(-2).join('.');
                    document.cookie = name + "=;expires=Thu, 01 Jan 1970 00:00:00 GMT;path=/;domain=" + parentDomain;
                }
            }
            
            // Clear storage
            localStorage.clear();
            sessionStorage.clear();
        } catch (e) {
            console.warn('Could not clear storage:', e);
        }
        
        // Redirect to login page after logout
        // Get the current community base URL to construct login page URL
        try {
            const currentUrl = new URL(window.location.href);
            const currentPath = window.location.pathname;
            
            // Find the community path (usually contains /s/)
            const sIndex = currentPath.indexOf('/s/');
            if (sIndex !== -1) {
                // Construct login page URL: communityPath/s/login
                const communityBase = currentPath.substring(0, sIndex + 3);
                const loginUrl = `${currentUrl.origin}${communityBase}login`;
                console.log('[LOGOUT] Redirecting to login page:', loginUrl);
                
                if (!this.isGuest) {
                    // Logged-in user - get logout URL from Apex with login page as retURL
                    try {
                        // First, construct the login page URL
                        const loginPageUrl = `${currentUrl.origin}${communityBase}login`;
                        
                        // Get logout URL from Apex, but we'll override retURL to go to login
                        const logoutUrl = await getLogoutUrl();
                        console.log('[LOGOUT] Logout URL from Apex:', logoutUrl);
                        
                        // Construct logout URL with login page as return URL
                        let finalLogoutUrl;
                        if (logoutUrl.includes('retURL=')) {
                            // Replace existing retURL
                            finalLogoutUrl = logoutUrl.replace(/retURL=[^&]*/, `retURL=${encodeURIComponent(loginPageUrl)}`);
                        } else {
                            // Add retURL parameter
                            const separator = logoutUrl.includes('?') ? '&' : '?';
                            finalLogoutUrl = `${logoutUrl}${separator}retURL=${encodeURIComponent(loginPageUrl)}`;
                        }
                        
                        console.log('[LOGOUT] Final logout URL with login redirect:', finalLogoutUrl);
                        
                        // Use replace() to prevent back button navigation
                        setTimeout(() => {
                            window.location.replace(finalLogoutUrl);
                        }, 100);
                    } catch (error) {
                        console.error('Error getting logout URL from Apex:', error);
                        // Fallback: Try to construct logout URL manually with login page as retURL
                        try {
                            const loginPageUrl = `${currentUrl.origin}${communityBase}login`;
                            let logoutUrl;
                            
                            if (currentUrl.origin.includes('.my.site.com')) {
                                // Extract instance part and construct Salesforce URL
                                const hostParts = currentUrl.origin.split('.');
                                if (hostParts.length >= 3) {
                                    const instancePart = hostParts[0];
                                    logoutUrl = `https://${instancePart}.salesforce.com/secur/logout.jsp?retURL=${encodeURIComponent(loginPageUrl)}`;
                                } else {
                                    logoutUrl = `${currentUrl.origin}/secur/logout.jsp?retURL=${encodeURIComponent(loginPageUrl)}`;
                                }
                            } else {
                                logoutUrl = `${currentUrl.origin}/secur/logout.jsp?retURL=${encodeURIComponent(loginPageUrl)}`;
                            }
                            
                            console.log('[LOGOUT] Using fallback logout URL:', logoutUrl);
                            setTimeout(() => {
                                window.location.replace(logoutUrl);
                            }, 100);
                        } catch (e2) {
                            // Final fallback: Direct redirect to login page
                            console.log('[LOGOUT] Using final fallback - direct redirect to login');
                            setTimeout(() => {
                                window.location.replace(loginUrl);
                            }, 100);
                        }
                    }
                } else {
                    // Guest user - directly redirect to login page
                    console.log('[LOGOUT] Guest user - redirecting to login page');
                    setTimeout(() => {
                        window.location.replace(loginUrl);
                    }, 100);
                }
            } else {
                // Could not determine community path, try NavigationMixin
                console.log('[LOGOUT] Could not determine community path, using NavigationMixin');
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
                            console.error('[LOGOUT] NavigationMixin failed, using fallback:', error);
                            // Fallback: try /s/login
                            setTimeout(() => {
                                window.location.replace('/s/login');
                            }, 100);
                        });
                    } else {
                        // NavigationMixin didn't return a promise, use fallback
                        setTimeout(() => {
                            window.location.replace('/s/login');
                        }, 100);
                    }
                } catch (navError) {
                    console.error('[LOGOUT] Navigation error:', navError);
                    // Final fallback
                    setTimeout(() => {
                        window.location.replace('/s/login');
                    }, 100);
                }
            }
        } catch (e) {
            console.error('[LOGOUT] Error constructing login URL:', e);
            // Final fallback: try /s/login
            setTimeout(() => {
                window.location.replace('/s/login');
            }, 100);
        }
    }
    
    // Close user menu when clicking outside
    handleClickOutside(event) {
        const userMenu = this.template.querySelector('.user-menu');
        const userNameButton = this.template.querySelector('.user-name-button');
        const gearButton = this.template.querySelector('.gear-icon-button');
        
        // Don't close if clicking on gear button or user menu elements
        if (gearButton && gearButton.contains(event.target)) {
            return;
        }
        
        if (userMenu && userNameButton) {
            if (!userMenu.contains(event.target) && !userNameButton.contains(event.target)) {
                this.showUserMenu = false;
            }
        }
    }
    
    // Handle mobile menu toggle
    handleMobileMenuToggle(event) {
        event.preventDefault();
        event.stopPropagation();
        this.showMobileMenu = !this.showMobileMenu;
    }
    
    // Handle mobile menu item click
    handleMobileMenuClick(event) {
        event.preventDefault();
        event.stopPropagation();
        
        // Handle keyboard accessibility
        if (event.type === 'keydown') {
            if (event.key !== 'Enter' && event.key !== ' ') {
                return;
            }
        }
        
        const tab = event.currentTarget.dataset.tab;
        if (tab) {
            // Only update if different tab to avoid unnecessary re-renders
            if (tab !== this.activeTab) {
                // Update active tab immediately (no page reload)
                this.activeTab = tab;
                
                // Update URL without page reload using history API
                const url = new URL(window.location);
                url.searchParams.set('tab', tab);
                window.history.pushState({ tab: tab }, '', url);
            }
            
            // Always close mobile menu after click
            this.showMobileMenu = false;
        }
    }
}