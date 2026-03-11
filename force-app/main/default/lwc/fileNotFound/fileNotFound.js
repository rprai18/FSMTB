import { LightningElement, track, wire } from 'lwc';
import { loadStyle } from 'lightning/platformResourceLoader';
import getErrorLabels from '@salesforce/apex/FileNotFoundLwcController.getErrorLabels';
import SLBAssets from '@salesforce/resourceUrl/SLBAssets';

export default class FileNotFound extends LightningElement {
    @track errorLabels = {
        fileNotFound: 'File Not Found'
    };
    
    @wire(getErrorLabels)
    wiredErrorLabels({ data, error }) {
        if (data) {
            this.errorLabels = data;
            // Set page title
            document.title = this.errorLabels.fileNotFound || 'File Not Found';
        } else if (error) {
            console.error('Error loading error labels:', error);
            // Keep default value
            document.title = 'File Not Found';
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
        document.title = this.errorLabels.fileNotFound || 'File Not Found';
    }
}

