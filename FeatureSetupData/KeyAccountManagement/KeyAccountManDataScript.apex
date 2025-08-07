// KAM Data Setup Script
// This script sets up the data structure for Key Account Management

// Query existing records loaded via JSON
List<AccountPlan> accountPlans = [SELECT Id, Name, AccountId FROM AccountPlan WHERE Name IN ('Mayo Clinic Oncology Plan', 'Johns Hopkins Cancer Plan', 'Stanford Health Oncology Plan')];

LifeSciMarketableProduct relatedProduct = [SELECT Id FROM LifeSciMarketableProduct LIMIT 1];

List<AccountPlanObjective> accountPlanObjectives = [
    SELECT Id, Name, AccountPlanId
    FROM AccountPlanObjective
    WHERE AccountPlanId IN :accountPlans
];

// Create Account Plan Relationships
List<AccountPlanRelationship> accountPlanRelationships = new List<AccountPlanRelationship>();
for (Integer i = 0; i < accountPlans.size(); i++) {
    for (Integer j = 0; j < accountPlans.size(); j++) {
        if (i != j) {
            accountPlanRelationships.add(new AccountPlanRelationship(
                AccountPlanId = accountPlans[i].Id,
                RelatedAccountPlanId = accountPlans[j].Id
            ));
        }
    }
}
insert accountPlanRelationships;

// Create Account Plan Stakeholders
List<AccountPlanStakeholder> accountPlanStakeholders = new List<AccountPlanStakeholder>();
for (AccountPlan ap : accountPlans) {
    accountPlanStakeholders.add(new AccountPlanStakeholder(
        AccountPlanId = ap.Id,
        RoleType = 'Internal',
        StakeholderRefnRecordId = ap.AccountId
    ));
}
insert accountPlanStakeholders;

// Create Action Plan Template
ActionPlanTemplate actionPlanTemplate = new ActionPlanTemplate(
    Name = 'Research Collaboration Template',
    Description = 'Template for managing research collaboration activities',
    TargetEntityType = 'AccountPlanObjective',
    ActionPlanType = 'KAM',
    IsAdHocItemCreationEnabled = true
);
insert actionPlanTemplate;

// Note: APTV is created automatically upon creating APT
ActionPlanTemplateVersion templateVersion = [SELECT Id FROM ActionPlanTemplateVersion WHERE ActionPlanTemplateId = :actionPlanTemplate.Id];

// Create Template Items and Values (AssessmentTask style)
Map<String, Map<String, String>> itemDetails = new Map<String, Map<String, String>>{
    'Initial Meeting' => new Map<String, String>{'AssessmentTask.Name' => 'Initial Meeting'},
    'Research Assessment' => new Map<String, String>{'AssessmentTask.Name' => 'Research Assessment'},
    'Collaboration Planning' => new Map<String, String>{'AssessmentTask.Name' => 'Collaboration Planning'}
};

List<ActionPlanTemplateItem> templateItems = new List<ActionPlanTemplateItem>();
List<ActionPlanTemplateItemValue> itemValues = new List<ActionPlanTemplateItemValue>();
Integer displayOrder = 1;
for (String itemName : itemDetails.keySet()) {
    ActionPlanTemplateItem item = new ActionPlanTemplateItem();
    item.Name = itemName;
    item.ActionPlanTemplateVersionId = templateVersion.Id;
    item.ItemEntityType = 'AssessmentTask';
    item.DisplayOrder = displayOrder++;
    item.IsRequired = true;
    insert item;
    templateItems.add(item);
    Map<String, String> fieldValues = itemDetails.get(itemName);
    for (String fieldName : fieldValues.keySet()) {
        ActionPlanTemplateItemValue itemValue = new ActionPlanTemplateItemValue();
        itemValue.ActionPlanTemplateItemId = item.Id;
        itemValue.ItemEntityFieldName = fieldName;
        itemValue.ValueLiteral = fieldValues.get(fieldName);
        itemValues.add(itemValue);
    }
}
if (!itemValues.isEmpty()) {
    insert itemValues;
}

templateVersion.Status = 'Final';
update templateVersion;

// Create Action Plans for each Objective
List<ActionPlan> actionPlans = new List<ActionPlan>();
for(AccountPlanObjective apo : accountPlanObjectives) {
    // Find the related AccountPlan for this objective
    AccountPlan relatedPlan = null;
    for (AccountPlan ap : accountPlans) {
        if (apo.AccountPlanId == ap.Id) {
            relatedPlan = ap;
            break;
        }
    }
    String planName = (relatedPlan != null) ? relatedPlan.Name : 'Plan 1';
    actionPlans.add(new ActionPlan(
        Name = 'Action Plan - ' + planName,
        TargetId = apo.Id,
        ActionPlanTemplateVersionId = templateVersion.Id,
        ActionPlanType = 'KAM',
        StartDate = Date.today(),
        StatusCode = 'NotStarted',
        OwnerId = UserInfo.getUserId()
    ));
}
insert actionPlans;

//Creating Situational Analysis
List<AccountPlanRelaObjAnalysis> analyses = new List<AccountPlanRelaObjAnalysis>{
    new AccountPlanRelaObjAnalysis(
        AccountPlanId = accountPlans[0].Id,
        RelatedObjectId = relatedProduct.Id,
        LegalAnalysisInfo = 'Compliant with all current regulations.',
        EnvironmentalAnalysisInfo = 'No major environmental risks identified.',
        EconomicalAnalysisInfo = 'Strong market growth expected.',
        PoliticalAnalysisInfo = 'Stable political environment.',
        SocialAnalysisInfo = 'Positive public perception.',
        OpportunitiesAnalysisInfo = 'Expansion into new markets.',
        StrengthAnalysisInfo = 'Strong R&D capabilities.',
        TechnologicalAnalysisInfo = 'Cutting-edge technology adoption.',
        ThreatsAnalysisInfo = 'Emerging competitors.',
        WeaknessAnalysisInfo = 'Limited distribution network.',
        SourceSystemName = 'ApexScript',
        SourceSystemIdentifier = 'APEX-001'
    )
};
insert analyses;

// Create ProviderAcctProductInfo records
List<ProviderAcctProductInfo> providerAcctProductInfos = new List<ProviderAcctProductInfo>();
for(AccountPlan ap : accountPlans) {
    providerAcctProductInfos.add(new ProviderAcctProductInfo(
        AccountId = ap.AccountId,
        ProductId = relatedProduct.Id,
        Description = 'Provider account product information for ' + ap.Name
    ));
}
insert providerAcctProductInfos;

// Create AccountPlanStakeholderProduct records
List<AccountPlanStkhldrProduct> stakeholderProducts = new List<AccountPlanStkhldrProduct>();
for(AccountPlanStakeholder stakeholder : accountPlanStakeholders) {
    stakeholderProducts.add(new AccountPlanStkhldrProduct(
        AccountPlanStakeholderId = stakeholder.Id,
        ProductId = relatedProduct.Id
    ));
}
insert stakeholderProducts;

// Create AccountPlanStakeholderAction records
List<AccountPlanStkhldrAction> stakeholderActions = new List<AccountPlanStkhldrAction>();
for(AccountPlanStakeholder stakeholder : accountPlanStakeholders) {
    // Get the related ActionPlan for this stakeholder's AccountPlan
    List<AccountPlan> relatedPlans = [SELECT Id FROM AccountPlan WHERE Id = :stakeholder.AccountPlanId];
    if (relatedPlans.isEmpty()) continue;
    AccountPlan relatedPlan = relatedPlans[0];

    // Find AccountPlanObjective for this AccountPlan
    List<AccountPlanObjective> relatedObjectives = [SELECT Id FROM AccountPlanObjective WHERE AccountPlanId = :relatedPlan.Id LIMIT 1];
    if (relatedObjectives.isEmpty()) continue;
    AccountPlanObjective relatedObjective = relatedObjectives[0];

    // Find ActionPlan that targets this Objective
    List<ActionPlan> relatedActionPlans = [SELECT Id FROM ActionPlan WHERE TargetId = :relatedObjective.Id LIMIT 1];
    if (relatedActionPlans.isEmpty()) continue;
    ActionPlan relatedActionPlan = relatedActionPlans[0];

    stakeholderActions.add(new AccountPlanStkhldrAction(
        AccountPlanStakeholderId = stakeholder.Id,
        ActionReferenceRecordId = relatedActionPlan.Id
    ));
}
insert stakeholderActions;

//TODO : commented as currently we don't have AccountPlanObjective as a value for AssociatedObjectId field , Ongoing W-18692906
// List<ActionPlanTemplateAssignment> templateAssignments = new List<ActionPlanTemplateAssignment>();
// for(AccountPlanObjective apo : accountPlanObjectives) {
//     // Find the related AccountPlan for this objective
//     AccountPlan relatedPlan = null;
//     for (AccountPlan ap : accountPlans) {
//         if (apo.AccountPlanId == ap.Id) {
//             relatedPlan = ap;
//             break;
//         }
//     }

//     if (relatedPlan != null) {
//         // Create assignment for GoalDefinition
//         templateAssignments.add(new ActionPlanTemplateAssignment(
//             ActionPlanTemplateVersionId = templateVersion.Id,
//             AssociatedObjectId = relatedPlan.Id
//         ));
//     }
// }
// insert templateAssignments;

// Get the existing ParticipantRole created via metadata
// ParticipantRole pr = [SELECT Id FROM ParticipantRole WHERE DeveloperName = 'OncologyDirector' LIMIT 1];

// // Create AccountPlanParticipant records
// List<AccountPlanParticipant> accountPlanParticipants = new List<AccountPlanParticipant>();
// for(ActionPlan ap : actionPlans) {
//     // Get the related AccountPlan for this ActionPlan
//     AccountPlanObjective relatedObjective = [SELECT Id, AccountPlanId FROM AccountPlanObjective WHERE Id = :ap.TargetId];
//     AccountPlan relatedPlan = [SELECT Id FROM AccountPlan WHERE Id = :relatedObjective.AccountPlanId];
    
//     accountPlanParticipants.add(new AccountPlanParticipant(
//         AccountPlanId = relatedPlan.Id,
//         ParticipantId = UserInfo.getUserId(),
//         ParticipantRoleId = pr.Id // Use the queried ParticipantRole's Id
//     ));
// }
// insert accountPlanParticipants;
