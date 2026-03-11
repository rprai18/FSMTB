import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { loadStyle } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getPasswordStatus from '@salesforce/apex/ChangePasswordLwcController.getPasswordStatus';
import changePassword from '@salesforce/apex/ChangePasswordLwcController.changePassword';
import SLBAssets from '@salesforce/resourceUrl/SLBAssets';

export default class ChangePassword extends NavigationMixin(LightningElement) {
    @track oldPassword = '';
    @track newPassword = '';
    @track verifyNewPassword = '';
    @track isPasswordExpired = false;
    @track siteMasterLabel = '';
    @track isLoading = false;
    @track errorMessage = '';
    @track pageTitle = 'Update Your Password';
    
    // Static resource for images
    headerImageUrl = `${SLBAssets}/SLBAssets/img/fsmtb_reach.png`;
    
    @wire(getPasswordStatus)
    wiredPasswordStatus({ data, error }) {
        if (data) {
            if (data.success) {
                this.isPasswordExpired = data.isPasswordExpired || false;
                this.siteMasterLabel = data.siteMasterLabel || '';
                // Update page title when site master label is loaded
                this.pageTitle = this.siteMasterLabel 
                    ? `${this.siteMasterLabel} - Update Your Password` 
                    : 'Update Your Password';
            } else {
                console.error('Error getting password status:', data.error);
                this.showErrorToast('Error', data.error || 'Failed to load password status.');
            }
        } else if (error) {
            console.error('Error loading password status:', error);
            this.showErrorToast('Error', 'Failed to load password status.');
        }
    }
    
    connectedCallback() {
        // Load portal CSS styles if available
        loadStyle(this, '/resource/FSMTBAssets/FSMTBAssets/css/global.css')
            .catch(error => {
                console.error('Error loading portal styles:', error);
            });
        
        // Set page title
        document.title = 'Update Your Password';
    }
    
    handleOldPasswordChange(event) {
        this.oldPassword = event.target.value;
        this.errorMessage = ''; // Clear error when user types
    }
    
    handleNewPasswordChange(event) {
        this.newPassword = event.target.value;
        this.errorMessage = ''; // Clear error when user types
    }
    
    handleVerifyPasswordChange(event) {
        this.verifyNewPassword = event.target.value;
        this.errorMessage = ''; // Clear error when user types
    }
    
    async handleSubmit(event) {
        event.preventDefault();
        
        // Clear previous errors
        this.errorMessage = '';
        
        // Client-side validation
        if (!this.isPasswordExpired && !this.oldPassword) {
            this.errorMessage = 'Old password is required.';
            this.showErrorToast('Validation Error', 'Old password is required.');
            return;
        }
        
        if (!this.newPassword) {
            this.errorMessage = 'New password is required.';
            this.showErrorToast('Validation Error', 'New password is required.');
            return;
        }
        
        if (!this.verifyNewPassword) {
            this.errorMessage = 'Please verify your new password.';
            this.showErrorToast('Validation Error', 'Please verify your new password.');
            return;
        }
        
        if (this.newPassword !== this.verifyNewPassword) {
            this.errorMessage = 'New password and verify password must match.';
            this.showErrorToast('Validation Error', 'New password and verify password must match.');
            return;
        }
        
        // Check password requirements (at least 10 characters)
        if (this.newPassword.length < 10) {
            this.errorMessage = 'Password must be at least 10 characters long.';
            this.showErrorToast('Validation Error', 'Password must be at least 10 characters long.');
            return;
        }
        
        this.isLoading = true;
        
        try {
            const result = await changePassword({
                newPassword: this.newPassword,
                verifyNewPassword: this.verifyNewPassword,
                oldPassword: this.isPasswordExpired ? null : this.oldPassword
            });
            
            if (result.success) {
                // Show success message
                this.showSuccessToast('Success', 'Your password has been changed successfully.');
                
                // Redirect after a short delay
                if (result.redirectUrl) {
                    setTimeout(() => {
                        window.location.href = result.redirectUrl;
                    }, 1500);
                } else {
                    // Navigate to Home page
                    setTimeout(() => {
                        this.navigateToHome();
                    }, 1500);
                }
            } else {
                this.errorMessage = result.error || 'Password change failed. Please try again.';
                this.showErrorToast('Password Change Failed', this.errorMessage);
            }
        } catch (error) {
            console.error('Error changing password:', error);
            const errorMsg = error.body?.message || error.message || 'An error occurred while changing your password. Please try again.';
            this.errorMessage = errorMsg;
            this.showErrorToast('Error', errorMsg);
        } finally {
            this.isLoading = false;
        }
    }
    
    navigateToHome() {
        try {
            const pageRef = {
                type: 'comm__namedPage',
                attributes: {
                    name: 'Home'
                }
            };
            
            const navPromise = this[NavigationMixin.Navigate](pageRef);
            
            if (navPromise && typeof navPromise === 'object' && typeof navPromise.then === 'function') {
                navPromise.catch(error => {
                    console.error('[CHANGE PASSWORD] Navigation to Home failed:', error);
                    // Fallback: redirect to /s/
                    window.location.href = '/s/';
                });
            } else {
                // Fallback: redirect to /s/
                window.location.href = '/s/';
            }
        } catch (navError) {
            console.error('[CHANGE PASSWORD] Error during navigation:', navError);
            // Fallback: redirect to /s/
            window.location.href = '/s/';
        }
    }
    
    showSuccessToast(title, message) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: 'success',
            mode: 'dismissable'
        });
        this.dispatchEvent(evt);
    }
    
    showErrorToast(title, message) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: 'error',
            mode: 'sticky'
        });
        this.dispatchEvent(evt);
    }
    
    get showOldPasswordField() {
        return !this.isPasswordExpired;
    }
    
    handleImageError(event) {
        // Hide image if it fails to load
        if (event.target) {
            event.target.style.display = 'none';
        }
    }
}

