import { LightningElement,api } from 'lwc';

export default class AutoScroll extends LightningElement {
    @api mobileHeight;
    @api objectApiName;
    @api recordId;
}
