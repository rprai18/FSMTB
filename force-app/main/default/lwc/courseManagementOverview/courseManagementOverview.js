import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadStyle } from 'lightning/platformResourceLoader';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';

import portalImages from '@salesforce/resourceUrl/Portal_Images';
import SchibstedGroteskFont from '@salesforce/resourceUrl/Schibsted_Grotesk_Font';
import getCourseManagementData from '@salesforce/apex/CeCourseManagementLwcController.getCourseManagementData';
import deleteCourse from '@salesforce/apex/CeCourseManagementLwcController.deleteCourse';
import changeCourseStatus from '@salesforce/apex/CeCourseManagementLwcController.changeCourseStatus';

const PUBLISHED = 'Published';
const INACTIVE = 'Inactive';

export default class CourseManagementOverview extends NavigationMixin(LightningElement) {

    /* ===================== PUBLIC / TRACKED ===================== */

    @api showCoursePendingReview = false;

    @track accountId;
    @track publishedCourses = [];
    @track draftCourses = [];
    @track inactiveCourses = [];
    @track showNoSessionWarning = false;
    @track showDeleteConfirmation = false;
    @track showInactivateConfirmation = false;
    @track showCourseExpiration = false;
    @track daysUntilExpiration = 0;
    @track courseFee = 35;
    @track modifyingCourseId;
    @track isLoading = true;
    @track error;
   // @track showNewCourseModal = false;
   // @track newCourseCourseId;
   // @track newCourseMethod;

    wiredResult;
    
    // Refresh control flags
    isRefreshing = false;
    lastRefreshTime = 0;
    refreshTimeout = null;
    wasHidden = false;

    /* ===================== STATIC RESOURCES ===================== */

    portalImages = portalImages;
    headerImage1 = portalImages + '/FSMTB_header1.png';
    fontUrl = SchibstedGroteskFont;

    /* ===================== LIFECYCLE ===================== */

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

    connectedCallback() {
        loadStyle(this, '/resource/FSMTBAssets/FSMTBAssets/css/global.css')
            .catch(err => console.error(err));

        // Load Schibsted Grotesk font
        this.loadFont();

        // Reset loading state when component is connected (handles tab switching)
        // The @wire will fire and set isLoading appropriately
        this.isLoading = true;
        this.error = null;

        const params = new URLSearchParams(window.location.search);
        if (params.get('pendingReview') === 'true') {
            this.showCoursePendingReview = true;
        }
        
        // Check if refresh flag exists in localStorage (set by child components)
        // Only refresh if flag exists AND we're not in initial load
        const refreshFlag = localStorage.getItem('refreshCourses');
        if (refreshFlag === 'true') {
            localStorage.removeItem('refreshCourses');
            // Small delay to ensure component is fully initialized
            // Only refresh if we have data already (not initial load)
            setTimeout(() => {
                if (this.wiredResult && this.wiredResult.data) {
                    this.scheduleRefresh();
                }
            }, 500);
        }
        
        // Listen for refresh events from child components using multiple methods
        this.handleRefreshCourses = this.handleRefreshCourses.bind(this);
        this.handleStorageRefresh = this.handleStorageRefresh.bind(this);
        this.handleVisibilityChange = this.handleVisibilityChange.bind(this);
        this.handlePageFocus = this.handlePageFocus.bind(this);
        this.handlePostMessage = this.handlePostMessage.bind(this);
        
        window.addEventListener('refreshcourses', this.handleRefreshCourses);
        
        // Also listen for storage events (cross-tab communication)
        window.addEventListener('storage', this.handleStorageRefresh);
        
        // Disabled visibility change handlers - they cause issues when switching tabs in portal
        // The component is conditionally rendered, so it gets disconnected/reconnected on tab switch
        // This causes the visibility handlers to fire incorrectly
        // document.addEventListener('visibilitychange', this.handleVisibilityChange);
        // window.addEventListener('focus', this.handlePageFocus);
        
        // Listen for postMessage events
        window.addEventListener('message', this.handlePostMessage);
    }
    
    disconnectedCallback() {
        // Clean up event listeners
        window.removeEventListener('refreshcourses', this.handleRefreshCourses);
        window.removeEventListener('storage', this.handleStorageRefresh);
        // document.removeEventListener('visibilitychange', this.handleVisibilityChange);
        // window.removeEventListener('focus', this.handlePageFocus);
        window.removeEventListener('message', this.handlePostMessage);
        
        // Clear any pending refresh timeout
        if (this.refreshTimeout) {
            clearTimeout(this.refreshTimeout);
            this.refreshTimeout = null;
        }
    }
    
    handlePostMessage(event) {
        // Handle postMessage events from child windows/components
        if (event.data && event.data.type === 'refreshCourses') {
            console.log('[COURSE OVERVIEW] PostMessage refresh event received');
            this.scheduleRefresh();
        }
    }
    
    handleRefreshCourses(event) {
        // Refresh the course data when child component dispatches event
        console.log('[COURSE OVERVIEW] Refresh event received');
        this.scheduleRefresh();
    }
    
    handleStorageRefresh(event) {
        // Refresh when storage event is triggered (cross-tab communication)
        if (event.key === 'refreshCourses' && event.newValue === 'true') {
            console.log('[COURSE OVERVIEW] Storage refresh event received');
            localStorage.removeItem('refreshCourses');
            this.scheduleRefresh();
        }
    }
    
    handleVisibilityChange() {
        // Only refresh when page becomes visible AND was previously hidden
        // This prevents refresh loops when the page is already visible
        if (document.hidden) {
            this.wasHidden = true;
        } else if (this.wasHidden) {
            // Page was hidden and is now visible - user likely navigated back
            console.log('[COURSE OVERVIEW] Page became visible after being hidden, refreshing data');
            this.wasHidden = false;
            this.scheduleRefresh();
        }
    }
    
    handlePageFocus() {
        // Only refresh if page was previously hidden (user navigated away and back)
        // Skip if we just loaded the page
        if (this.wasHidden && Date.now() - this.lastRefreshTime > 2000) {
            console.log('[COURSE OVERVIEW] Page focused after being hidden, refreshing data');
            this.wasHidden = false;
            this.scheduleRefresh();
        }
    }
    
    scheduleRefresh() {
        // Prevent multiple simultaneous refreshes
        if (this.isRefreshing) {
            console.log('[COURSE OVERVIEW] Refresh already in progress, skipping');
            return;
        }
        
        // Throttle refreshes - don't refresh more than once per second
        const now = Date.now();
        if (now - this.lastRefreshTime < 1000) {
            console.log('[COURSE OVERVIEW] Refresh throttled, too soon since last refresh');
            // Clear existing timeout and reschedule
            if (this.refreshTimeout) {
                clearTimeout(this.refreshTimeout);
            }
            this.refreshTimeout = setTimeout(() => {
                this.refreshDataWithDelay();
            }, 1000 - (now - this.lastRefreshTime));
            return;
        }
        
        // Clear any existing timeout
        if (this.refreshTimeout) {
            clearTimeout(this.refreshTimeout);
        }
        
        // Schedule the refresh
        this.refreshDataWithDelay();
    }
    
    refreshDataWithDelay() {
        // Add a small delay to ensure DML operations complete and cache is invalidated
        this.refreshTimeout = setTimeout(() => {
            this.refreshData();
        }, 300);
    }

    /* ===================== DATA ===================== */

    @wire(getCourseManagementData)
    wiredCourses(result) {
        this.wiredResult = result;

        if (result.data) {
            const d = result.data;
            this.accountId = d.accountId;
            // Use deep copy to force reactivity
            this.publishedCourses = JSON.parse(JSON.stringify(d.publishedCourses || []));
            this.draftCourses = JSON.parse(JSON.stringify(d.draftCourses || []));
            this.inactiveCourses = JSON.parse(JSON.stringify(d.inactiveCourses || []));
            this.showNoSessionWarning = d.showNoSessionWarning;
            this.showCourseExpiration = d.showCourseExpiration;
            this.daysUntilExpiration = d.daysUntilExpiration;
            this.courseFee = d.courseFee;
            this.isLoading = false;
            this.isRefreshing = false; // Ensure refresh flag is reset
            this.error = null; // Clear any errors
            console.log('[COURSE OVERVIEW] Data loaded:', {
                published: this.publishedCourses.length,
                draft: this.draftCourses.length,
                inactive: this.inactiveCourses.length
            });
        } else if (result.error) {
            this.error = result.error.body?.message;
            this.isLoading = false;
            this.isRefreshing = false; // Ensure refresh flag is reset
            console.error('[COURSE OVERVIEW] Error loading data:', this.error);
        } else if (result.loading) {
            // Wire is still loading
            this.isLoading = true;
        }
    }

    async refreshData() {
        // Prevent concurrent refreshes
        if (this.isRefreshing) {
            console.log('[COURSE OVERVIEW] Refresh already in progress, skipping duplicate call');
            return;
        }
        
        this.isRefreshing = true;
        this.isLoading = true;
        this.lastRefreshTime = Date.now();
        
        try {
            // Clear arrays first to show loading state
            this.publishedCourses = [];
            this.draftCourses = [];
            this.inactiveCourses = [];
            
            // Refresh the wired result
            await refreshApex(this.wiredResult);
            
            // Force a re-render by updating the wired result
            // The wiredCourses method will be called automatically
        } catch (error) {
            console.error('Error refreshing data:', error);
            this.error = error.body?.message || 'Error refreshing course data';
            this.isLoading = false;
        } finally {
            // Always reset the flag, even on error
            this.isRefreshing = false;
        }
    }

    /* ===================== GETTERS ===================== */

    get hasPublishedCourses() {
        return this.publishedCourses.length > 0;
    }

    get hasDraftCourses() {
        return this.draftCourses.length > 0;
    }

    get hasInactiveCourses() {
        return this.inactiveCourses.length > 0;
    }

    get courseFeeFormatted() {
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(this.courseFee);
    }

    get publishedCoursesColspan() {
        return this.showNoSessionWarning ? '7' : '6';
    }

    /* ===================== ACTION HANDLERS ===================== */

    handlePublishedCourseAction(event) {
        this.handleKey(event);
        const { action, id } = event.currentTarget.dataset;
        this.modifyingCourseId = id;

        if (action === 'Edit') this.editCourse(id);
        if (action === 'Copy') this.copyCourse(id);
        if (action === 'Inactivate') this.showInactivateConfirmation = true;
    }

    handleDraftCourseAction(event) {
        this.handleKey(event);
        const { action, id } = event.currentTarget.dataset;
        this.modifyingCourseId = id;

        if (action === 'Edit') this.editDraftCourse(id);
        if (action === 'Copy') this.copyCourse(id);
        if (action === 'Delete') this.showDeleteConfirmation = true;
    }

    handleInactiveCourseAction(event) {
        this.handleKey(event);
        this.activateCourse(event.currentTarget.dataset.id);
    }

    handleKey(event) {
        if (event.type === 'keydown' && !['Enter', ' '].includes(event.key)) return;
        event.preventDefault();
        event.stopPropagation();
    }

    /* ===================== STATUS CHANGES ===================== */

    activateCourse(courseId) {
        changeCourseStatus({ courseId, status: PUBLISHED })
            .then(() => {
                this.showToast('Success', 'Course activated successfully', 'success');
                return this.refreshData();
            })
            .catch(e => this.showToast('Error', e.body?.message, 'error'));
    }

    inactivateConfirmed() {
        changeCourseStatus({ courseId: this.modifyingCourseId, status: INACTIVE })
            .then(() => {
                this.showToast('Success', 'Course inactivated successfully', 'success');
                this.closeConfirmations();
                return this.refreshData();
            })
            .catch(e => this.showToast('Error', e.body?.message, 'error'));
    }

    async deleteConfirmed() {
        await deleteCourse({ courseId: this.modifyingCourseId });
        this.showToast('Success', 'Course deleted successfully', 'success');
        this.closeConfirmations();
        await this.refreshData();
    }

    /* ===================== NAVIGATION ===================== */


    handleAddNewCourse() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'CE_New_Course__c'
            }
        });
    }
    
    editCourse(courseId) {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: { name: 'CE_Edit_Course__c' },
            state: { courseId }
        });
    }

    editDraftCourse(courseId) {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'CE_Edit_Course__c'
            },
            state: {
                courseId: courseId
            }
        });
    }
    

    copyCourse(courseId) {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'CE_New_Course__c'
            },
            state: {
                courseId: courseId,
                method: 'Copy'
            }
        });
    }
    
    

    /* ===================== MODALS ===================== */

    closeConfirmations() {
        this.showDeleteConfirmation = false;
        this.showInactivateConfirmation = false;
        this.showCourseExpiration = false;
        this.showCoursePendingReview = false;
        this.showNewCourseModal = false;
        this.newCourseCourseId = null;
        this.newCourseMethod = null;
    }

    /* ===================== UTILS ===================== */

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
