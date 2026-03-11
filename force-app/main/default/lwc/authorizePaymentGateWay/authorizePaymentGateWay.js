import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import submitPaymentLWC from '@salesforce/apex/CommunityPaymentControllerLWC.submitPaymentLWC';

export default class AuthorizePaymentGateWay extends LightningElement {
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
    @track orderIds = ['801cY00000HWCgzQAH']; // fallback for testing
    _debug = false;

    @wire(CurrentPageReference)
    getPageRef(pageRef) {
        const state = pageRef?.state || {};
        const idsParam =
            state.ids ??
            state.c__ids ??
            new URLSearchParams(window.location.search).get('ids');

        if (idsParam) {
            this.orderIds = idsParam.split(',').map(s => s.trim()).filter(Boolean);
        }
        // eslint-disable-next-line no-console
        console.log('OrderIds captured:', this.orderIds);
    }

    connectedCallback() {
        const params = new URLSearchParams(window.location.search);
        this._debug = params.get('debug') === '1';
        if (this._debug) this.prefillTestValues();
    }

    prefillTestValues() {
        this.cardNumber    = '4111111111111111';
        this.expMonth      = '12';
        this.expYear       = String(new Date().getFullYear() + 1); // 4-digit
        this.cvv           = '123';
        this.firstName     = 'Test';
        this.lastName      = 'Buyer';
        this.billingAddress = '1 Main St';
        this.billingCity   = 'San Francisco';
        this.billingState  = 'CA';
        this.billingZip    = '94105';
    }

    get monthOptions() {
        return Array.from({ length: 12 }, (_, i) => {
            const v = (i + 1).toString().padStart(2, '0');
            return { label: v, value: v };
        });
    }
    get yearOptions() {
        const y = new Date().getFullYear();
        return Array.from({ length: 10 }, (_, i) => {
            const v = String(y + i);
            return { label: v, value: v };
        });
    }
    get stateOptions() {
        return [
            { label: 'Alabama', value: 'AL' }, { label: 'Alaska', value: 'AK' }, { label: 'Arizona', value: 'AZ' },
            { label: 'California', value: 'CA' }, { label: 'New York', value: 'NY' }, { label: 'Texas', value: 'TX' }
            // ...add full list as needed
        ];
    }

    handleInputChange(event) {
        const { name } = event.target;
        const value =
            event.detail && event.detail.value !== undefined
                ? event.detail.value
                : event.target.value;
        if (name && Object.prototype.hasOwnProperty.call(this, name)) this[name] = value;
    }

    // Extract a human-readable message from any Apex return shape
    pickMessage(obj) {
        if (!obj) return '';
        const keys = ['message','Message','responseText','ResponseText','error','errorMessage','detail','reason'];
        for (const k of keys) if (typeof obj[k] === 'string' && obj[k]) return obj[k];
        if (Array.isArray(obj.errors) && obj.errors.length) return obj.errors[0].message || JSON.stringify(obj.errors[0]);
        try { return JSON.stringify(obj); } catch { return ''; }
    }

    async handleSubmit() {
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

        // eslint-disable-next-line no-console
        console.log('Submitting via Apex (redacted):', {
            month: params.month, year: params.year,
            name: `${params.firstName} ${params.lastName}`,
            city: params.city, state: params.state, orderIds: params.orderIds
        });

        try {
            const result = await submitPaymentLWC(params);

            // Deep log to see exact shape coming back from Apex
            // eslint-disable-next-line no-console
            console.log('Apex result:', JSON.parse(JSON.stringify(result)));

            const success = result && (result.success === true || result.isSuccess === true);
            const message = this.pickMessage(result);

            if (success) {
                const url = result.redirectUrl || result.pageRef || result.url;
                if (url) {
                    window.location.href = url;
                } else {
                    // eslint-disable-next-line no-alert
                    alert(message || 'Payment successful!');
                }
            } else {
                // eslint-disable-next-line no-alert
                alert(`Payment failed: ${message || 'Unknown error (no message returned from Apex)'}`);
            }
        } catch (e) {
            const msg = (e && e.body && e.body.message) || e.message || 'Unexpected error';
            // eslint-disable-next-line no-console
            console.error('submitPaymentLWC threw:', e);
            // eslint-disable-next-line no-alert
            alert(`Error: ${msg}`);
        }
    }
}