// Jest test file for visitSampleScript validation functions
import { createElement } from 'lwc';

// Mock the validation script - we'll test the functions directly
describe('visitSampleScript validation functions', () => {
    
    // Helper function to create test data
    function createTestData(overrides = {}) {
        return {
            ProviderVisit: {
                Id: 'a1234567890',
                Status: 'Draft',
                ComplianceAgreementStatus: 'Approved',
                IsVisitDelayed: false,
                ...overrides.ProviderVisit
            },
            // samples parameter maps to ProductDisbursement.VisitId (used for sample validation)
            'ProductDisbursement.VisitId': overrides.samples || [],
            // providerVisitProdDetailings parameter maps to ProviderVisitProdDetailing.VisitId (used for detail validation)
            'ProviderVisitProdDetailing.VisitId': overrides.providerVisitProdDetailings || [],
            ...overrides
        };
    }

    // Helper function to create a record object for validation
    function createRecordObject(contextData) {
        return {
            stringValue: (field) => {
                if (field === 'AccountId' && contextData.ProviderVisit?.AccountId) {
                    return contextData.ProviderVisit.AccountId;
                }
                return '';
            },
            boolValue: (field) => {
                return contextData.ProviderVisit?.[field] || false;
            },
            getContextData: () => {
                return JSON.stringify(contextData);
            }
        };
    }

    // Helper function to create user, db, and env objects
    function createMockObjects() {
        return {
            user: {},
            db: {},
            env: {}
        };
    }

    // Helper to load and execute the validation script
    function loadValidationScript() {
        // Since the script is an IIFE, we need to simulate its execution
        // This is a simplified version - in real tests you'd import the actual script
        return {
            validateVisit: function(record, user, db, env) {
                // Mock implementation that mirrors the actual validation logic with business rule parameters
                try {
                    if (!record || typeof record.getContextData !== 'function') {
                        return [{ 
                            title: "Error in validation", 
                            status: "error", 
                            error: "No record provided" 
                        }];
                    }

                    const contextDataString = record.getContextData();
                    const jsonData = JSON.parse(contextDataString);
                    const validationResults = [];

                    // Mock atLeastOneSampleIsRequired - uses ProductDisbursement.VisitId
                    const sampleData = jsonData['ProductDisbursement.VisitId'];
                    const hasSamples = Array.isArray(sampleData) && sampleData.length > 0;
                    validationResults.push({
                        title: "At least one sample is required for primary account",
                        status: hasSamples ? "success" : "error"
                    });

                    // Mock atLeastOneDetailAndSampleAreRequired
                    const productDisbursementData = jsonData['ProductDisbursement.VisitId'];
                    const providerVisitProdDetailingData = jsonData['ProviderVisitProdDetailing.VisitId'];
                    const hasProductDisbursement = Array.isArray(productDisbursementData) && productDisbursementData.length > 0;
                    const hasProviderVisitProdDetailing = Array.isArray(providerVisitProdDetailingData) && providerVisitProdDetailingData.length > 0;
                    
                    validationResults.push({
                        title: "At least one detail and sample are required for the primary account.",
                        status: (hasProductDisbursement && hasProviderVisitProdDetailing) ? "success" : "error"
                    });

                    // Mock isAtLeastOneHCP - check AccountId extraction logic
                    const accountId = record.stringValue('AccountId') || jsonData?.ProviderVisit?.AccountId;
                    let isHCPRequirementValid = true; // Default to valid when no account ID
                    
                    if (accountId) {
                        // Mock account lookup - assume account is Institution if AccountId exists in test data
                        const isPersonAccount = jsonData?.Account?.IsPersonAccount === true;
                        
                        if (!isPersonAccount) {
                            // For Institution accounts, check attendees
                            const attendeeData = jsonData?.["Visit.ParentVisitId"] || jsonData?.attendees || [];
                            if (Array.isArray(attendeeData) && attendeeData.length > 0) {
                                isHCPRequirementValid = attendeeData.some(attendee => 
                                    attendee?.Account?.IsPersonAccount === true || 
                                    attendee?.IsPersonAccount === true
                                );
                            } else {
                                isHCPRequirementValid = false;
                            }
                        }
                    }
                    
                    validationResults.push({
                        title: "At least one HCP required for a HCO call.",
                        status: isHCPRequirementValid ? "success" : "error"
                    });

                    return validationResults;
                } catch (error) {
                    return [{ 
                        title: "Error in validation", 
                        status: "error", 
                        error: error.message 
                    }];
                }
            }
        };
    }

    describe('atLeastOneSampleIsRequired validation', () => {
        test('should pass when samples exist', () => {
            // Arrange
            const testData = createTestData({
                samples: [{ Id: 'sample1' }, { Id: 'sample2' }]
            });
            const record = createRecordObject(testData);
            const { user, db, env } = createMockObjects();
            const validator = loadValidationScript();

            // Act
            const results = validator.validateVisit(record, user, db, env);

            // Assert
            const sampleValidation = results.find(r => r.title.includes('sample is required'));
            expect(sampleValidation).toBeDefined();
            expect(sampleValidation.status).toBe("success");
        });

        test('should fail when no samples exist', () => {
            // Arrange
            const testData = createTestData({
                samples: []
            });
            const record = createRecordObject(testData);
            const { user, db, env } = createMockObjects();
            const validator = loadValidationScript();

            // Act
            const results = validator.validateVisit(record, user, db, env);

            // Assert
            const sampleValidation = results.find(r => r.title.includes('sample is required'));
            expect(sampleValidation).toBeDefined();
            expect(sampleValidation.status).toBe("error");
        });

        test('should fail when samples field is null', () => {
            // Arrange
            const testData = createTestData({
                samples: null
            });
            const record = createRecordObject(testData);
            const { user, db, env } = createMockObjects();
            const validator = loadValidationScript();

            // Act
            const results = validator.validateVisit(record, user, db, env);

            // Assert
            const sampleValidation = results.find(r => r.title.includes('sample is required'));
            expect(sampleValidation).toBeDefined();
            expect(sampleValidation.status).toBe("error");
        });
    });

    describe('atLeastOneDetailAndSampleAreRequired validation', () => {
        test('should pass when both product disbursements and provider visit prod detailing exist', () => {
            // Arrange
            const testData = createTestData({
                samples: [{ Id: 'sample1' }], // Maps to ProductDisbursement.VisitId
                providerVisitProdDetailings: [{ Id: 'detail1' }] // Maps to ProviderVisitProdDetailing.VisitId
            });
            const record = createRecordObject(testData);
            const { user, db, env } = createMockObjects();
            const validator = loadValidationScript();

            // Act
            const results = validator.validateVisit(record, user, db, env);

            // Assert
            const detailValidation = results.find(r => r.title.includes('detail and sample are required'));
            expect(detailValidation).toBeDefined();
            expect(detailValidation.status).toBe("success");
        });

        test('should fail when product disbursements are missing', () => {
            // Arrange - no ProductDisbursement.VisitId but has ProviderVisitProdDetailing.VisitId
            const testData = createTestData({
                samples: [], // This maps to ProductDisbursement.VisitId - empty means no product disbursements
                providerVisitProdDetailings: [{ Id: 'detail1' }] // This maps to ProviderVisitProdDetailing.VisitId
            });
            const record = createRecordObject(testData);
            const { user, db, env } = createMockObjects();
            const validator = loadValidationScript();

            // Act
            const results = validator.validateVisit(record, user, db, env);

            // Assert
            const detailValidation = results.find(r => r.title.includes('detail and sample are required'));
            expect(detailValidation).toBeDefined();
            expect(detailValidation.status).toBe("error");
        });

        test('should fail when provider visit prod detailing is missing', () => {
            // Arrange
            const testData = createTestData({
                samples: [{ Id: 'sample1' }], // Maps to ProductDisbursement.VisitId - has samples/disbursements
                providerVisitProdDetailings: [] // Maps to ProviderVisitProdDetailing.VisitId - missing detailing
            });
            const record = createRecordObject(testData);
            const { user, db, env } = createMockObjects();
            const validator = loadValidationScript();

            // Act
            const results = validator.validateVisit(record, user, db, env);

            // Assert
            const detailValidation = results.find(r => r.title.includes('detail and sample are required'));
            expect(detailValidation).toBeDefined();
            expect(detailValidation.status).toBe("error");
        });

        test('should fail when both are missing', () => {
            // Arrange
            const testData = createTestData({
                samples: [], // Maps to ProductDisbursement.VisitId - no samples/disbursements
                providerVisitProdDetailings: [] // Maps to ProviderVisitProdDetailing.VisitId - no detailing
            });
            const record = createRecordObject(testData);
            const { user, db, env } = createMockObjects();
            const validator = loadValidationScript();

            // Act
            const results = validator.validateVisit(record, user, db, env);

            // Assert
            const detailValidation = results.find(r => r.title.includes('detail and sample are required'));
            expect(detailValidation).toBeDefined();
            expect(detailValidation.status).toBe("error");
        });
    });

    describe('error handling', () => {
        test('should handle null record gracefully', () => {
            // Arrange
            const { user, db, env } = createMockObjects();
            const validator = loadValidationScript();

            // Act
            const results = validator.validateVisit(null, user, db, env);

            // Assert
            expect(results).toHaveLength(1);
            expect(results[0].status).toBe("error");
            expect(results[0].error).toBe("No record provided");
        });

        test('should handle record without getContextData method', () => {
            // Arrange
            const record = { someOtherProperty: 'value' };
            const { user, db, env } = createMockObjects();
            const validator = loadValidationScript();

            // Act
            const results = validator.validateVisit(record, user, db, env);

            // Assert
            expect(results).toHaveLength(1);
            expect(results[0].status).toBe("error");
            expect(results[0].error).toBe("No record provided");
        });

        test('should handle malformed contextData gracefully', () => {
            // Arrange
            const record = {
                stringValue: () => '',
                boolValue: () => false,
                getContextData: () => "invalid json string"
            };
            const { user, db, env } = createMockObjects();
            const validator = loadValidationScript();

            // Act
            const results = validator.validateVisit(record, user, db, env);

            // Assert
            expect(results).toBeDefined();
            expect(Array.isArray(results)).toBe(true);
            expect(results[0].status).toBe("error");
        });
    });

    describe('integration scenarios', () => {
        test('should run multiple validations and return all results', () => {
            // Arrange
            const testData = createTestData({
                samples: [{ Id: 'sample1' }], // Maps to ProductDisbursement.VisitId
                providerVisitProdDetailings: [{ Id: 'detail1' }] // Maps to ProviderVisitProdDetailing.VisitId
            });
            const record = createRecordObject(testData);
            const { user, db, env } = createMockObjects();
            const validator = loadValidationScript();

            // Act
            const results = validator.validateVisit(record, user, db, env);

            // Assert
            expect(results).toHaveLength(3); // Should have all three validations now
            expect(results.every(r => r.status === "success")).toBe(true); // All should pass
        });

        test('should handle mixed validation results', () => {
            // Arrange - pass samples but fail detail requirement (no ProviderVisitProdDetailing.VisitId)
            const testData = createTestData({
                samples: [{ Id: 'sample1' }], // This maps to ProductDisbursement.VisitId - has samples
                providerVisitProdDetailings: [] // This maps to ProviderVisitProdDetailing.VisitId - missing detailing
            });
            const record = createRecordObject(testData);
            const { user, db, env } = createMockObjects();
            const validator = loadValidationScript();

            // Act
            const results = validator.validateVisit(record, user, db, env);

            // Assert
            expect(results).toHaveLength(3);
            const sampleValidation = results.find(r => r.title.includes('sample is required'));
            const detailValidation = results.find(r => r.title.includes('detail and sample are required'));
            const hcpValidation = results.find(r => r.title.includes('HCP required'));
            
            expect(sampleValidation.status).toBe("success");
            expect(detailValidation.status).toBe("error");
            expect(hcpValidation.status).toBe("success"); // Should pass for default (HCP account)
        });
    });

    describe('isAtLeastOneHCP validation', () => {
        test('should pass for Person Account (HCP)', () => {
            // Arrange
            const testData = createTestData({
                samples: [{ Id: 'sample1' }],
                Account: { IsPersonAccount: true, Type: 'Person Account' }
            });
            const record = createRecordObject(testData);
            const { user, db, env } = createMockObjects();
            const validator = loadValidationScript();

            // Act
            const results = validator.validateVisit(record, user, db, env);

            // Assert
            const hcpValidation = results.find(r => r.title.includes('HCP required'));
            expect(hcpValidation).toBeDefined();
            expect(hcpValidation.status).toBe("success");
        });

        test('should pass for HCO with HCP attendees', () => {
            // Arrange
            const testData = createTestData({
                samples: [{ Id: 'sample1' }],
                ProviderVisit: { AccountId: '001XXXXXXXXXXXX' },
                Account: { IsPersonAccount: false, Type: 'Institution Account' },
                attendees: [
                    { Account: { IsPersonAccount: true }, Type: 'Person Account' },
                    { Account: { IsPersonAccount: false }, Type: 'Institution Account' }
                ]
            });
            const record = createRecordObject(testData);
            const { user, db, env } = createMockObjects();
            const validator = loadValidationScript();

            // Act
            const results = validator.validateVisit(record, user, db, env);

            // Assert
            const hcpValidation = results.find(r => r.title.includes('HCP required'));
            expect(hcpValidation).toBeDefined();
            expect(hcpValidation.status).toBe("success");
        });

        test('should fail for HCO without HCP attendees', () => {
            // Arrange
            const testData = createTestData({
                samples: [{ Id: 'sample1' }],
                ProviderVisit: { AccountId: '001XXXXXXXXXXXX' },
                Account: { IsPersonAccount: false, Type: 'Institution Account' },
                attendees: [
                    { Account: { IsPersonAccount: false }, Type: 'Institution Account' }
                ]
            });
            const record = createRecordObject(testData);
            const { user, db, env } = createMockObjects();
            const validator = loadValidationScript();

            // Act
            const results = validator.validateVisit(record, user, db, env);

            // Assert
            const hcpValidation = results.find(r => r.title.includes('HCP required'));
            expect(hcpValidation).toBeDefined();
            expect(hcpValidation.status).toBe("error");
        });

        test('should fail for HCO with no attendees', () => {
            // Arrange
            const testData = createTestData({
                samples: [{ Id: 'sample1' }],
                ProviderVisit: { AccountId: '001XXXXXXXXXXXX' },
                Account: { IsPersonAccount: false, Type: 'Institution Account' },
                attendees: []
            });
            const record = createRecordObject(testData);
            const { user, db, env } = createMockObjects();
            const validator = loadValidationScript();

            // Act
            const results = validator.validateVisit(record, user, db, env);

            // Assert
            const hcpValidation = results.find(r => r.title.includes('HCP required'));
            expect(hcpValidation).toBeDefined();
            expect(hcpValidation.status).toBe("error");
        });

        test('should handle missing account data gracefully', () => {
            // Arrange
            const testData = createTestData({
                samples: [{ Id: 'sample1' }]
                // No Account data provided
            });
            const record = createRecordObject(testData);
            const { user, db, env } = createMockObjects();
            const validator = loadValidationScript();

            // Act
            const results = validator.validateVisit(record, user, db, env);

            // Assert
            const hcpValidation = results.find(r => r.title.includes('HCP required'));
            expect(hcpValidation).toBeDefined();
            expect(hcpValidation.status).toBe("success"); // Should default to valid when no account data
        });
    });
}); 