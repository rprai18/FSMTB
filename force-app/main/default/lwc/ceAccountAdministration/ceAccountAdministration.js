import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadStyle } from 'lightning/platformResourceLoader';
import { NavigationMixin } from 'lightning/navigation';
import portalImages from '@salesforce/resourceUrl/Portal_Images';
import getAdministrationData from '@salesforce/apex/CommunityAdministrationLwcController.getAdministrationData';
import saveUser from '@salesforce/apex/CommunityAdministrationLwcController.saveUser';
import removeUser from '@salesforce/apex/CommunityAdministrationLwcController.removeUser';
import resetPassword from '@salesforce/apex/CommunityAdministrationLwcController.resetPassword';
import updateAccount from '@salesforce/apex/CommunityAdministrationLwcController.updateAccount';

export default class CeAccountAdministration extends NavigationMixin(LightningElement) {
    
    @track isLoading = true;
    @track error;
    
    @track accountId;
    @track siteName = 'CE_Registry';
    @track account;
    @track activeUsers = [];
    @track inactiveUsers = [];
    @track maximumNumberOfUsers = 3;
    @track profileOptions = [];
    @track currentMembership;
    @track nextMembership;
    @track statePicklist = [];
    @track currentUserId; // ID of the currently logged-in user
    @track contactRecordTypeId; // RecordType ID for CE_Provider_User Contact
    
    @track contentAddUser = '';
    @track contentEditUser = '';
    @track contentUpdateAccount = '';
    @track allowFeedbackAccess = false;
    @track showRenewalPopup = false;
    @track renewalDaysRemaining = 0;
    
    // Modal states
    @track showUserModal = false;
    @track showInactivateModal = false;
    @track showActivateModal = false;
    @track showRemoveModal = false;
    @track showResetPasswordModal = false;
    @track showUpdateAccountModal = false;
    
    @track isNewUser = true;
    @track modifyingUserId;
    @track modifyingUsername = '';
    
    // User form fields
    @track userFirstName = '';
    @track userLastName = '';
    @track userUsername = '';
    @track userEmail = '';
    @track userPhone = '';
    @track userTitle = '';
    @track selectedProfileId;
    @track showRosterEmailCheckbox = true;
    @track ceRegistryAlert = false;
    
    // Account form fields
    @track accountName = '';
    @track accountEmail = '';
    @track accountStreet = '';
    @track accountCity = '';
    @track accountState = '';
    @track accountPostalCode = '';
    @track accountPhone = '';
    @track accountFax = '';
    @track accountWebsite = '';
    
    // Error flags
    @track displayFirstNameError = false;
    @track displayLastNameError = false;
    @track displayUsernameError = false;
    @track displayUsernameUsedError = false;
    @track displayUsernameFormatError = false;
    @track displayEmailError = false;
    @track displayPhoneError = false;
    @track displayBusinessEmailError = false;
    @track displayStreetError = false;
    @track displayCityError = false;
    @track displayPostalCodeError = false;
    @track displayBusinessPhoneError = false;
    
    // Static resource images
    portalImages = portalImages;
    headerImage0 = portalImages + '/FSMTB_header0.png';
    
    // Columns for data tables
    activeUserColumns = [
        { label: 'Username', fieldName: 'username', type: 'text' },
        { label: 'First Name', fieldName: 'firstName', type: 'text' },
        { label: 'Last Name', fieldName: 'lastName', type: 'text' },
        { label: 'Email', fieldName: 'email', type: 'email' },
        { label: 'Title', fieldName: 'title', type: 'text' },
        { label: 'Phone', fieldName: 'phone', type: 'phone' },
        { label: 'Permissions', fieldName: 'profileName', type: 'text' },
        { label: 'CE Registry Alert', fieldName: 'ceRegistryAlert', type: 'boolean' },
        { label: 'Actions', type: 'action', typeAttributes: { rowActions: [] } }
    ];
    
    inactiveUserColumns = [
        { label: 'Username', fieldName: 'username', type: 'text' },
        { label: 'First Name', fieldName: 'firstName', type: 'text' },
        { label: 'Last Name', fieldName: 'lastName', type: 'text' },
        { label: 'Email', fieldName: 'email', type: 'email' },
        { label: 'Title', fieldName: 'title', type: 'text' },
        { label: 'Phone', fieldName: 'phone', type: 'phone' },
        { label: 'Permissions', fieldName: 'profileName', type: 'text' },
        { label: 'Actions', type: 'action', typeAttributes: { rowActions: [] } }
    ];
    
    connectedCallback() {
        this.loadData();
        
        // Load portal CSS styles
        loadStyle(this, '/resource/FSMTBAssets/FSMTBAssets/css/global.css')
            .catch(error => {
                console.error('Error loading portal styles:', error);
            });
    }
    
    loadData() {
        // Clear existing data to force a fresh refresh
        this.activeUsers = [];
        this.inactiveUsers = [];
        this.account = null;
        this.currentMembership = null;
        this.nextMembership = null;
        this.error = null;
        
        this.isLoading = true;
        getAdministrationData()
            .then(result => {
                this.accountId = result.accountId;
                this.siteName = result.siteName || 'CE_Registry';
                this.account = result.account;
                this.activeUsers = result.activeUsers || [];
                this.inactiveUsers = result.inactiveUsers || [];
                this.maximumNumberOfUsers = result.maximumNumberOfUsers || 3;
                
                // Find current user ID from the user list
                const allUsers = [...this.activeUsers, ...this.inactiveUsers];
                const currentUser = allUsers.find(u => u.isCurrentUser === true);
                this.currentUserId = currentUser ? currentUser.id : null;
                // Format profile options for lightning-combobox
                this.profileOptions = (result.profileOptions || []).map(profile => ({
                    label: profile.label,
                    value: profile.value
                }));
                this.currentMembership = result.currentMembership;
                this.nextMembership = result.nextMembership;
                // Format state picklist for lightning-combobox
                this.statePicklist = (result.statePicklist || []).map(state => ({
                    label: state.label,
                    value: state.value
                }));
                this.contentAddUser = result.contentAddUser || '';
                this.contentEditUser = result.contentEditUser || '';
                this.contentUpdateAccount = result.contentUpdateAccount || '';
                this.allowFeedbackAccess = result.allowFeedbackAccess || false;
                this.contactRecordTypeId = result.contactRecordTypeId;
                this.showRenewalPopup = result.showRenewalPopup || false;
                this.renewalDaysRemaining = result.renewalDaysRemaining || 0;
                
                // Set account form fields
                if (this.account) {
                    this.accountName = this.account.Name || '';
                    this.accountEmail = this.account.Email__c || '';
                    this.accountStreet = this.account.BillingStreet || '';
                    this.accountCity = this.account.BillingCity || '';
                    this.accountState = this.account.BillingStateCode || '';
                    this.accountPostalCode = this.account.BillingPostalCode || '';
                    this.accountPhone = this.account.Phone || '';
                    this.accountFax = this.account.Fax || '';
                    this.accountWebsite = this.account.Website || '';
                }
                
                // Set content HTML
                if (this.contentAddUser) {
                    setTimeout(() => {
                        const contentEl = this.template.querySelector('.content-add-user');
                        if (contentEl) {
                            contentEl.innerHTML = this.contentAddUser;
                        }
                    }, 0);
                }
                
                if (this.contentEditUser) {
                    setTimeout(() => {
                        const contentEl = this.template.querySelector('.content-edit-user');
                        if (contentEl) {
                            contentEl.innerHTML = this.contentEditUser;
                        }
                    }, 0);
                }
                
                if (this.contentUpdateAccount) {
                    setTimeout(() => {
                        const contentEl = this.template.querySelector('.content-update-account');
                        if (contentEl) {
                            contentEl.innerHTML = this.contentUpdateAccount;
                        }
                    }, 0);
                }
                
                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error loading data:', error);
                this.error = error.body?.message || error.message || 'An error occurred loading administration data.';
                this.isLoading = false;
                this.showToast('Error', this.error, 'error');
            });
    }
    
    // Getters
    get activeUserCount() {
        return this.activeUsers ? this.activeUsers.length : 0;
    }
    
    get canAddUser() {
        return this.activeUserCount < this.maximumNumberOfUsers;
    }
    
    get cannotAddUser() {
        return !this.canAddUser;
    }
    
    get usersUsedText() {
        if (this.isSlbPortal) {
            return `Your account has a limit of ${this.maximumNumberOfUsers} users (SLB Max Portal Users). You are currently using ${this.activeUserCount} of ${this.maximumNumberOfUsers} active users.`;
        }
        const email = this.siteName === 'CE_Registry' ? 'CE@fsmtb.org' : 'MLVC@fsmtb.org';
        const subject = this.siteName === 'CE_Registry' ? 
            `${this.account?.Name} CE Registry -- Request to allocate more users.` :
            `${this.account?.Name} Massage License Verification Center -- Request to allocate more users.`;
        return `Your organization is currently using ${this.activeUserCount} of ${this.maximumNumberOfUsers} allotted users. You may request more users by contacting FSMTB at <a href="mailto:${email}?subject=${encodeURIComponent(subject)}">${email}</a>.`;
    }
    
    renderedCallback() {
        // Set users used text in DOM
        const usersUsedEl = this.template.querySelector('.users-used-note');
        if (usersUsedEl && this.usersUsedText) {
            usersUsedEl.innerHTML = this.usersUsedText;
        }
        
        // Render Add User content
        if (this.contentAddUser) {
            const addUserDiv = this.template.querySelector('.content-add-user');
            if (addUserDiv) {
                addUserDiv.innerHTML = this.contentAddUser;
            }
        }
        
        // Render Edit User content
        if (this.contentEditUser) {
            const editUserDiv = this.template.querySelector('.content-edit-user');
            if (editUserDiv) {
                editUserDiv.innerHTML = this.contentEditUser;
            }
        }
        
        // Render Update Account content
        if (this.contentUpdateAccount) {
            const updateAccountDiv = this.template.querySelector('.content-update-account');
            if (updateAccountDiv) {
                updateAccountDiv.innerHTML = this.contentUpdateAccount;
            }
        }
    }
    
    get hasCurrentMembership() {
        return this.currentMembership != null;
    }
    
    get hasNextMembership() {
        return this.nextMembership != null;
    }
    
    get showRosterEmailCheckboxComputed() {
        if (this.isSlbPortal) return false;
        if (this.selectedProfileId && this.profileOptions) {
            const selectedProfile = this.profileOptions.find(p => p.value === this.selectedProfileId);
            if (selectedProfile) {
                return selectedProfile.label !== 'CE Courses Only' && this.siteName !== 'Massage_License_Verification_Center';
            }
        }
        return this.showRosterEmailCheckbox;
    }
    
    get isEditModeDisabled() {
        // If editing current user, disable some fields
        return this.modifyingUserId && this.modifyingUserId === this.currentUserId;
    }
    
    get isEditUserDisabled() {
        // Portal owner cannot be edited by themselves
        if (this.modifyingUserId) {
            const user = [...this.activeUsers, ...this.inactiveUsers].find(u => u.id === this.modifyingUserId);
            return user && user.isPortalOwner;
        }
        return false;
    }
    
    get usernamePlaceholder() {
        return this.siteName === 'Massage_License_Verification_Center' ? 'example@email.com' : '';
    }
    
    get isCERegistry() {
        return this.siteName === 'CE_Registry' || this.siteName === 'CE Registry';
    }
    
    get isMassageLicenseVerificationCenter() {
        return this.siteName === 'Massage_License_Verification_Center';
    }
    
    get isSlbPortal() {
        if (typeof window === 'undefined' || !window.location || !window.location.pathname) return false;
        return window.location.pathname.indexOf('slbportal') !== -1;
    }
    
    get headerSectionClass() {
        return this.isSlbPortal ? 'header-section header-section--slb' : 'header-section';
    }
    
    get showRenewButton() {
        // Show Renew button when: no current membership OR (current membership expires in < 60 days AND no next membership)
        if (!this.hasCurrentMembership) {
            return true;
        }
        
        if (this.currentMembership && this.currentMembership.Expiration_Date__c && !this.hasNextMembership) {
            const expirationDate = new Date(this.currentMembership.Expiration_Date__c);
            const today = new Date();
            const daysDiff = Math.ceil((expirationDate - today) / (1000 * 60 * 60 * 24));
            return daysDiff < 60;
        }
        
        return false;
    }
    
    get showRenewalMessage() {
        // Show message when no current membership
        return !this.hasCurrentMembership;
    }
    
    get renewalMessage() {
        if (!this.hasCurrentMembership && this.account && this.isCERegistry) {
            return `Your account, ${this.account.Name || ''}, has expired. Please renew your account for access to site features and to post your courses on www.fsmtb.org`;
        } else if (!this.hasCurrentMembership && this.account && !this.isCERegistry) {
            return `Your account, ${this.account.Name || ''}, has expired. Please renew your account for access to site features.`;
        }
        return '';
    }
    
    formatDate(dateValue) {
        if (!dateValue) return '';
        const date = new Date(dateValue);
        if (isNaN(date.getTime())) return '';
        return date.toLocaleDateString('en-US', { 
            year: 'numeric', 
            month: '2-digit', 
            day: '2-digit' 
        });
    }
    
    get currentMembershipStartDate() {
        return this.formatDate(this.currentMembership?.Start_Date__c);
    }
    
    get currentMembershipExpirationDate() {
        return this.formatDate(this.currentMembership?.Expiration_Date__c);
    }
    
    get nextMembershipStartDate() {
        return this.formatDate(this.nextMembership?.Start_Date__c);
    }
    
    get nextMembershipExpirationDate() {
        return this.formatDate(this.nextMembership?.Expiration_Date__c);
    }
    
    formatCurrency(value) {
        if (value == null || value === undefined) return '';
        return new Intl.NumberFormat('en-US', {
            style: 'currency',
            currency: 'USD'
        }).format(value);
    }
    
    get currentMembershipCost() {
        return this.formatCurrency(this.currentMembership?.Cost__c);
    }
    
    get nextMembershipCost() {
        return this.formatCurrency(this.nextMembership?.Cost__c);
    }
    
    // User Management Handlers
    handleAddUser() {
        if (!this.canAddUser) {
            this.showToast('Error', 'There are too many active users!', 'error');
            return;
        }
        
        this.isNewUser = true;
        this.modifyingUserId = null;
        this.clearUserForm();
        this.clearErrors();
        this.showUserModal = true;
    }
    
    handleEditUser(event) {
        const userId = event.currentTarget.dataset.userid;
        const user = [...this.activeUsers, ...this.inactiveUsers].find(u => u.id === userId);
        
        if (user) {
            this.isNewUser = false;
            this.modifyingUserId = user.id;
            this.modifyingUsername = user.username;
            this.userFirstName = user.firstName || '';
            this.userLastName = user.lastName || '';
            this.userUsername = user.username || '';
            this.userEmail = user.email || '';
            this.userPhone = user.phone || '';
            this.userTitle = user.title || '';
            this.selectedProfileId = user.profileId;
            this.ceRegistryAlert = user.ceRegistryAlert || false;
            this.clearErrors();
            this.showUserModal = true;
            
            // Update checkbox display based on profile
            this.updateRosterEmailCheckboxDisplay();
        }
    }
    
    handleRemoveUser(event) {
        const userId = event.currentTarget.dataset.userid;
        const user = this.inactiveUsers.find(u => u.id === userId);
        
        if (user) {
            this.modifyingUserId = user.id;
            this.modifyingUsername = user.username;
            this.showRemoveModal = true;
        }
    }
    
    handleRemoveConfirm() {
        this.isLoading = true;
        removeUser({ userId: this.modifyingUserId })
            .then(result => {
                if (result === 'SUCCESS') {
                    this.showToast('Success', 'User removed successfully', 'success');
                    this.closeAllModals();
                    // Reload data after a short delay to ensure modal is closed
                    setTimeout(() => {
                        this.loadData();
                    }, 100);
                } else {
                    this.showToast('Error', result.replace('ERROR: ', ''), 'error');
                    this.isLoading = false;
                }
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || error.message, 'error');
                this.isLoading = false;
            });
    }
    
    handleResetPassword(event) {
        const userId = event.currentTarget.dataset.userid;
        const user = this.activeUsers.find(u => u.id === userId);
        
        if (user) {
            this.modifyingUserId = user.id;
            this.modifyingUsername = user.username;
            this.showResetPasswordModal = true;
        }
    }
    
    handleResetPasswordConfirm() {
        this.isLoading = true;
        resetPassword({ userId: this.modifyingUserId })
            .then(result => {
                if (result === 'SUCCESS') {
                    this.showToast('Success', 'Password reset email sent successfully', 'success');
                    this.closeAllModals();
                    this.isLoading = false;
                } else {
                    this.showToast('Error', result.replace('ERROR: ', ''), 'error');
                    this.isLoading = false;
                }
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || error.message, 'error');
                this.isLoading = false;
            });
    }
    
    // User Form Handlers
    handleUserFirstNameChange(event) {
        const value = event.detail ? event.detail.value : event.target.value;
        this.userFirstName = value || '';
        this.displayFirstNameError = false;
        console.log('[CE ACCOUNT ADMIN] First name changed to:', this.userFirstName);
    }
    
    handleUserLastNameChange(event) {
        const value = event.detail ? event.detail.value : event.target.value;
        this.userLastName = value || '';
        this.displayLastNameError = false;
        console.log('[CE ACCOUNT ADMIN] Last name changed to:', this.userLastName);
    }
    
    handleUserUsernameChange(event) {
        const value = event.detail ? event.detail.value : event.target.value;
        this.userUsername = value || '';
        this.displayUsernameError = false;
        this.displayUsernameUsedError = false;
        this.displayUsernameFormatError = false;
        console.log('[CE ACCOUNT ADMIN] Username changed to:', this.userUsername);
    }
    
    handleUserEmailChange(event) {
        const value = event.detail ? event.detail.value : event.target.value;
        this.userEmail = value || '';
        this.displayEmailError = false;
        console.log('[CE ACCOUNT ADMIN] Email changed to:', this.userEmail);
    }
    
    handleUserPhoneChange(event) {
        const value = event.detail ? event.detail.value : event.target.value;
        this.userPhone = value || '';
        this.displayPhoneError = false;
        console.log('[CE ACCOUNT ADMIN] Phone changed to:', this.userPhone);
    }
    
    handleUserTitleChange(event) {
        const value = event.detail ? event.detail.value : event.target.value;
        this.userTitle = value || '';
        console.log('[CE ACCOUNT ADMIN] Title changed to:', this.userTitle);
    }
    
    handleProfileChange(event) {
        this.selectedProfileId = event.detail.value;
        this.updateRosterEmailCheckboxDisplay();
    }
    
    handleCeRegistryAlertChange(event) {
        this.ceRegistryAlert = event.detail.checked;
    }
    
    updateRosterEmailCheckboxDisplay() {
        if (this.selectedProfileId && this.profileOptions) {
            const selectedProfile = this.profileOptions.find(p => p.value === this.selectedProfileId);
            if (selectedProfile) {
                this.showRosterEmailCheckbox = selectedProfile.label !== 'CE Courses Only' && 
                                               this.siteName !== 'Massage_License_Verification_Center';
            }
        }
    }
    
    handleSaveUser() {
        this.clearErrors();
        
        // Client-side validation - check if form fields are filled
        let hasErrors = false;
        
        // Validate required fields
        if (!this.userFirstName || this.userFirstName.trim() === '') {
            this.displayFirstNameError = true;
            hasErrors = true;
        }
        if (!this.userLastName || this.userLastName.trim() === '') {
            this.displayLastNameError = true;
            hasErrors = true;
        }
        if (this.isNewUser && (!this.userUsername || this.userUsername.trim() === '')) {
            this.displayUsernameError = true;
            hasErrors = true;
        }
        if (!this.userEmail || this.userEmail.trim() === '') {
            this.displayEmailError = true;
            hasErrors = true;
        } else {
            // Validate email format
            const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
            if (!emailRegex.test(this.userEmail.trim())) {
                this.displayEmailError = true;
                hasErrors = true;
            }
        }
        if (!this.userPhone || this.userPhone.trim() === '') {
            this.displayPhoneError = true;
            hasErrors = true;
        }
        if (!this.selectedProfileId) {
            hasErrors = true;
        }
        
        if (hasErrors) {
            this.showToast('Error', 'Please fill in all required fields correctly.', 'error');
            return;
        }
        
        // Also validate using native HTML5 validation
        const inputs = this.template.querySelectorAll('lightning-input[required], lightning-combobox[required]');
        let allValid = true;
        inputs.forEach(input => {
            if (typeof input.reportValidity === 'function') {
                if (!input.reportValidity()) {
                    allValid = false;
                }
            }
        });
        
        if (!allValid) {
            this.showToast('Error', 'Please fix the validation errors in the form.', 'error');
            return;
        }
        
        // Prepare user data - ensure we're using trimmed values and handle null/undefined
        // Use tracked properties directly (they should be updated via onchange handlers)
        const userData = {
            id: this.modifyingUserId || null,
            firstName: String(this.userFirstName || '').trim(),
            lastName: String(this.userLastName || '').trim(),
            username: String(this.userUsername || '').trim(),
            email: String(this.userEmail || '').trim(),
            phone: String(this.userPhone || '').trim(),
            title: String(this.userTitle || '').trim(),
            ceRegistryAlert: this.ceRegistryAlert || false
        };
        
        console.log('[CE ACCOUNT ADMIN] Saving user with data:', JSON.stringify(userData, null, 2));
        console.log('[CE ACCOUNT ADMIN] Raw form values:', {
            userFirstName: this.userFirstName,
            userLastName: this.userLastName,
            userUsername: this.userUsername,
            userEmail: this.userEmail,
            userPhone: this.userPhone,
            userTitle: this.userTitle,
            isNewUser: this.isNewUser,
            selectedProfileId: this.selectedProfileId
        });
        
        this.isLoading = true;
        // Send as JSON string to avoid deserialization issues
        saveUser({ 
            userDataJson: JSON.stringify(userData), 
            isNewUser: this.isNewUser, 
            selectedProfileId: this.selectedProfileId 
        })
            .then(result => {
                console.log('[CE ACCOUNT ADMIN] Apex result:', result);
                if (result === 'SUCCESS' || result.startsWith('SUCCESS')) {
                    this.showToast('Success', 'User saved successfully', 'success');
                    this.closeAllModals();
                    // Reload data after a short delay to ensure modal is closed and UI is ready
                    setTimeout(() => {
                        this.loadData();
                    }, 100);
                } else {
                    const errorMessage = result.replace('ERROR: ', '');
                    console.log('[CE ACCOUNT ADMIN] Error message from Apex:', errorMessage);
                    this.parseUserErrors(errorMessage);
                    // Show full error message including debug info
                    this.showToast('Error', errorMessage, 'error');
                    this.isLoading = false;
                }
            })
            .catch(error => {
                console.error('[CE ACCOUNT ADMIN] Error saving user:', error);
                this.showToast('Error', error.body?.message || error.message, 'error');
                this.isLoading = false;
            });
    }
    
    parseUserErrors(errorMessage) {
        if (errorMessage.includes('First name is required')) {
            this.displayFirstNameError = true;
        }
        if (errorMessage.includes('Last name is required')) {
            this.displayLastNameError = true;
        }
        if (errorMessage.includes('Username is required')) {
            this.displayUsernameError = true;
        }
        if (errorMessage.includes('Username is already being used')) {
            this.displayUsernameUsedError = true;
        }
        if (errorMessage.includes('Username cannot be formatted') || errorMessage.includes('Username is not formatted')) {
            this.displayUsernameFormatError = true;
        }
        if (errorMessage.includes('email is required') || errorMessage.includes('email address')) {
            this.displayEmailError = true;
        }
        if (errorMessage.includes('Telephone number is required')) {
            this.displayPhoneError = true;
        }
    }
    
    // Account Update Handlers
    handleUpdateAccount() {
        this.clearErrors();
        this.showUpdateAccountModal = true;
    }
    
    handleAccountEmailChange(event) {
        this.accountEmail = event.detail.value;
        this.displayBusinessEmailError = false;
    }
    
    handleAccountStreetChange(event) {
        this.accountStreet = event.detail.value;
        this.displayStreetError = false;
    }
    
    handleAccountCityChange(event) {
        this.accountCity = event.detail.value;
        this.displayCityError = false;
    }
    
    handleAccountStateChange(event) {
        this.accountState = event.detail.value;
    }
    
    handleAccountPostalCodeChange(event) {
        this.accountPostalCode = event.detail.value;
        this.displayPostalCodeError = false;
    }
    
    handleAccountPhoneChange(event) {
        this.accountPhone = event.detail.value;
        this.displayBusinessPhoneError = false;
    }
    
    handleAccountFaxChange(event) {
        this.accountFax = event.detail.value;
    }
    
    handleAccountWebsiteChange(event) {
        this.accountWebsite = event.detail.value;
    }
    
    handleSaveAccount() {
        this.clearErrors();
        
        const accountToUpdate = {
            Id: this.accountId,
            Email__c: this.accountEmail,
            BillingStreet: this.accountStreet,
            BillingCity: this.accountCity,
            BillingStateCode: this.accountState,
            BillingPostalCode: this.accountPostalCode,
            Phone: this.accountPhone,
            Fax: this.accountFax,
            Website: this.accountWebsite
        };
        
        this.isLoading = true;
        updateAccount({ account: accountToUpdate })
            .then(result => {
                if (result === 'SUCCESS') {
                    this.showToast('Success', 'Account updated successfully', 'success');
                    this.closeAllModals();
                    // Reload data after a short delay to ensure modal is closed and UI is ready
                    setTimeout(() => {
                        this.loadData();
                    }, 100);
                } else {
                    const errorMessage = result.replace('ERROR: ', '');
                    this.parseAccountErrors(errorMessage);
                    this.showToast('Error', errorMessage, 'error');
                    this.isLoading = false;
                }
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || error.message, 'error');
                this.isLoading = false;
            });
    }
    
    parseAccountErrors(errorMessage) {
        if (errorMessage.includes('Business email') || errorMessage.includes('email address')) {
            this.displayBusinessEmailError = true;
        }
        if (errorMessage.includes('Address is required')) {
            this.displayStreetError = true;
        }
        if (errorMessage.includes('City is required')) {
            this.displayCityError = true;
        }
        if (errorMessage.includes('Zip code is required')) {
            this.displayPostalCodeError = true;
        }
        if (errorMessage.includes('Telephone number is required')) {
            this.displayBusinessPhoneError = true;
        }
    }
    
    // Purchased Survey Feedback Handler
    handlePurchasedSurveyRedirect() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'CEPurchaseFeedback__c' // API name of the community page for purchase feedback
            }
        }).catch(error => {
            console.error('[CE ACCOUNT ADMIN] Error navigating to Purchase Feedback:', error);
            // Fallback to window.location
            const currentUrl = new URL(window.location.href);
            const currentPath = currentUrl.pathname;
            const sIndex = currentPath.indexOf('/s/');
            if (sIndex !== -1) {
                const communityBase = currentPath.substring(0, sIndex + 3);
                window.location.href = `${currentUrl.origin}${communityBase}ce-purchase-feedback`;
            } else {
                window.location.href = `${currentUrl.origin}/CERegistryPortal/s/ce-purchase-feedback`;
            }
        });
    }

    // Navigate to General Provider Policies page
    handleEditGeneralPolicies() {
        try {
            this[NavigationMixin.Navigate]({
                type: 'comm__namedPage',
                attributes: {
                    name: 'CEGeneralProviderPolicies__c'
                }
            });
        } catch (error) {
            console.error('[CE ACCOUNT ADMIN] Error navigating to General Provider Policies:', error);
            this.showToast('Error', 'Unable to open General Provider Policies. Please try again.', 'error');
        }
    }
    
    // Renew Membership Handler - CE Registry: navigate to the renewal LWC page
    handleRenewMembership() {
        try {
            console.log('[CE ACCOUNT ADMIN] Navigating to renewal page');
            
            // Construct URL from current location
            const currentUrl = new URL(window.location.href);
            const currentPath = currentUrl.pathname;
            
            // Extract community base path (e.g., /CERegistryPortal/s/)
            let renewalUrl;
            const sIndex = currentPath.indexOf('/s/');
            if (sIndex !== -1) {
                const communityBase = currentPath.substring(0, sIndex + 3);
                renewalUrl = `${currentUrl.origin}${communityBase}ce-registry?paymentType=renewal`;
            } else {
                // Fallback: try to construct from known patterns
                renewalUrl = `${currentUrl.origin}/CERegistryPortal/s/ce-registry?paymentType=renewal`;
            }
            
            console.log('[CE ACCOUNT ADMIN] Navigating to:', renewalUrl);
            
            // Close renewal popup if open
            this.showRenewalPopup = false;
            
            // Use window.location for reliable navigation across all environments
            window.location.href = renewalUrl;
        } catch (error) {
            console.error('[CE ACCOUNT ADMIN] Error navigating to renewal page:', error);
            this.showToast('Error', 'Unable to start renewal. Please try again.', 'error');
        }
    }
    
    // Renewal Popup Handlers
    handleRenewalPopupRenew() {
        this.handleRenewMembership();
    }
    
    handleRenewalPopupNotNow() {
        this.showRenewalPopup = false;
    }
    
    // Helper Methods
    clearUserForm() {
        this.userFirstName = '';
        this.userLastName = '';
        this.userUsername = '';
        this.userEmail = '';
        this.userPhone = '';
        this.userTitle = '';
        this.selectedProfileId = null;
        this.ceRegistryAlert = false;
    }
    
    clearErrors() {
        this.displayFirstNameError = false;
        this.displayLastNameError = false;
        this.displayUsernameError = false;
        this.displayUsernameUsedError = false;
        this.displayUsernameFormatError = false;
        this.displayEmailError = false;
        this.displayPhoneError = false;
        this.displayBusinessEmailError = false;
        this.displayStreetError = false;
        this.displayCityError = false;
        this.displayPostalCodeError = false;
        this.displayBusinessPhoneError = false;
    }
    
    closeAllModals() {
        this.showUserModal = false;
        this.showInactivateModal = false;
        this.showActivateModal = false;
        this.showRemoveModal = false;
        this.showResetPasswordModal = false;
        this.showUpdateAccountModal = false;
        this.clearUserForm();
        this.clearErrors();
    }
    
    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(evt);
    }
}