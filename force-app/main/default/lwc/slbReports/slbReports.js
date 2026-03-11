import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getThreeLicenseReport from '@salesforce/apex/CeSlbReportsLwcController.getThreeLicenseReport';
import getDisciplineReport from '@salesforce/apex/CeSlbReportsLwcController.getDisciplineReport';
import getAdjustmentsReport from '@salesforce/apex/CeSlbReportsLwcController.getAdjustmentsReport';

const THERAPIST_REPORT_PAGE = 'SLB_Therapist_Report__c';

function formatDate(d) {
    if (!d) return '';
    const date = typeof d === 'string' ? new Date(d) : d;
    if (isNaN(date.getTime())) return d;
    const m = date.getMonth() + 1;
    const day = date.getDate();
    const y = date.getFullYear();
    return `${m}/${day}/${y}`;
}

export default class SlbReports extends NavigationMixin(LightningElement) {
    @track isLoading = false;
    @track error;

    @track selectedReport = '';

    // Three Licenses: flat rows from Apex, grouped in getter
    @track threeLicenseRows = [];
    // Board Actions: list of { therapistId, therapistName, licenses[], disciplinaryActions[] }
    @track disciplineGroups = [];
    // Exam Alerts: list of { therapistId, therapistName, licenses[] }
    @track examAlertGroups = [];

    get reportOptions() {
        return [
            { label: 'Therapists with 3 or More Licenses', value: 'threeLicenses' },
            { label: 'Therapists with Board Actions', value: 'boardActions' },
            { label: 'Therapists with Exam Alerts', value: 'examAlerts' }
        ];
    }

    // Group three-license flat rows by therapistId for template
    get threeLicenseTherapistGroups() {
        if (!this.threeLicenseRows || this.threeLicenseRows.length === 0) return [];
        const byId = new Map();
        for (const row of this.threeLicenseRows) {
            const id = row.therapistId || 'unknown';
            if (!byId.has(id)) {
                byId.set(id, {
                    therapistId: row.therapistId,
                    therapistName: row.therapistName || '',
                    licenses: []
                });
            }
            byId.get(id).licenses.push({
                source: row.source,
                licenseNumber: row.licenseNumber,
                licenseType: row.licenseType,
                status: row.status,
                issueDate: row.issueDate,
                expirationDate: row.expirationDate,
                therapistNameOnLicense: row.therapistNameOnLicense,
                issueDateFormatted: formatDate(row.issueDate),
                expirationDateFormatted: formatDate(row.expirationDate)
            });
        }
        return Array.from(byId.values());
    }

    // Discipline groups from Apex - format dates for display
    get disciplineGroupsFormatted() {
        return (this.disciplineGroups || []).map(grp => ({
            ...grp,
            licenses: (grp.licenses || []).map(l => ({
                ...l,
                issueDateFormatted: formatDate(l.issueDate),
                expirationDateFormatted: formatDate(l.expirationDate)
            })),
            disciplinaryActions: (grp.disciplinaryActions || []).map(a => ({
                ...a,
                dateOfLastActionFormatted: formatDate(a.dateOfLastAction)
            }))
        }));
    }

    // Exam alert groups from Apex (no date columns in table)
    get examAlertGroupsFormatted() {
        return this.examAlertGroups || [];
    }

    get showNoReportSelected() {
        return !this.selectedReport;
    }

    get isThreeLicenses() {
        return this.selectedReport === 'threeLicenses';
    }

    get isBoardActions() {
        return this.selectedReport === 'boardActions';
    }

    get isExamAlerts() {
        return this.selectedReport === 'examAlerts';
    }

    handleReportChange(event) {
        this.selectedReport = event.detail.value;
        this.error = undefined;

        if (this.isThreeLicenses) {
            this.loadThreeLicenseReport();
        } else if (this.isBoardActions) {
            this.loadDisciplineReport();
        } else if (this.isExamAlerts) {
            this.loadAdjustmentsReport();
        }
    }

    async loadThreeLicenseReport() {
        this.isLoading = true;
        try {
            const data = await getThreeLicenseReport();
            this.threeLicenseRows = (data || []).map((row, index) => ({
                ...row,
                rowId: `${row.therapistId || 'row'}_${index}`
            }));
        } catch (e) {
            console.error('Error loading threeLicenseReport', e);
            this.error = 'Error loading "Therapists with 3 or More Licenses" report: ' + (e.body && e.body.message ? e.body.message : e.message);
        } finally {
            this.isLoading = false;
        }
    }

    async loadDisciplineReport() {
        this.isLoading = true;
        try {
            const data = await getDisciplineReport();
            this.disciplineGroups = data || [];
        } catch (e) {
            console.error('Error loading disciplineReport', e);
            this.error = 'Error loading "Therapists with Board Actions" report: ' + (e.body && e.body.message ? e.body.message : e.message);
        } finally {
            this.isLoading = false;
        }
    }

    async loadAdjustmentsReport() {
        this.isLoading = true;
        try {
            const data = await getAdjustmentsReport();
            this.examAlertGroups = data || [];
        } catch (e) {
            console.error('Error loading adjustmentsReport', e);
            this.error = 'Error loading "Therapists with Exam Alerts" report: ' + (e.body && e.body.message ? e.body.message : e.message);
        } finally {
            this.isLoading = false;
        }
    }

    navigateToTherapistReport(event) {
        if (event && event.preventDefault) event.preventDefault();
        const therapistId = event.target.dataset.therapistId || (event.currentTarget && event.currentTarget.dataset.therapistId);
        if (!therapistId) return;
        try {
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: { name: THERAPIST_REPORT_PAGE },
                state: { id: therapistId }
            });
        } catch (err) {
            console.error('Navigation failed, using fallback:', err);
            this.navigateToTherapistReportFallback(therapistId);
        }
    }

    navigateToTherapistReportFallback(therapistId) {
        if (typeof window === 'undefined' || !therapistId) return;
        try {
            const currentUrl = new URL(window.location.href);
            const pathParts = currentUrl.pathname.split('/s/');
            const basePath = pathParts[0] + '/s/';
            const reportUrl = `${currentUrl.origin}${basePath}slb-therapist-report?id=${therapistId}`;
            window.location.href = reportUrl;
        } catch (e) {
            console.error('Fallback navigation failed:', e);
        }
    }
}
