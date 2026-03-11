import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { loadStyle } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import portalImages from '@salesforce/resourceUrl/Portal_Images';
import getInitData from '@salesforce/apex/CeProviderRegistrationLwcController.getInitData';
import proceed from '@salesforce/apex/CeProviderRegistrationLwcController.proceed';
import getCurrentUserAccountDetails from '@salesforce/apex/OrgRegistryController.getCurrentUserAccountDetails';
import updateAccountAndCreateOrder from '@salesforce/apex/OrgRegistryController.updateAccountAndCreateOrder';
import getStatePicklist from '@salesforce/apex/OrgRegistryController.getStatePicklist';
import getRenewalContent from '@salesforce/apex/OrgRegistryController.getRenewalContent';
import checkRenewalStatus from '@salesforce/apex/OrgRegistryController.checkRenewalStatus';

export default class CeProviderRegistrationForm extends NavigationMixin(LightningElement) {
    @track isRenewalMode = false;
    @track stateOptions = [];
    @track contentHtml = '';
    @track renewalContent = '';
    @track accountId = null;
    @track accountRecord = {};
    @track showRenewalCompletedPopup = false;
    @track isSubmitting = false;

    // Static resource images
    portalImages = portalImages;
    headerImage0 = portalImages + '/FSMTB_header0.png';

    // Form fields (used for both registration and renewal)
    @track accountName = '';
    @track website = '';
    @track email = '';
    @track emailVerify = '';
    @track address1 = '';
    @track address2 = '';
    @track city = '';
    @track state = '';
    @track postalCode = '';
    @track phone = '';
    @track fax = '';

    @track ownerFirstName = '';
    @track ownerLastName = '';
    @track ownerUsername = '';
    @track ownerEmail = '';
    @track ownerEmailVerify = '';
    @track ownerPhone = '';
    @track ownerTitle = '';

    // Error flags
    @track displayBusinessNameError = false;
    @track displayBusinessNameDuplicationError = false;
    @track displayBusinessEmailError = false;
    @track displayBusinessEmailReenterError = false;
    @track displayBusinessAddressError = false;
    @track displayCityError = false;
    @track displayZipError = false;
    @track displayBusinessPhoneError = false;
    @track displayFirstNameError = false;
    @track displayLastNameError = false;
    @track displayUsernameError = false;
    @track displayEmailError = false;
    @track displayEmailReenterError = false;
    @track displayPhoneError = false;
    @track displayWebsiteError = false;

    checkRenewalMode() {
        // Check multiple sources for paymentType parameter
        let paymentType = null;
        
        if (typeof window !== 'undefined') {
            // Check URL query parameters
            const urlParams = new URLSearchParams(window.location.search);
            paymentType = urlParams.get('paymentType');
            
            // Also check hash fragment
            if (!paymentType && window.location.hash) {
                const hashParams = new URLSearchParams(window.location.hash.substring(1));
                paymentType = hashParams.get('paymentType');
            }
            
            // Check full URL string as last resort
            if (!paymentType && window.location.href.includes('paymentType=renewal')) {
                paymentType = 'renewal';
            }
        }
        
        return paymentType === 'renewal';
    }

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        let paymentType = null;
        
        if (pageRef) {
            // Check for paymentType=renewal in the page state
            const state = pageRef.state || {};
            paymentType = state.paymentType || state.c__paymentType;
        }
        
        // Fallback to URL check if not in pageRef
        if (!paymentType) {
            paymentType = this.checkRenewalMode() ? 'renewal' : null;
        }

        const wasRenewalMode = this.isRenewalMode;
        this.isRenewalMode = paymentType === 'renewal';
        
        console.log('[CE PROVIDER REGISTRATION] Page reference update:', {
            hasPageRef: !!pageRef,
            paymentType: paymentType,
            isRenewalMode: this.isRenewalMode,
            wasRenewalMode: wasRenewalMode
        });
        
        // If switching to renewal mode, load renewal data
        if (this.isRenewalMode && !wasRenewalMode) {
            console.log('[CE PROVIDER REGISTRATION] Switching to renewal mode, loading data...');
            this.loadRenewalData();
        } else if (!this.isRenewalMode && wasRenewalMode) {
            // Switched away from renewal mode, load registration data
            console.log('[CE PROVIDER REGISTRATION] Switching to registration mode');
            this.loadInitData();
        }
    }

    connectedCallback() {
        // Check URL parameters directly first (in case wire hasn't fired yet)
        const isRenewal = this.checkRenewalMode();
        
        console.log('[CE PROVIDER REGISTRATION] Connected callback:', {
            currentIsRenewalMode: this.isRenewalMode,
            detectedFromURL: isRenewal,
            url: typeof window !== 'undefined' ? window.location.href : 'N/A'
        });
        
        if (isRenewal && !this.isRenewalMode) {
            console.log('[CE PROVIDER REGISTRATION] Detected renewal mode from URL in connectedCallback');
            this.isRenewalMode = true;
        }

        if (this.isRenewalMode) {
            console.log('[CE PROVIDER REGISTRATION] Loading renewal data in connectedCallback');
            this.loadRenewalData();
        } else {
            this.loadInitData();
        }
        // Load legacy portal styles to mimic VF UI
        loadStyle(this, '/resource/FSMTBAssets/FSMTBAssets/css/global.css').catch(err => {
            // eslint-disable-next-line no-console
            console.error('Error loading portal styles', err);
        });
    }

    renderedCallback() {
        // Final check for renewal mode after component renders (in case wire service is delayed)
        if (!this.isRenewalMode && typeof window !== 'undefined') {
            const isRenewal = this.checkRenewalMode();
            if (isRenewal) {
                console.log('[CE PROVIDER REGISTRATION] Detected renewal mode in renderedCallback');
                this.isRenewalMode = true;
                // Only load if we haven't loaded renewal data yet
                if (!this.renewalContent && this.stateOptions.length === 0) {
                    this.loadRenewalData();
                }
            }
        }
        
        // If in renewal mode and we have state options but state value isn't set yet, set it now
        if (this.isRenewalMode && this.stateOptions && this.stateOptions.length > 0 && 
            this.accountId && !this.state && this.accountRecord && this.accountRecord.BillingStateCode) {
            // State options are now available, set the state value
            const stateExists = this.stateOptions.some(opt => opt.value === this.accountRecord.BillingStateCode);
            if (stateExists) {
                this.state = this.accountRecord.BillingStateCode;
                console.log('[CE PROVIDER REGISTRATION] State value set in renderedCallback:', this.state);
            }
        }
    }

    async loadInitData() {
        try {
            const res = await getInitData();
            this.stateOptions = res.statePicklist || [];
            this.contentHtml = res.content || '';
        } catch (e) {
            // eslint-disable-next-line no-console
            console.error('Error loading registration init data', e);
        }
    }

    async loadRenewalData() {
        try {
            console.log('[CE PROVIDER REGISTRATION] Starting to load renewal data...');
            
            // Ensure we're in renewal mode before loading
            if (!this.isRenewalMode) {
                console.warn('[CE PROVIDER REGISTRATION] Not in renewal mode, skipping data load');
                return;
            }
            
            // Load state picklist first, then account data (state value needs options to be available)
            const stateResult = await getStatePicklist().catch((err) => {
                console.error('Error loading state picklist:', err);
                return [];
            });
            
            this.stateOptions = stateResult || [];
            console.log('[CE PROVIDER REGISTRATION] State options loaded:', this.stateOptions.length);
            
            // Load renewal content and account data in parallel
            const [contentResult, accountResult] = await Promise.all([
                getRenewalContent().catch((err) => {
                    console.error('Error loading renewal content:', err);
                    return '';
                }),
                getCurrentUserAccountDetails().catch((err) => {
                    console.error('Error loading account details:', err);
                    return null;
                })
            ]);

            console.log('[CE PROVIDER REGISTRATION] Data loaded:', {
                hasContent: !!contentResult,
                stateOptionsCount: this.stateOptions.length,
                hasAccount: !!accountResult,
                accountName: accountResult?.Name
            });

            this.renewalContent = contentResult || '';

            if (accountResult) {
                console.log('[CE PROVIDER REGISTRATION] Account data received:', {
                    Id: accountResult.Id,
                    Name: accountResult.Name,
                    Email__c: accountResult.Email__c,
                    BillingStreet: accountResult.BillingStreet,
                    BillingCity: accountResult.BillingCity,
                    BillingStateCode: accountResult.BillingStateCode,
                    BillingPostalCode: accountResult.BillingPostalCode,
                    Phone: accountResult.Phone,
                    Fax: accountResult.Fax,
                    Website: accountResult.Website
                });

                this.accountId = accountResult.Id;
                
                // Initialize accountRecord first
                this.accountRecord = {
                    Id: accountResult.Id,
                    Name: accountResult.Name || '',
                    Email__c: accountResult.Email__c || '',
                    BillingStreet: accountResult.BillingStreet || '',
                    BillingCity: accountResult.BillingCity || '',
                    BillingStateCode: accountResult.BillingStateCode || '',
                    BillingPostalCode: accountResult.BillingPostalCode || '',
                    Phone: accountResult.Phone || '',
                    Fax: accountResult.Fax || '',
                    Website: accountResult.Website || ''
                };
                
                // Update form fields immediately
                this.accountName = accountResult.Name || '';
                this.email = accountResult.Email__c || '';
                this.address1 = accountResult.BillingStreet || '';
                this.city = accountResult.BillingCity || '';
                this.postalCode = accountResult.BillingPostalCode || '';
                this.phone = accountResult.Phone || '';
                this.fax = accountResult.Fax || '';
                this.website = accountResult.Website || '';
                
                // Set state value - use Promise.resolve to ensure it happens after current execution
                // This ensures stateOptions are available for the combobox
                Promise.resolve().then(() => {
                    if (accountResult.BillingStateCode && this.stateOptions && this.stateOptions.length > 0) {
                        // Verify the state code exists in the options
                        const stateExists = this.stateOptions.some(opt => opt.value === accountResult.BillingStateCode);
                        if (stateExists) {
                            this.state = accountResult.BillingStateCode;
                        } else {
                            console.warn('[CE PROVIDER REGISTRATION] State code not found in options:', accountResult.BillingStateCode);
                            // Still set it - the combobox might accept it
                            this.state = accountResult.BillingStateCode;
                        }
                    } else if (accountResult.BillingStateCode) {
                        // Set it even if options aren't loaded yet
                        this.state = accountResult.BillingStateCode;
                    }
                    
                    console.log('[CE PROVIDER REGISTRATION] Form fields populated:', {
                        accountName: this.accountName,
                        email: this.email,
                        address1: this.address1,
                        city: this.city,
                        state: this.state,
                        postalCode: this.postalCode,
                        phone: this.phone,
                        fax: this.fax,
                        website: this.website,
                        stateOptionsCount: this.stateOptions.length
                    });
                });
            } else {
                console.warn('[CE PROVIDER REGISTRATION] No account data returned from getCurrentUserAccountDetails');
                this.showToast('Warning', 'Unable to load your account information. Please fill in the form manually.', 'warning');
            }
        } catch (e) {
            console.error('[CE PROVIDER REGISTRATION] Error loading renewal data:', e);
            this.showToast('Error', 'Unable to load account information. Please refresh the page.', 'error');
        }
    }

    handleInputChange(event) {
        const field = event.target.dataset.field;
        const value =
            event.detail && event.detail.value !== undefined
                ? event.detail.value
                : event.target.value;
        if (!field) return;
        this[field] = value;
        
        // Clear browser validation messages when field changes
        // This prevents browser from showing validation on field blur
        if (event.target && event.target.setCustomValidity) {
            event.target.setCustomValidity('');
        }
        
        // Validate email matching for Organization Information section
        if (field === 'email' || field === 'emailVerify') {
            this.validateEmailMatch('email', 'emailVerify', event.target);
        }
        
        // Validate email matching for Registry Account Owner section
        if (field === 'ownerEmail' || field === 'ownerEmailVerify') {
            this.validateEmailMatch('ownerEmail', 'ownerEmailVerify', event.target);
        }
        
        // If in renewal mode, also update accountRecord for the update call
        if (this.isRenewalMode && this.accountRecord) {
            // Map form fields to account record fields
            const fieldMap = {
                'email': 'Email__c',
                'address1': 'BillingStreet',
                'city': 'BillingCity',
                'state': 'BillingStateCode',
                'postalCode': 'BillingPostalCode',
                'phone': 'Phone',
                'fax': 'Fax',
                'website': 'Website'
            };
            
            if (fieldMap[field]) {
                this.accountRecord[fieldMap[field]] = value;
            }
        }
    }
    
    validateEmailMatch(primaryField, verifyField, currentInput) {
        const primaryValue = this[primaryField];
        const verifyValue = this[verifyField];
        
        // Only validate if both fields have values
        if (primaryValue && verifyValue) {
            const verifyInput = this.template.querySelector(`lightning-input[data-field="${verifyField}"]`);
            if (verifyInput) {
                if (primaryValue !== verifyValue) {
                    verifyInput.setCustomValidity('Email address must match.');
                } else {
                    verifyInput.setCustomValidity('');
                }
                verifyInput.reportValidity();
            }
        } else {
            // Clear validation if either field is empty
            const verifyInput = this.template.querySelector(`lightning-input[data-field="${verifyField}"]`);
            if (verifyInput) {
                verifyInput.setCustomValidity('');
                verifyInput.reportValidity();
            }
        }
    }

    resetErrorFlags() {
        this.displayBusinessNameError = false;
        this.displayBusinessNameDuplicationError = false;
        this.displayBusinessEmailError = false;
        this.displayBusinessEmailReenterError = false;
        this.displayBusinessAddressError = false;
        this.displayCityError = false;
        this.displayZipError = false;
        this.displayBusinessPhoneError = false;
        this.displayFirstNameError = false;
        this.displayLastNameError = false;
        this.displayUsernameError = false;
        this.displayEmailError = false;
        this.displayEmailReenterError = false;
        this.displayPhoneError = false;
        this.displayWebsiteError = false;
    }

    async handleNext() {
        // Prevent double-click / multiple submissions
        if (this.isSubmitting) {
            return;
        }

        this.isSubmitting = true;

        try {
            if (this.isRenewalMode) {
                // Handle renewal mode: validate and update account, create order, navigate to payment
                await this.handleRenewalNext();
            } else {
                // Handle registration mode: validate and create lead, navigate to terms
                await this.handleRegistrationNext();
            }
        } finally {
            // Always re-enable the button after processing
            this.isSubmitting = false;
        }
    }

    async handleRenewalNext() {
        // Check if renewal was already completed by another user (only if future Membership exists)
        if (this.accountId) {
            try {
                const renewalAlreadyCompleted = await checkRenewalStatus({ accountId: this.accountId });
                if (renewalAlreadyCompleted) {
                    console.log('[CE PROVIDER REGISTRATION] Renewal already completed by another user');
                    this.showRenewalCompletedPopup = true;
                    return; // Don't proceed with renewal if already complete
                }
            } catch (error) {
                console.error('[CE PROVIDER REGISTRATION] Error checking renewal status:', error);
                // Continue with renewal even if check fails
            }
        }
        
        // Ensure accountRecord is initialized
        if (!this.accountRecord) {
            this.accountRecord = {};
        }
        
        // Ensure accountRecord has Id
        if (!this.accountRecord.Id && this.accountId) {
            this.accountRecord.Id = this.accountId;
        }
        
        // Update accountRecord with current form values before validation
        this.accountRecord.Email__c = this.email || '';
        this.accountRecord.BillingStreet = this.address1 || '';
        this.accountRecord.BillingCity = this.city || '';
        this.accountRecord.BillingStateCode = this.state || '';
        this.accountRecord.BillingPostalCode = this.postalCode || '';
        this.accountRecord.Phone = this.phone || '';
        this.accountRecord.Fax = this.fax || '';
        this.accountRecord.Website = this.website || '';
        
        console.log('[CE PROVIDER REGISTRATION] Validating renewal form with accountRecord:', {
            Id: this.accountRecord.Id,
            Email__c: this.accountRecord.Email__c,
            BillingStreet: this.accountRecord.BillingStreet,
            BillingCity: this.accountRecord.BillingCity,
            BillingStateCode: this.accountRecord.BillingStateCode
        });
        
        // Clear all browser validation messages before submission
        const allInputs = this.template.querySelectorAll('lightning-input, lightning-textarea, lightning-combobox');
        allInputs.forEach(input => {
            if (input && input.setCustomValidity) {
                input.setCustomValidity('');
            }
        });
        
        // Client-side validation for renewal - check if required fields are filled
        let allValid = true;
        const requiredInputs = this.template.querySelectorAll('lightning-input[required], lightning-textarea[required], lightning-combobox[required]');
        requiredInputs.forEach(input => {
            const value = input.value || (input.detail && input.detail.value);
            if (!value || (typeof value === 'string' && value.trim() === '')) {
                allValid = false;
            }
        });
        
        // Validate website is required for renewal
        if (!this.website || this.website.trim() === '') {
            allValid = false;
            this.displayWebsiteError = true;
        } else {
            // Validate website format
            const websiteTrimmed = this.website.trim();
            const websitePattern = /^(https?:\/\/)?([\da-z\.-]+)\.([a-z\.]{2,6})([\/\w \.-]*)*\/?$/i;
            if (!websitePattern.test(websiteTrimmed) && !websiteTrimmed.includes('.') && websiteTrimmed.length < 3) {
                allValid = false;
                this.displayWebsiteError = true;
            }
        }

        if (!allValid) {
            if (this.displayWebsiteError) {
                this.showToast('Error', 'Business Website is required. Please enter a valid website URL.', 'error');
            } else {
                this.showToast('Error', 'Please fill in all required fields correctly.', 'error');
            }
            return;
        }

        try {
            const result = await updateAccountAndCreateOrder({ acc: this.accountRecord });
            if (result.success) {
                this.accountRecord = JSON.parse(JSON.stringify(result.updatedAccount));
                const orderId = result.orderId;
                this.showToast('Success', 'Account updated and Order created successfully', 'success');

                // Navigate to payment page with order ID
                this.navigateToPayment([orderId]);
            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', error.body ? error.body.message : 'Error updating account or creating order', 'error');
        }
    }

    async handleRegistrationNext() {
        this.resetErrorFlags();

        // Clear all browser validation messages before submission
        const allInputs = this.template.querySelectorAll('lightning-input, lightning-textarea, lightning-combobox');
        allInputs.forEach(input => {
            if (input && input.setCustomValidity) {
                input.setCustomValidity('');
            }
        });

        const formValues = {
            accountName: this.accountName || '',
            website: this.website || '',
            email: this.email || '',
            emailVerify: this.emailVerify || '',
            address1: this.address1 || '',
            address2: this.address2 || '',
            city: this.city || '',
            state: this.state || '',
            postalCode: this.postalCode || '',
            phone: this.phone || '',
            fax: this.fax || '',
            ownerFirstName: this.ownerFirstName || '',
            ownerLastName: this.ownerLastName || '',
            ownerUsername: this.ownerUsername || '',
            ownerEmail: this.ownerEmail || '',
            ownerEmailVerify: this.ownerEmailVerify || '',
            ownerPhone: this.ownerPhone || '',
            ownerTitle: this.ownerTitle || ''
        };

        try {
            // Website validation - required field
            if (!formValues.website || formValues.website.trim() === '') {
                this.displayWebsiteError = true;
                this.showToast('Error', 'Business Website is required. Please enter a valid website URL.', 'error');
                return;
            }
            
            // Basic website format validation
            const websiteTrimmed = formValues.website.trim();
            // Simple URL pattern: optional protocol + at least one dot and no spaces
            const websitePattern = /^(https?:\/\/)?[^\s]+\.[^\s]+$/i;
            if (!websitePattern.test(websiteTrimmed)) {
                this.displayWebsiteError = true;
                this.showToast('Validation Error', 'Please enter a valid website URL (for example: https://www.example.com).', 'error');
                return;
            }

            console.log('[CE PROVIDER REGISTRATION] Submitting form with values:', JSON.stringify(formValues, null, 2));
            const result = await proceed({ formValues });
            console.log('[CE PROVIDER REGISTRATION] Proceed result:', result);

            // Apply error flags so UI matches VF messages
            this.displayBusinessNameError = result.displayBusinessNameError;
            this.displayBusinessNameDuplicationError = result.displayBusinessNameDuplicationError;
            this.displayBusinessEmailError = result.displayBusinessEmailError;
            this.displayBusinessEmailReenterError = result.displayBusinessEmailReenterError;
            this.displayBusinessAddressError = result.displayBusinessAddressError;
            this.displayCityError = result.displayCityError;
            this.displayZipError = result.displayZipError;
            this.displayBusinessPhoneError = result.displayBusinessPhoneError;
            this.displayFirstNameError = result.displayFirstNameError;
            this.displayLastNameError = result.displayLastNameError;
            this.displayUsernameError = result.displayUsernameError;
            this.displayEmailError = result.displayEmailError;
            this.displayEmailReenterError = result.displayEmailReenterError;
            this.displayPhoneError = result.displayPhoneError;
            this.displayWebsiteError = result.displayWebsiteError || false;

            if (!result.success) {
                // Show error message to user
                console.warn('[CE PROVIDER REGISTRATION] Registration validation failed', result.message);
                if (result.message) {
                    this.showToast('Registration Error', result.message, 'error');
                }
                return;
            }

            // On success, navigate to Terms & Conditions page with accountId, contactId, and leadId
            // CRITICAL: leadId is needed so Order can be created with Lead__c for new registrations
            // CRITICAL: accountId and contactId are needed for Membership and User creation after payment
            const accountId = result.accountId;
            const contactId = result.contactId; // Get contactId from result
            const leadId = result.leadId; // Get leadId from result
            console.log('[CE PROVIDER REGISTRATION] Navigation - Account ID:', accountId, 'Contact ID:', contactId, 'Lead ID:', leadId);
            
            if (accountId) {
                const pageRef = {
                    type: 'comm__namedPage',
                    attributes: {
                        name: 'CE_Terms_and_Conditions__c'
                    },
                    state: {
                        accountId: accountId,
                        contactId: contactId,  // Pass contactId for User creation after payment
                        leadId: leadId  // Pass leadId so Order can be created with Lead__c
                    }
                };
                
                // Also add accountId to URL as fallback (in case state doesn't persist)
                // Note: NavigationMixin doesn't directly support URL params, but state should work
                
                console.log('[CE PROVIDER REGISTRATION] Navigating to Terms & Conditions with page reference:', pageRef);
                
                try {
                    const navigationPromise = this[NavigationMixin.Navigate](pageRef);
                    if (navigationPromise && typeof navigationPromise.then === 'function') {
                        navigationPromise
                            .then(() => {
                                console.log('[CE PROVIDER REGISTRATION] Navigation to Terms & Conditions successful');
                            })
                            .catch(error => {
                                console.error('[CE PROVIDER REGISTRATION] Navigation error:', error);
                                this.showToast('Error', 'Error navigating to Terms & Conditions page. Please try again.', 'error');
                            });
                    } else {
                        console.log('[CE PROVIDER REGISTRATION] Navigation completed synchronously');
                    }
                } catch (navError) {
                    console.error('[CE PROVIDER REGISTRATION] Navigation exception:', navError);
                    this.showToast('Error', 'Error navigating to Terms & Conditions page. Please try again.', 'error');
                }
            } else {
                console.error('[CE PROVIDER REGISTRATION] No leadId returned from proceed method');
                this.showToast('Error', 'Registration successful but Lead ID is missing. Cannot navigate to Terms page.', 'error');
            }
        } catch (e) {
            console.error('[CE PROVIDER REGISTRATION] Error submitting registration', e);
            let errorMessage = 'Error submitting registration';
            if (e.body) {
                if (e.body.message) {
                    errorMessage = e.body.message;
                } else if (e.body.pageErrors && e.body.pageErrors.length > 0) {
                    errorMessage = e.body.pageErrors[0].message;
                } else if (e.body.fieldErrors && Object.keys(e.body.fieldErrors).length > 0) {
                    const firstField = Object.keys(e.body.fieldErrors)[0];
                    errorMessage = e.body.fieldErrors[firstField][0].message;
                }
            } else if (e.message) {
                errorMessage = e.message;
            }
            this.showToast('Error', errorMessage, 'error');
        }
    }

    handleReturnToAdmin() {
        // Navigate to Home page where Account Administration is hosted
        try {
            const currentUrl = new URL(window.location.href);
            const currentPath = currentUrl.pathname;
            const sIndex = currentPath.indexOf('/s/');
            
            if (sIndex !== -1) {
                // Construct Home URL: communityPath/s/?tab=accountAdministration
                const communityBase = currentPath.substring(0, sIndex + 3);
                const homeUrl = `${currentUrl.origin}${communityBase}?tab=accountAdministration`;
                console.log('[CE PROVIDER REGISTRATION] Navigating to Home page:', homeUrl);
                window.location.href = homeUrl;
            } else {
                // Fallback: use NavigationMixin to navigate to Home page
                console.log('[CE PROVIDER REGISTRATION] Using NavigationMixin to navigate to Home');
                const navPromise = this[NavigationMixin.Navigate]({
                    type: 'comm__namedPage',
                    attributes: {
                        name: 'Home'
                    },
                    state: {
                        tab: 'accountAdministration'
                    }
                });
                
                if (navPromise && typeof navPromise === 'object' && typeof navPromise.then === 'function') {
                    navPromise.catch(error => {
                        console.error('[CE PROVIDER REGISTRATION] Navigation error:', error);
                        // Final fallback
                        window.location.href = `${currentUrl.origin}/CERegistryPortal/s/?tab=accountAdministration`;
                    });
                }
            }
        } catch (error) {
            console.error('[CE PROVIDER REGISTRATION] Error in handleReturnToAdmin:', error);
            // Final fallback
            try {
                const currentUrl = new URL(window.location.href);
                window.location.href = `${currentUrl.origin}/CERegistryPortal/s/?tab=accountAdministration`;
            } catch (fallbackError) {
                console.error('[CE PROVIDER REGISTRATION] Fallback navigation also failed:', fallbackError);
            }
        }
    }

    navigateToPayment(orderIds) {
        if (!orderIds || orderIds.length === 0) {
            this.showToast('Error', 'No order IDs available for payment. Please contact support.', 'error');
            return;
        }

        const pageRef = {
            type: 'comm__namedPage',
            attributes: {
                name: 'Payment__c'
            },
            state: {
                ids: JSON.stringify(orderIds)
            }
        };

        try {
            this[NavigationMixin.Navigate](pageRef);
        } catch (error) {
            console.error('Error navigating to payment page', error);
            this.showToast('Error', 'Unable to navigate to the payment page. Please try again.', 'error');
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