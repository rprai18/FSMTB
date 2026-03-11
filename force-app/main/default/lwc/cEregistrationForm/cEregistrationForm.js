import { LightningElement, track, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import GOOGLE_ANALYTICS from '@salesforce/resourceUrl/GoogleAnalytics';
import bannerImage from '@salesforce/resourceUrl/FSMTB_header';
import portalImages from '@salesforce/resourceUrl/Portal_Images';
import getRegistrationData from '@salesforce/apex/CeProviderRegistrationLwcController.getRegistrationData';
import proceed from '@salesforce/apex/CeProviderRegistrationLwcController.proceed';

export default class CEregistrationForm extends NavigationMixin(LightningElement) {
    // Form fields - Organization Information
    @track businessName;
    @track businessEmail;
    @track reEnterEmail;
    @track businessPhone;
    @track businessAddress1;
    @track businessAddress2;
    @track city;
    @track state;
    @track zip;
    @track fax;
    @track website;
    
    // Form fields - Registry Account Owner
    @track firstName;
    @track lastName;
    @track username;
    @track ownerEmail;
    @track ownerReEnterEmail;
    @track ownerPhone;
    @track title;
    
    // UI state
    @track showForm = true;
    @track buttonLabel = 'Next';
    @track isLoading = false;
    @track content = '';
    
    // IDs to use later
    leadId;
    orderIds = [];
    
    // State options
    @track stateOptions = [];
    
    // Images
    bannerImage = bannerImage;
    Header1 = bannerImage + '/fsmtb/image/Header1.png';
    Header2 = bannerImage + '/fsmtb/image/Header2.png';
    portalImages = portalImages;
    headerImage = portalImages + '/FSMTB_header0.png';
    
    // Field mapping for handleChange
    fieldMap = {
        'Business Name': 'businessName',
        'Business Email': 'businessEmail',
        'Re-enter Email': 'reEnterEmail',
        'Business Phone': 'businessPhone',
        'Business Address 1': 'businessAddress1',
        'Business Address 2': 'businessAddress2',
        'City': 'city',
        'State': 'state',
        'Zip Code': 'zip',
        'Business Fax': 'fax',
        'Business Website': 'website',
        'First Name': 'firstName',
        'Last Name': 'lastName',
        'Username': 'username',
        'Email': 'ownerEmail',
        'Re-enter Email': 'ownerReEnterEmail',
        'Phone': 'ownerPhone',
        'Title': 'title'
    };
    
    gtmInitialized = false;
    
    connectedCallback() {
        this.loadInitialData();
    }
    
    renderedCallback() {
        if (this.gtmInitialized) {
            // Render content if needed
            if (this.content && this.showContent) {
                this.renderContent();
            }
            return;
        }
        this.gtmInitialized = true;
        
        loadScript(this, GOOGLE_ANALYTICS)
            .then(() => {
                console.log('✅ GTM script loaded successfully');
            })
            .catch(error => {
                console.error('❌ Failed to load GTM script', error);
            });
        
        // Render content after script loads
        if (this.content && this.showContent) {
            this.renderContent();
        }
    }
    
    renderContent() {
        // Render content in content section
        const contentDiv = this.template.querySelector('[data-id="content"]');
        if (contentDiv && this.content) {
            contentDiv.innerHTML = this.content;
        }
        
        // Render content in terms section (when shown)
        const termsContentDiv = this.template.querySelector('[data-id="termsContent"]');
        if (termsContentDiv && this.content) {
            termsContentDiv.innerHTML = this.content;
        }
    }
    
    async loadInitialData() {
        this.isLoading = true;
        try {
            const data = await getRegistrationData({ isRenewal: false });
            this.content = data.content || '';
            this.stateOptions = data.stateOptions || [];
        } catch (error) {
            console.error('Error loading registration data:', error);
            this.showError('Error loading registration data. Please refresh the page.');
        } finally {
            this.isLoading = false;
        }
    }
    
    // Handle field changes
    handleChange(event) {
        const prop = this.fieldMap[event.target.label];
        if (prop) {
            this[prop] = event.target.value;
            this.clearFieldError(event.target);
        }
    }
    
    // Handle Business Name change
    handleBusinessNameChange(event) {
        this.businessName = event.target.value;
        this.clearFieldError(event.target);
        
        // Clear business name duplication error
        const errorDiv = this.template.querySelector('[data-id="businessNameDuplicationError"]');
        if (errorDiv) {
            errorDiv.classList.add('slds-hide');
        }
    }
    
    // Handle email changes
    handleEmailChange(event) {
        const field = event.target.dataset.id;
        if (!field) return;
        
        this[field] = event.target.value;
        this.clearFieldError(event.target);
        
        // Determine which email pair we're dealing with
        let primaryId, reId;
        if (field === 'businessEmail' || field === 'reEnterEmail') {
            primaryId = 'businessEmail';
            reId = 'reEnterEmail';
        } else if (field === 'ownerEmail' || field === 'ownerReEnterEmail') {
            primaryId = 'ownerEmail';
            reId = 'ownerReEnterEmail';
        }
        
        // Validate email match if both fields have values
        if (primaryId && reId && this[primaryId] && this[reId]) {
            const reInput = this.template.querySelector(`lightning-input[data-id="${reId}"]`);
            if (reInput && this[primaryId] !== this[reId]) {
                reInput.setCustomValidity('Email address must match.');
                reInput.reportValidity();
            } else if (reInput) {
                reInput.setCustomValidity('');
                reInput.reportValidity();
            }
        }
    }
    
    clearFieldError(input) {
        if (input && input.setCustomValidity) {
            input.setCustomValidity('');
            input.reportValidity();
        }
    }
    
    async handleNextOrAccept() {
        console.log('[REGISTRATION] Next button clicked - showForm:', this.showForm);
        if (this.showForm) {
            await this.handleNext();
        }
    }
    
    async handleNext() {
        console.log('[REGISTRATION] handleNext() called');
        
        // Validate all required fields
        const inputs = this.template.querySelectorAll(
            'lightning-input[required], lightning-textarea[required], lightning-combobox[required]'
        );
        
        console.log('[REGISTRATION] Found required inputs:', inputs.length);
        
        let isValid = true;
        inputs.forEach(input => {
            if (!input.reportValidity()) {
                console.log('[REGISTRATION] Invalid input:', input.label);
                isValid = false;
            }
        });
        
        console.log('[REGISTRATION] Form validation result:', isValid);
        
        // Validate email matching
        if (this.businessEmail && this.reEnterEmail && this.businessEmail !== this.reEnterEmail) {
            const reInput = this.template.querySelector('lightning-input[data-id="reEnterEmail"]');
            if (reInput) {
                reInput.setCustomValidity('Email address must match.');
                reInput.reportValidity();
            }
            isValid = false;
        }
        
        if (this.ownerEmail && this.ownerReEnterEmail && this.ownerEmail !== this.ownerReEnterEmail) {
            const reInput = this.template.querySelector('lightning-input[data-id="ownerReEnterEmail"]');
            if (reInput) {
                reInput.setCustomValidity('Email address must match.');
                reInput.reportValidity();
            }
            isValid = false;
        }
        
        // Validate email format
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (this.businessEmail && !emailRegex.test(this.businessEmail)) {
            const emailInput = this.template.querySelector('lightning-input[data-id="businessEmail"]');
            if (emailInput) {
                emailInput.setCustomValidity('Active email is required and must be formatted as an email address.');
                emailInput.reportValidity();
            }
            isValid = false;
        }
        
        if (this.ownerEmail && !emailRegex.test(this.ownerEmail)) {
            const emailInput = this.template.querySelector('lightning-input[data-id="ownerEmail"]');
            if (emailInput) {
                emailInput.setCustomValidity('Active email is required and must be formatted as an email address.');
                emailInput.reportValidity();
            }
            isValid = false;
        }
        
        // Validate username (required field)
        if (!this.username || this.username.trim() === '') {
            const usernameInput = this.template.querySelector('lightning-input[data-id="username"]');
            if (usernameInput) {
                usernameInput.setCustomValidity('Username is required.');
                usernameInput.reportValidity();
            }
            isValid = false;
        } else if (this.username && (this.username.includes(' ') || this.username.includes('@'))) {
            const usernameInput = this.template.querySelector('lightning-input[data-id="username"]');
            if (usernameInput) {
                usernameInput.setCustomValidity('Username is not available, and/or cannot be formatted as an email address.');
                usernameInput.reportValidity();
            }
            isValid = false;
        }
        
        if (!isValid) {
            console.log('[REGISTRATION] Form validation failed. Cannot proceed.');
            this.showError('Please fix the errors in the form and try again.');
            return;
        }
        
        console.log('[REGISTRATION] Form validation passed. Proceeding with submission.');
        
        // Prepare form values matching VF page structure
        const formValues = {
            accountName: this.businessName,
            email: this.businessEmail ? this.businessEmail.trim() : '',
            emailVerify: this.reEnterEmail ? this.reEnterEmail.trim() : '',
            address1: this.businessAddress1 || '',
            address2: this.businessAddress2 || '',
            city: this.city || '',
            state: this.state || '',
            postalCode: this.zip || '',
            phone: this.businessPhone || '',
            fax: this.fax || '',
            website: this.website || '',
            ownerFirstName: this.firstName || '',
            ownerLastName: this.lastName || '',
            ownerUsername: this.username || '',
            ownerEmail: this.ownerEmail ? this.ownerEmail.trim() : '',
            ownerEmailVerify: this.ownerReEnterEmail ? this.ownerReEnterEmail.trim() : '',
            ownerPhone: this.ownerPhone || '',
            ownerTitle: this.title || ''
        };
        
        // Ensure website starts with http/https if provided
        if (formValues.website && 
            !formValues.website.startsWith('http://') && 
            !formValues.website.startsWith('https://')) {
            formValues.website = 'https://' + formValues.website;
        }
        
        this.isLoading = true;
        console.log('[REGISTRATION] Submitting form with values:', JSON.stringify(formValues, null, 2));
        
        try {
            const result = await proceed({ formValues: formValues });
            console.log('[REGISTRATION] Proceed result:', result);
            
            if (result.success) {
                this.leadId = result.leadId;
                console.log('[REGISTRATION] Lead created successfully. Lead ID:', this.leadId);
                
                // Navigate to separate Terms & Conditions LWC page with leadId
                this.navigateToTerms(result.leadId);
            } else {
                console.error('[REGISTRATION] Proceed failed:', result.message);
                // Handle errors
                if (result.message && result.message.includes('already exists')) {
                    this.showBusinessNameDuplicationError(result.message);
                } else {
                    this.showBusinessNameError(result.message || 'Error submitting registration form.');
                }
            }
        } catch (error) {
            console.error('Error submitting registration:', error);
            const errorMessage = error.body?.message || error.message || 'Unexpected error while submitting registration form.';
            this.showBusinessNameError(errorMessage);
        } finally {
            this.isLoading = false;
        }
    }
    
    navigateToTerms(leadId) {
        console.log('[REGISTRATION] Navigating to Terms & Conditions with Lead ID:', leadId);
        
        if (!leadId) {
            this.showError('Lead ID is missing. Cannot navigate to Terms page.');
            return;
        }
        
        // Navigate to Terms & Conditions page using comm__namedPage
        const pageRef = {
            type: 'comm__namedPage',
            attributes: {
                name: 'CE_Terms_and_Conditions__c' // Community Page API name
            },
            state: {
                leadId: leadId
            }
        };
        
        console.log('[REGISTRATION] Navigation page reference:', pageRef);
        
        try {
            const navigationPromise = this[NavigationMixin.Navigate](pageRef);
            if (navigationPromise && typeof navigationPromise.then === 'function') {
                navigationPromise
                    .then(() => {
                        console.log('[REGISTRATION] Navigation successful');
                    })
                    .catch(error => {
                        console.error('[REGISTRATION] Navigation error:', error);
                        this.isLoading = false;
                        this.showError('Error navigating to Terms & Conditions page. Please try again.');
                    });
            } else {
                // Navigation completed synchronously
                console.log('[REGISTRATION] Navigation completed');
            }
        } catch (error) {
            console.error('[REGISTRATION] Navigation exception:', error);
            this.isLoading = false;
            this.showError('Error navigating to Terms & Conditions page. Please try again.');
        }
    }
    
    navigateToPayment(orderIds) {
        console.log('[REGISTRATION] Navigating to payment with order IDs:', orderIds);
        
        // Navigate to payment page using comm__namedPage
        const pageRef = {
            type: 'comm__namedPage',
            attributes: {
                name: 'Payment__c'
            },
            state: {
                ids: JSON.stringify(orderIds)
            }
        };
        
        this[NavigationMixin.Navigate](pageRef).catch(error => {
            console.error('[REGISTRATION] Navigation error:', error);
            this.showError('Error navigating to payment page. Please try again.');
        });
    }
    
    showBusinessNameError(message) {
        const bizNameInput = this.template.querySelector('lightning-input[data-id="businessName"]');
        if (bizNameInput) {
            bizNameInput.setCustomValidity(message || 'Business name is required. If you do not have a business name, insert your name here.');
            bizNameInput.reportValidity();
        }
        
        // Show error message div
        const errorDiv = this.template.querySelector('[data-id="businessNameError"]');
        if (errorDiv) {
            errorDiv.classList.remove('slds-hide');
        }
    }
    
    showBusinessNameDuplicationError(message) {
        // Hide regular error
        const errorDiv = this.template.querySelector('[data-id="businessNameError"]');
        if (errorDiv) {
            errorDiv.classList.add('slds-hide');
        }
        
        // Show duplication error
        const dupErrorDiv = this.template.querySelector('[data-id="businessNameDuplicationError"]');
        if (dupErrorDiv) {
            dupErrorDiv.classList.remove('slds-hide');
            // Update message if needed
            const messageElement = dupErrorDiv.querySelector('.error-message');
            if (messageElement) {
                messageElement.textContent = message;
            }
        }
    }
    
    showError(message) {
        // Show toast or error message
        const evt = new ShowToastEvent({
            title: 'Error',
            message: message,
            variant: 'error'
        });
        this.dispatchEvent(evt);
    }
    
    get showContent() {
        return this.content && this.content.length > 0;
    }
}
