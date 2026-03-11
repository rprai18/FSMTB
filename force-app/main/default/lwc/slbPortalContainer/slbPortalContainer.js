import { LightningElement, api, wire } from 'lwc';
import FSMTBAssets from '@salesforce/resourceUrl/FSMTBAssets';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
// Start added FR-90
import logoutIcon from '@salesforce/resourceUrl/SLBPortal_logoutIcon';
import settingsIcon from '@salesforce/resourceUrl/SLBPortal_settingsIcon';
import { getRecord } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import PROFILE_NAME from '@salesforce/schema/User.Profile.Name';
// End added FR-90 

export default class SlbPortalContainer extends NavigationMixin(LightningElement) {
    // Start added FR-90
    logoutIcon = logoutIcon;
    settingsIcon = settingsIcon;
    isSlbAdmin = false;
    // End added FR-90 
    
    therapistsearchTab = 'therapistsearch';
    reportsTab = 'reports';
    usermanagementTab = 'usermanagement';
    label = {
        therapistSearch: 'Therapist Search',
        reports: 'Reports',
        userManagement: 'User Management'
    };

    @api activeTab = this.therapistsearchTab; // default tab
    @api portalHeader = 'SLB Portal';

    commHomePage = 'Home';
    //commTherapistSearchPage = 'Therapist_Search__c';
    commReportsPage = 'Reports__c';
    commUserMgmtPage = 'UserManagement__c';

    logoUrl = `${FSMTBAssets}/FSMTBAssets/images/logo.svg`;
    
    // Track if component has been initialized
    initialized = false;
    
    connectedCallback() {
        // Set activeTab based on current page URL
        this.determineActiveTabFromUrl();
        this.initialized = true;
    }
    
    // Wire to CurrentPageReference to detect page changes
    @wire(CurrentPageReference)
    updateActiveTabFromPageRef(currentPageReference) {
        if (currentPageReference && this.initialized) {
            this.determineActiveTabFromUrl();
        }
    }
    
    // Determine active tab from current URL
    determineActiveTabFromUrl() {
        if (typeof window === 'undefined') return;
        
        try {
            const currentPath = window.location.pathname.toLowerCase();
            const currentUrl = window.location.href.toLowerCase();
            
            // Check if we're on User Management page
            if (currentPath.includes('/user-management') || 
                currentPath.includes('usermanagement') ||
                currentUrl.includes('usermanagement')) {
                if (this.activeTab !== this.usermanagementTab) {
                    this.activeTab = this.usermanagementTab;
                }
            }
            // Check if we're on Reports page (only when path is explicitly /reports, not therapist-report)
            else if ((currentPath.includes('/reports') || currentUrl.includes('/reports')) &&
                     !currentPath.includes('therapist-report') &&
                     !currentUrl.includes('therapist-report')) {
                if (this.activeTab !== this.reportsTab) {
                    this.activeTab = this.reportsTab;
                }
            }
            // Therapist Report or Therapist Search: show Therapist Search tab as active
            else {
                if (this.activeTab !== this.therapistsearchTab) {
                    this.activeTab = this.therapistsearchTab;
                }
            }
        } catch (error) {
            console.error('Error determining active tab from URL:', error);
            this.activeTab = this.therapistsearchTab;
        }
    }

    handleTabClick(event) {
        const tab = event.currentTarget?.dataset?.tab;
        if (!tab) {
            return;
        }

        this.activeTab = tab;

        if (tab === this.reportsTab) {
            // Navigate to the Reports community named page, which should host the slbReports LWC
            this.navigateToCommPage(this.commReportsPage, null);
            return;
        }

        if (tab === this.usermanagementTab) {
            this.navigateToCommPage(this.commUserMgmtPage, null);
            return;
        }

        // Default to Home / Therapist Search
        this.navigateToCommPage(this.commHomePage, null);
    }

    get isTherapistSearch() {
        return this.activeTab === this.therapistsearchTab;
    }
    get isReports() {
        return this.activeTab === this.reportsTab;
    }
    get isUserManagement() {
        return this.activeTab === this.usermanagementTab;
    }

    // SLDS tab button classes
    get therapistSearchTabClass() {
        return this.isTherapistSearch ? 'slb-tab slb-tab_active' : 'slb-tab';
    }
    get reportsTabClass() {
        return this.isReports ? 'slb-tab slb-tab_active' : 'slb-tab';
    }
    get userManagementTabClass() {
        return this.isUserManagement ? 'slb-tab slb-tab_active' : 'slb-tab';
    }

    navigateToCommPage(pageName, params) {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: pageName,
            },
            state: params
        });
    }

    // Start added FR-90
    @wire(getRecord, { recordId: USER_ID, fields: [PROFILE_NAME] })
    userDetails({ data }) {
        if (data) {
            this.isSlbAdmin = data.fields.Profile.value.fields.Name.value === 'SLB Portal Administrator';
        }
    }
    openSettings() {
        // Set activeTab before navigating to maintain state
        this.activeTab = this.usermanagementTab;
        this.navigateToCommPage(this.commUserMgmtPage, null);
    }
    openHomePage() {
        // Set activeTab before navigating to maintain state
        this.activeTab = this.therapistsearchTab;
        this.navigateToCommPage(this.commHomePage, null);
    }
    handleLogout() {
        window.location.href = '/secur/logout.jsp';
    }
    // End added FR-90
}