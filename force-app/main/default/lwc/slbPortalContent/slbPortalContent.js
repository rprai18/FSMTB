import { LightningElement, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';

const VIEW_THERAPIST_SEARCH = 'therapistsearch';
const VIEW_REPORTS = 'reports';
const VIEW_THERAPIST_REPORT = 'therapistreport';

const PAGE_THERAPIST_REPORT = 'slb_therapist_report__c';
const PAGE_REPORTS = 'reports__c';

/**
 * Content router for SLB Portal. Renders the correct view based on the current URL
 * and/or Experience Cloud page name so the correct component shows (e.g. Therapist Report
 * instead of Reports when on the therapist report page).
 */
export default class SlbPortalContent extends LightningElement {
    currentView = VIEW_THERAPIST_SEARCH;
    therapistReportId = null;
    initialized = false;
    _pageRef = null;

    @wire(CurrentPageReference)
    setViewFromPageRef(pageRef) {
        this._pageRef = pageRef;
        this.computeView();
    }

    connectedCallback() {
        this.computeView();
        this.initialized = true;
        this.boundHandlePopState = this.handlePopState.bind(this);
        if (typeof window !== 'undefined') {
            window.addEventListener('popstate', this.boundHandlePopState);
        }
    }

    disconnectedCallback() {
        if (typeof window !== 'undefined' && this.boundHandlePopState) {
            window.removeEventListener('popstate', this.boundHandlePopState);
        }
    }

    handlePopState() {
        this.computeView();
    }

    getPageName() {
        if (!this._pageRef || !this._pageRef.attributes || !this._pageRef.attributes.name) return null;
        return (this._pageRef.attributes.name || '').toLowerCase();
    }

    getStateId() {
        if (!this._pageRef || !this._pageRef.state) return null;
        const s = this._pageRef.state;
        return s.id || s.c__id || s.recordId || null;
    }

    computeView() {
        if (typeof window === 'undefined') return;

        const pathname = (window.location.pathname || '').toLowerCase();
        const href = (window.location.href || '').toLowerCase();
        const pageName = this.getPageName();
        const stateId = this.getStateId();

        // Therapist Report: by page name (SLB_Therapist_Report__c) or URL containing therapist-report/therapist_report
        const isTherapistReportPage = pageName === PAGE_THERAPIST_REPORT ||
            pathname.includes('therapist-report') || href.includes('therapist-report') ||
            pathname.includes('therapist_report') || href.includes('therapist_report');

        if (isTherapistReportPage) {
            this.therapistReportId = stateId || this.getTherapistIdFromUrlOrState();
            this.currentView = VIEW_THERAPIST_REPORT;
            return;
        }

        // Reports: only when page is Reports__c or URL is explicitly /reports (and not therapist report)
        const isReportsPage = pageName === PAGE_REPORTS ||
            ((pathname.includes('/reports') || href.includes('/reports')) &&
             !pathname.includes('therapist') && !href.includes('therapist'));

        if (isReportsPage) {
            this.therapistReportId = null;
            this.currentView = VIEW_REPORTS;
            return;
        }

        // Default: Therapist Search (Home, etc.)
        this.therapistReportId = null;
        this.currentView = VIEW_THERAPIST_SEARCH;
    }

    getTherapistIdFromUrlOrState() {
        const urlParams = new URLSearchParams(window.location.search || '');
        let id = urlParams.get('id') || urlParams.get('recordId') || urlParams.get('c__id');
        if (id) return id;
        if (window.location.hash) {
            const hashParams = new URLSearchParams(window.location.hash.substring(1));
            id = hashParams.get('id') || hashParams.get('recordId');
            if (id) return id;
        }
        const pathParts = (window.location.pathname || '').split('/');
        const lastPart = pathParts[pathParts.length - 1];
        if (lastPart && (lastPart.length === 15 || lastPart.length === 18) && /^[a-zA-Z0-9]+$/.test(lastPart)) {
            return lastPart;
        }
        return null;
    }

    get showTherapistSearch() {
        return this.currentView === VIEW_THERAPIST_SEARCH;
    }

    get showReports() {
        return this.currentView === VIEW_REPORTS;
    }

    get showTherapistReport() {
        return this.currentView === VIEW_THERAPIST_REPORT;
    }
}
