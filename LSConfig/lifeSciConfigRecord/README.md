# LifeSciConfigCategory and LifeSciConfigRecord records

LifeSciConfigCategory and LifeSciConfigRecord files are directly under `LSConfig/lifeSciConfigRecord/`:
- `lifeSciConfigCategories/` — contains LifeSciConfigCategory files
- `lifeSciConfigRecords/` — contains LifeSciConfigRecord files with field values, assignments, `isActive`, and `isOrgLevel` set

## Repository Structure

```
LSConfig/lifeSciConfigRecord/
├── lifeSciConfigCategories/
│   ├── ApplicationSettings.lifeSciConfigCategory
│   ├── DbSchema.lifeSciConfigCategory
│   └── ...
├── lifeSciConfigRecords/
│   ├── ApplicationSettings_OrgLevel.lifeSciConfigRecord
│   ├── DbSchema_Account.lifeSciConfigRecord
│   └── ...
└── package.xml
```

Each LifeSciConfigRecord file includes:
- Field values and assignments
- `isActive` and `isOrgLevel` properties set to their final values

## Instructions to deploy to a target org

### Using Salesforce CLI
```bash
sf project deploy start -d LSConfig/lifeSciConfigRecord
```

### Using Workbench
1. Zip `package.xml`, `lifeSciConfigCategories` and `lifeSciConfigRecords` folders together (do **not** include the `lifeSciConfigRecord` parent folder in the zip — select only `package.xml`, `lifeSciConfigCategories`, and `lifeSciConfigRecords`)
2. Go to **Metadata > Deploy** in Workbench
3. Click **Choose File** and select the zip
4. Choose the following options: **Single Package**, **Rollback on Error**
5. Click **Deploy**

Zip contents should be as follows:
```
├── lifeSciConfigCategories
│   ├── ApplicationSettings.lifeSciConfigCategory
│   ├── DbSchema.lifeSciConfigCategory
├── lifeSciConfigRecords
│   ├── ApplicationSettings_OrgLevel.lifeSciConfigRecord
│   ├── DbSchema_Account.lifeSciConfigRecord
│   ├── DbSchema_AccountSearchSettings.lifeSciConfigRecord
│   ├── DbSchema_ActivityPlan.lifeSciConfigRecord
└── package.xml
```

Note that deployment is an upsert; new records will be created for new files and existing records will be updated for existing files.

### Troubleshooting
If deployment fails, check the deployment error. Deployment error can also be found in **Setup > Deployment Status**.

#### No package.xml found
Make sure `package.xml` is in the zip and it is zipped along with the folders that include the xml files. Do not include the parent `lifeSciConfigRecord` folder in the zip.

#### Enter an assignment level and an assignment ID
This indicates that the profile referenced in the assignments does not exist on the org. The assignments in LifeSciConfigRecord files use "LSC Custom Profile" profile. Either create a profile with this same name on the org, or if a different profile is needed, update the files accordingly before deploying. Make sure the referenced profile exists on the org.

#### Unable to find an enum or id that matches the value provided for: ObjectValue
If there is a field that references an entity and the entity is not accessible on the org, this error will happen. DbSchema records are such. Check the API Name (file name) of the DbSchema record that failed and find the entity name in the xml file (check `ObjectValue` node). The record name usually includes the entity name too. E.g. File `DbSchema_AccountPlan` likely references `AccountPlan` entity.

## Instructions to make changes in the repository
* To add a new record, create a new file under `lifeSciConfigRecords/`. The file should include field values, assignments (if any), `isActive`, and `isOrgLevel` set to their intended values.
  * When naming records, prepend with the category name; e.g. `DbSchema_Account` where `DbSchema` is the category name
  * Assignments in LifeSciConfigRecord files use "LSC Custom Profile" profile. If different profile(s) are needed, update the files accordingly.
* To make a change to record fields or assignments, update the corresponding file under `lifeSciConfigRecords/`
* To make a change to `isActive` or `isOrgLevel`, update the corresponding file under `lifeSciConfigRecords/`
