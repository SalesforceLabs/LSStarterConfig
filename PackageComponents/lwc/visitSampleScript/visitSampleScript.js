(() => {
    // Safely parse JSON string
    function safelyParseJSON(jsonString) {
        try {
            const result = typeof jsonString === 'string' ? JSON.parse(jsonString) : null;
            return result;
        } catch (e) {
            console.error('Error parsing JSON:', e.message);
            return null;
        }
    }

    // Extract data from params property, needed by extractFromContextData
    function extractFromParams(obj) {
        const params = obj?.params;
        if (!params) return null;
        
        if (typeof params === 'string') {
            return safelyParseJSON(params);
        } else if (typeof params === 'object') {
            return params;
        }
        
        return null;
    }

    // Extract data from contextData property - APPROACH 1
    function extractFromContextData(obj) {
        const contextData = obj?.contextData;
        if (!contextData) return null;
        
        if (typeof contextData === 'string') {
            return safelyParseJSON(contextData);
        } else if (typeof contextData === 'object') {
            // Check if params is nested in contextData
            if (contextData.params) {
                return extractFromParams({ params: contextData.params });
            }
            return contextData;
        }
        
        return null;
    }

    // AccountDAO - Data Access Object for account-related operations
    var accountDao = (function () {
        var instance;
        var currentRecord;
        var isPersonAccount;
        var isInstitution;
        var childCallAccounts;
        var accountCache = new Map(); // Simple cache for account data

        // Helper functions for accountDao - moved inside closure to access currentRecord
        async function checkForPersonAccount() {
            let accountId = currentRecord.stringValue("Account");
            
            if (!accountId) {
                return false; // Default to not person account if no account ID
            }
            
            let account = await selectAccountById(accountId);
            let result = account && account.length > 0 ? account[0].boolValue("IsPersonAccount") : false;
            return result;
        }

        async function checkForInstitution() {
            let accountId = currentRecord.stringValue("Account");
            
            if (!accountId) {
                return false; // Default to not institution if no account ID
            }
            
            let account = await selectAccountById(accountId);
            let isPersonAccount = account && account.length > 0 ? account[0].boolValue("IsPersonAccount") : false;
            
            // If it's not a Person Account, then it's a Business Account (HCO)
            let result = !isPersonAccount;
            return result;
        }

        async function selectChildCallAccountsById() {
            // Extract attendee account IDs directly from the JSON data
            // The attendee data is in the Visit.ParentVisitId array in the JSON
            
            // Get the JSON data from the current record context
            let contextData;
            try {
                const contextJson = currentRecord.getContextData();
                contextData = JSON.parse(contextJson);
            } catch (error) {
                return [];
            }
            
            // Extract attendee account IDs from Visit.ParentVisitId array
            const attendeeVisits = contextData?.["Visit.ParentVisitId"] || [];
            
            if (!Array.isArray(attendeeVisits) || attendeeVisits.length === 0) {
                return [];
            }
            
            // Extract AccountIds from the attendee visits
            const attendeeAccountIds = attendeeVisits
                .map(visit => visit.AccountId)
                .filter(accountId => accountId); // Remove null/undefined values
                
            if (attendeeAccountIds.length === 0) {
                return [];
            }
            
            // Query the Account records for these IDs
            let result = await db.query(
                "Account",
                await new ConditionBuilder(
                    "Account",
                    new SetCondition("Id", "IN", attendeeAccountIds)
                ).build(),
                ["Id", "Name", "IsPersonAccount"]
            );
            
            return result || [];
        }

        function getRecordId(record) {
            return record ? record.stringValue("Id") : null;
        }

        async function selectAccountById(accountId) {
            // Check cache first
            if (accountCache.has(accountId)) {
                return accountCache.get(accountId);
            }
            
            // If not in cache, query database
            let accounts = await db.query(
                "Account",
                await new ConditionBuilder(
                    "Account",
                    new FieldCondition("Id", "=", accountId)
                ).build(),
                ["Id", "Name", "IsPersonAccount"]
            );
            
            // Cache the result
            accountCache.set(accountId, accounts);
            
            return accounts;
        }

        var initialize = async function(record) {
            currentRecord = record;
            // Clear cache for new record context
            accountCache.clear();
            isPersonAccount = await checkForPersonAccount();
            isInstitution = await checkForInstitution();
            childCallAccounts = await selectChildCallAccountsById();
        };

        var getIsPersonAccount = function () {
            return isPersonAccount;
        };

        var getIsInstitution = function () {
            return isInstitution;
        };

        var getChildCallAccounts = function () {
            return childCallAccounts;
        };

        var createInstance = function () {
            return {
                initialize: initialize,
                getIsPersonAccount: getIsPersonAccount,
                getChildCallAccounts: getChildCallAccounts,
                getIsInstitution: getIsInstitution,
            };
        };

        return {
            getInstance: function () {
                return instance || (instance = createInstance());
            },
        };
    })();

    // Main function that businessRuleValidator calls
    async function validateVisit() {
        try {
            const record = arguments[0];
            const user = arguments[1]; // jsUser parameter from business rule validator
            
            if (!record) {
                return [{ 
                    title: "Error in validation", 
                    isValid: false, 
                    error: "No record provided" 
                }];
            }
            
            // Only use Approach 1: Extract data from JsDbObject format (sObject with contextData)
            let jsonData = null;
            if (record.sObject) {
                jsonData = extractFromContextData(record);
            } else {
                return [{ 
                    title: "Invalid record format", 
                    isValid: false, 
                    error: "Record missing sObject property" 
                }];
            }
            
            // Default to empty object if no data found
            jsonData = jsonData || {};
            
            const validationResults = await runValidation(jsonData, user);
            
            // Handle mixed sync/async results
            const resolvedResults = await Promise.all(validationResults);
            
            // Ensure we always return an array
            const finalResults = Array.isArray(resolvedResults) ? resolvedResults : [resolvedResults];
            return finalResults;
        } catch (error) {
            console.error('validateVisit() - ERROR:', error);
            return [{ 
                title: "Error in validation", 
                isValid: false, 
                error: error.message 
            }];
        }
    }
    
    // Function to run the validation with provided data
    async function runValidation(jsonData, user) {
        // Create environment wrapper for the JSON data
        const env = createEnvironment(jsonData);
        
        // Get record from environment
        const record = env ? env.getRecord() : { 
            stringValue: (field) => field === 'Status' ? 'Draft' : '',
            boolValue: (field) => false
        };

        // Initialize accountDao with record context
        await accountDao.getInstance().initialize(record);

        // Always validate in this version
        const isValidationRequired = true;

        // Only run validations if needed
        let validationResults = [];
        if (isValidationRequired) {
            // Array of validation functions to run
            // Add new validation functions to this array
            const validationFunctions = [
                atLeastOneSampleIsRequired,
                atLeastOneDetailAndSampleAreRequired,
                atLeastOneMessageIsRequiredForEachVisitDetail,
                specificSampleDependencyCheck,
                isAtLeastOneHCP,
                isMoreThanOneHCO,
                // Add new validation functions here one at a time
                // Example: validateSampleType,
                // Example: validateComplianceAgreement,
            ];
            
            // Run all validation functions (handling both sync and async)
            validationResults = validationFunctions.map((validationFn, index) => {
                try {
                    // Pass user parameter to validation functions that need it
                    const result = validationFn(jsonData, record, env, user);
                    // If the result is a Promise, return it as is for Promise.all
                    if (result && typeof result.then === 'function') {
                        return result.catch(error => {
                            console.error(`Validation ${validationFn.name} error:`, error);
                            return {
                                title: `Error in ${validationFn.name}: ${error.message}`,
                                isValid: false,
                                error: error.message
                            };
                        });
                    }
                    return result;
                } catch (error) {
                    console.error(`Validation ${validationFn.name} caught error:`, error);
                    return {
                        title: `Error in ${validationFn.name}: ${error.message}`,
                        isValid: false,
                        error: error.message
                    };
                }
            });
        } else {
            // Default return when validation is not required
            validationResults = [{ 
                title: "Validation not required", 
                isValid: true 
            }];
        }

        return validationResults;
    }
    
    // Create environment wrapper for the JSON data
    function createEnvironment(jsonData) {
        const env = {
            getOption: (option) => {
                return option === 'actionName' ? 'Submit' : '';
            },
            currentUser: {
                ProfileId: jsonData?.currentUser?.ProfileId || null,
                Id: jsonData?.currentUser?.Id || null,
                Name: jsonData?.currentUser?.Name || null
            },
            getRecord: () => ({
                stringValue: (field) => {
                    let result;
                    
                    if (field === "Status") {
                        result = "Draft";
                    } else if (field === "Id") {
                        result = jsonData.ProviderVisit?.Id || '';
                    } else if (field === "VisitId") {
                        result = jsonData.ProviderVisit?.VisitId || '';
                    } else if (field === "Account") {
                        // Based on actual JSON structure: ProviderVisit.AccountId contains the account ID
                        result = jsonData.ProviderVisit?.AccountId || '';
                        
                        // Fallback: Try other possible locations
                        if (!result) {
                            result = jsonData.Visit?.Account || jsonData.ProviderVisit?.Account || 
                                   jsonData.Visit?.AccountId || '';
                        }
                        
                    } else if (field === "ComplianceAgreementStatus") {
                        result = jsonData.ProviderVisit?.ComplianceStmtAgreeStatus || '';
                    } else if (field === "SubmissionDelayReason") {
                        result = jsonData.ProviderVisit?.SubmitDelayReason || '';
                    } else if (field === "SubmissionDelayReasonPicklist") {
                        result = jsonData.ProviderVisit?.SubmitDelayReasonType || '';
                    } else if (field === "ProfileId") {
                        result = jsonData?.currentUser?.ProfileId || '';
                    } else {
                        result = jsonData.ProviderVisit?.[field] || '';
                    }
                    
                    return result;
                },
                boolValue: (field) => {
                    let result;
                    if (field === "IsVisitDelayed") result = jsonData.ProviderVisit?.IsVisitDelayed || false;
                    else result = jsonData.ProviderVisit?.[field] === true;
                    
                    return result;
                },
                getContextData: () => {
                    return JSON.stringify(jsonData);
                }
            })
        };
        return env;
    }
    
    // Validation rule: at least one sample is required
    function atLeastOneSampleIsRequired(jsonData, record, env, user) {
        const sampleField = "ProductDisbursement.VisitId";
        let hasSamples = false;
        
        try {
            const sampleData = jsonData?.[sampleField] || null;
            hasSamples = Array.isArray(sampleData) && sampleData.length > 0;
        } catch (e) {
            hasSamples = false;
        }
        
        return {
            title: hasSamples ? 
                `Found ${jsonData?.[sampleField]?.length || 0} sample(s)` :
                "At least one sample must be added to the visit.",
            isValid: hasSamples
        };
    }

    // Validation rule: at least one detail and sample are required
    function atLeastOneDetailAndSampleAreRequired(jsonData, record, env, user) {
        try {
            const productDisbursementField = "ProductDisbursement.VisitId";
            const providerVisitProdDetailingField = "ProviderVisitProdDetailing.ProviderVisitId";
            
            const productDisbursementData = jsonData?.[productDisbursementField];
            const providerVisitProdDetailingData = jsonData?.[providerVisitProdDetailingField];
            
            const hasProductDisbursement = Array.isArray(productDisbursementData) && productDisbursementData.length > 0;
            const hasProviderVisitProdDetailing = Array.isArray(providerVisitProdDetailingData) && providerVisitProdDetailingData.length > 0;
            
            const sampleCount = hasProductDisbursement ? productDisbursementData.length : 0;
            const detailCount = hasProviderVisitProdDetailing ? providerVisitProdDetailingData.length : 0;
            
            if (hasProductDisbursement && hasProviderVisitProdDetailing) {
                return {
                    title: `Found ${sampleCount} sample(s) and ${detailCount} detailed product(s)`,
                    isValid: true
                };
            }
            
            return {
                title: "At least one sample and detailed product must be added to the visit.",
                isValid: false
            };
        } catch (e) {
            return {
                title: "At least one sample and detailed product must be added to the visit.",
                isValid: false,
                error: e.message
            };
        }
    }

    // Validation rule: at least one message is required for each visit detail
    async function atLeastOneMessageIsRequiredForEachVisitDetail(jsonData, record, env, user) {
        try {
            let profileId;
            
            // Try to get ProfileId from jsUser parameter first
            if (user) {
                try {
                    profileId = user.stringValue('ProfileId');
                } catch (error) {
                    // Try alternative access methods
                    profileId = user.ProfileId || user["ProfileId"];
                    if (!profileId) {
                        console.error('Error accessing user ProfileId:', error);
                    }
                }
            }
            
            if (!profileId) {
                return {
                    title: 'Profile validation skipped - no ProfileId available',
                    isValid: true,
                };
            }

            // Query the Profile object to get the profile name
            let profiles;
            let isMedicalSalesRep = false;
            
            try {
                profiles = await db.query(
                    "Profile",
                    await new ConditionBuilder(
                        "Profile",
                        new FieldCondition("Id", "=", profileId)
                    ).build(),
                    ["Id", "Name"]
                );
                
                if (profiles && profiles.length > 0) {
                    const profileName = profiles[0].stringValue('Name');
                    isMedicalSalesRep = profileName === "Medical Sales Representative";
                } else {
                    return {
                        title: 'Profile validation skipped - profile not found',
                        isValid: true,
                    };
                }
                
            } catch (error) {
                return {
                    title: 'Profile validation skipped - unable to query profile',
                    isValid: true,
                };
            }

            if (!isMedicalSalesRep) {
                return {
                    title: `Profile validation skipped - user is not Medical Sales Representative`,
                    isValid: true,
                };
            }

            // Get visit context data (jsonData is already our visit data)
            const visitData = jsonData;

            // Check if channel is "Face to Face"
            const visitChannel = visitData?.Visit?.channel || visitData?.ProviderVisit?.Channel || '';

            if (visitChannel !== "Face to Face") {
                return {
                    title: `Message validation skipped - visit channel is "${visitChannel}", not "Face to Face"`,
                    isValid: true,
                };
            }

            // Check if we have visit details to validate
            const visitDetailsField = "ProviderVisitProdDetailing.ProviderVisitId";
            const visitDetails = visitData?.[visitDetailsField];

            if (!Array.isArray(visitDetails) || visitDetails.length === 0) {
                return {
                    title: 'Message validation passed - no visit details to validate',
                    isValid: true
                };
            }

            // Validate each visit detail has at least one message
            let detailsWithoutMessages = [];

            visitDetails.forEach((detail, index) => {
                const messagesField = "ProviderVisitDtlProductMsg.ProviderVisitId";
                const messages = detail?.[messagesField];
                const hasMessages = Array.isArray(messages) && messages.length > 0;

                if (!hasMessages) {
                    const detailInfo = {
                        index: index + 1,
                        productId: detail?.productid || 'Unknown Product',
                        uid: detail?.uid || 'Unknown Detail'
                    };
                    detailsWithoutMessages.push(detailInfo);
                }
            });

            // Set validation result
            if (detailsWithoutMessages.length > 0) {
                return {
                    title: "At least one message is required for each detailed product when the channel is 'Face to Face' and the user has a 'Medical Sales Representative' profile.",
                    isValid: false
                };
            } else {
                return {
                    title: `All ${visitDetails.length} detailed products have messages - Medical Sales Rep Face to Face validation passed`,
                    isValid: true
                };
            }

        } catch (error) {
            return {
                title: "At least one message is required for each detailed product when the channel is 'Face to Face' and the user has a 'Medical Sales Representative' profile.",
                isValid: false,
                error: error.message
            };
        }
    }

    /**
     * The rule 'specificSampleDependencyCheck' blocks the user from submitting a visit.
     * Validation: If sample "Immunexis 10mg" is selected,
     * then "ADRAVIL Sample Pack 5mg" must also be selected.
     * @returns result { title: string, isValid: boolean };
     */
    async function specificSampleDependencyCheck(jsonData, record, env, user) {
        try {
            
            // Get visit context data
            let visitJson = record.getContextData();
            let visitData = JSON.parse(visitJson);

            // Check if we have samples to validate
            const samplesField = "ProductDisbursement.VisitId";
            let samples = visitData[samplesField];
            
            if (!Array.isArray(samples) || samples.length === 0) {
                return {
                    title: 'Sample dependency validation passed - no samples to validate',
                    isValid: true
                };
            }

            // Get all product item IDs from samples
            let productItemIds = samples.map(sample => sample.ProductItemId).filter(id => id);

            if (productItemIds.length === 0) {
                return {
                    title: 'Sample dependency validation passed - no product item IDs found',
                    isValid: true
                };
            }

            // Query ProductItem to get product names
            let productItems = await db.query(
                "ProductItem",
                await new ConditionBuilder(
                    "ProductItem",
                    new SetCondition("Id", "IN", productItemIds)
                ).build(),
                ["Id", "ProductName"]
            );

            // Create a map of productItemId to ProductName
            let productNameMap = new Map();
            if (productItems && Array.isArray(productItems)) {
                productItems.forEach(item => {
                    const id = item.stringValue("Id");
                    const name = item.stringValue("ProductName");
                    productNameMap.set(id, name);
                });
            }

            // Get all sample names for the current visit
            let sampleNames = samples.map(sample => {
                let productItemId = sample.ProductItemId;
                let productName = productNameMap.get(productItemId) || '';
                return productName;
            }).filter(name => name);

            // Check if Immunexis 10mg is present
            const targetSample = "Immunexis 10mg";
            const requiredSample = "ADRAVIL Sample Pack 5mg";
            
            let hasImmunexis = sampleNames.includes(targetSample);

            if (hasImmunexis) {
                // If Immunexis is present, check if ADRAVIL is also present
                let hasAdravil = sampleNames.includes(requiredSample);

                if (!hasAdravil) {
                    return {
                        title: "If Immunexis 10mg is added to a visit, ADRAVIL Sample Pack 5mg must also be added. However, ADRAVIL Sample Pack 5mg can be added without Immunexis 10mg.",
                        isValid: false
                    };
                } else {
                    return {
                        title: "Sample dependency validation passed - both Immunexis 10mg and ADRAVIL Sample Pack 5mg present",
                        isValid: true
                    };
                }
            } else {
                return {
                    title: "Sample dependency validation passed - no Immunexis 10mg found",
                    isValid: true
                };
            }

        } catch (error) {
            console.error('specificSampleDependencyCheck - ERROR:', error);
            // In case of database error, we might want to pass validation or handle differently
            // For now, we'll pass the validation to avoid blocking the user due to technical issues
            return {
                title: "Sample dependency validation passed - technical error occurred",
                isValid: true
            };
        }
    }

    /**
     * The rule 'isAtLeastOneHCP' blocks the user from submitting a call.
     * Validation: Require at least one HCP (Person Account) for a HCO (Institution Account) call on Submit.
     * @returns result { title: string, isValid: boolean };
     */
    async function isAtLeastOneHCP(jsonData, record, env, user) {
        try {
            
            // Log current account details from record
            const currentAccountId = record.stringValue("Account");
            
            // Use accountDao to check if current account is a Person Account
            let isPersonAccount = await accountDao.getInstance().getIsPersonAccount();
            let isInstitution = await accountDao.getInstance().getIsInstitution();

            if (isPersonAccount) {
                // This is already a Person Account (HCP), so requirement is met
                return {
                    title: "HCP validation passed - current account is a Person Account (HCP)",
                    isValid: true
                };
            }

            // Only apply HCP validation to Institution accounts
            if (!isInstitution) {
                return {
                    title: "HCP validation skipped - account is not an Institution Account",
                    isValid: true
                };
            }

            // This is an Institution Account, check for HCP attendees
            let childCallAccounts = await accountDao.getInstance().getChildCallAccounts();
            
            
            let isRequirementValid = false;
            let hcpAttendees = [];
            let nonHcpAttendees = [];
            
            if (Array.isArray(childCallAccounts) && childCallAccounts.length > 0) {
                // Check if any attendee is a Person Account (HCP)
                for (let i = 0; i < childCallAccounts.length; i++) {
                    let attendee = childCallAccounts[i];
                    let attendeeIsPersonAccount = attendee.boolValue("IsPersonAccount");
                    let attendeeName = attendee.stringValue("Name") || attendee.stringValue("Id");
                    let attendeeRecordType = attendee.stringValue("RecordType.Name") || 'Unknown';
                    
                    
                    if (attendeeIsPersonAccount) {
                        isRequirementValid = true;
                        hcpAttendees.push(attendeeName);
                    } else {
                        nonHcpAttendees.push(attendeeName);
                    }
                }
            }


            // Add more descriptive message based on the scenario
            if (!isRequirementValid) {
                return {
                    title: "At least one HCP (Healthcare Professional) must be associated when creating a visit for an HCO (Healthcare Organization).",
                    isValid: false
                };
            } else {
                return {
                    title: `HCP validation passed - Institution Account with ${hcpAttendees.length} HCP attendee(s): ${hcpAttendees.join(', ')}`,
                    isValid: true
                };
            }

        } catch (error) {
            console.error('isAtLeastOneHCP - ERROR:', error);
            // In case of error, fail the validation to be safe
            return {
                title: "HCP validation failed - error occurred during validation",
                isValid: false,
                error: error.message
            };
        }
    }

    /**
     * The rule 'isMoreThanOneHCO' blocks user from submitting a call.
     * Validation: Restrict to one HCO (Institution Account) attendee per Call.
     * @returns result { title: string, isValid: boolean };
     * Note: Expected only 1 HCO attendee per call)
     */
    async function isMoreThanOneHCO(jsonData, record, env, user) {
        try {
            
            let counter = 0;
            let isPersonAccount = await accountDao.getInstance().getIsPersonAccount();
            let accsRelatedToChildCall = await accountDao.getInstance().getChildCallAccounts();


            let hcoAccounts = [];
            let hcpAccounts = [];

            if (isPersonAccount || accsRelatedToChildCall.length) {
                for (let i = 0; i < accsRelatedToChildCall.length; i++) {
                    let relatedAcc = accsRelatedToChildCall[i];
                    let attendeeIsPersonAccount = relatedAcc.boolValue("IsPersonAccount");
                    let attendeeName = relatedAcc.stringValue("Name") || relatedAcc.stringValue("Id");
                    let attendeeRecordType = relatedAcc.stringValue("RecordType.Name") || 'Unknown';
                    
                    
                    if (!attendeeIsPersonAccount) {
                        counter++;
                        hcoAccounts.push(attendeeName);
                    } else {
                        hcpAccounts.push(attendeeName);
                    }
                }
            } else {
                counter++;
            }


            const isValid = counter <= 1;

            if (!isValid) {
                return {
                    title: "Only 1 HCO (Healthcare Organization) attendee can be added per visit.",
                    isValid: false
                };
            } else {
                return {
                    title: `HCO count validation passed - found ${counter} HCO account(s)`,
                    isValid: true
                };
            }

        } catch (error) {
            console.error('isMoreThanOneHCO - ERROR:', error);
            return {
                title: "HCO count validation failed - error occurred during validation",
                isValid: false,
                error: error.message
            };
        }
    }

    // We need to check if we're being called immediately (during script load)
    // or later with arguments (through the validator)
    
    
    // If there are arguments, extract the record data and run validation
    if (arguments && arguments.length > 0 && arguments[0]) {
        // Pass all arguments to validateVisit, not just the first one
        return [validateVisit.apply(null, Array.from(arguments))];
    }
    
    // If no arguments yet, return a function that will run validation when called
    // This is wrapped in an array to make it iterable for Promise.all()
    return [validateVisit];
})();

