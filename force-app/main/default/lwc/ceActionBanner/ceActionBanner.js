import { LightningElement, api, track } from 'lwc';
import getAccountStatus from '@salesforce/apex/CEBannerController.getAccountStatus';
import getAccountBannerStatuses from '@salesforce/apex/CEBannerController.getAccountBannerStatuses';

export default class CeActionBanner extends LightningElement {
    _recordId;
    @api statusFieldApiName = 'Current_Active_Action_Status__c';

    @track statusValue;
    @track registrationStatus;
    @track actionStatus;
    @track error;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        if (this._recordId !== value) {
            this._recordId = value;
            if (value) {
                this.loadStatus();
            } else {
                this.statusValue = null;
            }
        }
    }

    connectedCallback() {
        if (this.recordId) {
            this.loadStatus();
        }
    }

    @api refresh() {
        this.loadStatus();
    }

    loadStatus() {
        if (!this.recordId) {
            return;
        }
        
        // Load both Registration Status and Action Status
        getAccountBannerStatuses({
            recordId: this.recordId
        })
            .then(result => {
                console.log('Banner Status Result:', result);
                this.registrationStatus = result.registrationStatus;
                this.actionStatus = result.actionStatus;
                // Keep statusValue for backward compatibility - combine both statuses
                this.statusValue = this.buildCombinedStatus();
                this.error = null;
            })
            .catch(err => {
                console.error('Banner Error:', err);
                this.error = err;
                this.statusValue = null;
                this.registrationStatus = null;
                this.actionStatus = null;
            });
    }
    
    buildCombinedStatus() {
        // Build combined status string for backward compatibility
        let combined = [];
        if (this.registrationStatus === 'Provisional') {
            combined.push('Provisional');
        }
        if (this.actionStatus) {
            combined.push(this.actionStatus);
        }
        return combined.length > 0 ? combined.join(' & ') : null;
    }

    get showBanner() {
        // Show banner if we have Provisional Registration Status OR Action Status
        return !!this.bannerType && (!!this.registrationStatus || !!this.actionStatus);
    }

    _has(value) {
        return this.statusValue?.toLowerCase().includes(value.toLowerCase());
    }

    get isProvisionalAndUnderReview() {
        // Check both Registration Status and Action Status
        return (
            this.registrationStatus === 'Provisional' &&
            this.actionStatus === 'Under Review'
        );
    }

    get isProvisionalAndInternalInvestigation() {
        // Check both Registration Status and Action Status
        return (
            this.registrationStatus === 'Provisional' &&
            this.actionStatus === 'Internal Investigation'
        );
    }

    get isProvisional() {
        // Check Registration Status for Provisional
        return (
            this.registrationStatus === 'Provisional' &&
            !this.isProvisionalAndUnderReview &&
            !this.isProvisionalAndInternalInvestigation
        );
    }

    get isUnderReview() {
        // Check Action Status for Under Review
        return (
            this.actionStatus === 'Under Review' &&
            !this.isProvisionalAndUnderReview &&
            this.registrationStatus !== 'Provisional'
        );
    }
    
    get hasActionStatus() {
        // Check if there's any action status (Under Review, Restricted, Internal Investigation, Revoked)
        return (
            this.actionStatus === 'Under Review' ||
            this.actionStatus === 'Restricted' ||
            this.actionStatus === 'Internal Investigation' ||
            this.actionStatus === 'Revoked'
        );
    }

    get bannerType() {
        // Priority order: combined statuses first, then individual statuses
        if (this.isProvisionalAndUnderReview) return 'provisional-under';
        if (this.isProvisionalAndInternalInvestigation) return 'provisional-internal';
        if (this.isProvisional && this.hasActionStatus) return 'provisional-under'; // Generic combined status
        if (this.hasActionStatus) return 'under-review'; // Any action status shows orange
        if (this.isProvisional) return 'provisional'; // Provisional registration shows green
        return null;
    }

    get bannerClass() {
        const t = this.bannerType;
        if (t === 'under-review' || t === 'provisional-under') return 'banner banner--orange';
        if (t === 'provisional' || t === 'provisional-internal') return 'banner banner--green';
        return 'banner';
    }

    get bannerMessage() {
        switch (this.bannerType) {
            case 'provisional':
                return 'Your account has not yet received 50 favorable reviews from students.';
            case 'under-review':
                return 'Your account is in the process of taking corrective action in order to comply with FSMTB CE Standards.';
            case 'provisional-under':
                return 'Your account has not yet received 50 favorable reviews from students, and your account also is in the process of taking corrective action in order to comply with FSMTB CE Standards.';
            case 'provisional-internal':
                return 'Your account has not yet received 50 favorable reviews from students.';
            default:
                return '';
        }
    }

    get showFlagIcon() {
        return (
            this.bannerType === 'provisional' ||
            this.bannerType === 'provisional-under' ||
            this.bannerType === 'provisional-internal'
        );
    }

    get showEyeIcon() {
        return (
            this.bannerType === 'under-review' ||
            this.bannerType === 'provisional-under'
        );
    }
}