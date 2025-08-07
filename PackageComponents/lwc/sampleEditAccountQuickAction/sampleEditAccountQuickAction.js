import { LightningElement, api } from 'lwc';

export default class LightningRecordFormDemo extends LightningElement {
    fields = ["Name", "Phone", "Email"];

    @api recordId;
    @api objectApiName = 'Account';
}