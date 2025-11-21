/**
 * This class is used to run the LSC_ToolingUpdater class.
 * 
 * Usage:
 * // Enqueue with default chunk size (75)
List<Id> jobs = LSC_LifeSciConfigRecordsActivate.runAllQueued();
System.debug(jobs);

// Or specify chunk size
List<Id> jobs = LSC_LifeSciConfigRecordsActivate.runAllQueued(75);
System.debug(jobs);
 */

public class LSC_LifeSciConfigRecordsActivate {

    // Build requests for a list of developer names, toggling IsActive=true
    private static List<LSC_UpdateRequest> buildRequests(List<String> developerNames) {
        List<LSC_UpdateRequest> out = new List<LSC_UpdateRequest>();
        for (String dn : developerNames) {
            if (String.isBlank(dn)) {
                continue;
            }
            LSC_UpdateRequest r = new LSC_UpdateRequest();
            r.developerName = dn.trim();
            r.fieldsToUpdate = new Map<String, Object>{ 'IsActive' => true };
            out.add(r);
        }
        return out;
    }

    // Enqueue updates in chunks to avoid "Too many callouts: 101"
    // Returns job Ids for tracking
    public static List<Id> runAllQueued() {
        return runAllQueued(75);
    }

    public static List<Id> runAllQueued(Integer chunkSize) {
        if (chunkSize == null || chunkSize <= 0) {
            chunkSize = 75;
        }
        List<String> names = new List<String>{
            'AccountProviderVisitRecordTypeMapping_OrgLevel',
            'AccountSearchSettings_OrgLevel',
            'ActivityHistoryAdministration_OrgLevel',
            'ActivityHistoryRelatedLabel_OrgLevel',
            'ActivityPlanConfiguration_OrgLevel',
            'ActivityPlanSettings_OrgLevel',
            'AddressSettings_OrgLevel',
            'AffiliationReverseRoleMapping_OrgLevel',
            'AffiliationSettings_OrgLevel',
            'ApplicationSettings_OrgLevel',
            'BestTimeSettings_OrgLevel',
            'BulkUpdateRestrictedEntity_OrgLevel',
            'CalendarEvent_AssessmentTask',
            'CalendarEvent_CompletedEvent',
            'CalendarEvent_ConfirmedEvent',
            'CalendarEvent_GeneralEvent',
            'CalendarEvent_Holiday',
            'CalendarEvent_PlannedEvent',
            'CalendarEvent_TimeOffTerritory',
            'CallCustomDiscussionRecordType_OrgLevel',
            'CallDiscussionRecordType_OrgLevel',
            'ColumbusDay_OrgLevel',
            'CustomAction_SearchGoogle',
            'CustomerMergeSettings_OrgLevel',
            'DbSchema_Account',
            'DbSchema_AccountPlan',
            'DbSchema_AccountPlanObjective',
            'DbSchema_AccountPlanParticipant',
            'DbSchema_AccountPlanProduct',
            'DbSchema_AccountPlanRelaObjAnalysis',
            'DbSchema_AccountPlanRelationship',
            'DbSchema_AccountPlanStakeholder',
            'DbSchema_AccountPlanStkhldrAction',
            'DbSchema_AccountPlanStkhldrProduct',
            'DbSchema_AcctPlanPtcpStakeholder',
            'DbSchema_ActionPlan',
            'DbSchema_ActionPlanItem',
            'DbSchema_ActionPlanTemplate',
            'DbSchema_ActionPlanTemplateAssignment',
            'DbSchema_ActionPlanTemplateItem',
            'DbSchema_ActivityPlan',
            'DbSchema_ActivityPlanTerritory',
            'DbSchema_Address',
            'DbSchema_AppAlert',
            'DbSchema_AppAlertTerritory',
            'DbSchema_AppAlertUserResponse',
            'DbSchema_BusinessLicense',
            'DbSchema_BusinessLicenseProduct',
            'DbSchema_CareSpecialty',
            'DbSchema_Case',
            'DbSchema_CodeSetBundle',
            'DbSchema_CommSubConsentCmplSnpsht',
            'DbSchema_CommSubscription',
            'DbSchema_CommSubscriptionChannelType',
            'DbSchema_CommSubscriptionConsent',
            'DbSchema_ComplianceStatementDef',
            'DbSchema_Contact',
            'DbSchema_ContactPointAddress',
            'DbSchema_ContactPointBestContactTime',
            'DbSchema_ContactPointEmail',
            'DbSchema_ContactPointPhone',
            'DbSchema_ContactPointSocial',
            'DbSchema_ContentDocument',
            'DbSchema_ContentDocumentLink',
            'DbSchema_ContentVersion',
            'DbSchema_Dashboard',
            'DbSchema_DataUsePurpose',
            'DbSchema_DeviceSyncTransactionRecord',
            'DbSchema_DigitalSignature',
            'DbSchema_EngagementChannelType',
            'DbSchema_Event',
            'DbSchema_EventRelation',
            'DbSchema_Expense',
            'DbSchema_ExpenseParticipant',
            'DbSchema_ExpenseType',
            'DbSchema_Folder',
            'DbSchema_GoalAssignment',
            'DbSchema_GoalDefinition',
            'DbSchema_GoalDefinitionProduct',
            'DbSchema_Group',
            'DbSchema_GroupMember',
            'DbSchema_HealthcareFacility',
            'DbSchema_HealthcareProvider',
            'DbSchema_HealthcareProviderNpi',
            'DbSchema_HealthcareProviderSpecialty',
            'DbSchema_Holiday',
            'DbSchema_Inquiry',
            'DbSchema_InquiryQuestion',
            'DbSchema_InquiryQuestionAnswer',
            'DbSchema_LifeSciAccountListColumn',
            'DbSchema_LifeSciAccountListMember',
            'DbSchema_LifeSciAcctListFilterCrit',
            'DbSchema_LifeSciDataChangeDef',
            'DbSchema_LifeSciDataChangeRequest',
            'DbSchema_LifeSciDataChgDefMngFld',
            'DbSchema_LifeSciDataChgDefRecType',
            'DbSchema_LifeSciDataChgPersonaDef',
            'DbSchema_LifeSciEmailTemplate',
            'DbSchema_LifeSciEmailTmplFragment',
            'DbSchema_LifeSciEmailTmplRelaFrgmt',
            'DbSchema_LifeSciEmailTmplSnapshot',
            'DbSchema_LifeScienceAccountList',
            'DbSchema_LifeScienceAccountListObject',
            'DbSchema_LifeScienceCustomScript',
            'DbSchema_LifeScienceEmail',
            'DbSchema_LifeSciMarketableProduct',
            'DbSchema_LifeSciProductAcctRstrc',
            'DbSchema_LifeSciStageAction',
            'DbSchema_LifeSciStageObject',
            'DbSchema_LifeSciStageOperation',
            'DbSchema_LifeSciStageOperationAction',
            'DbSchema_LifeSciStageOperationCondn',
            'DbSchema_LifeSciStagePath',
            'DbSchema_LifeSciStageValue',
            'DbSchema_Location',
            'DbSchema_ObjectTerritory2Association',
            'DbSchema_Presentation',
            'DbSchema_PresentationClickStrmEntry',
            'DbSchema_PresentationForum',
            'DbSchema_PresentationLinkedPage',
            'DbSchema_PresentationPage',
            'DbSchema_PresentationPageProduct',
            'DbSchema_PresentationPartyAccess',
            'DbSchema_Product2',
            'DbSchema_ProductBatchItem',
            'DbSchema_ProductDisbursement',
            'DbSchema_ProductGuidance',
            'DbSchema_ProductionBatch',
            'DbSchema_ProductItem',
            'DbSchema_ProductTerrDtlAvailability',
            'DbSchema_ProductTerritoryAvailability',
            'DbSchema_ProviderAcctProductInfo',
            'DbSchema_ProviderAcctTerritoryInfo',
            'DbSchema_ProviderActivityGoal',
            'DbSchema_ProviderActivityGoalMeasure',
            'DbSchema_ProviderActivityMeasureType',
            'DbSchema_ProviderActvtyPlanAdjusment',
            'DbSchema_ProviderAffiliation',
            'DbSchema_ProviderAffiliationProduct',
            'DbSchema_ProviderSampleLimit',
            'DbSchema_ProviderSampleLimitTemplate',
            'DbSchema_ProviderSmplLmtTmplAssignment',
            'DbSchema_ProviderVisit',
            'DbSchema_ProviderVisitDtlProductMsg',
            'DbSchema_ProviderVisitMarketingItem',
            'DbSchema_ProviderVisitProdDetailing',
            'DbSchema_ProviderVisitProdDiscussion',
            'DbSchema_ProviderVisitRqstSample',
            'DbSchema_PrvdAccountTerritorySummary',
            'DbSchema_PrvdAccountUserGroupInfo',
            'DbSchema_PrvdActvtyGoalMeasureProdt',
            'DbSchema_PrvdClassificationLayout',
            'DbSchema_PrvdClsfnAttrDefinition',
            'DbSchema_PrvdClsfnLayoutAttribute',
            'DbSchema_PrvdVstSmplLmtDiscrepancy',
            'DbSchema_PrvdVstSmplLmtTransaction',
            'DbSchema_RecordAlert',
            'DbSchema_RecordType',
            'DbSchema_Report',
            'DbSchema_Sprint',
            'DbSchema_Subject',
            'DbSchema_SubjectAssignment',
            'DbSchema_Survey',
            'DbSchema_SurveyEngagementContext',
            'DbSchema_SurveyInvitation',
            'DbSchema_SurveyPage',
            'DbSchema_SurveyQstnResponseOffline',
            'DbSchema_SurveyQuestion',
            'DbSchema_SurveyQuestionChoice',
            'DbSchema_SurveyQuestionResponse',
            'DbSchema_SurveyResponse',
            'DbSchema_SurveyResponseOffline',
            'DbSchema_SurveySubject',
            'DbSchema_SurveyVersion',
            'DbSchema_Territory2',
            'DbSchema_TerritoryAccountScore',
            'DbSchema_TerritoryAcctProdMsgScore',
            'DbSchema_TerritoryAcctRcmdAction',
            'DbSchema_TerritoryProdtQtyAllocation',
            'DbSchema_TerritoryUserDowntime',
            'DbSchema_TimePeriod',
            'DbSchema_Topic',
            'DbSchema_TopicAssignment',
            'DbSchema_User',
            'DbSchema_UserTerritory2Association',
            'DbSchema_VideoCall',
            'DbSchema_VideoCallParticipant',
            'DbSchema_VideoCallPtcpRequest',
            'DbSchema_VideoCallPtcpSession',
            'DbSchema_VideoCallRecording',
            'DbSchema_Visit',
            'DbSchema_Visitor',
            'DEASettings_OrgLevel',
            'DEASettings_LSCProfile',
            'DTVComponentConfig_StudyObjectivesTreeView',
            'DTVObjectConfig_Contact',
            'DTVObjectConfig_Contract',
            'DTVObjectConfig_Opportunity',
            'ExternalSearchPreferences_OrgLevel',
            'ExternalSearchUserSettings_OrgLevel',
            'FriBusHrsWDConfig_OrgLevel',
            'HolidayWDConfig_OrgLevel',
            'InventoryManagementSettings_OrgLevel',
            'KAMSettings_OrgLevel',
            'LogSettings_OrgLevel',
            'MonBusHrsWDConfig_OrgLevel',
            'OptAdministration_OrgLevel',
            'PlannerAdministration_OrgLevel',
            'PlannerAdministration_LSCProfile',
            'ProfileBasedAppSettings_OrgLevel',
            'QuickAction_SearchEmail',
            'QuickAction_SearchIntelligentContent',
            'ReportsAndDashboardsSync_OrgLevel',
            'SatBusHrsWDConfig_OrgLevel',
            'SearchBeforeCreate_OrgLevel',
            'SprintSettings_OrgLevel',
            'StateDistributorLicenseSettings_OrgLevel',
            'StateDistributorLicenseSettings_LSCProfile',
            'StateLicenseNumberSettings_OrgLevel',
            'StateLicenseNumberSettings_LSCProfile',
            'SunBusHrsWDConfig_OrgLevel',
            'SyncProcessorConfiguration_OrgLevel',
            'SyncTransactionAdminView_All',
            'SyncTransactionAdminView_Failed',
            'SyncTransactionAdminView_Success',
            'SyncTransactionConfig_OrgLevel',
            'TASAccount_Activity_OrgLevel',
            'TASAssessmentTask_OrgLevel',
            'TASInquiry_OrgLevel',
            'TASLifeScienceEmail_OrgLevel',
            'TASSurveyResponse_OrgLevel',
            'TASVisit_OrgLevel',
            'TerritoryManagement_OrgLevel',
            'ThurBusHrsWDConfig_OrgLevel',
            'TimeOffTerritorySettings_OrgLevel',
            'TimeOffTerritorySlots_OrgLevel',
            'TimeOffTerritoryWorkingDaySettings_OrgLevel',
            'TOT_DefaultCivicActivity_OrgLevel',
            'TOT_DefaultDisciplinary_OrgLevel',
            'TOT_DefaultHoliday_OrgLevel',
            'TOT_DefaultPersonalAbsence_OrgLevel',
            'TOT_DefaultTraining_OrgLevel',
            'TOT_DefaultUnexcused_OrgLevel',
            'TOT_DefaultVacation_OrgLevel',
            'TOTWDConfig_OrgLevel',
            'TueBusHrsWDConfig_OrgLevel',
            'VideoCallPhoneNumber_USA',
            'VideoCallSettings_Twilio',
            'WedBusHrsWDConfig_OrgLevel'
        };
        // In tests, avoid deep chaining by limiting the set and chunk size
        if (Test.isRunningTest()) {
            Integer limitCount = Math.min(2, names.size());
            List<String> limited = new List<String>();
            for (Integer i = 0; i < limitCount; i++) {
                limited.add(names[i]);
            }
            names = limited;
            chunkSize = limitCount;
        }
        Id jobId = System.enqueueJob(new LSC_UpdateQueue(names, 0, chunkSize));
        return new List<Id>{ jobId };
    }

    // Test helper and utility: allow enqueuing with a provided, smaller name list to control callouts/chaining
    @TestVisible
    public static List<Id> runWithNamesQueued(List<String> developerNames, Integer chunkSize) {
        List<String> safe = developerNames == null ? new List<String>() : new List<String>(developerNames);
        Integer c = (chunkSize == null || chunkSize <= 0) ? safe.size() : chunkSize;
        Id jobId = System.enqueueJob(new LSC_UpdateQueue(safe, 0, c));
        return new List<Id>{ jobId };
    }
}


