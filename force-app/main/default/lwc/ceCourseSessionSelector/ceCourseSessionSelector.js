import { LightningElement, track, wire } from 'lwc';
import getRosterContentDetails from '@salesforce/apex/CeRosterLwcController.getRosterContentDetails';
import getCourses from '@salesforce/apex/CeRosterLwcController.getCourses';
import getEligibleSessions from '@salesforce/apex/CeRosterLwcController.getEligibleSessions';
import getRosterTableData from '@salesforce/apex/CeRosterLwcController.getRosterTableData';

export default class CeRosterUploader extends LightningElement {
    @track headerHtml;
    @track messageHtml;

    @track courses = [];
    @track sessions = [];
    @track selectedCourseId = '';
    @track selectedSessionId = '';

    @track rosters = [];
    @track columns = [
        { label: 'Upload Date', fieldName: 'UploadDate', type: 'date' },
        { label: 'File Processed', fieldName: 'FileProcessed', type: 'text' },
        { label: 'Course Name', fieldName: 'CourseName', type: 'text' },
        { label: 'Course ID', fieldName: 'CourseId', type: 'text' },
        { label: 'Session ID', fieldName: 'SessionId', type: 'text' },
        { label: 'Session Completion Date', fieldName: 'SessionCompletionDate', type: 'date' },
        { label: 'Total Records', fieldName: 'TotalRecords', type: 'number' },
        { label: 'Successful Records', fieldName: 'SuccessfulRecords', type: 'number' },
        { label: 'Uploaded By', fieldName: 'UploadedBy', type: 'text' }
    ];

    @track showModal = false;
    @track file;

    connectedCallback() {
        this.loadHeaderContent();
        this.loadCourses();
        this.loadRosterTable();
    }

    loadHeaderContent() {
        getRosterContentDetails().then(result => {
            this.headerHtml = result.header;
            this.messageHtml = result.message;
            const headerDiv = this.template.querySelector('.header-content');
            if (headerDiv) headerDiv.innerHTML = this.headerHtml;
        });
    }

    loadCourses() {
        getCourses().then(result => {
            this.courses = result;
        });
    }

    loadSessions() {
        if (!this.selectedCourseId) {
            this.sessions = [];
            return;
        }
        getEligibleSessions({ courseId: this.selectedCourseId }).then(result => {
            this.sessions = result;
        });
    }

    loadRosterTable() {
        getRosterTableData().then(result => {
            this.rosters = result;
        });
    }

    handleCourseChange(event) {
        this.selectedCourseId = event.detail.value;
        this.selectedSessionId = '';
        this.loadSessions();
    }

    handleSessionChange(event) {
        this.selectedSessionId = event.detail.value;
    }

    handleFileChange(event) {
        this.file = event.target.files[0];
    }

    openModal() {
        this.showModal = true;
    }

    closeModal() {
        this.showModal = false;
        this.selectedCourseId = '';
        this.selectedSessionId = '';
        this.sessions = [];
        this.file = null;
    }
}