import { LightningElement, track, wire, api } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';
import GOOGLE_ANALYTICS from '@salesforce/resourceUrl/GoogleAnalytics';
import portalImages from '@salesforce/resourceUrl/Portal_Images';
import getTherapistSearchData from '@salesforce/apex/CeSlbTherapistSearchLwcController.getTherapistSearchData';
import search from '@salesforce/apex/CeSlbTherapistSearchLwcController.search';
import setShowParticipating from '@salesforce/apex/CeSlbTherapistSearchLwcController.setShowParticipating';

export default class CeSlbTherapistSearch extends NavigationMixin(LightningElement) {
    @track geographicalRegions = [];
    @track showGeographicalRegions = true;
    @track hasUserManagementAccess = false;
    @track isLoading = true;
    @track error;
    
    // Form fields
    @track searchTerm = '';
    @track lastFourSSN = '';
    @track selectedStates = [];
    
    // Search results
    @track allSearchResults = []; // All results from server
    @track displayedResults = []; // Currently displayed results (for infinite scroll)
    @track showResults = false;
    @track showNoResults = false;
    @track isSearching = false;
    @track formError = '';
    @track showFormError = false;
    
    // Infinite scroll
    @track isLoadingMore = false;
    @track enableInfiniteLoading = false;
    loadedCount = 0;
    totalCount = 0;
    batchSize = 25;
    
    // Sorting (client-side)
    @track sortedBy = 'lastName';
    @track sortedDirection = 'asc';
    
    // Configurable message for exam-only results
    @api examOnlyMessage = 'Result has exam results only, no licenses.';
    
    // Images
    portalImages = portalImages;
    headerImage = portalImages + '/FSMTB_header0.png';
    
    gtmInitialized = false;
    @track isStateDialogOpen = false;
    
    // Table columns definition
    tableColumns = [
        {
            label: 'Exam',
            type: 'button-icon',
            initialWidth: 70,
            typeAttributes: {
                iconName: 'utility:assignment',
                alternativeText: 'Exam candidate: has exam results only, no state licenses',
                title: 'Exam candidate: has exam results only, no state licenses',
                name: 'examInfo',
                variant: 'border-filled'
            },
            cellAttributes: {
                class: { fieldName: 'examIconClass' }
            }
        },
        {
            label: 'Last Name',
            fieldName: 'lastName',
            type: 'text',
            sortable: true,
            cellAttributes: { 
                class: { fieldName: 'rowClass' }
            }
        },
        {
            label: 'First Name',
            fieldName: 'firstName',
            type: 'text',
            sortable: true
        },
        {
            label: 'Middle Name',
            fieldName: 'middleName',
            type: 'text',
            sortable: true
        },
        {
            label: 'Also Known As',
            fieldName: 'aka',
            type: 'text',
            sortable: false
        },
        {
            label: 'License State',
            fieldName: 'licenseState',
            type: 'text',
            sortable: true
        },
        {
            label: 'License Number',
            fieldName: 'licenseNumber',
            type: 'text',
            sortable: false
        },
        {
            label: 'Last Four SSN',
            fieldName: 'lastFour',
            type: 'text',
            sortable: false
        },
        {
            label: 'Action',
            type: 'button',
            typeAttributes: {
                label: 'View',
                name: 'view',
                variant: 'base',
                iconName: 'utility:preview',
                iconPosition: 'left'
            }
        }
    ];
    
    @wire(getTherapistSearchData)
    wiredTherapistSearchData({ error, data }) {
        // Always set loading to false when wire completes (whether data or error)
        // This ensures consistent UI regardless of cache state
        if (data) {
            this.geographicalRegions = data.geographicalRegions || [];
            this.showGeographicalRegions = data.showGeographicalRegions != null ? data.showGeographicalRegions : true;
            this.hasUserManagementAccess = data.hasUserManagementAccess || false;
            this.isLoading = false;
            
            // Clear any timeout since wire fired successfully
            if (this.loadingTimeout) {
                clearTimeout(this.loadingTimeout);
                this.loadingTimeout = null;
            }
        } else if (error) {
            this.error = 'Error loading therapist search data: ' + error.body.message;
            this.isLoading = false;
            console.error('Error loading therapist search data:', error);
            
            // Clear any timeout since we got an error
            if (this.loadingTimeout) {
                clearTimeout(this.loadingTimeout);
                this.loadingTimeout = null;
            }
        }
        // Note: If neither data nor error, wire is still loading, so isLoading stays true
    }
    
    connectedCallback() {
        // Always start with loading state for consistent UI
        // Wire service will set it to false when data arrives
        this.isLoading = true;
        this.error = null;
        
        // Set a timeout fallback to ensure loading doesn't get stuck
        // This handles cases where wire service might not fire (shouldn't happen with cacheable=true)
        if (this.loadingTimeout) {
            clearTimeout(this.loadingTimeout);
        }
        this.loadingTimeout = setTimeout(() => {
            // If still loading after 500ms, check if we have data
            // With cacheable=true, wire should fire almost immediately
            if (this.isLoading) {
                if (this.geographicalRegions && this.geographicalRegions.length > 0) {
                    // We have data, wire must have fired with cached data
                    this.isLoading = false;
                } else {
                    // No data - set loading to false to show form (wire might be slow)
                    this.isLoading = false;
                }
            }
        }, 500);
        
        // Load Google Analytics (only once)
        if (!this.gtmInitialized) {
            loadScript(this, GOOGLE_ANALYTICS)
                .then(() => {
                    console.log('✅ GTM script loaded successfully');
                    this.gtmInitialized = true;
                })
                .catch(error => {
                    console.error('❌ Failed to load GTM script', error);
                    this.gtmInitialized = true; // Set to true even on error to prevent retries
                });
        }
    }
    
    disconnectedCallback() {
        // Clean up timeout when component is disconnected
        if (this.loadingTimeout) {
            clearTimeout(this.loadingTimeout);
            this.loadingTimeout = null;
        }
    }
    
    renderedCallback() {
        // Check if we have data but are still loading (wire might have cached data)
        // This ensures we don't get stuck in loading state
        if (this.isLoading && this.geographicalRegions && this.geographicalRegions.length > 0) {
            // We have data, so wire must have fired with cached data
            // Clear the timeout and set loading to false
            if (this.loadingTimeout) {
                clearTimeout(this.loadingTimeout);
                this.loadingTimeout = null;
            }
            this.isLoading = false;
        }
    }
    
    // State options for multi-select
    get stateOptions() {
        return this.geographicalRegions.map(state => ({
            label: state,
            value: state
        }));
    }
    
    // Handle form field changes
    handleSearchTermChange(event) {
        this.searchTerm = event.target.value;
        this.clearFormError();
    }
    
    handleLastFourSSNChange(event) {
        this.lastFourSSN = event.target.value;
        this.clearFormError();
    }
    
    handleStateChange(event) {
        this.selectedStates = event.detail.value || [];
        this.clearFormError();
    }
    
    // Validate form
    validateForm() {
        const searchTermInput = this.template.querySelector('[name="searchTerm"]');
        const lastFourSSNInput = this.template.querySelector('[name="lastFourSSN"]');
        
        // At least one field must be filled (search term, SSN, or state)
        const hasSearchTerm = this.searchTerm && this.searchTerm.trim().length > 0;
        const hasLastFourSSN = this.lastFourSSN && this.lastFourSSN.trim().length > 0;
        const hasStates = this.selectedStates && this.selectedStates.length > 0;
        
        if (!hasSearchTerm && !hasLastFourSSN && !hasStates) {
            this.showFormError = true;
            this.formError = 'Please enter search criteria';
            return false;
        }
        
        // Validate search term: support wildcard * with rules
        if (hasSearchTerm) {
            const term = this.searchTerm.trim();
            
            if (term.includes('*')) {
                // Remove all asterisks and ensure at least 2 real characters remain
                const stripped = term.replace(/\*/g, '').trim();
                if (stripped.length < 2) {
                    this.showFormError = true;
                    this.formError = 'Wildcard searches require at least 2 characters';
                    if (searchTermInput) {
                        searchTermInput.setCustomValidity('Wildcard searches require at least 2 characters');
                        searchTermInput.reportValidity();
                    }
                    return false;
                }
            } else if (term.length < 3) {
                this.showFormError = true;
                this.formError = '3 characters or more are required';
                if (searchTermInput) {
                    searchTermInput.setCustomValidity('3 characters or more are required');
                    searchTermInput.reportValidity();
                }
                return false;
            }
        }
        
        // Validate last four SSN (4 digits)
        if (hasLastFourSSN) {
            const ssnPattern = /^[0-9]{4}$/;
            if (!ssnPattern.test(this.lastFourSSN)) {
                this.showFormError = true;
                this.formError = 'Last four SSN must be 4 digits';
                if (lastFourSSNInput) {
                    lastFourSSNInput.setCustomValidity('Last four SSN must be 4 digits');
                    lastFourSSNInput.reportValidity();
                }
                return false;
            }
        }
        
        this.clearFormError();
        return true;
    }

    // Disable Search button when no criteria entered or while searching
    get isSearchDisabled() {
        const hasSearchTerm = this.searchTerm && this.searchTerm.trim().length > 0;
        const hasLastFourSSN = this.lastFourSSN && this.lastFourSSN.trim().length > 0;
        const hasStates = this.selectedStates && this.selectedStates.length > 0;
        const hasAnyCriteria = hasSearchTerm || hasLastFourSSN || hasStates;
        return this.isSearching || !hasAnyCriteria;
    }
    
    clearFormError() {
        this.formError = '';
        this.showFormError = false;
        
        // Clear custom validity
        const inputs = this.template.querySelectorAll('.js-form-input');
        inputs.forEach(input => {
            input.setCustomValidity('');
            input.reportValidity();
        });
    }
    
    // Perform search (extracted for reuse)
    async performSearch() {
        this.isSearching = true;
        this.showResults = false;
        this.showNoResults = false;
        this.displayedResults = [];
        this.allSearchResults = [];
        
        try {
            const result = await search({
                searchTerm: this.searchTerm || '',
                lastFourSSN: this.lastFourSSN || '',
                stateCodes: this.selectedStates || [],
                pageNum: 0,
                offset: 1000, // Get all results for client-side pagination
                orderBy: this.sortedBy || 'lastName',
                orderDir: this.sortedDirection.toUpperCase()
            });
            
            if (result.success) {
                this.allSearchResults = (result.results || []).map((item, index) => ({
                    ...item,
                    id: item.contactId + '_' + index, // Unique key for each row
                    rowClass: item.isExamCandidate ? 'exam-candidate-row' : '',
                    examIconClass: item.isExamCandidate ? 'exam-icon-cell' : 'exam-icon-cell exam-icon-cell--hidden'
                }));
                
                this.totalCount = this.allSearchResults.length;
                this.loadedCount = 0;
                
                if (this.totalCount > 0) {
                    // Load first batch
                    this.loadMoreResults();
                    this.showResults = true;
                    this.showNoResults = false;
                } else {
                    this.showResults = false;
                    this.showNoResults = true;
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'No Results Found',
                            message: 'No therapists found matching your search criteria. Please try different search terms.',
                            variant: 'info'
                        })
                    );
                }
            } else {
                this.showErrorToast('Search Error', result.message || 'Error performing search');
            }
        } catch (error) {
            console.error('Error performing search:', error);
            this.showErrorToast('Search Error', error.body?.message || error.message || 'An error occurred while searching. Please try again.');
        } finally {
            this.isSearching = false;
        }
    }
    
    // Load more results (infinite scroll)
    loadMoreResults() {
        const start = this.loadedCount;
        const end = Math.min(start + this.batchSize, this.totalCount);
        const newResults = this.allSearchResults.slice(start, end);
        
        this.displayedResults = [...this.displayedResults, ...newResults];
        this.loadedCount = end;
        
        // Enable infinite loading if more results available
        this.enableInfiniteLoading = this.loadedCount < this.totalCount;
    }
    
    // Handle form submit
    async handleSubmit(event) {
        event.preventDefault();
        
        if (!this.validateForm()) {
            return;
        }
        
        await this.performSearch();
    }
    
    // Handle clear form
    handleClear(event) {
        event.preventDefault();
        this.searchTerm = '';
        this.lastFourSSN = '';
        this.selectedStates = [];
        this.allSearchResults = [];
        this.displayedResults = [];
        this.showResults = false;
        this.showNoResults = false;
        this.loadedCount = 0;
        this.totalCount = 0;
        this.clearFormError();
    }
    
    // Handle sort (client-side)
    handleSort(event) {
        const { fieldName: sortedBy, sortDirection } = event.detail;
        this.sortedBy = sortedBy;
        this.sortedDirection = sortDirection;
        
        // Sort all results client-side
        this.sortResults();
        
        // Reset displayed results and reload first batch
        this.loadedCount = 0;
        this.displayedResults = [];
        this.loadMoreResults();
    }
    
    // Sort results client-side
    sortResults() {
        const sortMultiplier = this.sortedDirection === 'asc' ? 1 : -1;
        const field = this.sortedBy;
        
        this.allSearchResults = [...this.allSearchResults].sort((a, b) => {
            let aVal = a[field] || '';
            let bVal = b[field] || '';
            
            // Handle string comparison
            if (typeof aVal === 'string') {
                aVal = aVal.toLowerCase();
                bVal = bVal.toLowerCase();
            }
            
            if (aVal < bVal) return -1 * sortMultiplier;
            if (aVal > bVal) return 1 * sortMultiplier;
            return 0;
        });
    }
    
    // Handle infinite scroll load more
    handleLoadMore(event) {
        event.target.isLoading = true;
        this.isLoadingMore = true;
        
        // Simulate delay for loading (remove in production)
        setTimeout(() => {
            this.loadMoreResults();
            event.target.isLoading = false;
            this.isLoadingMore = false;
        }, 500);
    }
    
    // Show error toast
    showErrorToast(title, message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: 'error',
                mode: 'sticky'
            })
        );
    }
    
    // Dialog handling
    showDialog() {
        this.isStateDialogOpen = true;
    }
    
    hideDialog() {
        this.isStateDialogOpen = false;
    }
    
    handleDialogTrigger(event) {
        event.preventDefault();
        this.showDialog();
    }
    
    @track doNotDisplayAgain = false;
    
    handleDoNotDisplayChange(event) {
        this.doNotDisplayAgain = event.target.checked;
    }
    
    async handleDialogDismiss(event) {
        event.preventDefault();
        
        // Check if "Do Not Display Again" is checked
        if (this.doNotDisplayAgain) {
            try {
                await setShowParticipating({ bool: false });
                this.showGeographicalRegions = false;
            } catch (error) {
                console.error('Error setting showGeographicalRegions:', error);
            }
        }
        
        this.hideDialog();
    }
    
    // Handle row action (Exam info + View button)
    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        
        if (actionName === 'examInfo') {
            // Only show message for exam candidates
            if (row.isExamCandidate) {
                this.showInfoToast('Exam Result Only', this.examOnlyMessage);
            }
        } else if (actionName === 'view') {
            console.log('[CE SLB THERAPIST SEARCH] View button clicked:', {
                contactId: row.contactId,
                url: row.url,
                row: row
            });

            // Prefer the full community URL built by Apex (works from VF or Community)
            if (row.url) {
                try {
                    window.location.href = row.url;
                    return;
                } catch (e) {
                    console.error('[CE SLB THERAPIST SEARCH] Error using row.url for navigation:', e);
                }
            }

            // Fallbacks if url is missing for some reason
            if (!row.contactId) {
                this.showErrorToast('Error', 'Contact ID is missing. Cannot navigate to therapist report.');
                return;
            }

            // Try NavigationMixin if running inside a community page
            try {
                this[NavigationMixin.Navigate]({
                    type: 'comm__namedPage',
                    attributes: {
                        name: 'SLB_Therapist_Report__c'
                    },
                    state: {
                        id: row.contactId
                    }
                });
            } catch (error) {
                console.error('[CE SLB THERAPIST SEARCH] NavigationMixin failed, using URL fallback:', error);
                this.navigateToReportFallback(row.contactId);
            }
        }
    }
    
    // Show info toast (for exam-only message)
    showInfoToast(title, message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: 'info',
                mode: 'dismissible'
            })
        );
    }
    
    // Fallback navigation method using direct URL
    navigateToReportFallback(contactId) {
        if (typeof window !== 'undefined' && contactId) {
            try {
                const currentUrl = new URL(window.location.href);
                const basePath = currentUrl.pathname.split('/s/')[0] + '/s/';
                const reportUrl = `${currentUrl.origin}${basePath}slb-therapist-report?id=${contactId}`;
                console.log('[CE SLB THERAPIST SEARCH] Using fallback navigation to:', reportUrl);
                window.location.href = reportUrl;
            } catch (error) {
                console.error('[CE SLB THERAPIST SEARCH] Fallback navigation failed:', error);
                this.showErrorToast('Navigation Error', 'Unable to navigate to therapist report. Please try again.');
            }
        }
    }
    
    // Results count display
    get resultsCountText() {
        if (this.loadedCount === this.totalCount) {
            return `Showing all ${this.totalCount} results`;
        } else {
            return `Loaded ${this.loadedCount} of ${this.totalCount} total results`;
        }
    }
}

