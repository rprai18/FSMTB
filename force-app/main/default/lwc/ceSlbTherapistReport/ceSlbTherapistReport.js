import { LightningElement, track, wire } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import GOOGLE_ANALYTICS from '@salesforce/resourceUrl/GoogleAnalytics';
import Icons from '@salesforce/resourceUrl/Icons';
import getTherapistReportData from '@salesforce/apex/CeSlbTherapistReportLwcController.getTherapistReportData';

export default class CeSlbTherapistReport extends NavigationMixin(LightningElement) {
    @track contact = null;
    @track contactInformations = [];
    @track licenses = [];
    @track schools = [];
    @track disciplinaryActions = [];
    @track pceWrappers = [];
    @track hasUserManagementAccess = false;
    @track isLoading = true;
    @track error = null;
    
    therapistId = null;
    @track iconsBaseUrl = Icons;
    pageRefLoaded = false;
    
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (!currentPageReference) return;
        
        this.pageRefLoaded = true;
        const state = currentPageReference.state || {};
        const idFromState = state.id || state.c__id || state.recordId;
        
        if (idFromState) {
            this.therapistId = idFromState;
            this.loadReportData();
        } else {
            this.checkUrlForId();
        }
    }
    
    connectedCallback() {
        // When navigating back to this page, reset state so we always show correct Therapist Report UI (not stale or wrong view)
        this.contact = null;
        this.contactInformations = [];
        this.licenses = [];
        this.schools = [];
        this.disciplinaryActions = [];
        this.pceWrappers = [];
        this.error = null;
        this.isLoading = true;
        
        // Load Google Analytics
        loadScript(this, GOOGLE_ANALYTICS)
            .then(() => {
                console.log('✅ GTM script loaded successfully');
            })
            .catch(error => {
                console.error('❌ Failed to load GTM script', error);
            });
        
        // Always re-read therapistId from URL when component is connected (e.g. after navigating back)
        this.checkUrlForId();
    }
    
    checkUrlForId() {
        if (typeof window === 'undefined') return;
        
        const pathname = window.location.pathname || '';
        const href = window.location.href || '';
        // Only run URL logic when we're actually on the therapist report page (avoid overwriting state when on other pages)
        if (!pathname.includes('therapist-report') && !href.includes('therapist-report')) {
            return;
        }
        
        const urlParams = new URLSearchParams(window.location.search);
        const idFromQuery = urlParams.get('id') || urlParams.get('recordId');
        
        if (idFromQuery) {
            this.therapistId = idFromQuery;
        }
        
        if (!this.therapistId && window.location.hash) {
            const hashParams = new URLSearchParams(window.location.hash.substring(1));
            this.therapistId = hashParams.get('id') || hashParams.get('recordId');
        }
        
        if (!this.therapistId) {
            const pathParts = pathname.split('/');
            const lastPart = pathParts[pathParts.length - 1];
            if (lastPart && (lastPart.length === 15 || lastPart.length === 18) && /^[a-zA-Z0-9]+$/.test(lastPart)) {
                this.therapistId = lastPart;
            }
        }
        
        if (this.therapistId) {
            this.loadReportData();
        } else if (this.pageRefLoaded) {
            this.error = 'Therapist ID is missing from URL parameters';
            this.isLoading = false;
        }
    }
    
    renderedCallback() {
        // Final check after rendering in case wire service is delayed
        if (!this.therapistId && !this.contact && !this.error) {
            setTimeout(() => {
                if (!this.therapistId) {
                    this.checkUrlForId();
                }
            }, 100);
        }
    }
    
    async loadReportData() {
        if (!this.therapistId) {
            this.error = 'Therapist ID is required';
            this.isLoading = false;
            return;
        }
        
        try {
            this.isLoading = true;
            const reportData = await getTherapistReportData({ therapistId: this.therapistId });
            
            // Format dates for contact
            if (reportData.contact) {
                this.contact = {
                    ...reportData.contact,
                    formattedBirthdate: this.formatDate(reportData.contact.birthdate),
                    formattedDateOfDeath: this.formatDate(reportData.contact.dateOfDeath)
                };
            }
            
            // Format dates for contact informations
            this.contactInformations = (reportData.contactInformations || []).map(ci => ({
                ...ci,
                formattedSystemModstamp: this.formatDate(ci.systemModstamp)
            }));
            
            // Format dates for licenses
            this.licenses = (reportData.licenses || []).map(lic => ({
                ...lic,
                formattedIssueDate: this.formatDate(lic.issueDate),
                formattedExpirationDate: this.formatDate(lic.expirationDate)
            }));
            
            // Format dates for schools
            this.schools = (reportData.schools || []).map(school => ({
                ...school,
                formattedCompletionDate: this.formatDate(school.completionGraduationDate),
                formattedSystemModstamp: this.formatDate(school.systemModstamp)
            }));
            
            // Format dates for disciplinary actions
            this.disciplinaryActions = (reportData.disciplinaryActions || []).map(da => ({
                ...da,
                formattedDateOfLastAction: this.formatDate(da.dateOfLastAction)
            }));
            
            // Format dates and icon URLs for PCE
            this.pceWrappers = (reportData.pceWrappers || []).map(pce => ({
                ...pce,
                formattedCompletedOn: this.formatDate(pce.completedOn),
                iconUrl: pce.imageUrl ? `${this.iconsBaseUrl}/${pce.imageUrl}` : ''
            }));
            
            this.hasUserManagementAccess = reportData.hasUserManagementAccess || false;
            
            this.isLoading = false;
        } catch (error) {
            console.error('Error loading therapist report:', error);
            this.error = 'Error loading therapist report: ' + (error.body?.message || error.message);
            this.isLoading = false;
        }
    }
    
    // Format date helper - accessible from template
    formatDate(dateValue) {
        if (!dateValue) return '';
        // Handle both Date and DateTime
        let date;
        if (typeof dateValue === 'string') {
            date = new Date(dateValue);
        } else if (dateValue instanceof Date) {
            date = dateValue;
        } else {
            // Assume it's a timestamp or date string
            date = new Date(dateValue);
        }
        
        if (isNaN(date.getTime())) return '';
        
        const month = date.getMonth() + 1;
        const day = date.getDate();
        const year = date.getFullYear();
        return `${month}/${day}/${year}`;
    }
    
    // Getter methods for legend icons
    get revokedIconUrl() {
        return `${this.iconsBaseUrl}/CE_Action_Icons/revoked-warning.png`;
    }
    
    get restrictedIconUrl() {
        return `${this.iconsBaseUrl}/CE_Action_Icons/restricted-warning.png`;
    }
    
    get underReviewIconUrl() {
        return `${this.iconsBaseUrl}/CE_Action_Icons/under-review-eye.png`;
    }
    
    get provisionalIconUrl() {
        return `${this.iconsBaseUrl}/CE_Action_Icons/provisional-flag.png`;
    }
    
    // Get therapist full name
    get therapistFullName() {
        if (!this.contact) return '';
        const parts = [];
        if (this.contact.FirstName) parts.push(this.contact.FirstName);
        if (this.contact.Middle_Name__c) parts.push(this.contact.Middle_Name__c);
        if (this.contact.LastName) parts.push(this.contact.LastName);
        if (this.contact.Suffix__c) parts.push(this.contact.Suffix__c);
        return parts.join(' ');
    }
    
    // Get icon URL - accessible from template
    getIconUrl(imagePath) {
        if (!imagePath) return '';
        return `${this.iconsBaseUrl}/${imagePath}`;
    }
    
    // Helper to format dates in template (for use with @api or getter)
    get formattedBirthdate() {
        return this.formatDate(this.contact?.Birthdate);
    }
    
    get formattedDateOfDeath() {
        return this.formatDate(this.contact?.Date_Of_Death__c);
    }
    
    // Legend icon URLs
    get revokedIconUrl() {
        return `${this.iconsBaseUrl}/CE_Action_Icons/revoked-warning.png`;
    }
    
    get restrictedIconUrl() {
        return `${this.iconsBaseUrl}/CE_Action_Icons/restricted-warning.png`;
    }
    
    get underReviewIconUrl() {
        return `${this.iconsBaseUrl}/CE_Action_Icons/under-review-eye.png`;
    }
    
    get provisionalIconUrl() {
        return `${this.iconsBaseUrl}/CE_Action_Icons/provisional-flag.png`;
    }
    
    // Navigate to PCE report (Professional Continuing Education Record page)
    handlePCEReportClick(event) {
        event.preventDefault();
        const target = event.currentTarget;
        const recordId = target.dataset.recordId;
        const contactId = target.dataset.contactId;
        const url = target.dataset.url;
        if (recordId && contactId) {
            try {
                this[NavigationMixin.Navigate]({
                    type: 'comm__namedPage',
                    attributes: { name: 'Slb_Pce_Report__c' },
                    state: { recordId: recordId, id: contactId }
                });
            } catch (err) {
                if (url) window.location.href = url;
            }
        } else if (url) {
            window.location.href = url;
        }
    }
    
    // Remove unused methods
    // formatDate, getIconUrl, therapistFullName are still used internally
}
