import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { getRecord } from 'lightning/uiRecordApi';

const FIELDS = ['Account.Id', 'Account.Name'];

export default class LscMobileInline_ParentInfo extends NavigationMixin(LightningElement) {
    @api objectApiName;
    @api recordId;
    @api mobileHeight;
    
    parentAccountId;
    parentAccount;
    parentAddressData;
    parentAddress;
    error;
    loading = true;
    
    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'HealthcareProviders',
        fields: ['HealthcareProvider.Id', 'HealthcareProvider.ParentOrganizationAccountId', 'HealthcareProvider.Name', 'HealthcareProvider.CreatedDate']
    })
    wiredHealthcareProviders({ error, data }) {
        if (data) {
            this.processHealthcareProviders(data);
        } else if (error) {
            this.error = 'Error fetching HealthcareProvider records: ' + error.body.message;
            this.loading = false;
        }
    }
    
    @wire(getRecord, { recordId: '$parentAccountId', fields: FIELDS })
    wiredParentAccount({ error, data }) {
        if (data) {
            this.parentAccount = data;
            this.fetchParentContactPointAddress();
        } else if (error) {
            this.error = 'Error fetching Parent Account: ' + error.body.message;
            this.loading = false;
        }
    }
    
    @wire(getRelatedListRecords, {
        parentRecordId: '$parentAccountId',
        relatedListId: 'ContactPointAddresses',
        fields: [
            'ContactPointAddress.Id', 
            'ContactPointAddress.FullAddress', 
            'ContactPointAddress.CreatedDate'
        ],
        sortBy: ['ContactPointAddress-CreatedDate']
    })
    wiredContactPointAddresses({ error, data }) {
        if (data) {
            this.parentAddressData = data;
            this.processContactPointAddresses();
        } else if (error && this.parentAccountId) {
            console.error('Error loading contact point addresses:', error);
            // Continue even if addresses fail to load
            this.loading = false;
        }
    }
    
    processHealthcareProviders(data) {
        if (data && data.records && data.records.length > 0) {
            // Sort by CreatedDate (descending) and take the latest
            const sortedProviders = [...data.records];
            sortedProviders.sort((a, b) => {
                const dateA = new Date(a.fields.CreatedDate.value);
                const dateB = new Date(b.fields.CreatedDate.value);
                return dateB - dateA;
            });
            
            // Use the latest provider
            const latestProvider = sortedProviders[0];
            
            // Check if there's a parent org account ID
            if (latestProvider.fields.ParentOrganizationAccountId.value) {
                this.parentAccountId = latestProvider.fields.ParentOrganizationAccountId.value;
            } else {
                this.loading = false;
            }
        } else {
            this.loading = false;
        }
    }
    
    processContactPointAddresses() {
        if (this.parentAddressData && 
            this.parentAddressData.records && 
            this.parentAddressData.records.length > 0) {
            
            // Get the most recent address (already sorted by CreatedDate in wire service)
            const latestAddress = this.parentAddressData.records[0];
            
            if (latestAddress.fields.FullAddress && latestAddress.fields.FullAddress.value) {
                this.parentAddress = latestAddress.fields.FullAddress.value;
            }
        }
        
        this.loading = false;
    }
    
    fetchParentContactPointAddress() {
        // This method exists to handle sequencing if needed
        // The actual fetching is done by the wire service
    }
    
    navigateToParentAccount() {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.parentAccountId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }
    
    get hasParentAccount() {
        return this.parentAccount && this.parentAccount.fields.Id.value;
    }
    
    get parentAccountName() {
        return this.hasParentAccount ? this.parentAccount.fields.Name.value : '';
    }
    
    get hasParentAddress() {
        return this.parentAddress ? true : false;
    }
    
    get hasError() {
        return this.error ? true : false;
    }
}