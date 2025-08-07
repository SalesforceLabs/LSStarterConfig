# LifeSciConfigCategory and LifeSciConfigRecord records
LifeSciConfigCategory and LifeSciConfigRecord files are in two folders:
1. **1_inactive** folder includes LifeSciConfigCategory and LifeSciConfigRecord files. Each LifeSciConfigRecord file includes the field values and assignments. LifeSciConfigRecord files do not set isActive and isOrgLevel, so the records created on the target org will have isActive and isOrglevel set to false.
2. **2_activate** folder includes LifeSciConfigRecord files as well. Each LifeSciConfigRecord file includes the isActive and isOrgLevel properties. isActive is set to true and isOrgLevel is set to true for the records that require it.

## Instructions to deploy to a target org
1. Zip package.xml, lifeSciConfigCategories and lifeSciConfigRecords folders under 1_inactive folder and deploy to the org using metadata api. (Do not include 1_inactive folder in the zip, select package.xml, lifeSciConfigCategories and lifeSciConfigRecords folders and zip only those)
    1. Note that assignments in LifeSciConfigRecord files use Medical Sales Representative profile. If a different profile is needed, update the files accordingly before creating the zip.
2. Zip package.xml and lifeSciConfigRecords folders under 2_activate folder and deploy to the org using metadata api.(Do not include 2_activate folder in the zip, select package.xml and lifeSciConfigRecords folders and zip only those)

Zip contents should be as follows, e.g.
```
├── lifeSciConfigCategories
│   ├── ApplicationSettings.lifeSciConfigCategory
│   ├── DbSchema.lifeSciConfigCategory
├── lifeSciConfigRecords
│   ├── ApplicationSettings_OrgLevel.lifeSciConfigRecord
│   ├── DbSchema_Account.lifeSciConfigRecord
│   ├── DbSchema_AccountSearchSettings.lifeSciConfigRecord
│   ├── DbSchema_ActivityPlan.lifeSciConfigRecord
└── package.xml

```

Note that deployment is an upsert; new records will be created for new files and existing records will be updated for existing files.

**IMPORTANT:** The first deployment will set isActive and isOrgLevel on the records to false, so make sure to follow with the second deployment.

### Deploying through workbench
Go to Metadata/Deploy.
Click Choose File. Choose the zip file to be deployed.
Choose the following options: Single Package, Auto Update Package, Rollback on Error
Click Deploy.

### Troubleshooting
If deployment fails, check the deployment error. Deployment error can also be found in Setup/Deployment Status.
#### No package.xml found
Make sure package.xml is in the zip and it is zipped along with the folder(s) that include the xml files. Do not include the parent folder 1_inactive or 2_activate in the zip.
#### Enter an assignment level and an assignment ID.
This indicates that the profile that is referenced in the assignments does not exist on the org. The assignments in LifeSciConfigRecord files use Medical Sales Representative profile. Either create a profile with this same name on the org, or if a different profile is needed, update the files accordingly before creating the zip. Make sure the referenced profile exists on the org.
#### Unable to find an enum or id that matches the value provided for: ObjectValue
If there is a field that reference an entity and the entity is not accessible on the org, this error will happen. DbSchema records are such. Check the API Name (file name) of the DbSchema record that failed and find the entity name in the xml file (check ObjectValue node). The record name usually includes the entity name, too. E.g. File DbSchema_PartyRoleRelation likely references PartyRoleRelation entity.

## Instructions to make changes in the repository
* To add a new category, create a new file under 1_inactive/lifeSciConfigCategories
* To add a new record, create a new file under 1_inactive/lifeSciConfigRecords and a new file under 2_activate/lifeSciConfigRecords. The file under 1_inactive should include field values and assignments, if any. The file under 2_activate should only include lifeSciConfigRecord properties; i.e. omit field values and assignments.
  * When naming records, prepend with the category name; e.g. DbSchema_Account where DbSchema is the category name, e.g. ApplicationSettings_Orglevel where ApplicationSettings is the record name. Use the same for master label; e.g. DbSchema_Account, ApplicationSettings_Orglevel.
  * Assignments in LifeSciConfigRecord files use Medical Sales Representative profile. If different profile(s) is needed, update the files accordingly.
* To make a change to record fields or assignments, update the corresponding file under 1_inactive/lifeSciConfigCategories
* To make a change to record isActive or isOrgLevel fields, update the corresponding file under 2_activate/lifeSciConfigRecords
