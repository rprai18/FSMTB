import { LightningElement, track, wire } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import getPageInfo from '@salesforce/apex/AccessRestrictedLwcController.getPageInfo';
import SLBAssets from '@salesforce/resourceUrl/SLBAssets';

export default class AccessRestricted extends LightningElement {
    @track pageInfo = {
        siteMasterLabel: '',
        userFirstName: '',
        userLastName: '',
        accountName: '',
        emailSubject: 'Under Review Inquiry'
    };
    
    // Static resource for images
    headerImageUrl = `${SLBAssets}/SLBAssets/img/fsmtb_reach.png`;
    
    @wire(getPageInfo)
    wiredPageInfo({ data, error }) {
        if (data) {
            this.pageInfo = data;
            // Set page title
            const pageTitle = this.pageInfo.siteMasterLabel 
                ? `${this.pageInfo.siteMasterLabel} Access Restricted` 
                : 'Access Restricted';
            document.title = pageTitle;
        } else if (error) {
            console.error('Error loading page info:', error);
            document.title = 'Access Restricted';
        }
    }
    
    connectedCallback() {
        // Load CSS from SLBAssets
        loadStyle(this, SLBAssets + '/SLBAssets/fsmtb_sforce.css')
            .catch(error => {
                console.error('Error loading SLBAssets CSS:', error);
            });
        
        // Load portal CSS styles if available
        loadStyle(this, '/resource/FSMTBAssets/FSMTBAssets/css/global.css')
            .catch(error => {
                console.error('Error loading portal styles:', error);
            });
        
        // Set page title
        const pageTitle = this.pageInfo.siteMasterLabel 
            ? `${this.pageInfo.siteMasterLabel} Access Restricted` 
            : 'Access Restricted';
        document.title = pageTitle;
    }
    
    get emailLink() {
        const subject = this.pageInfo.emailSubject || 'Under Review Inquiry';
        return `mailto:CE@fsmtb.org?subject=${subject}`;
    }
    
    handleImageError(event) {
        // Hide image if it fails to load
        if (event.target) {
            event.target.style.display = 'none';
        }
    }
}

