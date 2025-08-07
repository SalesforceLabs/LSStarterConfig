import {  LightningElement, api } from "lwc";
import { getBarcodeScanner } from "lightning/mobileCapabilities";

export default class LscMobileInline_SimpleWidget extends LightningElement {
    @api mobileHeight;
    @api objectApiName;
    @api recordId;

    barcodeScanner;
    @api isBarcodeScannerAvailable;
    @api scannedBarcodes;
  
    connectedCallback() {
      this.barcodeScanner = getBarcodeScanner();
      this.isBarcodeScannerAvailable = this.barcodeScanner != null && this.barcodeScanner.isAvailable();
    }

    isScanningDisabled() {
      return !this.isBarcodeScannerAvailable;
    }
  
    beginScanning() {
      // Set your configuration options, including bulk and multi-scanning if desired, in this scanningOptions object
      const scanningOptions = {
        barcodeTypes: [this.barcodeScanner.barcodeTypes.QR],
        scannerSize: "FULLSCREEN",
        cameraFacing: "BACK",
        showSuccessCheckMark: true,
        enableBulkScan: true,
        enableMultiScan: true,
      };
  
      // Make sure BarcodeScanner is available before trying to use it
      if (this.barcodeScanner != null && this.barcodeScanner.isAvailable()) {
        // Reset scannedBarcodes before starting new scanning session
        this.scannedBarcodes = [];
        // Start scanning barcodes
        this.barcodeScanner
          .scan(scanningOptions)
          .then((results) => {
            this.processScannedBarcodes(results);
          })
          .catch((error) => {
            this.processError(error);
          })
          .finally(() => {
            this.barcodeScanner.dismiss();
          });
      } else {
        console.log("BarcodeScanner unavailable. Non-mobile device?");
      }
    }
  
    processScannedBarcodes(barcodes) {
      // Do something with the barcode scan value:
      // - look up a record
      // - create or update a record
      // - parse data and put values into a form
      // - and so on; this is YOUR code
      console.log(JSON.stringify(barcodes));
      this.scannedBarcodes = this.scannedBarcodes.concat(barcodes);
    }
  
    processError(error) {
      // Check to see if user ended scanning
      if (error.code == "USER_DISMISSED") {
        console.log("User terminated scanning session.");
      } else {
        console.error(error);
      }
    }
  
    get scannedBarcodesAsString() {
      return this.scannedBarcodes.map((barcode) => barcode.value).join("\n");
    }
}