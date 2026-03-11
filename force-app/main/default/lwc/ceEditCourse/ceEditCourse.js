import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadStyle } from 'lightning/platformResourceLoader';
import { NavigationMixin } from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';
import portalImages from '@salesforce/resourceUrl/Portal_Images';
import getCourseEditData from '@salesforce/apex/CeEditCourseLwcController.getCourseEditData';
import publishCourseUpdates from '@salesforce/apex/CeEditCourseLwcController.publishCourseUpdates';
import changeSessionStatus from '@salesforce/apex/CeEditCourseLwcController.changeSessionStatus';
import deleteSession from '@salesforce/apex/CeEditCourseLwcController.deleteSession';
import getCourseStatusOptions from '@salesforce/apex/CeEditCourseLwcController.getCourseStatusOptions';

const PUBLISHED = 'Published';
const UNDER_REVIEW = 'Under Review';
const DRAFT = 'Draft';
const INACTIVE = 'Inactive';
const COMPLETE = 'Complete';
const REVOKED = 'Revoked';

export default class CeEditCourse extends NavigationMixin(LightningElement) {
    @api courseId;
    
    @track course;
    
    pageReference;
    @track publishedSessions = [];
    @track draftSessions = [];
    @track inactiveSessions = [];
    @track content = '';
    @track statusConstants = {};
    
    @track showPublishedSessions = false;
    @track showDraftSessions = false;
    @track showInactiveSessions = false;
    @track showNoAccessMessage = false;
    @track showLastActiveSessionConfirmation = false;
    @track isLoading = true;
    @track error;
    
    @track modifyingSessionId;
    
    // Form fields
    @track courseName;
    @track courseSummary;
    @track description;
    @track status;
    @track statusOptions = [];
    @track specialCircumstances;
    @track registrationPhone;
    @track registrationWebsite;
    @track courseIdText;
    @track categoryText;
    
    @track displayRegistrationPhoneError = false;
    @track displayCourseSummaryError = false;
    @track displayDescriptionError = false;
    @track displayDescriptionCountError = false;
    
    // Static resource images
    portalImages = portalImages;
    headerImage0 = portalImages + '/FSMTB_header0.png';

    sessionMgmtPage = 'CESessionManagement__c';
    
    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        if (pageRef) {
            this.pageReference = pageRef;
            // Get courseId from page reference state (for comm__namedPage navigation)
            if (!this.courseId && pageRef.state) {
                this.courseId = pageRef.state.courseId || pageRef.state.c__courseId;
            }
            
            // Also check URL query string (fallback)
            if (!this.courseId) {
                const urlParams = new URLSearchParams(window.location.search);
                this.courseId = urlParams.get('courseId');
            }
            
            if (this.courseId && !this.isLoading) {
                this.loadData();
            }
        }
    }
    
    connectedCallback() {
        // Load portal CSS styles
        loadStyle(this, '/resource/FSMTBAssets/FSMTBAssets/css/global.css')
            .catch(error => {
                console.error('Error loading portal styles:', error);
            });
        
        // Check URL for courseId as fallback if @api property not set
        if (!this.courseId) {
            const urlParams = new URLSearchParams(window.location.search);
            this.courseId = urlParams.get('courseId');
        }
        
        // Load status options
        this.loadStatusOptions();
        
        // If courseId is available, load data
        if (this.courseId) {
            this.loadData();
        } else {
            // If no courseId found, show error
            this.error = 'No course ID provided. Please navigate from the Course Management page.';
            this.isLoading = false;
        }
    }
    
    loadData() {
        this.isLoading = true;
        this.error = null;
        
        getCourseEditData({ courseId: this.courseId })
            .then(result => {
                this.course = result.course;
            // Add helper properties for session display
            this.publishedSessions = (result.publishedSessions || []).map(item => ({
                ...item,
                canEdit: this.canEditSession(item.session),
                canInactivate: this.canInactivateSession(item.session)
            }));
            
            this.draftSessions = result.draftSessions || [];
            
            this.inactiveSessions = (result.inactiveSessions || []).map(item => ({
                ...item,
                isComplete: this.isCompleteSession(item.session),
                isInactive: this.isInactiveSession(item.session),
                isRevoked: this.isRevokedSession(item.session)
            }));
                this.content = result.content || '';
                
                // Set content HTML if exists
                if (this.content) {
                    setTimeout(() => {
                        const contentEl = this.template.querySelector('.content-section');
                        if (contentEl) {
                            contentEl.innerHTML = this.content;
                        }
                    }, 0);
                }
                this.statusConstants = result.statusConstants || {};
                this.showPublishedSessions = result.showPublishedSessions;
                this.showDraftSessions = result.showDraftSessions;
                this.showInactiveSessions = result.showInactiveSessions;
                this.showNoAccessMessage = result.showNoAccessMessage;
                
                // Set form fields
                this.courseName = this.course.Course_Name__c;
                this.courseSummary = this.course.Course_Objectives__c || '';
                // Store description HTML for rendering
                this.description = this.course.Description__c || '';
                this.status = this.course.Status_Selected__c || this.course.Status__c || '';
                this.specialCircumstances = this.course.Special_Circumstances__c;
                this.registrationPhone = this.course.Registration_Phone__c;
                this.registrationWebsite = this.course.Registration_Website__c;
                this.courseIdText = this.course.Name;
                
                // Set description HTML content if published
                if (this.isPublished && this.description) {
                    setTimeout(() => {
                        const descEl = this.template.querySelector('.description-content');
                        if (descEl) {
                            descEl.innerHTML = this.description;
                        }
                    }, 0);
                }
                
                // Build category text
                if (this.course.Sub_Category__c != null) {
                    this.categoryText = this.course.Category__c + ' - ' + this.course.Sub_Category__c;
                } else {
                    this.categoryText = this.course.Category__c;
                }
                
                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error loading course data:', error);
                this.error = error.body?.message || 'An error occurred loading course data';
                this.isLoading = false;
                this.showToast('Error', this.error, 'error');
            });
    }
    
    get isPublished() {
        return this.course?.Status__c === PUBLISHED;
    }
    
    get isLastActiveSession() {
        return this.publishedSessions.length === 1;
    }
    
    get publishedSessionColumns() {
        return [
            { label: 'Actions', fieldName: 'actions', type: 'text', sortable: false },
            { label: 'Status', fieldName: 'Status__c', type: 'text' },
            { label: 'Session ID', fieldName: 'Name', type: 'text' },
            { label: 'Session Type', fieldName: 'Session_Type__c', type: 'text' },
            { label: 'Start Date', fieldName: 'startDT', type: 'text' },
            { label: 'End Date', fieldName: 'endDT', type: 'text' },
            { label: 'Cost', fieldName: 'Cost__c', type: 'currency' },
            { label: 'Instructor', fieldName: 'Instructor_Name__c', type: 'text' },
            { label: 'Total Hours', fieldName: 'Hours_Earned__c', type: 'number' }
        ];
    }
    
    get draftSessionColumns() {
        return this.publishedSessionColumns;
    }
    
    get inactiveSessionColumns() {
        return this.publishedSessionColumns;
    }
    
    handleCancel() {
        // Navigate back to course management overview page
        // Use the same approach as ceNewCourse - try browser history first, then fallback
        if (window.history.length > 1) {
            window.history.back();
        } else {
            // Fallback: navigate to home page
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: {
                    name: 'Home'
                }
            });
        }
    }
    
    handleCourseNameChange(event) {
        this.courseName = event.target.value;
    }
    
    handleCourseSummaryChange(event) {
        const value = event.target.value || '';
        // Enforce 500 character limit
        if (value.length > 500) {
            this.courseSummary = value.substring(0, 500);
            this.displayCourseSummaryError = true;
            this.showToast('Validation Error', 'Course Objectives cannot exceed 500 characters.', 'error');
        } else {
            this.courseSummary = value;
            this.displayCourseSummaryError = false;
        }
    }
    
    handleDescriptionChange(event) {
        const value = event.target.value || '';
        if (value.length > 500) {
            this.description = value.substring(0, 500);
            this.displayDescriptionCountError = true;
            this.showToast('Validation Error', 'Course Summary cannot exceed 500 characters.', 'error');
        } else {
            this.description = value;
            this.displayDescriptionCountError = false;
        }
        this.displayDescriptionError = false;
    }
    
    handleStatusChange(event) {
        this.status = event.detail.value;
        this.dispatchRefreshEvent();
    }
    
    loadStatusOptions() {
        getCourseStatusOptions()
            .then(result => {
                this.statusOptions = result.map(opt => ({
                    label: opt.label,
                    value: opt.value
                }));
            })
            .catch(error => {
                console.error('Error loading status options:', error);
            });
    }
    
    dispatchRefreshEvent() {
        // Dispatch custom event to refresh parent component
        // Since we're on a different page, use multiple methods to ensure the refresh happens
        console.log('[CE EDIT COURSE] Dispatching refresh event');
        
        // Method 1: Window event (works if components are in same window)
        const refreshEvent = new CustomEvent('refreshcourses', {
            bubbles: true,
            composed: true,
            detail: { timestamp: Date.now() }
        });
        window.dispatchEvent(refreshEvent);
        
        // Method 2: localStorage event (works across page navigations)
        // Set a value in localStorage to trigger storage event
        const refreshKey = 'refreshCourses';
        const currentValue = localStorage.getItem(refreshKey);
        localStorage.setItem(refreshKey, currentValue === 'true' ? 'false' : 'true');
        
        // Method 3: Also trigger immediately via postMessage if parent window exists
        if (window.parent && window.parent !== window) {
            window.parent.postMessage({ type: 'refreshCourses', timestamp: Date.now() }, '*');
        }
    }
    
    handleSpecialCircumstancesChange(event) {
        this.specialCircumstances = event.target.value;
    }
    
    handleRegistrationPhoneChange(event) {
        this.registrationPhone = event.target.value;
        this.displayRegistrationPhoneError = false;
    }
    
    handleRegistrationWebsiteChange(event) {
        this.registrationWebsite = event.target.value;
    }
    
    get registrationPhoneErrorClass() {
        return this.displayRegistrationPhoneError ? 'slds-has-error' : '';
    }
    
    get courseSummaryErrorClass() {
        return this.displayCourseSummaryError ? 'slds-has-error' : '';
    }
    
    get courseSummaryLength() {
        return this.courseSummary ? this.courseSummary.length : 0;
    }

    get descriptionLength() {
        return this.description ? this.description.length : 0;
    }
    
    handlePublishUpdates() {
        this.displayRegistrationPhoneError = false;
        this.displayCourseSummaryError = false;
        this.displayDescriptionError = false;
        this.displayDescriptionCountError = false;
        
        // Validate course objectives (required and length) - only for new courses (Draft status)
        if (!this.isPublished) {
            if (!this.courseSummary || this.courseSummary.trim() === '') {
                this.displayCourseSummaryError = true;
                this.showToast('Validation Error', 'Course Objectives are required.', 'error');
                return;
            }
            if (this.courseSummary.length > 500) {
                this.displayCourseSummaryError = true;
                this.showToast('Validation Error', 'Course Objectives cannot exceed 500 characters.', 'error');
                return;
            }
        }

        if (!this.description || this.description.trim() === '') {
            this.displayDescriptionError = true;
            this.showToast('Validation Error', 'Course Summary is required.', 'error');
            return;
        }
        if (this.description.length > 500) {
            this.displayDescriptionCountError = true;
            this.showToast('Validation Error', 'Course Summary cannot exceed 500 characters.', 'error');
            return;
        }
        
        if (!this.registrationPhone || this.registrationPhone.trim() === '') {
            this.displayRegistrationPhoneError = true;
            this.showToast('Validation Error', 'A course registration contact telephone number is required.', 'error');
            return;
        }
        
        publishCourseUpdates({
            courseId: this.courseId,
            courseName: this.courseName,
            courseSummary: this.courseSummary,
            description: this.description,
            specialCircumstances: this.specialCircumstances,
            registrationPhone: this.registrationPhone,
            registrationWebsite: this.registrationWebsite,
            status: this.status
        })
            .then(result => {
                if (result.startsWith('ERROR:')) {
                    this.showToast('Error', result.replace('ERROR: ', ''), 'error');
                } else {
                    // Dispatch refresh event after successful update
                    this.dispatchRefreshEvent();
                    this.showToast('Success', 'Course updated successfully', 'success');
                    setTimeout(() => {
                        // Navigate to Home page after successful update
                        this[NavigationMixin.Navigate]({
                            type: 'comm__namedPage',
                            attributes: {
                                name: 'Home'
                            }
                        });
                    }, 1000);
                }
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || error.message, 'error');
            });
    }
    
    handleConfirmInactivate() {
        if (this.modifyingSessionId) {
            this.confirmInactivateSession(this.modifyingSessionId);
        }
    }
    
    handleAddSession() {
        this.dispatchRefreshEvent();
        /*this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: `/CESession?courseId=${this.courseId}&previousPage=CEEditCourse&method=Add`
            }
        });*/

        // RP: FR1-89
        let params = {
            c__courseId: this.courseId
        };
        this.navigateToCommPage(this.sessionMgmtPage, params);
    }

    // RP: FR1-89
    navigateToCommPage(pageName, params) {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: pageName,
            },
            state: params
        });
    }
    
    handleSessionAction(event) {
        event.preventDefault();
        event.stopPropagation();
        
        const action = event.currentTarget.dataset.action;
        const sessionId = event.currentTarget.dataset.sessionid;
        this.modifyingSessionId = sessionId;
        
        if (action === 'Edit') {
            this.editSession(sessionId);
        } else if (action === 'Copy') {
            this.copySession(sessionId);
        } else if (action === 'Inactivate') {
            this.inactivateSession(sessionId);
        } else if (action === 'Delete') {
            this.deleteSessionHandler(sessionId);
        } else if (action === 'Activate') {
            this.activateSession(sessionId);
        } else if (action === 'Upload Roster') {
            this.uploadRoster(sessionId);
        }
    }
    
    editSession(sessionId) {
        this.dispatchRefreshEvent();
        // this[NavigationMixin.Navigate]({
        //     type: 'standard__webPage',
        //     attributes: {
        //         url: `/CESession?courseId=${this.courseId}&sessionId=${sessionId}&previousPage=CEEditCourse&method=Edit`
        //     }
        // });

        // RP: FR1-89
        let params = {
            c__courseId: this.courseId,
            c__sessionId: sessionId
        };
        this.navigateToCommPage(this.sessionMgmtPage, params);
    }
    
    copySession(sessionId) {
        this.dispatchRefreshEvent();
        // this[NavigationMixin.Navigate]({
        //     type: 'standard__webPage',
        //     attributes: {
        //         url: `/CESession?courseId=${this.courseId}&sessionId=${sessionId}&previousPage=CEEditCourse&method=Copy`
        //     }
        // });

        // RP: FR1-89
        let params = {
            c__courseId: this.courseId,
            c__sessionId: sessionId
        };
        this.navigateToCommPage(this.sessionMgmtPage, params);
    }
    
    inactivateSession(sessionId) {
        if (this.isLastActiveSession && this.publishedSessions.length === 1) {
            this.showLastActiveSessionConfirmation = true;
            this.modifyingSessionId = sessionId;
        } else {
            this.confirmInactivateSession(sessionId);
        }
    }
    
    confirmInactivateSession(sessionId) {
        changeSessionStatus({
            sessionId: sessionId,
            status: INACTIVE
        })
            .then(() => {
                // Reload local data first
                this.loadData();
                // Then dispatch refresh event for parent component
                setTimeout(() => {
                    this.dispatchRefreshEvent();
                }, 200);
                this.showToast('Success', 'Session inactivated successfully', 'success');
                this.showLastActiveSessionConfirmation = false;
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || error.message, 'error');
            });
    }
    
    closeConfirmation() {
        this.showLastActiveSessionConfirmation = false;
    }
    
    deleteSessionHandler(sessionId) {
        if (confirm('Are you sure you want to delete this session?')) {
            deleteSession({ sessionId: sessionId })
                .then(() => {
                    // Reload local data first
                    this.loadData();
                    // Then dispatch refresh event for parent component
                    setTimeout(() => {
                        this.dispatchRefreshEvent();
                    }, 200);
                    this.showToast('Success', 'Session deleted successfully', 'success');
                })
                .catch(error => {
                    this.showToast('Error', error.body?.message || error.message, 'error');
                });
        }
    }
    
    activateSession(sessionId) {
        changeSessionStatus({
            sessionId: sessionId,
            status: PUBLISHED
        })
            .then(() => {
                // Reload local data first
                this.loadData();
                // Then dispatch refresh event for parent component
                setTimeout(() => {
                    this.dispatchRefreshEvent();
                }, 200);
                this.showToast('Success', 'Session activated successfully', 'success');
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || error.message, 'error');
            });
    }
    
    uploadRoster(sessionId) {
        this.dispatchRefreshEvent();
        // Navigate to myRosterUpload with prefilled courseId and sessionId
        // Try named page first, fallback to URL
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'CE_Roster_Upload__c'
            },
            state: {
                courseId: this.courseId,
                sessionId: sessionId
            }
        }).catch(() => {
            // Fallback to URL navigation if named page doesn't exist
            window.location.href = `/CERegistryPortal/s/ce-roster-upload?courseId=${this.courseId}&sessionId=${sessionId}`;
        });
    }
    
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(evt);
    }
    
    // Check if session can be edited/inactivated
    canEditSession(session) {
        return session.Status__c === PUBLISHED || session.Status__c === UNDER_REVIEW;
    }
    
    canInactivateSession(session) {
        return session.Status__c !== UNDER_REVIEW;
    }
    
    isCompleteSession(session) {
        return session.Status__c === COMPLETE;
    }
    
    isInactiveSession(session) {
        return session.Status__c === INACTIVE;
    }
    
    isRevokedSession(session) {
        return session.Status__c === REVOKED;
    }
}