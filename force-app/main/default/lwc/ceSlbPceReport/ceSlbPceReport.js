import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import getPceReportData from '@salesforce/apex/CeSlbPceReportLwcController.getPceReportData';

export default class CeSlbPceReport extends LightningElement {
    @track data = null;
    @track error = null;
    @track isLoading = true;

    recordId = null;
    contactId = null;

    connectedCallback() {
        if (!this.recordId || !this.contactId) {
            this.checkUrlForIds();
        }
    }

    @wire(CurrentPageReference)
    getState(currentPageReference) {
        if (currentPageReference && currentPageReference.state) {
            this.recordId = currentPageReference.state.recordId || currentPageReference.state.c__recordId;
            this.contactId = currentPageReference.state.id || currentPageReference.state.c__id;
            if (!this.contactId) this.contactId = currentPageReference.state.recordId;
            if (this.recordId && this.contactId && this.contactId !== this.recordId) {
                this.loadData();
            } else if (this.recordId && this.contactId) {
                this.loadData();
            } else {
                this.checkUrlForIds();
            }
        } else {
            this.checkUrlForIds();
        }
    }

    checkUrlForIds() {
        if (typeof window === 'undefined') return;
        const params = new URLSearchParams(window.location.search);
        const recId = params.get('recordId');
        const id = params.get('id');
        if (recId && id) {
            this.recordId = recId;
            this.contactId = id;
            this.loadData();
        } else if (!this.recordId && !this.contactId) {
            this.isLoading = false;
            this.error = 'Missing recordId or id in the URL. Use ?recordId=<PCE Id>&id=<Contact Id>';
        }
    }

    async loadData() {
        if (!this.recordId || !this.contactId) return;
        this.isLoading = true;
        this.error = null;
        try {
            const result = await getPceReportData({
                recordId: this.recordId,
                contactId: this.contactId
            });
            this.data = this.formatData(result);
        } catch (e) {
            this.error = e.body?.message || e.message || 'Error loading PCE report.';
            this.data = null;
        } finally {
            this.isLoading = false;
        }
    }

    formatData(result) {
        if (!result) return null;
        const out = { ...result };
        if (out.stateLicenses && out.stateLicenses.length) {
            out.stateLicenses = out.stateLicenses.map(l => ({
                ...l,
                issueDateFormatted: this.formatDate(l.issueDate),
                expirationDateFormatted: this.formatDate(l.expirationDate)
            }));
        }
        if (out.adjustments && out.adjustments.length) {
            out.adjustments = out.adjustments.map((a, i) => ({
                ...a,
                uniqueKey: `adj-${i}-${a.action || ''}-${a.startDate || ''}`,
                startDateFormatted: this.formatDate(a.startDate),
                endDateFormatted: this.formatDate(a.endDate)
            }));
        }
        if (out.sessionInfo) {
            out.sessionInfo = {
                ...out.sessionInfo,
                completedOnFormatted: this.formatDate(out.sessionInfo.completedOn)
            };
        }
        return out;
    }

    formatDate(d) {
        if (!d) return '';
        const date = typeof d === 'string' ? new Date(d) : d;
        if (isNaN(date.getTime())) return String(d);
        const m = date.getMonth() + 1;
        const day = date.getDate();
        const y = date.getFullYear();
        return `${m}/${day}/${y}`;
    }

    get hasStateLicenses() {
        return this.data && this.data.stateLicenses && this.data.stateLicenses.length > 0;
    }

    get hasAdjustments() {
        return this.data && this.data.adjustments && this.data.adjustments.length > 0;
    }

    get hasCourseInfo() {
        return this.data && this.data.courseInfo;
    }

    get hasSessionInfo() {
        return this.data && this.data.sessionInfo;
    }
}
