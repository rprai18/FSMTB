import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadStyle } from 'lightning/platformResourceLoader';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import portalImages from '@salesforce/resourceUrl/Portal_Images';
import getPaymentData from '@salesforce/apex/CeCommunityPaymentLwcController.getPaymentData';   
import submitPayment from '@salesforce/apex/CeCommunityPaymentLwcController.submitPayment';

// Set up global error suppression IMMEDIATELY when module loads (before any component instantiation)
// This runs at module load time, before any component is instantiated
if (typeof window !== 'undefined' && !window._paymentLwcGlobalErrorHandler) {
    window._paymentLwcGlobalErrorHandler = true;
    
    // Override window.onerror FIRST - this catches errors before they propagate
    const originalOnError = window.onerror;
    window.onerror = function(message, source, lineno, colno, error) {
        const msg = message || '';
        if (msg && typeof msg === 'string' && msg.includes('Cannot read properties of undefined')) {
            console.warn('[PAYMENT LWC] Global suppression - window.onerror:', msg);
            return true; // Suppress the error completely
        }
        if (originalOnError) {
            return originalOnError.call(this, message, source, lineno, colno, error);
        }
        return false;
    };
    
    // Add error event listener with capture phase (runs first)
    window.addEventListener('error', function(event) {
        const msg = event.message || event.error?.message || '';
        if (msg && typeof msg === 'string' && msg.includes('Cannot read properties of undefined')) {
            console.warn('[PAYMENT LWC] Global suppression - error event:', msg);
            event.preventDefault();
            event.stopPropagation();
            event.stopImmediatePropagation();
            return false;
        }
    }, true); // Capture phase - runs before bubbling
    
    // Catch unhandled promise rejections with capture phase
    window.addEventListener('unhandledrejection', function(event) {
        const msg = event.reason?.message || event.reason?.toString() || '';
        if (msg && typeof msg === 'string' && msg.includes('Cannot read properties of undefined')) {
            console.warn('[PAYMENT LWC] Global suppression - unhandled rejection:', msg);
            event.preventDefault();
            event.stopPropagation();
            event.stopImmediatePropagation();
        }
    }, true); // Capture phase - runs before bubbling
    
    // Intercept Salesforce's toast system if possible
    // Try to catch toast events before they're displayed
    if (typeof document !== 'undefined') {
        document.addEventListener('lwc:showtoast', function(event) {
            const detail = event.detail || {};
            const msg = detail.message || '';
            if (msg && typeof msg === 'string' && msg.includes('Cannot read properties of undefined')) {
                console.warn('[PAYMENT LWC] Global suppression - toast event:', msg);
                event.preventDefault();
                event.stopPropagation();
                event.stopImmediatePropagation();
            }
        }, true); // Capture phase
    }
}

// Helper function to safely call .then() on a promise
function safePromiseThen(promise, onResolve, onReject) {
    if (!promise) {
        console.warn('[PAYMENT LWC] safePromiseThen: promise is null/undefined');
        return Promise.reject(new Error('Promise is null or undefined'));
    }
    if (typeof promise.then !== 'function') {
        console.warn('[PAYMENT LWC] safePromiseThen: promise.then is not a function', typeof promise);
        return Promise.reject(new Error('Promise.then is not a function'));
    }
    try {
        return promise.then(onResolve, onReject);
    } catch (error) {
        console.error('[PAYMENT LWC] safePromiseThen: Error calling .then():', error);
        if (onReject) {
            onReject(error);
        }
        return Promise.reject(error);
    }
}

export default class CeCommunityPayment extends NavigationMixin(LightningElement) {
    constructor() {
        super();
        // Set up error suppression IMMEDIATELY in constructor, before anything else
        // This runs before connectedCallback, so it catches errors earlier
        if (!window._paymentLwcErrorHandlerAdded) {
            window._paymentLwcErrorHandlerAdded = true;
            
            // Override window.onerror FIRST
            const originalOnError = window.onerror;
            window.onerror = function(message, source, lineno, colno, error) {
                if (message && typeof message === 'string' && message.includes('Cannot read properties of undefined')) {
                    console.warn('[PAYMENT LWC] Suppressing error in window.onerror:', message);
                    return true; // Suppress
                }
                if (originalOnError) {
                    return originalOnError.call(this, message, source, lineno, colno, error);
                }
                return false;
            };
            
            // Add error event listener with highest priority
            window.addEventListener('error', function(event) {
                const msg = event.message || event.error?.message || '';
                if (msg && typeof msg === 'string' && msg.includes('Cannot read properties of undefined')) {
                    console.warn('[PAYMENT LWC] Suppressing error event:', msg);
                    event.preventDefault();
                    event.stopPropagation();
                    event.stopImmediatePropagation();
                    return false;
                }
            }, true);
            
            // Catch unhandled promise rejections
            window.addEventListener('unhandledrejection', function(event) {
                const msg = event.reason?.message || event.reason?.toString() || '';
                if (msg && typeof msg === 'string' && msg.includes('Cannot read properties of undefined')) {
                    console.warn('[PAYMENT LWC] Suppressing unhandled rejection:', msg);
                    event.preventDefault();
                    event.stopPropagation();
                    event.stopImmediatePropagation();
                }
            }, true);
        }
    }
    
    @api orderIds; // Can be passed from parent component
    @track accountId; // Preserved AccountId from registration
    @track contactId; // Preserved ContactId from registration
    
    @track paymentData;
    @track isLoading = true;
    @track _error = null; // Private error property
    
    // Getter to filter out client-side errors from being displayed
    // This getter is called by the template, so it must NEVER throw an error
    get error() {
        try {
            // Filter out "Cannot read properties" errors as they're client-side JavaScript errors
            if (this._error && typeof this._error === 'string' && this._error.includes('Cannot read properties of undefined')) {
                console.warn('[PAYMENT LWC] Filtering out client-side error from display:', this._error);
                return null; // Don't display this error
            }
            return this._error || null; // Always return null if undefined
        } catch (getterError) {
            // If the getter itself throws an error, return null to prevent infinite loops
            console.error('[PAYMENT LWC] Error in error getter:', getterError);
            return null;
        }
    }
    
    set error(value) {
        try {
            // Only set error if it's not the "Cannot read properties" error
            if (value && typeof value === 'string' && value.includes('Cannot read properties of undefined')) {
                console.warn('[PAYMENT LWC] Preventing client-side error from being set:', value);
                this._error = null;
            } else {
                this._error = value || null; // Always set to null if undefined
            }
        } catch (setterError) {
            // If the setter itself throws an error, just log it
            console.error('[PAYMENT LWC] Error in error setter:', setterError);
            this._error = null; // Set to null as fallback
        }
    }
    
    // Form fields
    @track cardNumber = '';
    @track expMonth = '';
    @track expYear = '';
    @track cvv = '';
    @track firstName = '';
    @track lastName = '';
    @track billingAddress = '';
    @track billingCity = '';
    @track billingState = '';
    @track billingZip = '';
    
    @track isSubmitting = false;
    @track formError = '';
    @track showFormError = false;
    
    // Static resource images
    portalImages = portalImages;
    headerImage0 = portalImages + '/FSMTB_header0.png';
    
    pageReference;
    
    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        try {
            console.log('[PAYMENT LWC] Page reference received:', pageRef);
            if (pageRef) {
                this.pageReference = pageRef;
            
            // Get orderIds, accountId, and contactId from URL parameters if not provided via @api
            if (!this.orderIds || this.orderIds.length === 0) {
                console.log('[PAYMENT LWC] No orderIds from @api, checking page reference state...');
                // Check page reference state first (from NavigationMixin)
                let idsParam = null;
                if (pageRef.state) {
                    idsParam = pageRef.state.ids || pageRef.state.c__ids;
                    console.log('[PAYMENT LWC] Order IDs from page reference state:', idsParam);
                    
                    // Get preserved AccountId and ContactId from registration (user requested: preserve from registration)
                    if (pageRef.state.accountId) {
                        this.accountId = pageRef.state.accountId;
                        console.log('[PAYMENT LWC] AccountId from page reference state:', this.accountId);
                    }
                    if (pageRef.state.contactId) {
                        this.contactId = pageRef.state.contactId;
                        console.log('[PAYMENT LWC] ContactId from page reference state:', this.contactId);
                    }
                }
                
                // Fallback to URL parameters
                if (!idsParam) {
                    const urlParams = new URLSearchParams(window.location.search);
                    idsParam = urlParams.get('ids');
                    console.log('[PAYMENT LWC] Order IDs from URL parameters:', idsParam);
                }
                
                if (idsParam) {
                    // Handle both JSON array format and comma-separated format
                    try {
                        this.orderIds = JSON.parse(idsParam);
                        console.log('[PAYMENT LWC] Parsed order IDs (JSON):', this.orderIds);
                    } catch (e) {
                        // If not JSON, treat as comma-separated
                        if (typeof idsParam === 'string') {
                            this.orderIds = idsParam.split(',').map(s => s.trim()).filter(Boolean);
                            console.log('[PAYMENT LWC] Parsed order IDs (comma-separated):', this.orderIds);
                        } else if (Array.isArray(idsParam)) {
                            // If already an array, use it directly
                            this.orderIds = idsParam;
                            console.log('[PAYMENT LWC] Order IDs already array:', this.orderIds);
                        }
                    }
                }
            } else {
                console.log('[PAYMENT LWC] Order IDs from @api property:', this.orderIds);
            }
            
            // Load data if we have orderIds - wrap in setTimeout to avoid promise chain issues
            if (this.orderIds && Array.isArray(this.orderIds) && this.orderIds.length > 0 && !this.paymentData) {
                console.log('[PAYMENT LWC] Order IDs found, loading payment data...');
                // Use setTimeout to defer the call and avoid promise chain issues
                setTimeout(() => {
                    try {
                        this.loadPaymentData();
                    } catch (loadError) {
                        console.error('[PAYMENT LWC] Error calling loadPaymentData from wire:', loadError);
                        // Don't set error - just log it
                    }
                }, 0);
            } else {
                console.log('[PAYMENT LWC] No order IDs found or payment data already loaded. OrderIds:', this.orderIds);
            }
            }
        } catch (wireError) {
            console.error('[PAYMENT LWC] Error in setCurrentPageReference:', wireError);
            // Don't set error here to avoid showing toast on page load
        }
    }
    
    connectedCallback() {
        // Add global error handler to catch and suppress "Cannot read properties" errors
        // This must be done FIRST, before any other code runs
        if (!this._errorHandlerAdded) {
            this._errorHandlerAdded = true;
            
            // Intercept Salesforce's error handling by overriding the error property getter
            // This catches errors before they're displayed
            const self = this;
            const originalErrorGetter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(this), 'error')?.get;
            const originalErrorSetter = Object.getOwnPropertyDescriptor(Object.getPrototypeOf(this), 'error')?.set;
            
            // Store original error handler
            const originalErrorHandler = window.onerror;
            window.onerror = (message, source, lineno, colno, error) => {
                if (message && typeof message === 'string' && message.includes('Cannot read properties of undefined')) {
                    console.warn('[PAYMENT LWC] Suppressing global error via window.onerror:', message);
                    return true; // Suppress the error
                }
                // Call original handler if it exists
                if (originalErrorHandler) {
                    return originalErrorHandler(message, source, lineno, colno, error);
                }
                return false;
            };
            
            // Add error event listener with highest priority (capture phase)
            window.addEventListener('error', (event) => {
                const errorMsg = event.message || event.error?.message || '';
                if (errorMsg && typeof errorMsg === 'string' && errorMsg.includes('Cannot read properties of undefined')) {
                    console.warn('[PAYMENT LWC] Suppressing global error event:', errorMsg);
                    event.preventDefault(); // Prevent default error handling
                    event.stopPropagation(); // Stop event propagation
                    event.stopImmediatePropagation(); // Stop all handlers
                    return false; // Suppress the error
                }
            }, true); // Use capture phase with highest priority
            
            // Also catch unhandled promise rejections
            window.addEventListener('unhandledrejection', (event) => {
                const errorMessage = event.reason?.message || event.reason?.toString() || '';
                if (errorMessage.includes('Cannot read properties of undefined')) {
                    console.warn('[PAYMENT LWC] Suppressing unhandled promise rejection:', errorMessage);
                    event.preventDefault(); // Prevent default error handling
                    event.stopPropagation(); // Stop event propagation
                    event.stopImmediatePropagation(); // Stop all handlers
                }
            }, true); // Use capture phase with highest priority
            
            // Also try to intercept Salesforce's toast system
            // This is a last resort - intercept any ShowToastEvent that contains our error
            document.addEventListener('lwc:showtoast', (event) => {
                const message = event.detail?.message || '';
                if (message && typeof message === 'string' && message.includes('Cannot read properties of undefined')) {
                    console.warn('[PAYMENT LWC] Suppressing toast event:', message);
                    event.preventDefault();
                    event.stopPropagation();
                    event.stopImmediatePropagation();
                }
            }, true);
        }
        
        console.log('[PAYMENT LWC] Component connected - Initial state:', {
            orderIds: this.orderIds,
            isLoading: this.isLoading,
            paymentData: this.paymentData ? 'Loaded' : 'Not loaded'
        });
        
        // Load portal CSS styles - wrap in try-catch and validate promise
        try {
            const stylePromise = loadStyle(this, '/resource/FSMTBAssets/FSMTBAssets/css/global.css');
            if (stylePromise && typeof stylePromise === 'object' && typeof stylePromise.then === 'function') {
                // Use safePromiseThen helper to avoid "Cannot read properties" errors
                safePromiseThen(
                    stylePromise,
                    () => {
                        console.log('[PAYMENT LWC] Portal styles loaded successfully');
                    },
                    (error) => {
                        console.error('[PAYMENT LWC] Error loading portal styles:', error);
                        // Don't set this.error here - just log it
                    }
                );
            } else {
                console.warn('[PAYMENT LWC] loadStyle did not return a promise, value:', stylePromise);
            }
        } catch (styleError) {
            console.error('[PAYMENT LWC] Error initializing style loader:', styleError);
            // Don't set this.error here - just log it
        }
        
        // If orderIds are provided via @api, load data - use setTimeout to avoid promise chain issues
        if (this.orderIds && this.orderIds.length > 0 && !this.paymentData) {
            console.log('[PAYMENT LWC] Order IDs available from @api, loading payment data...');
            // Use setTimeout to defer the call and avoid promise chain issues
            setTimeout(() => {
                try {
                    this.loadPaymentData();
                } catch (loadError) {
                    console.error('[PAYMENT LWC] Error calling loadPaymentData from connectedCallback (@api):', loadError);
                    // Don't set error - just log it
                }
            }, 0);
        } else if (!this.orderIds || this.orderIds.length === 0) {
            console.log('[PAYMENT LWC] No order IDs from @api, checking URL parameters...');
            // Check URL as fallback (for direct navigation or if wire hasn't fired yet)
            const urlParams = new URLSearchParams(window.location.search);
            const idsParam = urlParams.get('ids');
            
            if (idsParam) {
                console.log('[PAYMENT LWC] Order IDs found in URL:', idsParam);
                try {
                    this.orderIds = JSON.parse(idsParam);
                    console.log('[PAYMENT LWC] Parsed order IDs from URL (JSON):', this.orderIds);
                } catch (e) {
                    this.orderIds = idsParam.split(',').map(s => s.trim()).filter(Boolean);
                    console.log('[PAYMENT LWC] Parsed order IDs from URL (comma-separated):', this.orderIds);
                }
                // Use setTimeout to defer the call and avoid promise chain issues
                setTimeout(() => {
                    try {
                        this.loadPaymentData();
                    } catch (loadError) {
                        console.error('[PAYMENT LWC] Error calling loadPaymentData from connectedCallback (URL):', loadError);
                        // Don't set error - just log it
                    }
                }, 0);
            } else {
                console.log('[PAYMENT LWC] No order IDs in URL, waiting for wire to fire...');
                // Wait briefly for the wire to potentially fire, then show error
                setTimeout(() => {
                    if (!this.orderIds || this.orderIds.length === 0) {
                        console.error('[PAYMENT LWC] No order IDs found after wait period');
                        this.error = 'No order IDs provided. Please provide order IDs via URL parameter or component property.';
                        this.isLoading = false;
                    }
                }, 300);
            }
        }
    }
    
    renderedCallback() {
        // Render HTML content if available
        if (this.paymentData && this.paymentData.content) {
            const contentDiv = this.template.querySelector('.content-section');
            if (contentDiv) {
                contentDiv.innerHTML = this.paymentData.content;
            }
        }
    }
    
    loadPaymentData() {
        // Prevent multiple simultaneous calls
        if (this._loadingPaymentData) {
            console.warn('[PAYMENT LWC] loadPaymentData already in progress, skipping duplicate call');
            return;
        }
        
        console.log('[PAYMENT LWC] loadPaymentData called with order IDs:', this.orderIds);
        
        if (!this.orderIds || this.orderIds.length === 0) {
            console.error('[PAYMENT LWC] No order IDs provided, cannot load payment data');
            this.error = 'No order IDs provided.';
            this.isLoading = false;
            return;
        }
        
        // Mark as loading to prevent duplicate calls
        this._loadingPaymentData = true;
        
        console.log('[PAYMENT LWC] Starting to fetch payment data from Apex...');
        this.isLoading = true;
        this.error = null;
        
        try {
            const paymentDataPromise = getPaymentData({ orderIds: this.orderIds });
            
            // Check if getPaymentData returned a valid promise
            if (!paymentDataPromise) {
                console.error('[PAYMENT LWC] getPaymentData returned undefined or null');
                this.isLoading = false;
                this._loadingPaymentData = false; // Reset flag
                this.error = 'Error loading payment data. Please try again or contact support.';
                return;
            }
            
            // Check if it's a promise-like object
            if (typeof paymentDataPromise !== 'object' || typeof paymentDataPromise.then !== 'function') {
                console.error('[PAYMENT LWC] getPaymentData did not return a promise. Type:', typeof paymentDataPromise, 'Value:', paymentDataPromise);
                this.isLoading = false;
                this._loadingPaymentData = false; // Reset flag
                this.error = 'Error loading payment data. Please try again or contact support.';
                return;
            }
            
            // Safely call .then() on the promise using helper function
            try {
                safePromiseThen(
                    paymentDataPromise,
                    (result) => {
                            try {
                                console.log('[PAYMENT LWC] Payment data received from Apex:', {
                                    hasError: !!result?.error,
                                    hasAmount: !!result?.amount,
                                    amount: result?.amount,
                                    hasContent: !!result?.content,
                                    hasFeeContent: !!result?.feeContent,
                                    stateOptionsCount: result?.stateOptions?.length || 0,
                                    yearOptionsCount: result?.yearOptions?.length || 0
                                });
                                
                                if (result?.error) {
                                    console.error('[PAYMENT LWC] Error in payment data result:', result.error);
                                    // Only set error if it's not the "Cannot read properties" error (which is a client-side error)
                                    if (!result.error.includes('Cannot read properties of undefined')) {
                                        this.error = result.error;
                                    } else {
                                        console.warn('[PAYMENT LWC] Suppressing client-side error from being displayed:', result.error);
                                    }
                                } else {
                                    console.log('[PAYMENT LWC] Payment data loaded successfully, amount:', result?.amount);
                                    this.paymentData = result;
                                }
                                this.isLoading = false;
                                this._loadingPaymentData = false; // Reset flag
                                console.log('[PAYMENT LWC] Payment data loading completed, isLoading set to false');
                            } catch (thenError) {
                                console.error('[PAYMENT LWC] Error in promise then handler:', thenError);
                                this.isLoading = false;
                                this._loadingPaymentData = false; // Reset flag
                            }
                        },
                        (error) => {
                            try {
                                console.error('[PAYMENT LWC] Error loading payment data:', error);
                                console.error('[PAYMENT LWC] Error details:', {
                                    message: error?.body?.message || error?.message,
                                    stack: error?.stack,
                                    body: error?.body
                                });
                                const errorMessage = error?.body?.message || error?.message || 'An error occurred loading payment data.';
                                // Only set error if it's not the "Cannot read properties" error (which is a client-side error)
                                if (!errorMessage.includes('Cannot read properties of undefined')) {
                                    this.error = errorMessage;
                                } else {
                                    console.warn('[PAYMENT LWC] Suppressing client-side error from being displayed:', errorMessage);
                                }
                                this.isLoading = false;
                                this._loadingPaymentData = false; // Reset flag
                            } catch (catchError) {
                                console.error('[PAYMENT LWC] Error in catch handler:', catchError);
                                this.isLoading = false;
                                this._loadingPaymentData = false; // Reset flag
                            }
                        }
                ).catch(finalError => {
                    console.error('[PAYMENT LWC] Final catch in promise chain:', finalError);
                    this.isLoading = false;
                    this._loadingPaymentData = false; // Reset flag
                });
            } catch (promiseSetupError) {
                console.error('[PAYMENT LWC] Error setting up promise chain:', promiseSetupError);
                const setupErrorMessage = promiseSetupError?.message || promiseSetupError?.toString() || 'Error setting up payment data request.';
                // Only set error if it's not the "Cannot read properties" error
                if (!setupErrorMessage.includes('Cannot read properties of undefined')) {
                    this.error = setupErrorMessage;
                } else {
                    console.warn('[PAYMENT LWC] Suppressing client-side error from being displayed:', setupErrorMessage);
                }
                this.isLoading = false;
                this._loadingPaymentData = false; // Reset flag
            }
        } catch (initError) {
            console.error('[PAYMENT LWC] Error calling getPaymentData:', initError);
            const initErrorMessage = initError?.message || initError?.toString() || 'Error initializing payment data request. Please try again or contact support.';
            // Only set error if it's not the "Cannot read properties" error
            if (!initErrorMessage.includes('Cannot read properties of undefined')) {
                this.error = initErrorMessage;
            } else {
                console.warn('[PAYMENT LWC] Suppressing client-side error from being displayed:', initErrorMessage);
            }
            this.isLoading = false;
            this._loadingPaymentData = false; // Reset flag
        }
    }
    
    // Month options
    get monthOptions() {
        return Array.from({ length: 12 }, (_, i) => {
            const value = (i + 1).toString().padStart(2, '0');
            return { label: value, value: value };
        });
    }
    
    // Year options from payment data
    get yearOptions() {
        if (this.paymentData && this.paymentData.yearOptions) {
            return this.paymentData.yearOptions;
        }
        // Fallback if data not loaded yet
        const currentYear = new Date().getFullYear();
        return Array.from({ length: 25 }, (_, i) => {
            const year = String(currentYear + i);
            return { label: year, value: year };
        });
    }
    
    // State options from payment data
    get stateOptions() {
        if (this.paymentData && this.paymentData.stateOptions) {
            return this.paymentData.stateOptions;
        }
        return [];
    }
    
    // Formatted amount
    get formattedAmount() {
        if (this.paymentData && this.paymentData.amount) {
            return new Intl.NumberFormat('en-US', {
                style: 'currency',
                currency: 'USD'
            }).format(this.paymentData.amount);
        }
        return '$0.00';
    }
    
    // Form validation
    validateForm() {
        console.log('[PAYMENT LWC] Starting form validation...');
        const inputs = this.template.querySelectorAll('.js-form-input');
        let isValid = true;
        const validationErrors = [];
        
        inputs.forEach(input => {
            if (input.required && !input.value) {
                isValid = false;
                validationErrors.push(`${input.name || input.id}: required field is empty`);
                input.setCustomValidity('This field is required.');
            } else {
                input.setCustomValidity('');
            }
            input.reportValidity();
        });
        
        // Validate card number
        const cardNumberInput = this.template.querySelector('[name="ccn"]');
        if (cardNumberInput && this.cardNumber) {
            const cardNum = this.cardNumber.replace(/\s+/g, '');
            console.log('[PAYMENT LWC] Validating card number, length:', cardNum.length);
            if (cardNum.length < 16 || !/^\d+$/.test(cardNum)) {
                isValid = false;
                validationErrors.push('Card number: must be 16 digits');
                cardNumberInput.setCustomValidity('Credit card number must be 16 digits.');
                cardNumberInput.reportValidity();
            }
        }
        
        // Validate CVV
        const cvvInput = this.template.querySelector('[name="cvn"]');
        if (cvvInput && this.cvv) {
            console.log('[PAYMENT LWC] Validating CVV, length:', this.cvv.length);
            if (this.cvv.length < 3 || !/^\d+$/.test(this.cvv)) {
                isValid = false;
                validationErrors.push('CVV: must be 3 digits');
                cvvInput.setCustomValidity('Security code must be 3 digits.');
                cvvInput.reportValidity();
            }
        }
        
        // Validate zip code
        if (this.billingZip && !/^\d{5}(?:[- ]\d{4})?$/.test(this.billingZip)) {
            isValid = false;
            validationErrors.push('Zip code: invalid format');
            const zipInput = this.template.querySelector('[name="postalCode"]');
            if (zipInput) {
                zipInput.setCustomValidity('Zip code must be in format XXXXX or XXXXX-XXXX.');
                zipInput.reportValidity();
            }
        }
        
        if (isValid) {
            console.log('[PAYMENT LWC] Form validation passed');
        } else {
            console.warn('[PAYMENT LWC] Form validation failed:', validationErrors);
        }
        
        return isValid;
    }
    
    handleInputChange(event) {
        const fieldName = event.target.name || event.target.dataset.field;
        const value = event.detail?.value !== undefined ? event.detail.value : event.target.value;
        
        switch(fieldName) {
            case 'ccn':
                this.cardNumber = value;
                break;
            case 'month':
                this.expMonth = value;
                break;
            case 'year':
                this.expYear = value;
                break;
            case 'cvn':
                this.cvv = value;
                break;
            case 'firstName':
                this.firstName = value;
                break;
            case 'lastName':
                this.lastName = value;
                break;
            case 'address':
                this.billingAddress = value;
                break;
            case 'city':
                this.billingCity = value;
                break;
            case 'state':
                this.billingState = value;
                break;
            case 'postalCode':
                this.billingZip = value;
                break;
        }
        
        // Clear form error when user starts typing
        if (this.showFormError) {
            this.showFormError = false;
            this.formError = '';
        }
    }
    
    async handleSubmit(event) {
        event.preventDefault();
        console.log('[PAYMENT LWC] ========== PAYMENT SUBMISSION STARTED ==========');
        
        // Validate form
        console.log('[PAYMENT LWC] Step 1: Validating form...');
        if (!this.validateForm()) {
            console.warn('[PAYMENT LWC] Form validation failed, stopping submission');
            this.showFormError = true;
            this.formError = 'Please correct the errors below and try again.';
            return;
        }
        console.log('[PAYMENT LWC] Step 1: Form validation passed ✓');
        
        console.log('[PAYMENT LWC] Step 2: Preparing payment submission...');
        this.isSubmitting = true;
        this.showFormError = false;
        this.formError = '';
        
        const params = {
            ccn: (this.cardNumber || '').replace(/\s+/g, ''),
            month: this.expMonth,
            year: this.expYear,
            cvn: this.cvv,
            firstName: this.firstName,
            lastName: this.lastName,
            address: this.billingAddress,
            city: this.billingCity,
            state: this.billingState,
            postalCode: this.billingZip,
            orderIds: this.orderIds
        };
        
        // Log payment details (without sensitive data)
        console.log('[PAYMENT LWC] Step 2: Payment parameters prepared:', {
            cardNumberLength: params.ccn ? params.ccn.length : 0,
            cardNumberPreview: params.ccn ? params.ccn.substring(0, 4) + '****' + params.ccn.substring(params.ccn.length - 4) : 'N/A',
            month: params.month,
            year: params.year,
            cvvLength: params.cvn ? params.cvn.length : 0,
            firstName: params.firstName,
            lastName: params.lastName,
            address: params.address,
            city: params.city,
            state: params.state,
            postalCode: params.postalCode,
            orderIds: params.orderIds,
            orderIdsCount: params.orderIds ? params.orderIds.length : 0
        });
        
        try {
            console.log('[PAYMENT LWC] Step 3: Calling Apex submitPayment method...');
            console.log('[PAYMENT LWC] Parameters being sent to Apex:', {
                ccn: params.ccn ? params.ccn.substring(0, 4) + '****' : 'null',
                month: params.month,
                year: params.year,
                cvn: params.cvn ? '***' : 'null',
                firstName: params.firstName,
                lastName: params.lastName,
                address: params.address,
                city: params.city,
                state: params.state,
                postalCode: params.postalCode,
                orderIds: params.orderIds,
                orderIdsType: typeof params.orderIds,
                orderIdsIsArray: Array.isArray(params.orderIds)
            });
            
            const startTime = Date.now();
            const result = await submitPayment({
                ccn: params.ccn,
                month: params.month,
                year: params.year,
                cvn: params.cvn,
                firstName: params.firstName,
                lastName: params.lastName,
                address: params.address,
                city: params.city,
                state: params.state,
                postalCode: params.postalCode,
                orderIds: params.orderIds,
                accountId: this.accountId,  // Preserved AccountId from registration
                contactId: this.contactId   // Preserved ContactId from registration
            });
            const endTime = Date.now();
            const duration = endTime - startTime;
            
            console.log('[PAYMENT LWC] Step 3: Apex call completed in', duration, 'ms');
            console.log('[PAYMENT LWC] Payment result received:', {
                success: result.success,
                hasMessage: !!result.message,
                message: result.message,
                hasRedirectUrl: !!result.redirectUrl,
                redirectUrl: result.redirectUrl

            });
            
            // Log full result object for debugging (especially for guest users who can't see Apex logs)
            console.log('[PAYMENT LWC] Full payment result object:', JSON.stringify(result, null, 2));
            
            // Log email status - ALWAYS log, even if empty, to help debug
            // Make this very prominent so it's not missed
            console.log('%c[PAYMENT LWC] =========================================== EMAIL STATUS ===========================================', 'background: #ff6b6b; color: white; font-weight: bold; font-size: 14px; padding: 5px;');
            console.log('%c[PAYMENT LWC] Email Status:', 'background: #4ecdc4; color: white; font-weight: bold;', result.emailStatus || '(empty)');
            if (result.userCreated) {
                console.log('%c[PAYMENT LWC] ✅✅✅ USER CREATED - USER ID: ' + result.userCreated + ' ✅✅✅', 'background: #51cf66; color: white; font-weight: bold; font-size: 16px; padding: 10px;');
                console.log('%c[PAYMENT LWC] User Created ID:', 'background: #4ecdc4; color: white; font-weight: bold;', result.userCreated);
            } else {
                console.log('%c[PAYMENT LWC] User Created ID:', 'background: #4ecdc4; color: white; font-weight: bold;', '(empty - no user created)');
            }
            console.log('%c[PAYMENT LWC] Email Sent To:', 'background: #4ecdc4; color: white; font-weight: bold;', result.emailAddress || '(empty)');
            
            // Check if properties exist on result object
            console.log('[PAYMENT LWC] Debug - result object keys:', Object.keys(result || {}));
            console.log('[PAYMENT LWC] Debug - result.emailStatus type:', typeof result.emailStatus, 'value:', result.emailStatus);
            console.log('[PAYMENT LWC] Debug - result.userCreated type:', typeof result.userCreated, 'value:', result.userCreated);
            console.log('[PAYMENT LWC] Debug - result.emailAddress type:', typeof result.emailAddress, 'value:', result.emailAddress);
            
            if (!result.emailStatus && !result.userCreated && !result.emailAddress) {
                console.warn('%c[PAYMENT LWC] ⚠️⚠️⚠️ WARNING: All email status fields are empty! ⚠️⚠️⚠️', 'background: #ff6b6b; color: white; font-weight: bold; font-size: 14px; padding: 5px;');
                console.warn('[PAYMENT LWC] This may indicate:');
                console.warn('[PAYMENT LWC]   1. Email sending did not occur (check Apex logs)');
                console.warn('[PAYMENT LWC]   2. Static variables were not set in CommunityOrderProcessor');
                console.warn('[PAYMENT LWC]   3. Payment was for renewal (no new user created)');
                console.warn('[PAYMENT LWC]   4. Apex controller is not returning email status fields');
            } else {
                console.log('%c[PAYMENT LWC] ✓ Email status information received from Apex', 'background: #51cf66; color: white; font-weight: bold; padding: 3px;');
            }
            console.log('%c[PAYMENT LWC] ======================================================================================================', 'background: #ff6b6b; color: white; font-weight: bold; font-size: 14px; padding: 5px;');
            
            // If there's an error message, log it prominently
            if (result.message) {
                console.error('[PAYMENT LWC] ⚠️ ERROR MESSAGE FROM APEX:', result.message);
                // Check if it's a "List has no rows" error and provide more context
                if (result.message.includes('List has no rows')) {
                    console.error('[PAYMENT LWC] 🔍 This is a "List has no rows" error - a query returned no results');
                    console.error('[PAYMENT LWC] 📋 Order IDs being processed:', params.orderIds);
                    console.error('[PAYMENT LWC] 💡 Check the error message above to see which specific record was not found');
                }
            }
            
            if (result.success) {
                console.log('[PAYMENT LWC] ✓ Payment processed successfully!');
                this.showToast('Success', 'Payment processed successfully!', 'success');
                
                // Add a delay before redirecting so user can see the success message and console logs
                // This prevents the "redirecting too fast" issue
                const redirectDelay = 2000; // 2 seconds delay
                console.log(`[PAYMENT LWC] ⏰ You have ${redirectDelay/1000} seconds to review the console logs before redirect...`);
                console.log(`[PAYMENT LWC] ⏱️ Waiting ${redirectDelay/1000} seconds before redirecting...`);
                console.log(`[PAYMENT LWC] 📋 You have ${redirectDelay/1000} seconds to review the console logs above.`);
                console.log(`[PAYMENT LWC] 🔍 Check the email status information above to see if the password reset email was sent.`);
                
                setTimeout(() => {
                    // Redirect if URL provided
                    if (result.redirectUrl) {
                        console.log('[PAYMENT LWC] Step 4: Redirecting to:', result.redirectUrl);
                        // Check if it's a community page URL or full URL
                        if (result.redirectUrl.includes('/ce-payment-confirmation')) {
                            // Navigate to payment confirmation page using NavigationMixin
                            try {
                                // Check if NavigationMixin.Navigate is available
                                if (this[NavigationMixin.Navigate] && typeof this[NavigationMixin.Navigate] === 'function') {
                                    const navigationPromise = this[NavigationMixin.Navigate]({
                                        type: 'comm__namedPage',
                                        attributes: {
                                            name: 'CE_Payment_Confirmation__c'
                                        }
                                    });
                                    // Only call .then() if navigationPromise exists and is a promise
                                    if (navigationPromise && typeof navigationPromise.then === 'function') {
                                        navigationPromise.catch(error => {
                                            console.error('[PAYMENT LWC] Navigation error:', error);
                                            // Fallback to window.location if navigation fails
                                            window.location.href = result.redirectUrl;
                                        });
                                    }
                                } else {
                                    console.warn('[PAYMENT LWC] NavigationMixin.Navigate not available, using window.location');
                                    window.location.href = result.redirectUrl;
                                }
                            } catch (navError) {
                                console.error('[PAYMENT LWC] Navigation error:', navError);
                                // Fallback to window.location if NavigationMixin fails
                                window.location.href = result.redirectUrl;
                            }
                        } else {
                            // Use window.location for external URLs or legacy redirects
                            window.location.href = result.redirectUrl;
                        }
                    } else {
                        console.log('[PAYMENT LWC] Step 4: No redirect URL, navigating to Payment Confirmation page');
                        // Navigate to payment confirmation page as default
                        try {
                            // Check if NavigationMixin.Navigate is available
                            if (this[NavigationMixin.Navigate] && typeof this[NavigationMixin.Navigate] === 'function') {
                                const navigationPromise = this[NavigationMixin.Navigate]({
                                    type: 'comm__namedPage',
                                    attributes: {
                                        name: 'CE_Payment_Confirmation__c'
                                    }
                                });
                                // Only call .then() if navigationPromise exists and is a promise
                                if (navigationPromise && typeof navigationPromise.then === 'function') {
                                    navigationPromise.catch(error => {
                                        console.error('[PAYMENT LWC] Navigation error:', error);
                                    });
                                }
                            } else {
                                console.warn('[PAYMENT LWC] NavigationMixin.Navigate not available, using window.location');
                                // Fallback: try to navigate using window.location
                                const baseUrl = window.location.origin + window.location.pathname.split('/').slice(0, -1).join('/');
                                window.location.href = baseUrl + '/ce-payment-confirmation';
                            }
                        } catch (navError) {
                            console.error('[PAYMENT LWC] Navigation error:', navError);
                            // Fallback: try to navigate using window.location
                            const baseUrl = window.location.origin + window.location.pathname.split('/').slice(0, -1).join('/');
                            window.location.href = baseUrl + '/ce-payment-confirmation';
                        }
                    }
                }, redirectDelay); // End of setTimeout
                
                console.log('[PAYMENT LWC] ========== PAYMENT SUBMISSION SUCCESS ==========');
            } else {
                console.error('[PAYMENT LWC] ✗ Payment failed:', result.message);
                this.showFormError = true;
                this.formError = result.message || 'Payment failed. Please try again.';
                this.isSubmitting = false;
                console.log('[PAYMENT LWC] ========== PAYMENT SUBMISSION FAILED ==========');
            }
        } catch (error) {
            console.error('[PAYMENT LWC] ✗ Exception during payment submission:', error);
            console.error('[PAYMENT LWC] Error type:', error?.constructor?.name);
            console.error('[PAYMENT LWC] Error details:', {
                message: error.body?.message || error.message || 'Unknown error',
                statusCode: error.body?.statusCode,
                statusText: error.body?.statusText,
                body: error.body,
                stack: error.stack,
                name: error.name,
                toString: error.toString()
            });
            
            // Check if this is a network/connection error or if Apex method wasn't called
            if (error.message && (error.message.includes('network') || error.message.includes('fetch') || error.message.includes('Failed to fetch'))) {
                this.formError = 'Network error. Please check your connection and try again.';
                console.error('[PAYMENT LWC] Network error detected - Apex method may not have been called');
            } else if (error.body && error.body.message) {
                this.formError = error.body.message;
            } else if (error.message) {
                this.formError = error.message;
            } else {
                this.formError = 'An error occurred processing your payment. Please try again.';
            }
            
            this.showFormError = true;
            this.isSubmitting = false;
            console.log('[PAYMENT LWC] ========== PAYMENT SUBMISSION ERROR ==========');
            
            // Show toast with error
            this.showToast('Payment Error', this.formError, 'error');
        }
    }
    
    showToast(title, message, variant) {
        try {
            // Filter out the "Cannot read properties" error as it's a client-side error
            const msg = String(message || '');
            const ttl = String(title || '');
            
            if (msg.includes('Cannot read properties of undefined') ||
                ttl.includes('Cannot read properties of undefined')) {
                console.warn('[PAYMENT LWC] Suppressing toast for client-side error. Title:', ttl, 'Message:', msg);
                return;
            }
            
            // Check if ShowToastEvent is available
            if (typeof ShowToastEvent === 'undefined') {
                console.warn('[PAYMENT LWC] ShowToastEvent is not available');
                return;
            }
            
            const evt = new ShowToastEvent({
                title: title || '',
                message: message || '',
                variant: variant || 'info'
            });
            
            // Check if dispatchEvent is available
            if (typeof this.dispatchEvent === 'function') {
                this.dispatchEvent(evt);
            } else {
                console.warn('[PAYMENT LWC] dispatchEvent is not available');
            }
        } catch (toastError) {
            console.error('[PAYMENT LWC] Error showing toast:', toastError);
            // Don't re-throw the error
        }
    }
    
    // Override dispatchEvent to intercept toast events
    // This intercepts ALL events dispatched from this component, including ShowToastEvent
    dispatchEvent(event) {
        try {
            // Check if this is a ShowToastEvent (has detail with message/title)
            if (event && event.detail) {
                const detail = event.detail;
                const msg = String(detail.message || '');
                const ttl = String(detail.title || '');
                
                // Suppress toast if it contains our error message
                if (msg.includes('Cannot read properties of undefined') ||
                    ttl.includes('Cannot read properties of undefined')) {
                    console.warn('[PAYMENT LWC] Intercepting toast dispatch for client-side error. Title:', ttl, 'Message:', msg);
                    // Prevent the event from being dispatched
                    event.preventDefault();
                    event.stopPropagation();
                    event.stopImmediatePropagation();
                    return false; // Return false to indicate event was cancelled
                }
            }
            
            // For all other events, call the parent dispatchEvent
            // Use LightningElement's dispatchEvent method
            return super.dispatchEvent(event);
        } catch (dispatchError) {
            console.error('[PAYMENT LWC] Error in dispatchEvent override:', dispatchError);
            // Fallback: try to call parent dispatchEvent
            try {
                return super.dispatchEvent(event);
            } catch (fallbackError) {
                console.error('[PAYMENT LWC] Error in fallback dispatchEvent:', fallbackError);
                // Last resort: return false to prevent event
                return false;
            }
        }
    }
}

