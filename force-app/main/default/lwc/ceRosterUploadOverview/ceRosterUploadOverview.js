import { LightningElement, track, wire } from 'lwc';
import favicon from '@salesforce/resourceUrl/favicon';
import getUserDetails from '@salesforce/apex/UserInfoController.getUserDetails';

export default class CeRosterUploadOverview extends LightningElement {
    faviconUrl = favicon;
    logoutUrl = '/secur/logout.jsp';

    @track userName = '';
    @track organizationName = '';
    @track activeTab = 'roster';

    connectedCallback() {
        document.title = 'CE Roster Upload Overview';
    }

    // Fetch user details dynamically
    @wire(getUserDetails)
    wiredUser({ data, error }) {
        if (data) {
            this.userName = data.Name;
            this.organizationName = data.AccountName;
        } else if (error) {
            console.error('Error fetching user details:', error);
        }
    }

    // -----------------------
    // Tab handling logic
    // -----------------------
    handleTabClick(event) {
        this.activeTab = event.target.dataset.tab;
    }

    get showRosterUpload() {
        return this.activeTab === 'roster';
    }
    get showPlaceholder() {
        return this.activeTab !== 'roster';
    }

    get tabClassRoster() {
        return this.activeTab === 'roster' ? 'tab active' : 'tab';
    }
    get tabClassCourses() {
        return this.activeTab === 'courses' ? 'tab active' : 'tab';
    }
    get tabClassSurveys() {
        return this.activeTab === 'surveys' ? 'tab active' : 'tab';
    }
    get tabClassInstructors() {
        return this.activeTab === 'instructors' ? 'tab active' : 'tab';
    }
    get tabClassAdmin() {
        return this.activeTab === 'admin' ? 'tab active' : 'tab';
    }
}