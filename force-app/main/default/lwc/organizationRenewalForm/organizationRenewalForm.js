import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { loadStyle } from 'lightning/platformResourceLoader';
import portalImages from '@salesforce/resourceUrl/Portal_Images';
import getAccountDetails from '@salesforce/apex/OrgRegistryController.getAccountDetails';
import getCurrentUserAccountDetails from '@salesforce/apex/OrgRegistryController.getCurrentUserAccountDetails';
import updateAccountAndCreateOrder from '@salesforce/apex/OrgRegistryController.updateAccountAndCreateOrder';
import getStatePicklist from '@salesforce/apex/OrgRegistryController.getStatePicklist';
import getRenewalContent from '@salesforce/apex/OrgRegistryController.getRenewalContent';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { FlowNavigationNextEvent } from 'lightning/flowSupport';

export default class OrganizationRenewalForm extends NavigationMixin(LightningElement) {
    @api accountId;   
    @api orderId; // exposed to Flow so next screen (payment) can receive the created Order Id
    @track accountRecord = {};
    @track stateOptions = [];
    @track renewalContent = '';
    
    // Static resource images
    portalImages = portalImages;
    headerImage0 = portalImages + '/FSMTB_header0.png';

    connectedCallback() {
        if (this.accountId) {
            this.loadAccount();
        } else {
            this.loadCurrentUserAccount();
        }
        this.loadStatePicklist();
        this.loadRenewalContent();
        // Load global portal styles so layout/required bars match VF page
        loadStyle(this, '/resource/FSMTBAssets/FSMTBAssets/css/global.css').catch(error => {
            // eslint-disable-next-line no-console
            console.error('Error loading portal styles', error);
        });
    }

    async loadAccount() {
        try {
            const acc = await getAccountDetails({ accountId: this.accountId });
            if (acc) {
                // Use deep copy to ensure reactivity and preserve Id
                this.accountRecord = JSON.parse(JSON.stringify({
                    Id: acc.Id,
                    Name: acc.Name,
                    Email__c: acc.Email__c || '',
                    BillingStreet: acc.BillingStreet || '',
                    BillingCity: acc.BillingCity || '',
                    BillingStateCode: acc.BillingStateCode || '',
                    BillingPostalCode: acc.BillingPostalCode || '',
                    Phone: acc.Phone || '',
                    Fax: acc.Fax || '',
                    Website: acc.Website || ''
                }));
                // Ensure we keep the Id locally for downstream events
                if (!this.accountId) {
                    this.accountId = acc.Id;
                }
            }
        } catch (error) {
            console.error('Error loading account details:', error);
            this.showToast('Error', 'Unable to load account details', 'error');
        }
    }

    async loadCurrentUserAccount() {
        try {
            const acc = await getCurrentUserAccountDetails();
            if (acc) {
                this.accountId = acc.Id;
                // Use deep copy to ensure reactivity and preserve Id
                this.accountRecord = JSON.parse(JSON.stringify({
                    Id: acc.Id,
                    Name: acc.Name,
                    Email__c: acc.Email__c || '',
                    BillingStreet: acc.BillingStreet || '',
                    BillingCity: acc.BillingCity || '',
                    BillingStateCode: acc.BillingStateCode || '',
                    BillingPostalCode: acc.BillingPostalCode || '',
                    Phone: acc.Phone || '',
                    Fax: acc.Fax || '',
                    Website: acc.Website || ''
                }));
            } else {
                console.warn('No account found for current user');
            }
        } catch (error) {
            // Non-blocking; user can still fill in details manually
            console.error('Error loading current user account details:', error);
        }
    }

    async loadStatePicklist() {
        try {
            const options = await getStatePicklist();
            this.stateOptions = options || [];
        } catch (error) {
            // Non-blocking error; just log
            // eslint-disable-next-line no-console
            console.error('Error loading state picklist', error);
        }
    }

    async loadRenewalContent() {
        try {
            const content = await getRenewalContent();
            this.renewalContent = content || '';
        } catch (error) {
            // Non-blocking error; just log
            // eslint-disable-next-line no-console
            console.error('Error loading renewal content', error);
        }
    }

    handleInputChange(event) {
        const field = event.target.dataset.field;
        const value =
            event.detail && event.detail.value !== undefined
                ? event.detail.value
                : event.target.value;
        this.accountRecord = {
            ...this.accountRecord,
            [field]: value
        };
    }

    async handleNext() {
        // Client-side validation similar to VF required checks
        let allValid = true;
        const inputs = this.template.querySelectorAll('lightning-input, lightning-textarea');
        inputs.forEach(input => {
            if (typeof input.reportValidity === 'function') {
                allValid = input.reportValidity() && allValid;
            }
        });

        if (!allValid) {
            this.showToast('Error', 'Please fill in all required fields.', 'error');
            return;
        }

        try {
            // Ensure accountRecord has the Id for the update
            if (!this.accountRecord.Id && this.accountId) {
                this.accountRecord.Id = this.accountId;
            }
            
            // Call Apex to update Account and create Order
            const result = await updateAccountAndCreateOrder({ acc: this.accountRecord });
            if (result.success) {
                // Use deep copy to ensure reactivity
                this.accountRecord = JSON.parse(JSON.stringify(result.updatedAccount));
                this.orderId = result.orderId;
                this.showToast('Success', 'Account updated and Order created successfully', 'success');

                // Fire custom event so parent components (if any) can react
                // Includes the created Order Id and Account Id for payment processing
                this.dispatchEvent(
                    new CustomEvent('renewalsuccess', {
                        detail: {
                            orderId: this.orderId,
                            accountId: this.accountRecord.Id || this.accountId
                        },
                        bubbles: true,
                        composed: true
                    })
                );

                // Navigate directly to the shared Payment page used elsewhere in the portal
                // This mirrors the navigation pattern from ceTermsAndConditions and ceNewCourse
                this.navigateToPayment([this.orderId]);

                // If this component is used inside a Flow, also move to the next screen
                this.dispatchEvent(new FlowNavigationNextEvent());
            } else {
                this.showToast('Error', result.message, 'error');
            }
        } catch (error) {
            this.showToast('Error', error.body ? error.body.message : 'Error  updating account or creating order', 'error');
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
            // NavigationMixin.Navigate does not reliably return a promise in all runtimes,
            // so we simply call it inside a try/catch for safety.
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            this[NavigationMixin.Navigate](pageRef);
        } catch (error) {
            // eslint-disable-next-line no-console
            console.error('Error navigating to payment page', error);
            this.showToast('Error', 'Unable to navigate to the payment page. Please try again.', 'error');
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}