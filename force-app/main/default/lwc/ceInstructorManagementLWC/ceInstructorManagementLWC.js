import { LightningElement, track, wire, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getInstructorsByStatus from '@salesforce/apex/CEInstructorMgmtLWCCtrl.getInstructorsByStatus';
import updateInstructorStatus from '@salesforce/apex/CEInstructorMgmtLWCCtrl.updateInstructorStatus';
import setRemoveFromView from '@salesforce/apex/CEInstructorMgmtLWCCtrl.setRemoveFromView';
import getCurrentUserAccountId from '@salesforce/apex/CEInstructorMgmtLWCCtrl.getCurrentUserAccountId';

export default class CeInstructorManagementLWC extends LightningElement {
    @track activeData = [];
    @track inactiveData = [];
    @track isEditOpen = false;
    @track isNewOpen = false;
    @track editingRecordId = null;

    @track accountId;
    statusVal = 'Active';

    label = {
        imHeader: 'Instructor Management',
        descOne: 'Instructors must be added before they can be added to a session. Instructor names must be unique. If you have two instructors with the same name, include their middle names or a value in the \'Also Known As\' field. The value in Also Known As will not show on the website with the listed course and session.',
        descTwo: 'If your instructor teaches at another provider, you must add them here for your provider.',
        activeInstLbl: 'Active Instructors',
        inactiveInsLbl: 'Inactive Instructors',
        editInstHeader: 'Edit Instructor',
        addNewInstHeader: 'Add New Instructor'
    }

    connectedCallback() {
        this.loadTables();
    }

    columns = [
        { label: 'Name', fieldName: 'Name', type: 'text' },
        { label: 'Status', fieldName: 'Status__c', type: 'text' },
        { label: 'First Name', fieldName: 'First_Name__c', type: 'text' },
        { label: 'Last Name', fieldName: 'Last_Name__c', type: 'text' },
        { label: 'Also Known As', fieldName: 'Also_Known_As__c', type: 'text' },
        {
            type: 'action',
            typeAttributes: { rowActions: this.getRowActions.bind(this) },
        },
    ];

    @wire(getCurrentUserAccountId)
    wiredAccountId({ error, data }) {
        if (data) {
            this.accountId = data;
        } else if (error) {
            console.log('Error fetching Account Id:', error);
        }
    }

    loadTables() {
        Promise.all([
            getInstructorsByStatus({ status: 'Active' }),
            getInstructorsByStatus({ status: 'Inactive' })
        ])
        .then(([active, inactive]) => {
            this.activeData = [...active];
            this.inactiveData = [...inactive];
        })
        .catch(error => {
            console.log('Error in loadTables:', error);
            this.showToast('Error', 'Failed to load instructors: ' + (error.body?.message || error.message), 'error');
        });
    }

    getRowActions(row, doneCallback) {
        const actions = [{ label: 'Edit', name: 'edit', iconName: 'utility:edit' }];
        if (row.Status__c === 'Active') {
            actions.push({ label: 'Deactivate', name: 'deactivate', iconName: 'utility:pause' });
        } else {
            actions.push({ label: 'Activate', name: 'activate', iconName: 'utility:play' });
        }
        actions.push({ label: 'Delete', name: 'delete', iconName: 'utility:delete' });
        doneCallback(actions);
    }

    handleRowAction(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;

        switch (action) {
            case 'edit':
                this.openEdit(row.Id);
                break;
            case 'deactivate':
                this.changeStatus([row.Id], 'Inactive');
                break;
            case 'activate':
                this.changeStatus([row.Id], 'Active');
                break;
            case 'delete':
                this.removeFromView(row.Id);
                break;
        }
    }

    removeFromView(instId) {
        setRemoveFromView({ instructorId: instId })
        .then(() => {
            this.showToast('Success', 'Instructor removed from view.', 'success');
            this.refreshAfterAction();
        })
        .catch(error => {
            this.showToast('Error', 'Remove from view failed: ' + (error.body?.message || error.message), 'error');
        });
    }

    changeStatus(ids, status) {
        updateInstructorStatus({ instructorIds: ids, newStatus: status })
        .then(() => {
            this.showToast('Success', `Status updated to ${status}`, 'success');
            this.loadTables();
        })
        .catch(error => {
            console.log('Error in changeStatus:', error);
            this.showToast('Error', 'Unable to update status: ' + (error.body?.message || error.message), 'error');
        });
    }

    handleNew() {
        this.isNewOpen = true;
    }

    closeNew() {
        this.isNewOpen = false;
    }

    handleNewSuccess() {
        this.showToast('Success', 'New Instructor created', 'success');
        this.closeNew();
        this.refreshAfterAction();
    }

    openEdit(recordId) {
        this.editingRecordId = recordId;
        this.isEditOpen = true;
    }

    closeEdit() {
        this.editingRecordId = null;
        this.isEditOpen = false;
    }

    handleEditSuccess() {
        this.showToast('Success', 'Record updated', 'success');
        this.closeEdit();
        this.refreshAfterAction();
    }

    refreshAfterAction() {
        Promise.all([
            getInstructorsByStatus({ status: 'Active' }),
            getInstructorsByStatus({ status: 'Inactive' })
        ])
        .then(([active, inactive]) => {
            this.activeData = JSON.parse(JSON.stringify(active));
            this.inactiveData = JSON.parse(JSON.stringify(inactive));
        })
        .catch(error => {
            console.log('Error in refreshAfterAction:', error);
            this.showToast('Error', 'Unable to refresh instructors list', 'error');
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    handleError(event) {
        const error = event.detail;
        console.error('Error in lightning-record-edit-form:', error);

        let errorMessage = 'An unknown error occurred.';
        if (error && error.message) {
            errorMessage = error.message;
        } else if (error && error.body && error.body.message) {
            errorMessage = error.body.message;
        } else if (error && Array.isArray(error.body)) {
            errorMessage = error.body.map(e => e.message).join('; ');
        }

        this.showToast('Error', errorMessage, 'error');
    }
}