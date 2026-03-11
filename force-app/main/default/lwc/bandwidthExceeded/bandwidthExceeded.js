import { LightningElement, track, wire } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import getErrorLabels from '@salesforce/apex/BandwidthExceededLwcController.getErrorLabels';
import SLBAssets from '@salesforce/resourceUrl/SLBAssets';

export default class BandwidthExceeded extends LightningElement {
    @track errorLabels = {
        bandwidthLimitExceeded: 'Bandwidth Exceeded'
    };
    
    @wire(getErrorLabels)
    wiredErrorLabels({ data, error }) {
        if (data) {
            this.errorLabels = data;
            // Set page title
            document.title = this.errorLabels.bandwidthLimitExceeded || 'Bandwidth Exceeded';
        } else if (error) {
            console.error('Error loading error labels:', error);
            // Keep default value
            document.title = 'Bandwidth Exceeded';
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
        document.title = this.errorLabels.bandwidthLimitExceeded || 'Bandwidth Exceeded';
    }
}

