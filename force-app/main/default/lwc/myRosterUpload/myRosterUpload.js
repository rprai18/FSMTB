import { LightningElement, track, wire } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import { CurrentPageReference } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import portalImages from '@salesforce/resourceUrl/Portal_Images';
import fsmtbPortalFiles from '@salesforce/resourceUrl/FSMTBPortalFiles';
import getRosters from '@salesforce/apex/MyRosterUploadHandler.getRosters';
import getCourses from '@salesforce/apex/MyRosterUploadHandler.getCourses';
import getSessions from '@salesforce/apex/MyRosterUploadHandler.getSessions';
import getContent from '@salesforce/apex/MyRosterUploadHandler.getContent';
import startUpload from '@salesforce/apex/MyRosterUploadHandler.startUpload';
import uploadRosterFile from '@salesforce/apex/MyRosterUploadHandler.uploadRosterFile';
import validateRosterData from '@salesforce/apex/MyRosterUploadHandler.validateRosterData';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const STATE_OPTIONS = [
    { label: 'Alabama', value: 'AL' }, { label: 'Alaska', value: 'AK' }, { label: 'Arizona', value: 'AZ' },
    { label: 'Arkansas', value: 'AR' }, { label: 'California', value: 'CA' }, { label: 'Colorado', value: 'CO' },
    { label: 'Connecticut', value: 'CT' }, { label: 'Delaware', value: 'DE' }, { label: 'District of Columbia', value: 'DC' },
    { label: 'Florida', value: 'FL' }, { label: 'Georgia', value: 'GA' }, { label: 'Hawaii', value: 'HI' },
    { label: 'Idaho', value: 'ID' }, { label: 'Illinois', value: 'IL' }, { label: 'Indiana', value: 'IN' },
    { label: 'Iowa', value: 'IA' }, { label: 'Kansas', value: 'KS' }, { label: 'Kentucky', value: 'KY' },
    { label: 'Louisiana', value: 'LA' }, { label: 'Maine', value: 'ME' }, { label: 'Maryland', value: 'MD' },
    { label: 'Massachusetts', value: 'MA' }, { label: 'Michigan', value: 'MI' }, { label: 'Minnesota', value: 'MN' },
    { label: 'Mississippi', value: 'MS' }, { label: 'Missouri', value: 'MO' }, { label: 'Montana', value: 'MT' },
    { label: 'Nebraska', value: 'NE' }, { label: 'Nevada', value: 'NV' }, { label: 'New Hampshire', value: 'NH' },
    { label: 'New Jersey', value: 'NJ' }, { label: 'New Mexico', value: 'NM' }, { label: 'New York', value: 'NY' },
    { label: 'North Carolina', value: 'NC' }, { label: 'North Dakota', value: 'ND' }, { label: 'Ohio', value: 'OH' },
    { label: 'Oklahoma', value: 'OK' }, { label: 'Oregon', value: 'OR' }, { label: 'Pennsylvania', value: 'PA' },
    { label: 'Rhode Island', value: 'RI' }, { label: 'South Carolina', value: 'SC' }, { label: 'South Dakota', value: 'SD' },
    { label: 'Tennessee', value: 'TN' }, { label: 'Texas', value: 'TX' }, { label: 'Utah', value: 'UT' },
    { label: 'Vermont', value: 'VT' }, { label: 'Virginia', value: 'VA' }, { label: 'Washington', value: 'WA' },
    { label: 'West Virginia', value: 'WV' }, { label: 'Wisconsin', value: 'WI' }, { label: 'Wyoming', value: 'WY' },
    { label: 'American Samoa', value: 'AS' }, { label: 'Guam', value: 'GU' }, { label: 'Northern Mariana Islands', value: 'MP' },
    { label: 'Puerto Rico', value: 'PR' }, { label: 'U.S. Virgin Islands', value: 'VI' }
];

export default class MyRosterUpload extends LightningElement {
    @track rosters = [];
    @track content = {};
    bodyScrollLocked = false;
    pendingFocusRowId = null;
    
    // Store wired result for refreshApex
    wiredRostersResult;

    // Static resource images
    portalImages = portalImages;
    headerImage0 = portalImages + '/FSMTB_header0.png';
    
    // Static resource files
    fsmtbPortalFiles = fsmtbPortalFiles;
    fileExplanationUrl = `${fsmtbPortalFiles}/UploadingRosterstoCERegistry.pdf`;
    templateDownloadUrl = `${fsmtbPortalFiles}/Roster.csv`;

    // state vars
    showSelection = false;
    showFileUpload = false;
    showVerification = false;
    showSuccess = false;
    showSuccessTable = false; // Show table with uploaded roster data
    showError = false;
    showSessionPicklist = false;
    courseName = '';
    sessionName = '';
    errorMessage = '';
    validationErrors = ''; // Inline validation error messages
    hasIncompleteRows = false; // Flag for showing summary message
    manualValidationTriggered = false; // Show inline errors only after submit attempt
    
    // Store uploaded roster entries for display
    @track uploadedRosterEntries = [];
    
    // Verification data
    @track verifiedEntries = [];
    validEntriesForUpload = []; // Store valid entries for display after upload
    validationSummary = {
        totalCount: 0,
        validCount: 0,
        invalidCount: 0,
        hasErrors: false
    };

    disableNext = true;
    disableUpload = true;
    uploadLabel = 'UPLOAD';

    courseId;
    sessionId;
    rosterUploadId;
    fileBase64;
    fileName;

    courseOptions = [];
    sessionOptions = [];
    
    // Manual entry table data
    @track rosterRows = [];
    entryMode = 'file'; // 'manual' or 'file' - default to 'file' (Upload CSV File)
    
    get showFileUploadSection() {
        return this.entryMode === 'file';
    }
    
    get showManualEntrySection() {
        return this.entryMode === 'manual';
    }
    
    get fileButtonVariant() {
        return this.entryMode === 'file' ? 'brand' : 'neutral';
    }
    
    get manualButtonVariant() {
        return this.entryMode === 'manual' ? 'brand' : 'neutral';
    }
    
    get validationStatusText() {
        return this.validationSummary.hasErrors ? 'Has Errors' : 'All Valid';
    }
    
    get validationStatusClass() {
        return this.validationSummary.hasErrors ? 'slds-text-color_error' : 'slds-text-color_success';
    }
    
    get hasVerifiedEntries() {
        return this.verifiedEntries && this.verifiedEntries.length > 0;
    }
    
    get canConfirmSubmission() {
        // Check if all verified entries are valid
        if (!this.verifiedEntries || this.verifiedEntries.length === 0) {
            return true; // Disable if no entries
        }
        
        // Validate all entries
        for (let entry of this.verifiedEntries) {
            if (!this.validateVerifiedEntry(entry)) {
                return true; // Disable if any entry is invalid
            }
        }
        
        return false; // Enable if all entries are valid
    }

    get showIncompleteRowsMessage() {
        return this.manualValidationTriggered && this.hasIncompleteRows;
    }

    get stateOptions() {
        return STATE_OPTIONS;
    }

    setDefaultUploadLabel() {
        this.uploadLabel = this.entryMode === 'manual' ? 'VALIDATE' : 'UPLOAD';
    }

    isStateField(fieldName) {
        return fieldName === 'stateOfLicense1' || fieldName === 'stateOfLicense2' || fieldName === 'stateOfLicense3';
    }

    normalizeStateValue(value) {
        return (value || '').toUpperCase().substring(0, 2);
    }

    isValidStateCode(value) {
        return STATE_OPTIONS.some(option => option.value === value);
    }

    rowHasAnyData(row) {
        return row.firstName || row.lastName || row.stateOfLicense1 || row.licenseNumber1 ||
            row.stateOfLicense2 || row.licenseNumber2 || row.stateOfLicense3 || row.licenseNumber3 ||
            row.email || row.courseCompletedOn;
    }

    sanitizeDateInput(value) {
        if (!value) {
            return '';
        }

        // Allow typing continuous digits and auto-format to MM/DD/YYYY.
        const digits = value.replace(/\D/g, '').slice(0, 8);
        if (digits.length <= 2) {
            return digits;
        }
        if (digits.length <= 4) {
            return `${digits.slice(0, 2)}/${digits.slice(2)}`;
        }
        return `${digits.slice(0, 2)}/${digits.slice(2, 4)}/${digits.slice(4, 8)}`;
    }

    normalizeImportedDate(value) {
        if (!value) {
            return null;
        }

        const raw = value.toString().trim().replace(/^"|"$/g, '');
        if (!raw) {
            return null;
        }

        // Support Excel serial date values from CSV exports.
        if (/^\d+$/.test(raw)) {
            const serial = parseInt(raw, 10);
            if (!Number.isNaN(serial) && serial > 0) {
                const excelBase = new Date(1899, 11, 30);
                const serialDate = new Date(excelBase);
                serialDate.setDate(excelBase.getDate() + serial);
                const month = serialDate.getMonth() + 1;
                const day = serialDate.getDate();
                const year = serialDate.getFullYear();
                if (year >= 1900 && year <= 2100) {
                    return `${String(month).padStart(2, '0')}/${String(day).padStart(2, '0')}/${year}`;
                }
            }
        }

        const cleaned = raw.replace(/[-.]/g, '/');
        const match = cleaned.match(/^(\d{1,2})\/(\d{1,2})\/(\d{2}|\d{4})$/);
        if (!match) {
            return null;
        }

        const month = parseInt(match[1], 10);
        const day = parseInt(match[2], 10);
        let year = parseInt(match[3], 10);
        if (match[3].length === 2) {
            year += year >= 50 ? 1900 : 2000;
        }

        if (month < 1 || month > 12 || day < 1 || day > 31 || year < 1900 || year > 2100) {
            return null;
        }

        const dateObj = new Date(year, month - 1, day);
        if (dateObj.getFullYear() !== year || dateObj.getMonth() !== month - 1 || dateObj.getDate() !== day) {
            return null;
        }

        return `${String(month).padStart(2, '0')}/${String(day).padStart(2, '0')}/${year}`;
    }

    preserveManualTableScroll(updateFn) {
        const wrapper = this.template ? this.template.querySelector('.manual-entry-table-wrapper') : null;
        const currentScrollTop = wrapper ? wrapper.scrollTop : null;
        updateFn();
        if (wrapper && currentScrollTop !== null) {
            requestAnimationFrame(() => {
                wrapper.scrollTop = currentScrollTop;
            });
        }
    }

    focusPendingManualRow() {
        if (!this.pendingFocusRowId) {
            return;
        }

        const selector = `lightning-input[data-row-id="${this.pendingFocusRowId}"][data-field="firstName"]`;
        const targetInput = this.template.querySelector(selector);
        if (!targetInput) {
            return;
        }

        this.pendingFocusRowId = null;
        requestAnimationFrame(() => {
            try {
                targetInput.scrollIntoView({ behavior: 'smooth', block: 'center' });
                targetInput.focus();
            } catch (e) {
                // no-op
            }
        });
    }
    
    // Validate a single verified entry
    validateVerifiedEntry(entry) {
        // First Name (required)
        if (!entry.firstName || entry.firstName.trim() === '') {
            return false;
        }

        // Last Name (required)
        if (!entry.lastName || entry.lastName.trim() === '') {
            return false;
        }

        const state1 = this.normalizeStateValue(entry.stateOfLicense1);
        const state2 = this.normalizeStateValue(entry.stateOfLicense2);
        const state3 = this.normalizeStateValue(entry.stateOfLicense3);
        const license1 = (entry.licenseNumber1 || '').trim();
        const license2 = (entry.licenseNumber2 || '').trim();
        const license3 = (entry.licenseNumber3 || '').trim();

        if (!state1 || !license1 || !this.isValidStateCode(state1)) {
            return false;
        }

        if ((state2 || license2) && (!state2 || !license2 || !this.isValidStateCode(state2))) {
            return false;
        }
        if ((state3 || license3) && (!state3 || !license3 || !this.isValidStateCode(state3))) {
            return false;
        }

        // Email (required, valid format)
        if (!entry.email || entry.email.trim() === '') {
            return false;
        }
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        if (!emailRegex.test(entry.email.trim())) {
            return false;
        }

        // Course Completed On (required; accepts MM/DD/YYYY, M/D/YY, M/D/YYYY, Excel serial)
        if (!entry.courseCompletedOn || entry.courseCompletedOn.trim() === '') {
            return false;
        }
        const normalizedDate = this.normalizeImportedDate(entry.courseCompletedOn);
        if (!normalizedDate) {
            return false;
        }
        entry.courseCompletedOn = normalizedDate;

        return true;
    }
    
    // Add new row to verification table
    addVerifiedRow() {
        const newRowNumber = this.verifiedEntries.length + 1;
        const newEntry = {
            rowNumber: newRowNumber,
            firstName: '',
            lastName: '',
            stateOfLicense1: '',
            licenseNumber1: '',
            stateOfLicense2: '',
            licenseNumber2: '',
            stateOfLicense3: '',
            licenseNumber3: '',
            email: '',
            courseCompletedOn: '',
            status: 'Invalid',
            errorMessage: '',
            rowClass: 'slds-text-color_error',
            statusBadgeClass: 'status-pill status-pill-invalid',
            isValid: false
        };
        
        this.verifiedEntries = [...this.verifiedEntries, newEntry];
        // Use deep copy for reactivity
        this.verifiedEntries = JSON.parse(JSON.stringify(this.verifiedEntries));
    }
    
    // Delete row from verification table
    deleteVerifiedRow(event) {
        const rowNumber = parseInt(event.currentTarget.dataset.rowNumber, 10);
        this.verifiedEntries = this.verifiedEntries.filter(entry => entry.rowNumber !== rowNumber);
        
        // Renumber rows
        this.verifiedEntries = this.verifiedEntries.map((entry, index) => ({
            ...entry,
            rowNumber: index + 1
        }));
        
        // Use deep copy for reactivity
        this.verifiedEntries = JSON.parse(JSON.stringify(this.verifiedEntries));
    }
    
    // Handle input change in verification table
    handleVerifiedEntryChange(event) {
        const rowNumber = parseInt(event.currentTarget.dataset.rowNumber, 10);
        const field = event.currentTarget.dataset.field;
        let value = (event.detail && event.detail.value !== undefined) ? event.detail.value : event.target.value;
        
        // Convert state to uppercase and limit to 2 characters
        if (this.isStateField(field) && value) {
            value = this.normalizeStateValue(value);
            // Update the input field value immediately
            const inputElement = event.target;
            if (inputElement) {
                inputElement.value = value;
            }
        }
        
        // Date input: sanitize, do not auto-insert slashes to avoid backspace glitches
        if (field === 'courseCompletedOn' && value) {
            value = this.sanitizeDateInput(value);
            
            // Update the input field value immediately
            const inputElement = event.target;
            if (inputElement) {
                inputElement.value = value;
            }
        }
        
        const entryIndex = this.verifiedEntries.findIndex(entry => entry.rowNumber === rowNumber);
        if (entryIndex !== -1) {
            // Update the field value
            this.verifiedEntries[entryIndex][field] = value;
            
            // Re-validate entry and update status immediately on typing
            const isValid = this.validateVerifiedEntry(this.verifiedEntries[entryIndex]);
            this.verifiedEntries[entryIndex].isValid = isValid;
            this.verifiedEntries[entryIndex].status = isValid ? 'Valid' : 'Invalid';
            this.verifiedEntries[entryIndex].rowClass = isValid ? 'slds-text-color_success' : 'slds-text-color_error';
            this.verifiedEntries[entryIndex].statusBadgeClass = isValid ? 'status-pill status-pill-valid' : 'status-pill status-pill-invalid';
            this.verifiedEntries[entryIndex].errorMessage = isValid ? '' : 'Please fill all required fields correctly';
            
            // Use deep copy for reactivity
            this.verifiedEntries = JSON.parse(JSON.stringify(this.verifiedEntries));
        }
    }
    
    columns = [
        { label: 'Upload Date', fieldName: 'Upload_Date__c', type: 'date' },
        { label: 'File Processed', fieldName: 'File_Processed__c' },
        { label: 'Course Name', fieldName: 'Course_Name__c' },
        { label: 'Course ID', fieldName: 'Course_ID__c' },
        { label: 'Session ID', fieldName: 'Session_ID__c' },
        { label: 'Session Completion Date', fieldName: 'Session_Completion_Date__c', type: 'date' },
        { label: 'Total Records', fieldName: 'Number_of_Records__c', type: 'number' },
        { label: 'Successful Records', fieldName: 'Successful_Records__c', type: 'number' },
        { label: 'Uploaded By', fieldName: 'Uploaded_By__c' }
    ];
    
    // Verification table columns (for verification modal)
    verificationColumns = [
        { label: 'Row #', fieldName: 'rowNumber', type: 'number', fixedWidth: 80 },
        { label: 'First Name', fieldName: 'firstName', type: 'text' },
        { label: 'Last Name', fieldName: 'lastName', type: 'text' },
        { label: 'State #1', fieldName: 'stateOfLicense1', type: 'text', fixedWidth: 80 },
        { label: 'License #1', fieldName: 'licenseNumber1', type: 'text' },
        { label: 'State #2', fieldName: 'stateOfLicense2', type: 'text', fixedWidth: 80 },
        { label: 'License #2', fieldName: 'licenseNumber2', type: 'text' },
        { label: 'State #3', fieldName: 'stateOfLicense3', type: 'text', fixedWidth: 80 },
        { label: 'License #3', fieldName: 'licenseNumber3', type: 'text' },
        { label: 'Email', fieldName: 'email', type: 'email' },
        { label: 'Course Completed On', fieldName: 'courseCompletedOn', type: 'text' },
        { label: 'Status', fieldName: 'status', type: 'text', fixedWidth: 100, cellAttributes: { class: { fieldName: 'rowClass' } } },
        { label: 'Error', fieldName: 'errorMessage', type: 'text', wrapText: true }
    ];
    
    // Uploaded roster entries table columns (for success modal)
    uploadedRosterColumns = [
        { label: 'Row #', fieldName: 'rowNumber', type: 'number', fixedWidth: 80 },
        { label: 'First Name', fieldName: 'firstName', type: 'text' },
        { label: 'Last Name', fieldName: 'lastName', type: 'text' },
        { label: 'State #1', fieldName: 'stateOfLicense1', type: 'text', fixedWidth: 80 },
        { label: 'License #1', fieldName: 'licenseNumber1', type: 'text' },
        { label: 'State #2', fieldName: 'stateOfLicense2', type: 'text', fixedWidth: 80 },
        { label: 'License #2', fieldName: 'licenseNumber2', type: 'text' },
        { label: 'State #3', fieldName: 'stateOfLicense3', type: 'text', fixedWidth: 80 },
        { label: 'License #3', fieldName: 'licenseNumber3', type: 'text' },
        { label: 'Email', fieldName: 'email', type: 'email' },
        { label: 'Course Completed On', fieldName: 'courseCompletedOn', type: 'text' }
    ];

    @wire(CurrentPageReference)
    setCurrentPageReference(pageRef) {
        if (pageRef && pageRef.state) {
            // Get courseId and sessionId from URL parameters
            const urlCourseId = pageRef.state.courseId || pageRef.state.c__courseId;
            const urlSessionId = pageRef.state.sessionId || pageRef.state.c__sessionId;
            
            if (urlCourseId && urlSessionId) {
                // Prefill courseId and sessionId, then automatically proceed to file upload
                this.courseId = urlCourseId;
                this.sessionId = urlSessionId;
                // Load sessions for the course to populate options
                this.loadSessionsAndProceed();
            } else if (urlCourseId) {
                // Only courseId provided, load sessions
                this.courseId = urlCourseId;
                this.loadSessionsForCourse();
            }
        }
    }
    
    connectedCallback() {
        // Load portal CSS styles from static resource
        loadStyle(this, '/resource/FSMTBAssets/FSMTBAssets/css/global.css')
            .catch(error => {
                console.error('Error loading portal styles:', error);
            });
    }

    renderedCallback() {
        this.updateBodyScrollLock();
        this.focusPendingManualRow();
    }

    disconnectedCallback() {
        this.releaseBodyScrollLock();
    }

    get isAnyModalOpen() {
        return this.showSelection || this.showFileUpload || this.showVerification || this.showSuccess || this.showError;
    }

    updateBodyScrollLock() {
        if (typeof document === 'undefined' || !document.body) {
            return;
        }
        if (this.isAnyModalOpen && !this.bodyScrollLocked) {
            document.body.style.overflow = 'hidden';
            this.bodyScrollLocked = true;
        } else if (!this.isAnyModalOpen && this.bodyScrollLocked) {
            this.releaseBodyScrollLock();
        }
    }

    releaseBodyScrollLock() {
        if (typeof document !== 'undefined' && document.body) {
            document.body.style.overflow = '';
        }
        this.bodyScrollLocked = false;
    }
    
    formatSessionLabel(session) {
        // Get the current label - it might already be formatted or we might need to build it
        let label = session.label || '';
        
        // If label doesn't exist, try to build it from individual fields
        if (!label && (session.sessionId || session.instructorName || session.recordType)) {
            const parts = [];
            if (session.sessionId) parts.push(session.sessionId);
            if (session.instructorName) parts.push(session.instructorName);
            if (session.recordType) parts.push(session.recordType);
            label = parts.join(' - ');
        }
        // The Apex handler already appends the correct "End Date" suffix
        // using Last_Time_Frame_End_Date__c when appropriate, so we simply
        // return the label here to avoid duplicating the end date.
        return label;
    }

    processSessionOptions(sessions) {
        if (!sessions || !Array.isArray(sessions)) {
            return [];
        }
        
        return sessions.map(session => {
            const formattedLabel = this.formatSessionLabel(session);
            return {
                ...session,
                label: formattedLabel
            };
        });
    }

    async loadSessionsForCourse() {
        if (this.courseId) {
            try {
                const sessions = await getSessions({ courseId: this.courseId });
                // Process sessions to format labels with end date
                this.sessionOptions = this.processSessionOptions(sessions);
                this.showSessionPicklist = this.sessionOptions.length > 0;
            } catch (error) {
                console.error('Error loading sessions:', error);
            }
        }
    }
    
    async loadSessionsAndProceed() {
        if (this.courseId && this.sessionId) {
            try {
                // Load sessions to populate options
                await this.loadSessionsForCourse();
                // Automatically proceed to file upload
                await this.continueToFile();
            } catch (error) {
                console.error('Error loading sessions and proceeding:', error);
                this.toast('Error', 'Failed to load session details', 'error');
            }
        }
    }


    @wire(getRosters)
    wiredRosters(result) {
        // Store the result for refreshApex
        this.wiredRostersResult = result;
        const { data, error } = result;
        
        if (data) {
            this.rosters = data.map(r => ({
                ...r,
                Course_Name__c: r.Session__r?.Course__r?.Course_Name__c || '',
                Session_Name__c: r.Session__r?.Name || '',
                Course_ID__c: r.Session__r?.Course__r?.Name || '',
                Session_ID__c: r.Session__r?.Name || ''
            }));
        } else if (error) {
            console.error('Error loading rosters:', error);
            this.toast('Error', error.body?.message || error.message, 'error');
        }
    }


    @wire(getContent)
    wiredContent({ data, error }) {
        if (data) {
            this.content = data;
            this.setHtml('.content', data.content);
        }
    }

    // ------------------ helper methods ------------------
    setHtml(selector, html) {
        const el = this.template.querySelector(selector);
        if (el) el.innerHTML = html || '';
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // ------------------ Selection Modal ------------------
    async openSelection() {
        this.showSelection = true;
        const courses = await getCourses();
        this.courseOptions = courses;
        this.setHtml('[data-id="uploadMsg"]', this.content.contentUploadMessage);
    }

    closeSelection() {
        this.resetSelection();
        this.showSelection = false;
    }

    async onCourseChange(e) {
        this.courseId = e.detail.value;
        this.sessionId = undefined;
        this.disableNext = true;
        const sessions = await getSessions({ courseId: this.courseId });
        // Process sessions to format labels with end date
        this.sessionOptions = this.processSessionOptions(sessions);
        this.showSessionPicklist = this.sessionOptions.length > 0;
    }

    onSessionChange(e) {
        this.sessionId = e.detail.value;
        this.disableNext = !this.sessionId;
    }

    async continueToFile() {
        try {
            // Get course and session names for display (don't create Roster_Upload__c yet)
            // We'll create it only when data is actually submitted
            const courseRes = await getCourses();
            const sessionRes = await getSessions({ courseId: this.courseId });
            
            const selectedCourse = courseRes.find(c => c.value === this.courseId);
            const selectedSession = sessionRes.find(s => s.value === this.sessionId);
            
            this.courseName = selectedCourse ? selectedCourse.label.split(' - ')[1] || selectedCourse.label : '';
            this.sessionName = selectedSession ? selectedSession.label.split(' - ')[0] || selectedSession.label : '';
            
            console.log('[Roster Upload] Preparing to collect data for Course:', this.courseName);
            console.log('[Roster Upload] Session:', this.sessionName);
            console.log('[Roster Upload] Note: Roster_Upload__c record will be created when data is submitted');

            // Close "Select Course" modal
            this.showSelection = false;

            // Show the "Upload File" modal (CSV Upload screen)
            this.showFileUpload = true;

            // ensure other states reset
            this.rosterUploadId = undefined; // Will be created on submission
            this.disableUpload = true;
            this.fileBase64 = undefined;
            this.fileName = undefined;
            this.entryMode = 'file'; // Default to file upload mode
            this.validationErrors = ''; // Clear any validation errors
            this.rosterRows = []; // Clear manual entry rows
            this.setDefaultUploadLabel();

        } catch (err) {
            console.error('Error preparing upload', err);
            this.toast('Error', err.body?.message || err.message, 'error');
        }
    }


    // ------------------ Manual Entry Table Management ------------------
    initRosterTable() {
        // Initialize with one empty row
        this.rosterRows = [{
            id: this.generateRowId(),
            firstName: '',
            lastName: '',
            stateOfLicense1: '',
            licenseNumber1: '',
            stateOfLicense2: '',
            licenseNumber2: '',
            stateOfLicense3: '',
            licenseNumber3: '',
            email: '',
            courseCompletedOn: '',
            errorFirstName: '',
            errorLastName: '',
            errorStateOfLicense1: '',
            errorLicenseNumber1: '',
            errorStateOfLicense2: '',
            errorLicenseNumber2: '',
            errorStateOfLicense3: '',
            errorLicenseNumber3: '',
            errorEmail: '',
            errorCourseCompletedOn: '',
            hasErrors: false,
            rowClass: 'slds-hint-parent'
        }];
        this.entryMode = 'manual';
        this.validateTable(this.manualValidationTriggered);
    }

    generateRowId() {
        return 'row_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
    }

    addRow() {
        const newRowId = this.generateRowId();
        this.rosterRows.push({
            id: newRowId,
            firstName: '',
            lastName: '',
            stateOfLicense1: '',
            licenseNumber1: '',
            stateOfLicense2: '',
            licenseNumber2: '',
            stateOfLicense3: '',
            licenseNumber3: '',
            email: '',
            courseCompletedOn: '',
            errorFirstName: '',
            errorLastName: '',
            errorStateOfLicense1: '',
            errorLicenseNumber1: '',
            errorStateOfLicense2: '',
            errorLicenseNumber2: '',
            errorStateOfLicense3: '',
            errorLicenseNumber3: '',
            errorEmail: '',
            errorCourseCompletedOn: '',
            hasErrors: false,
            rowClass: 'slds-hint-parent'
        });
        this.pendingFocusRowId = newRowId;
        // Use deep copy for reactivity
        this.rosterRows = JSON.parse(JSON.stringify(this.rosterRows));
        this.validateTable(this.manualValidationTriggered);
    }

    deleteRow(event) {
        const rowId = event.currentTarget.dataset.rowId;
        this.rosterRows = this.rosterRows.filter(row => row.id !== rowId);
        // Ensure at least one row exists
        if (this.rosterRows.length === 0) {
            this.initRosterTable();
        } else {
            // Use deep copy for reactivity
            this.rosterRows = JSON.parse(JSON.stringify(this.rosterRows));
            this.validateTable(this.manualValidationTriggered);
        }
    }

    handleRowInputChange(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const field = event.currentTarget.dataset.field;
        let value = (event.detail && event.detail.value !== undefined) ? event.detail.value : event.target.value;
        
        // Convert state to uppercase and limit to 2 characters
        if (this.isStateField(field) && value) {
            value = this.normalizeStateValue(value);
            // Update the input field value immediately
            const inputElement = event.target;
            if (inputElement) {
                inputElement.value = value;
            }
        }
        
        // Date input: sanitize, do not auto-insert slashes to avoid backspace glitches
        if (field === 'courseCompletedOn' && value) {
            value = this.sanitizeDateInput(value);
            
            // Update the input field value immediately
            const inputElement = event.target;
            if (inputElement) {
                inputElement.value = value;
            }
        }
        
        const rowIndex = this.rosterRows.findIndex(row => row.id === rowId);
        if (rowIndex !== -1) {
            this.preserveManualTableScroll(() => {
                this.rosterRows[rowIndex][field] = value;
                // Clear error for this field when user starts typing
                if (this.rosterRows[rowIndex]['error' + field.charAt(0).toUpperCase() + field.slice(1)]) {
                    this.rosterRows[rowIndex]['error' + field.charAt(0).toUpperCase() + field.slice(1)] = '';
                }
                // Use deep copy for reactivity
                this.rosterRows = JSON.parse(JSON.stringify(this.rosterRows));
            });
        }
    }
    
    // Validate on blur (when user exits field)
    handleRowInputBlur(event) {
        const rowId = event.currentTarget.dataset.rowId;
        const rowIndex = this.rosterRows.findIndex(row => row.id === rowId);
        if (rowIndex !== -1) {
            this.preserveManualTableScroll(() => {
                // Validate the row when user leaves the field
                this.validateRow(this.rosterRows[rowIndex], this.manualValidationTriggered);
                // Use deep copy for reactivity
                this.rosterRows = JSON.parse(JSON.stringify(this.rosterRows));
                this.validateTable(this.manualValidationTriggered);
            });
        }
    }

    // ------------------ Validation ------------------
    validateTable(showErrors = false) {
        // Remove empty rows for validation (rows with all fields empty)
        const nonEmptyRows = this.rosterRows.filter(row => {
            return this.rowHasAnyData(row);
        });

        if (nonEmptyRows.length === 0) {
            this.disableUpload = true;
            this.hasIncompleteRows = false;
            return false;
        }

        let hasIncomplete = false;
        // Validate each non-empty row
        for (let row of nonEmptyRows) {
            if (!this.validateRow(row, showErrors)) {
                hasIncomplete = true;
                this.disableUpload = true;
            }
        }
        
        this.hasIncompleteRows = hasIncomplete;
        if (!hasIncomplete) {
            this.disableUpload = false;
            return true;
        }

        return false;
    }

    validateRow(row, showErrors = false) {
        // Pre-submit validation should not mutate inline errors.
        if (!showErrors) {
            const rowCopy = JSON.parse(JSON.stringify(row));
            return this.validateRow(rowCopy, true);
        }

        // Clear previous errors
        row.errorFirstName = '';
        row.errorLastName = '';
        row.errorStateOfLicense1 = '';
        row.errorLicenseNumber1 = '';
        row.errorStateOfLicense2 = '';
        row.errorLicenseNumber2 = '';
        row.errorStateOfLicense3 = '';
        row.errorLicenseNumber3 = '';
        row.errorEmail = '';
        row.errorCourseCompletedOn = '';
        row.hasErrors = false; // Flag for row-level styling
        row.rowClass = 'slds-hint-parent'; // Default row class
        
        let isValid = true;

        // First Name (required)
        if (!row.firstName || row.firstName.trim() === '') {
            row.errorFirstName = 'This field is required.';
            row.hasErrors = true;
            row.rowClass = 'slds-hint-parent row-error';
            isValid = false;
        }

        // Last Name (required)
        if (!row.lastName || row.lastName.trim() === '') {
            row.errorLastName = 'This field is required.';
            row.hasErrors = true;
            row.rowClass = 'slds-hint-parent row-error';
            isValid = false;
        }

        // State of License #1 (required, valid dropdown code)
        if (!row.stateOfLicense1 || row.stateOfLicense1.trim() === '') {
            row.errorStateOfLicense1 = 'This field is required.';
            row.hasErrors = true;
            row.rowClass = 'slds-hint-parent row-error';
            isValid = false;
        } else if (!this.isValidStateCode(this.normalizeStateValue(row.stateOfLicense1))) {
            row.errorStateOfLicense1 = 'Select a valid state/territory.';
            row.hasErrors = true;
            row.rowClass = 'slds-hint-parent row-error';
            isValid = false;
        }

        // License Number #1 (required)
        if (!row.licenseNumber1 || row.licenseNumber1.trim() === '') {
            row.errorLicenseNumber1 = 'This field is required.';
            row.hasErrors = true;
            row.rowClass = 'slds-hint-parent row-error';
            isValid = false;
        }

        // License pair #2 (optional, but both fields required if one is provided)
        const hasState2 = !!(row.stateOfLicense2 && row.stateOfLicense2.trim());
        const hasLicense2 = !!(row.licenseNumber2 && row.licenseNumber2.trim());
        if (hasState2 || hasLicense2) {
            if (!hasState2) {
                row.errorStateOfLicense2 = 'State is required when License #2 is provided.';
                row.hasErrors = true;
                row.rowClass = 'slds-hint-parent row-error';
                isValid = false;
            } else if (!this.isValidStateCode(this.normalizeStateValue(row.stateOfLicense2))) {
                row.errorStateOfLicense2 = 'Select a valid state/territory.';
                row.hasErrors = true;
                row.rowClass = 'slds-hint-parent row-error';
                isValid = false;
            }
            if (!hasLicense2) {
                row.errorLicenseNumber2 = 'License #2 is required when State #2 is provided.';
                row.hasErrors = true;
                row.rowClass = 'slds-hint-parent row-error';
                isValid = false;
            }
        }

        // License pair #3 (optional, but both fields required if one is provided)
        const hasState3 = !!(row.stateOfLicense3 && row.stateOfLicense3.trim());
        const hasLicense3 = !!(row.licenseNumber3 && row.licenseNumber3.trim());
        if (hasState3 || hasLicense3) {
            if (!hasState3) {
                row.errorStateOfLicense3 = 'State is required when License #3 is provided.';
                row.hasErrors = true;
                row.rowClass = 'slds-hint-parent row-error';
                isValid = false;
            } else if (!this.isValidStateCode(this.normalizeStateValue(row.stateOfLicense3))) {
                row.errorStateOfLicense3 = 'Select a valid state/territory.';
                row.hasErrors = true;
                row.rowClass = 'slds-hint-parent row-error';
                isValid = false;
            }
            if (!hasLicense3) {
                row.errorLicenseNumber3 = 'License #3 is required when State #3 is provided.';
                row.hasErrors = true;
                row.rowClass = 'slds-hint-parent row-error';
                isValid = false;
            }
        }

        // Email (required, valid format)
        if (!row.email || row.email.trim() === '') {
            row.errorEmail = 'This field is required.';
            row.hasErrors = true;
            row.rowClass = 'slds-hint-parent row-error';
            isValid = false;
        } else {
            const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
            if (!emailRegex.test(row.email.trim())) {
                row.errorEmail = 'Please enter a valid email address.';
                row.hasErrors = true;
                row.rowClass = 'slds-hint-parent row-error';
                isValid = false;
            }
        }

        // Course Completed On (required; accepts MM/DD/YYYY, M/D/YY, M/D/YYYY, Excel serial)
        if (!row.courseCompletedOn || row.courseCompletedOn.trim() === '') {
            row.errorCourseCompletedOn = 'This field is required.';
            row.hasErrors = true;
            row.rowClass = 'slds-hint-parent row-error';
            isValid = false;
        } else {
            const normalizedDate = this.normalizeImportedDate(row.courseCompletedOn);
            if (!normalizedDate) {
                row.errorCourseCompletedOn = 'Use MM/DD/YYYY, M/D/YY, or M/D/YYYY format.';
                row.hasErrors = true;
                row.rowClass = 'slds-hint-parent row-error';
                isValid = false;
            } else {
                row.courseCompletedOn = normalizedDate;
            }
        }

        return isValid;
    }

    // ------------------ File Upload Modal ------------------
    handleFileChange(e) {
        const file = e.target.files && e.target.files[0];
        if (!file) return;
        
        // Switch to file mode - clear manual entry data
        this.entryMode = 'file';
        this.setDefaultUploadLabel();
        this.rosterRows = [];
        this.fileName = file.name;
        const reader = new FileReader();
        reader.onload = () => {
            this.fileBase64 = reader.result.split(',')[1];
            this.disableUpload = false;
        };
        reader.readAsDataURL(file);
    }

    switchToManualEntry() {
        // Switch to manual entry mode - clear file data
        this.entryMode = 'manual';
        this.fileBase64 = undefined;
        this.fileName = undefined;
        this.validationErrors = ''; // Clear validation errors
        this.manualValidationTriggered = false;
        this.initRosterTable();
        this.setDefaultUploadLabel();
    }
    
    handleFileModeClick() {
        this.entryMode = 'file';
        this.fileBase64 = undefined;
        this.fileName = undefined;
        this.rosterRows = [];
        this.validationErrors = ''; // Clear validation errors
        this.manualValidationTriggered = false;
        this.disableUpload = true;
        this.setDefaultUploadLabel();
    }

    async uploadFile() {
        // First validate the data and show verification table
        this.uploadLabel = 'Validating...';
        this.disableUpload = true;

        try {
            let base64DataToValidate = null;
            let manualEntries = null;

            if (this.entryMode === 'file') {
                if (!this.fileBase64) {
                    this.validationErrors = 'Please attach a file before uploading.';
                    this.disableUpload = false;
                    this.setDefaultUploadLabel();
                    return;
                }
                base64DataToValidate = this.fileBase64;
            } else {
                // Handle manual entry - convert to format for validation
                this.manualValidationTriggered = true;
                if (!this.validateTable(true)) {
                    this.validationErrors = 'Please fill all required fields correctly before submitting.';
                    this.disableUpload = false;
                    this.setDefaultUploadLabel();
                    return;
                }

                // Remove empty rows
                const rowsToSubmit = this.rosterRows.filter(row => {
                    return this.rowHasAnyData(row);
                });

                if (rowsToSubmit.length === 0) {
                    this.validationErrors = 'Please add at least one roster entry before submitting.';
                    this.disableUpload = false;
                    this.setDefaultUploadLabel();
                    return;
                }

                // Convert to manual entries format for validation
                manualEntries = rowsToSubmit.map(row => ({
                    firstName: row.firstName || '',
                    lastName: row.lastName || '',
                    stateOfLicense1: row.stateOfLicense1 || '',
                    licenseNumber1: row.licenseNumber1 || '',
                    stateOfLicense2: row.stateOfLicense2 || '',
                    licenseNumber2: row.licenseNumber2 || '',
                    stateOfLicense3: row.stateOfLicense3 || '',
                    licenseNumber3: row.licenseNumber3 || '',
                    email: row.email || '',
                    courseCompletedOn: row.courseCompletedOn || ''
                }));
            }

            // Validate roster data
            const validationResult = await validateRosterData({
                base64Data: base64DataToValidate,
                manualEntries: manualEntries
            });

            if (validationResult.success === false) {
                this.validationErrors = validationResult.message || 'Error validating roster data. Please try again.';
                this.disableUpload = false;
                this.setDefaultUploadLabel();
                return;
            }

            // Process validation results
            this.validationSummary = {
                totalCount: validationResult.totalCount || 0,
                validCount: validationResult.validCount || 0,
                invalidCount: validationResult.invalidCount || 0,
                hasErrors: validationResult.hasErrors || false
            };

            // Build validation error messages from invalid entries
            if (this.validationSummary.hasErrors) {
                const invalidEntries = validationResult.entries.filter(entry => !entry.isValid);
                let errorMessages = [];
                
                invalidEntries.forEach(entry => {
                    errorMessages.push(`Row ${entry.rowNumber}: ${entry.errorMessage}`);
                });
                
                this.validationErrors = errorMessages.join('\n');
            } else {
                this.validationErrors = ''; // Clear errors if all valid
            }

            // Format entries for display and store for later use
            this.verifiedEntries = (validationResult.entries || []).map(entry => {
                const formattedEntry = {
                    rowNumber: entry.rowNumber,
                    firstName: entry.firstName || '',
                    lastName: entry.lastName || '',
                    stateOfLicense1: entry.stateOfLicense1 || '',
                    licenseNumber1: entry.licenseNumber1 || '',
                    stateOfLicense2: entry.stateOfLicense2 || '',
                    licenseNumber2: entry.licenseNumber2 || '',
                    stateOfLicense3: entry.stateOfLicense3 || '',
                    licenseNumber3: entry.licenseNumber3 || '',
                    email: entry.email || '',
                    courseCompletedOn: entry.courseCompletedOn || '',
                    status: entry.isValid ? 'Valid' : 'Invalid',
                    errorMessage: entry.errorMessage || '',
                    rowClass: entry.isValid ? 'slds-text-color_success' : 'slds-text-color_error',
                    statusBadgeClass: entry.isValid ? 'status-pill status-pill-valid' : 'status-pill status-pill-invalid',
                    isValid: entry.isValid || false
                };
                return formattedEntry;
            });
            
            console.log('[Roster Upload] Formatted verifiedEntries:', this.verifiedEntries);
            
            // Store a copy of valid entries for display after upload
            this.validEntriesForUpload = validationResult.entries
                .filter(entry => entry.isValid)
                .map(entry => ({
                    firstName: entry.firstName,
                    lastName: entry.lastName,
                    stateOfLicense1: entry.stateOfLicense1,
                    licenseNumber1: entry.licenseNumber1,
                    stateOfLicense2: entry.stateOfLicense2,
                    licenseNumber2: entry.licenseNumber2,
                    stateOfLicense3: entry.stateOfLicense3,
                    licenseNumber3: entry.licenseNumber3,
                    email: entry.email,
                    courseCompletedOn: entry.courseCompletedOn
                }));

            // If there are errors, show them inline in the file upload section
            // If all valid, show verification table
            if (this.validationSummary.hasErrors) {
                // Keep file upload modal open and show errors inline
                this.showFileUpload = true;
                this.showVerification = false;
                this.disableUpload = false;
                this.setDefaultUploadLabel();
            } else {
                // All valid - show verification table
                this.showFileUpload = false;
                this.showVerification = true;
                this.disableUpload = false;
                this.setDefaultUploadLabel();
                this.toast(
                    'Validation Complete',
                    `${this.validationSummary.validCount} record(s) are ready. Click CONFIRM & SUBMIT to finish.`,
                    'success'
                );
            }

        } catch (err) {
            console.error('Error validating roster data:', err);
            this.validationErrors = err.body?.message || err.message || 'An error occurred while validating the roster data. Please try again.';
            this.disableUpload = false;
            this.setDefaultUploadLabel();
        }
    }

    // Confirm and submit after verification
    async confirmSubmission() {
        this.uploadLabel = 'Submitting...';
        this.disableUpload = true;

        try {
            let base64DataToSubmit = null;
            const isManualEntry = this.entryMode === 'manual';

            if (this.entryMode === 'file') {
                base64DataToSubmit = this.fileBase64;
                console.log('[Roster Upload] Submitting file upload - File:', this.fileName);
            } else {
                // Convert manual entries to CSV for submission
                const rowsToSubmit = this.rosterRows.filter(row => {
                    return this.rowHasAnyData(row);
                });

                console.log('[Roster Upload] Submitting manual entry - Rows to submit:', rowsToSubmit.length);
                console.log('[Roster Upload] Manual entry data:', rowsToSubmit);

                let csvContent = 'First Name,Last Name,State of License #1,License Number #1,State of License #2,License Number #2,State of License #3,License Number #3,Email,Course Completed On\n';
                rowsToSubmit.forEach(row => {
                    csvContent += `${row.firstName},${row.lastName},${row.stateOfLicense1},${row.licenseNumber1},${row.stateOfLicense2 || ''},${row.licenseNumber2 || ''},${row.stateOfLicense3 || ''},${row.licenseNumber3 || ''},${row.email},${row.courseCompletedOn}\n`;
                });

                base64DataToSubmit = btoa(unescape(encodeURIComponent(csvContent)));
            }

            console.log('[Roster Upload] Submitting to rosterUploadId:', this.rosterUploadId);
            console.log('[Roster Upload] Course ID:', this.courseId);
            console.log('[Roster Upload] Session ID:', this.sessionId);
            console.log('[Roster Upload] Entry Mode:', this.entryMode);

            const res = await uploadRosterFile({
                rosterUploadId: this.rosterUploadId || null, // Will be created in Apex if null
                courseId: this.courseId,
                sessionId: this.sessionId,
                fileName: this.entryMode === 'file' ? this.fileName : 'manual_entry.csv',
                base64Data: base64DataToSubmit
            });
            
            // Store the rosterUploadId from response (it was created in uploadRosterFile)
            if (res.rosterUploadId) {
                this.rosterUploadId = res.rosterUploadId;
                console.log('[Roster Upload] Roster_Upload__c record created with ID:', this.rosterUploadId);
            }

            console.log('[Roster Upload] Upload response:', res);

            const isSuccess = res.success === true || res.success === 'true';
            if (isSuccess) {
                console.log('[Roster Upload] Upload successful!');
                console.log('[Roster Upload] Roster Upload Record ID:', this.rosterUploadId);
                if (res.totalRecords) {
                    console.log('[Roster Upload] Total records:', res.totalRecords);
                }
                if (isManualEntry) {
                    console.log('[Roster Upload] ===== MANUAL ENTRY RECORD CREATED =====');
                    console.log('[Roster Upload] Manual entry Roster_Upload__c record ID:', this.rosterUploadId);
                    console.log('[Roster Upload] Course ID:', this.courseId);
                    console.log('[Roster Upload] Session ID:', this.sessionId);
                    console.log('[Roster Upload] Total records submitted:', res.totalRecords || 'N/A');
                    if (res.rosterUploadId) {
                        console.log('[Roster Upload] Roster Upload Record ID from response:', res.rosterUploadId);
                    }
                    console.log('[Roster Upload] ========================================');
                }
                // Store uploaded roster entries for display (use verified entries which may have been edited)
                // Format them for display with row numbers
                if (this.verifiedEntries && this.verifiedEntries.length > 0) {
                    const validEntries = this.verifiedEntries.filter(entry => this.validateVerifiedEntry(entry));
                    this.uploadedRosterEntries = validEntries.map((entry, index) => ({
                        rowNumber: index + 1,
                        firstName: entry.firstName,
                        lastName: entry.lastName,
                        stateOfLicense1: entry.stateOfLicense1,
                        licenseNumber1: entry.licenseNumber1,
                        stateOfLicense2: entry.stateOfLicense2,
                        licenseNumber2: entry.licenseNumber2,
                        stateOfLicense3: entry.stateOfLicense3,
                        licenseNumber3: entry.licenseNumber3,
                        email: entry.email,
                        courseCompletedOn: entry.courseCompletedOn
                    }));
                    console.log('[Roster Upload] Prepared ' + this.uploadedRosterEntries.length + ' entries for display (from verifiedEntries)');
                } else if (this.validEntriesForUpload && this.validEntriesForUpload.length > 0) {
                    // Fallback to validEntriesForUpload
                    this.uploadedRosterEntries = this.validEntriesForUpload.map((entry, index) => ({
                        rowNumber: index + 1,
                        firstName: entry.firstName,
                        lastName: entry.lastName,
                        stateOfLicense1: entry.stateOfLicense1,
                        licenseNumber1: entry.licenseNumber1,
                        stateOfLicense2: entry.stateOfLicense2,
                        licenseNumber2: entry.licenseNumber2,
                        stateOfLicense3: entry.stateOfLicense3,
                        licenseNumber3: entry.licenseNumber3,
                        email: entry.email,
                        courseCompletedOn: entry.courseCompletedOn
                    }));
                    console.log('[Roster Upload] Prepared ' + this.uploadedRosterEntries.length + ' entries for display (from validEntriesForUpload)');
                }
                
                this.showVerification = false;
                this.showSuccess = true;
                this.showSuccessTable = true;
            } else {
                this.showVerification = false;
                this.showError = true;
                this.errorMessage = res.message || 'An error occurred while submitting the roster. Please try again.';
            }
        } catch (err) {
            this.showVerification = false;
            this.showError = true;
            this.errorMessage = err.body?.message || err.message || 'An error occurred while submitting the roster. Please try again.';
        } finally {
            this.setDefaultUploadLabel();
            this.disableUpload = false;
        }
    }

    // Go back to file upload from verification
    backToFileUpload() {
        this.showVerification = false;
        this.showFileUpload = true;
        this.verifiedEntries = [];
        this.validationSummary = {
            totalCount: 0,
            validCount: 0,
            invalidCount: 0,
            hasErrors: false
        };
    }
    


    async backToSelection() {
        // Cleanup roster upload record if needed
        // Note: deleteRosterUpload method may need to be implemented in Apex if cleanup is required
        this.showFileUpload = false;
        this.showSelection = true;
    }

    async cancelUpload() {
        // Cleanup roster upload record if needed
        // Note: deleteRosterUpload method may need to be implemented in Apex if cleanup is required
        this.resetSelection();
        this.showFileUpload = false;
    }


    // ------------------ Success Modal ------------------
    async closeSuccess() {
        this.showSuccess = false;
        this.showSuccessTable = false;
        this.uploadedRosterEntries = [];
        this.validEntriesForUpload = [];
        this.resetSelection();
        
        // Refresh the roster data to show the newly created record
        if (this.wiredRostersResult) {
            await refreshApex(this.wiredRostersResult);
        }
        
        // Also do a page reload as backup to ensure data is refreshed
        window.location.reload();
    }
    
    // ------------------ Error Modal ------------------
    closeError() {
        this.showError = false;
        this.errorMessage = '';
        this.showSelection = true;
    }

    // ------------------ Utility ------------------
    resetSelection() {
        this.courseId = undefined;
        this.sessionId = undefined;
        this.showSessionPicklist = false;
        this.fileBase64 = undefined;
        this.fileName = undefined;
        this.disableNext = true;
        this.disableUpload = true;
        this.rosterRows = [];
        this.entryMode = 'manual';
        this.manualValidationTriggered = false;
        this.setDefaultUploadLabel();
    }
}