import { LightningElement, api } from 'lwc';
import {
    FlowNavigationNextEvent,
    FlowNavigationFinishEvent
} from 'lightning/flowSupport';

export default class NavigationFooterForFlow extends LightningElement {
    @api availableActions = [];
    @api footerAction; // <-- Bound to Flow variable

    handleCancel() {
        if (this.availableActions.includes('FINISH')) {
            this.dispatchEvent(new FlowNavigationFinishEvent());
        }
    }

    handleSaveDraft() {
        this.footerAction = 'Draft';
        this.sendValueToFlow();
        this.goNext();
    }

    handleSubmit() {
        this.footerAction = 'Submit';
        this.sendValueToFlow();
        this.goNext();
    }

    sendValueToFlow() {
        // Notify Flow that the value has changed
        const valueChangedEvent = new CustomEvent('valuechange', {
            detail: { value: this.footerAction }
        });
        this.dispatchEvent(valueChangedEvent);
    }

    goNext() {
        if (this.availableActions.includes('NEXT')) {
            this.dispatchEvent(new FlowNavigationNextEvent());
        }
    }
}