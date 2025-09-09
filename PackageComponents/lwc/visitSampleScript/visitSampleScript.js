(() => {
    // Note: Old data extraction functions removed - no longer needed 
    // since businessRuleValidator provides clean, structured parameters

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
            let accountId = currentRecord.stringValue("AccountId");
            
            // If not found, try extracting directly from context data
            if (!accountId) {
                try {
                    const contextData = parseContextData(currentRecord);
                    
                    // Try different possible locations for AccountId
                    accountId = contextData.ProviderVisit?.AccountId || 
                               contextData.AccountId || 
                               contextData.Account?.Id ||
                               contextData.Account;
                } catch (e) {
                    console.log("Context data error:", e.message);
                    // Error accessing context data, continue with null accountId
                    accountId = null;
                }
            }
            
            if (!accountId) {
                return false; // Default to not person account if no account ID
            }
            
            try {
                let account = await selectAccountById(accountId);
                let result = account && account.length > 0 ? account[0].boolValue("IsPersonAccount") : false;
                return result;
            } catch (error) {
                console.log("Account check error:", error.message);
                return false; // Default to false on error
            }
        }

        async function checkForInstitution() {
            let accountId = currentRecord.stringValue("AccountId");
            // If not found, try extracting directly from context data
            if (!accountId) {
                try {
                    const contextData = parseContextData(currentRecord);
                    
                    // Try different possible locations for AccountId
                    accountId = contextData.ProviderVisit?.AccountId || 
                               contextData.AccountId || 
                               contextData.Account?.Id ||
                               contextData.Account;
                } catch (e) {
                    // Error accessing context data, continue with null accountId
                    console.log("Context data error:", e.message);
                }
            }
            
            if (!accountId) {
                return false; // Default to not institution if no account ID
            }
            
            try {
                let account = await selectAccountById(accountId);
                let isPersonAccount = account && account.length > 0 ? account[0].boolValue("IsPersonAccount") : false;
                
                // If it's not a Person Account, then it's a Business Account (HCO)
                let result = !isPersonAccount;
                return result;
            } catch (error) {
                console.log("Institution check error:", error.message);
                return false; // Default to false on error
            }
        }

        async function selectChildCallAccountsById() {
            // Extract attendee account IDs directly from the JSON data
            // The attendee data is in the Visit.ParentVisitId array in the JSON
            
            // Get the data from the current record context
            let contextData;
            try {
                contextData = parseContextData(currentRecord);
            } catch (error) {
                console.log("Context data error:", error.message);
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
            const record = arguments[0]; // JsDbObject with stringValue(), boolValue(), getContextData()
            const user = arguments[1];   // JsUser object  
            const db = arguments[2];     // JsDb object for database operations
            const env = arguments[3];    // JsEnv object for environment options
            
            if (!record) {
                return [{ 
                    title: "Error in validation", 
                    status: "error", 
                    error: "No record provided" 
                }];
            }
            
            // Use the properly provided business rule parameters directly
            const validationResults = await runValidation(record, user, db, env);
            
            // Handle mixed sync/async results
            const resolvedResults = await Promise.all(validationResults);
            
            // Ensure we always return an array
            const finalResults = Array.isArray(resolvedResults) ? resolvedResults : [resolvedResults];
            return finalResults;
      } catch (error) {
            return [{ 
                title: "Error in validation", 
                status: "error", 
                error: error.message 
            }];
        }
    }
    
    // Function to run the validation with provided data
    async function runValidation(record, user, db, env) {

        // Initialize accountDao with the proper record object (JsDbObject)
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
                    // Pass proper business rule parameters: record, user, db, env
                    const result = validationFn(record, user, db, env);
                    // If the result is a Promise, return it as is for Promise.all
                    if (result && typeof result.then === 'function') {
                        return result.then(asyncResult => {
                            return asyncResult;
                        }).catch(error => {
                            console.log(`${validationFn.name} error:`, error.message);
                            return {
                                title: `Error in ${validationFn.name}: ${error.message}`,
                                status: "error",
                                error: error.message
                            };
                        });
                    }
                    return result;
                } catch (error) {
                    console.log(`${validationFn.name} error:`, error.message);
                        return {
                                title: `Error in ${validationFn.name}: ${error.message}`,
                                status: "error",
                                error: error.message
                            };
                }
            });
            } else {
                // Default return when validation is not required
                validationResults = [{ 
                    title: "Validation not required", 
                    status: "success" 
                }];
            }

        return validationResults;
    }
    


    // Helper function to get context data safely
    function parseContextData(record) {
        try {
            if (!record || typeof record.getContextData !== 'function') {
                return {};
            }
            
            const contextData = record.getContextData();
            
            // Handle different return types from getContextData()
            if (typeof contextData === 'string') {
                // If it's a JSON string, parse it
                return JSON.parse(contextData);
            } else if (typeof contextData === 'object' && contextData !== null) {
                // If it's already an object (including Proxy), use it directly
                return contextData;
            } else {
                return {};
            }
        } catch (error) {
            return {};
        }
    }
    
    // Validation rule: at least one sample is required
    function atLeastOneSampleIsRequired(record, user, db, env) {
        const sampleField = "ProductDisbursement.VisitId";
        let hasSamples = false;
        let sampleCount = 0;
        
        try {
            // Get context data from the record object
            const contextData = parseContextData(record);
            const sampleData = contextData?.[sampleField] || null;
            
            // Handle Proxy arrays properly
            if (sampleData) {
                try {
                    // Try to get length property (works for both arrays and Proxy arrays)
                    sampleCount = sampleData.length || 0;
                    hasSamples = sampleCount > 0;

                } catch (lengthError) {
                    // Handle Proxy length access error
                    // Fallback: check if object has any enumerable properties
                    try {
                        const keys = Object.keys(sampleData);
                        hasSamples = keys.length > 0;
                        sampleCount = keys.length;
                    } catch (keysError) {
                        console.log("Sample keys access error:", keysError.message);
                        // Error getting keys - graceful fallback
                        hasSamples = false;
                        sampleCount = 0;
                    }
                }
            }           
        } catch (e) {
            console.log("Sample validation error:", e.message);
            // Handle validation error gracefully
            hasSamples = false;
            sampleCount = 0;
        }
        
        return {
            title: hasSamples ? 
                `Found ${sampleCount} sample(s)` :
                "At least one sample must be added to the visit.",
            status: hasSamples ? "success" : "error"
        };
    }

    // Validation rule: at least one detail and sample are required
    function atLeastOneDetailAndSampleAreRequired(record, user, db, env) {     
        try {
            const contextData = parseContextData(record);            
            const productDisbursementField = "ProductDisbursement.VisitId";
            const providerVisitProdDetailingField = "ProviderVisitProdDetailing.ProviderVisitId";
            
            const productDisbursementData = contextData?.[productDisbursementField];
            const providerVisitProdDetailingData = contextData?.[providerVisitProdDetailingField];
            
            // Handle Proxy arrays properly for both fields
            let sampleCount = 0;
            let detailCount = 0;
            let hasProductDisbursement = false;
            let hasProviderVisitProdDetailing = false;
            
            // Check product disbursement
            if (productDisbursementData) {
                try {
                    sampleCount = productDisbursementData.length || 0;
                    hasProductDisbursement = sampleCount > 0;
                } catch (e) {
                    console.log("Sample length error:", e.message);
                    // Error accessing length property
                    const keys = Object.keys(productDisbursementData || {});
                    sampleCount = keys.length;
                    hasProductDisbursement = sampleCount > 0;
                }
            }
            
            // Check provider visit prod detailing
            if (providerVisitProdDetailingData) {
                try {
                    detailCount = providerVisitProdDetailingData.length || 0;
                    hasProviderVisitProdDetailing = detailCount > 0;
                } catch (e) {
                    console.log("Detail length error:", e.message);
                    // Error accessing length property
                    const keys = Object.keys(providerVisitProdDetailingData || {});
                    detailCount = keys.length;
                    hasProviderVisitProdDetailing = detailCount > 0;
                }
            }
            
            if (hasProductDisbursement && hasProviderVisitProdDetailing) {
                return {
                    title: `Found ${sampleCount} sample(s) and ${detailCount} detailed product(s)`,
                    status: "success"
                };
            }
            
            return {
                title: "At least one sample and detailed product must be added to the visit.",
                status: "error"
            };
        } catch (e) {
            console.log("Detail validation error:", e.message);
            return {
                title: "At least one sample and detailed product must be added to the visit.",
                status: "error",
                error: e.message
            };
        }
    }

    // Validation rule: at least one message is required for each visit detail
    async function atLeastOneMessageIsRequiredForEachVisitDetail(record, user, db, env) {
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
                        // Error accessing ProfileId, continue with fallback
                    }
                }
            }
            
            if (!profileId) {
                return {
                    title: 'Profile validation skipped - no ProfileId available',
                    status: "success",
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
                        status: "success",
                    };
                }
                
            } catch (error) {
                return {
                    title: 'Profile validation skipped - unable to query profile',
                    status: "success",
                };
            }

            if (!isMedicalSalesRep) {
                return {
                    title: `Profile validation skipped - user is not Medical Sales Representative`,
                    status: "success",
                };
            }

            // Get visit context data from the record object
            const visitData = parseContextData(record);

            // Check if channel is "Face to Face"
            const visitChannel = visitData?.Visit?.channel || visitData?.ProviderVisit?.Channel || '';

            if (visitChannel !== "Face to Face") {
                return {
                    title: `Message validation skipped - visit channel is "${visitChannel}", not "Face to Face"`,
                    status: "success",
                };
            }

            // Check if we have visit details to validate
            const visitDetailsField = "ProviderVisitProdDetailing.ProviderVisitId";
            const visitDetails = visitData?.[visitDetailsField];

            if (!Array.isArray(visitDetails) || visitDetails.length === 0) {
                return {
                    title: 'Message validation passed - no visit details to validate',
                    status: "success"
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
                    status: "error"
                };
            } else {
                return {
                    title: `All ${visitDetails.length} detailed products have messages - Medical Sales Rep Face to Face validation passed`,
                    status: "success"
                };
            }

        } catch (error) {
            return {
                title: "At least one message is required for each detailed product when the channel is 'Face to Face' and the user has a 'Medical Sales Representative' profile.",
                status: "error",
                error: error.message
            };
        }
    }

    /**
     * The rule 'specificSampleDependencyCheck' blocks the user from submitting a visit.
     * Validation: If sample "Immunexis 10mg" is selected,
     * then "ADRAVIL Sample Pack 5mg" must also be selected.
     * @returns result { title: string, status: "success" | "error" };
     */
    async function specificSampleDependencyCheck(record, user, db, env) {

        try {
            // Get visit context data using the proper helper function
            let visitData = parseContextData(record);
            
            // Check if we have samples to validate
            const samplesField = "ProductDisbursement.VisitId";
            let samples = visitData[samplesField];
            
            // Handle Proxy arrays properly
            let samplesCount = 0;
            let isValidSamples = false;
            
            if (samples) {
                try {
                    samplesCount = samples.length || 0;
                    isValidSamples = samplesCount > 0;
                } catch (e) {
                    console.log("Sample length error:", e.message);
                    // Error accessing samples length
                    const keys = Object.keys(samples || {});
                    samplesCount = keys.length;
                    isValidSamples = samplesCount > 0;
                }
            }
            
            if (!isValidSamples) {
                return {
                    title: 'Sample dependency validation passed - no samples to validate',
                    status: "success"
                };
            }

            // Get all product item IDs from samples
            let productItemIds = [];
            try {
                if (samples && typeof samples === 'object') {
                    // Handle both array and Proxy array
                    for (let i = 0; i < samplesCount; i++) {
                        try {
                            const sample = samples[i];
                            if (sample && sample.ProductItemId) {
                                productItemIds.push(sample.ProductItemId);
                            }
                        } catch (sampleError) {
                            // Error accessing sample
                        }
                    }
                }
            } catch (mappingError) {
                // Error mapping product item IDs
            }
            

            if (productItemIds.length === 0) {
                return {
                    title: 'Sample dependency validation passed - no product item IDs found',
                    status: "success"
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
            let sampleNames = [];
            try {
                if (samples && typeof samples === 'object') {
                    // Handle both array and Proxy array for sample names
                    for (let i = 0; i < samplesCount; i++) {
                        try {
                            const sample = samples[i];
                            if (sample && sample.ProductItemId) {
                                const productItemId = sample.ProductItemId;
                                const productName = productNameMap.get(productItemId) || '';
                                if (productName) {
                                    sampleNames.push(productName);
                                }
                            }
                        } catch (sampleError) {
                            // Error accessing sample for name mapping
                        }
                    }
                }
            } catch (nameMappingError) {
                // Error mapping sample names
            }
            

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
                        status: "error"
                    };
                } else {
                    return {
                        title: "Sample dependency validation passed - both Immunexis 10mg and ADRAVIL Sample Pack 5mg present",
                        status: "success"
                    };
                }
            } else {
                return {
                    title: "Sample dependency validation passed - no Immunexis 10mg found",
                    status: "success"
                };
            }

      } catch (error) {
            // Error in specificSampleDependencyCheck
            // In case of database error, we might want to pass validation or handle differently
            // For now, we'll pass the validation to avoid blocking the user due to technical issues
            return {
                title: "Sample dependency validation passed - technical error occurred",
                status: "success"
            };
        }
    }

    /**
     * The rule 'isAtLeastOneHCP' blocks the user from submitting a call.
     * Validation: Require at least one HCP (Person Account) for a HCO (Institution Account) call on Submit.
     * @returns result { title: string, status: "success" | "error" };
     */
    async function isAtLeastOneHCP(record, user, db, env) {
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
                    status: "success"
                };
            }

            // Only apply HCP validation to Institution accounts
            if (!isInstitution) {
                return {
                    title: "HCP validation skipped - account is not an Institution Account",
                    status: "success"
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
                    status: "error"
                };
            } else {
                return {
                    title: `HCP validation passed - Institution Account with ${hcpAttendees.length} HCP attendee(s): ${hcpAttendees.join(', ')}`,
                    status: "success"
                };
            }

      } catch (error) {
            // Error in isAtLeastOneHCP
            // In case of error, fail the validation to be safe
            return {
                title: "HCP validation failed - error occurred during validation",
                status: "error",
                error: error.message
            };
        }
    }

    /**
     * The rule 'isMoreThanOneHCO' blocks user from submitting a call.
     * Validation: Restrict to one HCO (Institution Account) attendee per Call.
     * @returns result { title: string, status: "success" | "error" };
     * Note: Expected only 1 HCO attendee per call)
     */
    async function isMoreThanOneHCO(record, user, db, env) {
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
                    status: "error"
                };
            } else {
                return {
                    title: `HCO count validation passed - found ${counter} HCO account(s)`,
                    status: "success"
                };
            }

    } catch (error) {
            // Error in isMoreThanOneHCO
            return {
                title: "HCO count validation failed - error occurred during validation",
                status: "error",
                error: error.message
            };
        }
    }


    // If there are arguments, extract the record data and run validation
    if (arguments && arguments.length > 0 && arguments[0]) {
        // Pass all arguments to validateVisit, not just the first one
        return [validateVisit.apply(null, Array.from(arguments))];
    }
    
    // If no arguments yet, return a function that will run validation when called
    // This is wrapped in an array to make it iterable for Promise.all()
    return [validateVisit];
  })();

