import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadStyle } from 'lightning/platformResourceLoader';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import portalImages from '@salesforce/resourceUrl/Portal_Images';
import getNewCourseData from '@salesforce/apex/CeNewCourseLwcController.getNewCourseData';
import checkRenderDependentPicklist from '@salesforce/apex/CeNewCourseLwcController.checkRenderDependentPicklist';
import saveCourseDraft from '@salesforce/apex/CeNewCourseLwcController.saveCourseDraft';
import submitAndPay from '@salesforce/apex/CeNewCourseLwcController.submitAndPay';

export default class CeNewCourse extends NavigationMixin(LightningElement) {
    
    @api courseId;
    @api method; // 'Edit' or null (for copy)
    
    pageReference;
    
    @track isLoading = true;
    @track error;
    
    @track course = {};
    @track accountId;
    @track contactId;
    @track courseFee;
    @track content = '';
    @track dependentPicklistMap = {};
    @track renderDependentPicklist = false;
    @track isEditMode = false;
    
    // Form fields
    @track courseName;
    @track courseSummary;
    @track category;
    @track subCategory;
    @track description;
    @track registrationPhone;
    @track registrationWebsite;
    @track specialCircumstances;
    
    // Error flags
    @track displayCourseNameError = false;
    @track displayCategoryError = false;
    @track displaySubCategoryError = false;
    @track displayDescriptionError = false;
    @track displayDescriptionCountError = false;
    @track displayRegistrationPhoneError = false;
    @track displayCourseSummaryError = false;
    
    // Static resource images
    portalImages = portalImages;
    headerImage0 = portalImages + '/FSMTB_header0.png';
    
    // Sub category options
    @track subCategoryOptions = [];
    
    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        if (pageRef) {
            this.pageReference = pageRef;
            
            // Get courseId and method from URL parameters if not provided via @api (for standalone page)
            if (!this.courseId) {
                if (pageRef.state && pageRef.state.courseId) {
                    this.courseId = pageRef.state.courseId;
                } else {
                    const urlParams = new URLSearchParams(window.location.search);
                    const urlCourseId = urlParams.get('courseId');
                    if (urlCourseId) {
                        this.courseId = urlCourseId;
                    }
                }
            }
            
            if (!this.method) {
                if (pageRef.state && pageRef.state.method) {
                    this.method = pageRef.state.method;
                } else {
                    const urlParams = new URLSearchParams(window.location.search);
                    const urlMethod = urlParams.get('method');
                    if (urlMethod) {
                        this.method = urlMethod;
                    }
                }
            }
        }
    }
    
    connectedCallback() {
        // Load portal CSS styles
        loadStyle(this, '/resource/FSMTBAssets/FSMTBAssets/css/global.css')
            .catch(error => {
                console.error('Error loading portal styles:', error);
            });
        
        // Load data - wait a bit for page reference to be set if needed
        setTimeout(() => {
            this.loadData();
        }, 100);
    }
    
    loadData() {
        this.isLoading = true;
        getNewCourseData({ 
            courseId: this.courseId, 
            method: this.method 
        })
            .then(result => {
                this.course = result.course || {};
                this.accountId = result.accountId;
                this.contactId = result.contactId;
                this.courseFee = result.courseFee;
                this.content = result.content || '';
                this.dependentPicklistMap = result.dependentPicklistMap || {};
                this.renderDependentPicklist = result.renderDependentPicklist || false;
                this.isEditMode = result.isEditMode || false;
                
                // Set form fields
                this.courseName = this.course.Course_Name__c || '';
                this.courseSummary = this.course.Course_Objectives__c || '';
                this.category = this.course.Category__c || '';
                this.subCategory = this.course.Sub_Category__c || '';
                this.description = this.course.Description__c || '';
                this.registrationPhone = this.course.Registration_Phone__c || '';
                this.registrationWebsite = this.course.Registration_Website__c || '';
                this.specialCircumstances = this.course.Special_Circumstances__c || '';
                
                // Set subcategory options based on category
                if (this.category && this.dependentPicklistMap[this.category]) {
                    this.subCategoryOptions = this.dependentPicklistMap[this.category].map(value => ({
                        label: value,
                        value: value
                    }));
                } else {
                    this.subCategoryOptions = [];
                }
                
                // Set content HTML
                if (this.content) {
                    setTimeout(() => {
                        const contentEl = this.template.querySelector('.instruction-content');
                        if (contentEl) {
                            contentEl.innerHTML = this.content;
                        }
                    }, 0);
                }
                
                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error loading data:', error);
                this.error = error.body?.message || error.message || 'An error occurred loading course data.';
                this.isLoading = false;
                this.showToast('Error', this.error, 'error');
            });
    }
    
    // Getters
    get courseFeeFormatted() {
        return this.courseFee ? '$' + this.courseFee.toFixed(2) : '$35.00';
    }
    
    get categoryOptions() {
        if (!this.dependentPicklistMap || Object.keys(this.dependentPicklistMap).length === 0) {
            return [];
        }
        return Object.keys(this.dependentPicklistMap).map(value => ({
            label: value,
            value: value
        }));
    }
    
    get isCategoryDisabled() {
        return this.isEditMode && this.method === 'Edit';
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
    
    // Event handlers
    handleCourseNameChange(event) {
        this.courseName = event.detail.value;
        this.displayCourseNameError = false;
    }
    
    handleCategoryChange(event) {
        this.category = event.detail.value;
        this.displayCategoryError = false;
        this.subCategory = '';
        this.displaySubCategoryError = false;
        
        // Update subcategory options
        if (this.category && this.dependentPicklistMap[this.category]) {
            this.subCategoryOptions = this.dependentPicklistMap[this.category].map(value => ({
                label: value,
                value: value
            }));
            this.renderDependentPicklist = this.subCategoryOptions.length > 0;
        } else {
            this.subCategoryOptions = [];
            this.renderDependentPicklist = false;
        }
    }
    
    handleSubCategoryChange(event) {
        this.subCategory = event.detail.value;
        this.displaySubCategoryError = false;
    }
    
    handleCourseSummaryChange(event) {
        const value = event.detail.value || '';
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
        const value = event.detail.value || '';
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
    
    handleRegistrationPhoneChange(event) {
        this.registrationPhone = event.detail.value;
        this.displayRegistrationPhoneError = false;
    }
    
    handleRegistrationWebsiteChange(event) {
        this.registrationWebsite = event.detail.value;
    }
    
    handleSpecialCircumstancesChange(event) {
        this.specialCircumstances = event.detail.value;
    }
    
    // handleCancel() {
    //     // If used as standalone page, navigate back to course management
    //     if (this.pageReference) {
    //         this.navigateToCourseManagement();
    //     } else {
    //         // If used as modal, close it
    //         this.dispatchEvent(new CustomEvent('close'));
    //     }
    // }
    handleCancel() {
        // Navigate to Course Management Overview page
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'CE_Course_Management__c'
            }
        });
    }
    
    
    navigateToCourseManagement() {
        // Navigate back to course management overview page
        // Try to use browser history first, then fallback to navigation
        if (window.history.length > 1) {
            window.history.back();
        } else {
            // Fallback: navigate to home page or course management if known
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: {
                    name: 'Home' // Fallback to home page
                }
            });
        }
    }
    
    handleSaveDraft() {
        // Clear all errors
        this.clearErrors();
        
        // Validate course objectives (required field)
        if (!this.courseSummary || this.courseSummary.trim() === '') {
            this.displayCourseSummaryError = true;
            this.showToast('Validation Error', 'Course Objectives are required.', 'error');
            return;
        }
        
        // Validate course objectives length
        if (this.courseSummary.length > 500) {
            this.displayCourseSummaryError = true;
            this.showToast('Validation Error', 'Course Objectives cannot exceed 500 characters.', 'error');
            return;
        }

        // Validate course summary length
        if (this.description && this.description.length > 500) {
            this.displayDescriptionCountError = true;
            this.showToast('Validation Error', 'Course Summary cannot exceed 500 characters.', 'error');
            return;
        }
        
        // Build course object
        const courseToSave = {
            Id: this.course.Id || null,
            Course_Name__c: this.courseName,
            Category__c: this.category,
            Sub_Category__c: this.subCategory,
            Course_Objectives__c: this.courseSummary,
            Description__c: this.description,
            Registration_Phone__c: this.registrationPhone,
            Registration_Website__c: this.registrationWebsite,
            Special_Circumstances__c: this.specialCircumstances,
            Account__c: this.accountId,
            Contact__c: this.contactId
        };
        
        this.isLoading = true;
        saveCourseDraft({ course: courseToSave })
            .then(result => {
                this.showToast('Success', 'Course saved as draft successfully', 'success');
                this.isLoading = false;
                // Dispatch event to refresh parent and close modal (if used as modal)
                this.dispatchEvent(new CustomEvent('saved', { detail: { courseId: result } }));
                
                // If used as standalone page, navigate back to course management
                if (this.pageReference) {
                    setTimeout(() => {
                        this.navigateToCourseManagement();
                    }, 1000);
                } else {
                    // If used as modal, close it
                    setTimeout(() => {
                        this.dispatchEvent(new CustomEvent('close'));
                    }, 1000);
                }
            })
            .catch(error => {
                console.error('Error saving draft:', error);
                this.isLoading = false;
                this.showToast('Error', error.body?.message || error.message, 'error');
            });
    }
    
    handleSubmit() {
        // Clear all errors
        this.clearErrors();
        
        // Validate course objectives (required field)
        if (!this.courseSummary || this.courseSummary.trim() === '') {
            this.displayCourseSummaryError = true;
            this.showToast('Validation Error', 'Course Objectives are required.', 'error');
            return;
        }
        
        // Validate course objectives length
        if (this.courseSummary.length > 500) {
            this.displayCourseSummaryError = true;
            this.showToast('Validation Error', 'Course Objectives cannot exceed 500 characters.', 'error');
            return;
        }

        // Validate course summary length
        if (this.description && this.description.length > 500) {
            this.displayDescriptionCountError = true;
            this.showToast('Validation Error', 'Course Summary cannot exceed 500 characters.', 'error');
            return;
        }
        
        // Build course object
        const courseToSave = {
            Id: this.course.Id || null,
            Course_Name__c: this.courseName,
            Category__c: this.category,
            Sub_Category__c: this.subCategory,
            Course_Objectives__c: this.courseSummary,
            Description__c: this.description,
            Registration_Phone__c: this.registrationPhone,
            Registration_Website__c: this.registrationWebsite,
            Special_Circumstances__c: this.specialCircumstances,
            Account__c: this.accountId,
            Contact__c: this.contactId
        };
        
        this.isLoading = true;
        submitAndPay({ course: courseToSave })
            .then(result => {
                if (!result.isValid) {
                    // Display validation errors
                    this.displayErrors(result.errors);
                    this.isLoading = false;
                } else {
                    // Navigate to payment page
                    this.isLoading = false;
                    this.showToast('Success', 'Course submitted successfully', 'success');
                    
                    // Navigate to payment page with order IDs
                    if (result.orderIds && result.orderIds.length > 0) {
                        // Pass order IDs as JSON string for navigation state
                        const orderIdsParam = JSON.stringify(result.orderIds);
                        
                        // Use comm__namedPage with the API name 'Payment__c'
                        // This is the proper way to navigate to community pages
                        console.log('Navigating to payment page with order IDs:', result.orderIds);
                        
                        this[NavigationMixin.Navigate]({
                            type: 'comm__namedPage',
                            attributes: {
                                name: 'Payment__c'
                            },
                            state: {
                                ids: orderIdsParam
                            }
                        });
                    } else {
                        this.showToast('Error', 'No order IDs generated. Please try again.', 'error');
                    }
                }
            })
            .catch(error => {
                console.error('Error submitting course:', error);
                this.isLoading = false;
                this.showToast('Error', error.body?.message || error.message, 'error');
            });
    }
    
    clearErrors() {
        this.displayCourseNameError = false;
        this.displayCategoryError = false;
        this.displaySubCategoryError = false;
        this.displayDescriptionError = false;
        this.displayDescriptionCountError = false;
        this.displayRegistrationPhoneError = false;
        this.displayCourseSummaryError = false;
    }
    
    displayErrors(errors) {
        if (errors.courseName) {
            this.displayCourseNameError = true;
        }
        if (errors.category) {
            this.displayCategoryError = true;
        }
        if (errors.subCategory) {
            this.displaySubCategoryError = true;
        }
        if (errors.courseSummary) {
            this.displayCourseSummaryError = true;
        }
        if (errors.description) {
            this.displayDescriptionError = true;
        }
        if (errors.descriptionCount) {
            this.displayDescriptionCountError = true;
        }
        if (errors.registrationPhone) {
            this.displayRegistrationPhoneError = true;
        }
    }
    
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(evt);
    }
}