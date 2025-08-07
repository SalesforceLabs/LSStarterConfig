// Apex Script to delete all workflows from an org
List<LifeSciStageOperationAction> operationActions = [SELECT Id FROM LifeSciStageOperationAction];
if(!operationActions.isEmpty()) delete operationActions;

List<LifeSciStageOperationCondn> operationConditions = [SELECT Id FROM LifeSciStageOperationCondn];
if(!operationConditions.isEmpty()) delete operationConditions;

List<LifeSciStageOperation> childOperations = [SELECT Id FROM LifeSciStageOperation WHERE ParentStageOperationId != null];
if(!childOperations.isEmpty()) delete childOperations;

List<LifeSciStageOperation> parentOperations = [SELECT Id FROM LifeSciStageOperation];
if(!parentOperations.isEmpty()) delete parentOperations;

List<LifeSciStageValue> values = [SELECT Id FROM LifeSciStageValue];
if(!values.isEmpty()) delete values;

List<LifeSciStagePath> paths = [SELECT Id FROM LifeSciStagePath];
if(!paths.isEmpty()) delete paths;

List<LifeSciStageAction> actions = [SELECT Id FROM LifeSciStageAction];
if(!actions.isEmpty()) delete actions;

List<LifeSciStageObject> objects = [SELECT Id FROM LifeSciStageObject];
if(!objects.isEmpty()) delete objects;
