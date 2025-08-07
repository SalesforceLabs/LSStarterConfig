List<ProviderSampleLimit> limits = [
    SELECT Id, ProductId, Rule, SourceSystemIdentifier 
    FROM ProviderSampleLimit 
    WHERE SourceSystemIdentifier = 'LifeSciMarketableProductRef'
];

List<ProviderSampleLimit> limitsToUpdate = new List<ProviderSampleLimit>();

for(ProviderSampleLimit sampleLimit : limits) {
    if(String.isNotBlank(sampleLimit.Rule)) {
        try {
            // Parse the Rule JSON
            Map<String, Object> ruleMap = (Map<String, Object>)JSON.deserializeUntyped(sampleLimit.Rule);
            Map<String, Object> template = (Map<String, Object>)ruleMap.get('template');
            
            // Handle operations in template
            if(template.containsKey('operations')) {
                List<Object> operations = (List<Object>)template.get('operations');
                // Process each operation in the template
                for(Object operation : operations) {
                    Map<String, Object> opMap = (Map<String, Object>)operation;
                    Map<String, Object> info = (Map<String, Object>)opMap.get('info');
                    if(info != null && info.containsKey('productId')) {
                        String productId = (String)info.get('productId');
                        // Replace the reference with actual ProductId
                        if(productId == '@LifeSciMarketableProductRef') {
                            info.put('productId', sampleLimit.ProductId);
                        }
                    }
                }
            }
            
            // Handle products section if it exists
            if(ruleMap.containsKey('products')) {
                Map<String, Object> products = (Map<String, Object>)ruleMap.get('products');
                // Handle both the key and the productId in info
                for(String productKey : new List<String>(products.keySet())) {
                    Map<String, Object> productData = (Map<String, Object>)products.get(productKey);
                    if(productData.containsKey('info')) {
                        Map<String, Object> info = (Map<String, Object>)productData.get('info');
                        if(info != null && info.containsKey('productId')) {
                            String productId = (String)info.get('productId');
                            if(productId == '@LifeSciMarketableProductRef') {
                                info.put('productId', sampleLimit.ProductId);
                            }
                        }
                    }
                    
                    // If the key itself is the reference, update it
                    if(productKey == '@LifeSciMarketableProductRef') {
                        products.remove(productKey);
                        products.put(sampleLimit.ProductId, productData);
                    }
                }
            }
            
            // Update the Rule field with modified JSON
            sampleLimit.Rule = JSON.serialize(ruleMap);
            limitsToUpdate.add(sampleLimit);
        } catch(Exception e) {
            System.debug('Error processing record ' + sampleLimit.Id + ': ' + e.getMessage());
        }
    }
}

if(!limitsToUpdate.isEmpty()) {
    try {
        update limitsToUpdate;
        System.debug('Successfully updated ' + limitsToUpdate.size() + ' records');
    } catch(Exception e) {
        System.debug('Error updating records: ' + e.getMessage());
    }
}
