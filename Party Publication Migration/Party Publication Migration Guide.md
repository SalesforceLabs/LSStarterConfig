# Migrate Party Publications to Publications: Setup Guide

This guide shows Salesforce admins how to move **PartyPublication** records  into **Publication** and **Publication Contributor** records with the migration script.

| You get | You don't get (by design) |
|---|---|
| One **Publication** per paper, plus one **Publication Contributor** per PartyPublication record | Publication Venue or Contributor Affiliation records |
| A record of every PartyPublication's result (Migrated / Failed + the reason), kept either in 5 fields on PartyPublication (**Path A**) or in a separate log object so PartyPublication is never touched (**Path B**) | Your own custom fields, notes, or attachments (see [Step 9](#step-9-optional-move-your-custom-fields-notes-and-attachments) for how to move them yourself) |
| A status, error code and fix instructions on every record that couldn't be migrated | Deleted PartyPublication records: the script never deletes them |
| Safe reruns: fix the data, run again, and only the unfinished records are processed | Matching against Publications you already created by hand |

```
 PartyPublication (one row per author per paper)          Publication (one per paper)
 ┌─────────────────────────────────────────┐              ┌──────────────────────────┐
 │ Dr. Lee  | "Gene X..." | 10.1038/abc    │──┐           │ "Gene X..."  10.1038/abc │
 │ Dr. Shah | "Gene X..." | 10.1038/abc    │──┼── same ──▶│                          │
 │ Univ. Y  | "Gene X..." | 10.1038/abc    │──┘  paper    └────────────┬─────────────┘
 └──────────────────┬──────────────────────┘                           │ master-detail
                    │ PublicationContributor__c (lookup)    ┌──────────▼─────────────┐
                    └──────────────────────────────────────▶│ Publication Contributor│ × 3
                                                            │ Dr. Lee / Dr. Shah / Y │
                                                            └────────────────────────┘
```

**Order matters.** Each step depends on the one before it:

| Step | What | Time |
|---|---|---|
| [0](#step-0-choose-your-path-a-or-b) | **Choose Path A or Path B** | 5 min |
| [1](#step-1-create-the-custom-fields) | Create the tracking fields (Path A) or the log object (Path B), plus 1 field on Publication | 15 min |
| [2](#step-2-check-the-running-users-permissions) | Check the running user's permissions, turn off your automation (Path A) | 10 min |
| [3](#step-3-deploy-the-apex-classes) | Set the Path switch, deploy the 17 Apex classes, check the prerequisites | 15 min |
| [4](#step-4-create-the-list-view-and-report) | List view and report for triage | 10 min |
| [5](#step-5-read-this-before-running-what-the-script-changes) | Read what the script changes on your records | 5 min |
| [6](#step-6-run-the-pre-flight-report-and-fix-the-data) | Pre-flight report, then fix the data | varies |
| [7](#step-7-run-the-migration) | Run the migration | minutes to hours |
| [8](#step-8-review-results-fix-and-rerun) | Review results, fix, rerun | varies |
| [9](#step-9-optional-move-your-custom-fields-notes-and-attachments) | (Optional) Move custom fields, notes and attachments | varies |

> **Do it in a full or partial-copy sandbox first.** Run the whole guide there, check the results (Step 8), then repeat in production.

**Want to know how it works and why?** Read [Reference: How the migration works](#reference-how-the-migration-works-business-logic): paper matching, linking to Contributors, status tracking and rerun logic, all in one place.

**Who this guide is for:** someone comfortable with Apex, Setup and the Developer Console.

---

## Background in 2 minutes

| Term | Meaning |
|---|---|
| **PartyPublication** (source) | A Life Sciences record that says "this person or organization is linked to this paper". It is flat: **one record per author per paper**. A paper with 3 authors has 3 records, each repeating the title, date and identifier. |
| **Publication** (target) | The record for the paper itself. **One per paper**. |
| **Publication Contributor** (target) | The record for one author of a paper. It is a master-detail child of Publication. **One per PartyPublication record**. |
| **Paper key** | How the script decides that 3 PartyPublication records are the same paper: the same Publication Identifier (DOI, PMID …) or, when there is no identifier, the same Title + Publication Date + Published On. The script stores a fingerprint of this in `MigrationGroupKey__c`. Details: [How papers are matched](#how-papers-are-matched). |
| **Migration fields** | Five custom fields **you** create on PartyPublication (Step 1a). The script writes its progress there. That is how it knows what it already migrated, so reruns don't create duplicates. |
| **Pre-flight** | A read-only report that finds papers the script would split into two Publications. Run it before the migration. |
| **Compensation** | If the script creates a Publication but then can't link it back to its PartyPublication record, it deletes that Publication again, so nothing is orphaned. It only ever deletes records created in the same run. |

Every PartyPublication record is in exactly one of these states:

```
            ┌──── run ────▶ Migrated     final; skipped on every later run
 (blank) ───┤
 not yet    └──── run ────▶ Failed ──── you fix the data, then rerun ───▶ Migrated
 processed                  (error code + message say what to fix)

 Excluded = you set it by hand; the script never touches the record
```

**The whole job is a loop:** run → read the failures → fix the data → run again, until nothing is Failed. Rerunning is always safe.

---

## Step 0: Choose your path (A or B)

The script has to remember, for every PartyPublication record, whether it is Migrated, Failed or Excluded. That memory is what makes reruns safe. You choose **where it is kept**. Both paths are built into the same Apex. You switch with **one Boolean** in one class (Step 3).

```
 PATH A (default)                              PATH B
 5 fields ON PartyPublication                  Separate object PublicationMigrationLog__c
 ┌──────────────────────┐                      ┌──────────────────────┐   ┌─────────────────────────┐
 │ PartyPublication     │  script UPDATES it   │ PartyPublication     │   │ Publication Migration   │
 │  + MigrationStatus   │                      │ (never touched:      │──▶│ Log (1 row per record)  │
 │  + ErrorCode ...     │                      │  read only)          │   │ Status, ErrorCode ...   │
 └──────────────────────┘                      └──────────────────────┘   └─────────────────────────┘
```

| | **Path A: fields on PartyPublication** | **Path B: log object** |
|---|---|---|
| Schema change on PartyPublication | 5 new fields | **None** |
| PartyPublication records updated | **Yes**, once per record (audit dates change; your triggers, flows and validation rules run; change events publish) | **No** |
| Where you see failures | List view on PartyPublication | List view on the log object (with a link back to the record) |
| Marking a record Excluded | Edit a field on the record | Upsert a log row (Data Loader) |
| Pre-flight report | Works | Works |
| Tests included in this folder | **Yes** (Path A) | **No** (see [Step 3](#3b-deploy)) |
| Extra object to maintain afterwards | No | Yes (can be deleted when the migration is done and verified) |

**When to use which:**
- **Path A** if you accept record updates on PartyPublication (or have no automation on it). It is the simplest and the one with tests.
- **Path B** if your org syncs, audits or reacts to changes on PartyPublication, or the data owner says the source records must not be modified. Choose it when "modified since" integrations, change data capture, or compliance rules make Path A unacceptable.

> **Choose once.** Each path keeps its own record of what was migrated. If you migrate part of the data on one path and then switch, the script can't see the earlier results and creates duplicate Publications.

Wherever a step below applies to only one path it is marked **Path A** or **Path B**. Unmarked steps apply to both.

---

## Before you start

| Requirement | How to check |
|---|---|
| PartyPublication is available | Setup → Object Manager → **Party Publication** exists |
| Publications is available | Setup → Object Manager → **Publication** and **Publication Contributor** exist |
| The org is on API version **68.0** or later | Setup → Apex Classes → any class → Version settings |
| Running user is a System Administrator (or equivalent) with **Author Apex** (needed for Execute Anonymous and to deploy) | Setup → Users → the user → Profile → System Permissions |
| In a **sandbox**: email deliverability is **All email** | Setup → Email → Deliverability → Access level. Sandboxes default to *System email only*, which can stop the summary emails from arriving. The migration still works; you would read the results with the Step 8 queries instead |
| (**Optional**, if you would like to use CLI to deploy the Apex class) Salesforce CLI (`sf`) and the source folder `partypublication-migration/` on your machine, **or** VS Code with Salesforce Extensions | `sf --version` |

---

## Step 1: Create the custom fields

The script finds these fields **by their API names**, so type them exactly as shown, including capitalization. If a field or object is missing, misspelled, or the wrong type, the script refuses to start and names the problem in its summary email. Nothing is created or changed in that case.

Do **1a (Path A)** or **1a-B (Path B)**, never both. Then do 1b and 1c, which apply to both paths.

### 1a. Path A: five fields on Party Publication

Setup → Object Manager → **Party Publication** → Fields & Relationships → **New**.

| # | Field Label | API Name (exact) | Data Type | Settings |
|---|---|---|---|---|
| 1 | Publication Contributor | `PublicationContributor__c` | Lookup Relationship → **Publication Contributor** | "What to do if the lookup record is deleted?" → **Clear the value of this field**. Don't use "Don't allow deletion": you'd never be able to delete a migrated contributor. |
| 2 | Migration Status | `MigrationStatus__c` | Picklist | Values, one per line, API names exactly: **`Migrated`**, **`Failed`**, **`Excluded`**. No default value. |
| 3 | Migration Error Code | `MigrationErrorCode__c` | Text | Length **80** |
| 4 | Migration Message | `MigrationMessage__c` | Text Area (Long) | Length **32,768**, visible lines 5 |
| 5 | Migration Group Key | `MigrationGroupKey__c` | Text | Length **64**. Check **External ID**. Leave **Unique** unchecked (records of the same paper share a key). |

Page layouts: add fields 1–4 to the Party Publication layout so users can see why a record failed. Field 5 is managed by the script; keep it off the layout or make it read-only.

### 1a-B. Path B: the log object (nothing is added to Party Publication)

**Create the object.** Setup → Object Manager → **Create → Custom Object**:

| Setting | Value |
|---|---|
| Label / Plural Label | `Publication Migration Log` / `Publication Migration Logs` |
| Object Name (API name) | `PublicationMigrationLog` (becomes **`PublicationMigrationLog__c`**) |
| Record Name | Label `Log Number`, Data Type **Auto Number**, Display Format `PML-{00000000}`, Starting Number `1`. **It must be Auto Number**: the script doesn't provide a name, and the prerequisite check fails otherwise |
| Allow Reports, Allow Search | Checked (you need the report in Step 4) |
| Deployment Status | **Deployed** |
| Track Field History, Allow Activities | Unchecked |

**Create these 7 fields** on it (Fields & Relationships → New):

| # | Field Label | API Name (exact) | Data Type | Settings |
|---|---|---|---|---|
| 1 | Source Id | `SourceId__c` | Text | Length **18**. Check **Required**, **Unique** and **External ID**. It holds the PartyPublication Id, and the script uses it to find the row again, so it must be unique |
| 2 | Group Key | `GroupKey__c` | Text | Length **64**. Check **External ID**. Leave **Unique** unchecked (records of the same paper share a key) |
| 3 | Status | `Status__c` | Picklist | Values, one per line, API names exactly: **`Migrated`**, **`Failed`**, **`Excluded`**. No default value |
| 4 | Error Code | `ErrorCode__c` | Text | Length **80** |
| 5 | Message | `Message__c` | Text Area (Long) | Length **32,768**, visible lines 5 |
| 6 | Publication Contributor | `PublicationContributor__c` | Lookup Relationship → **Publication Contributor** | "If the lookup record is deleted" → **Clear the value of this field** |
| 7 | Publication | `Publication__c` | Lookup Relationship → **Publication** | "If the lookup record is deleted" → **Clear the value of this field** |

Optional but handy for triage: a Formula (Text) field `Source Record` = `HYPERLINK("/" & SourceId__c, "Open Party Publication")`. The script doesn't use it.

Page layout: put Source Id, Status, Error Code and Message on the layout. Nothing in this step touches Party Publication.

### 1b. One field on Publication

Setup → Object Manager → **Publication** → Fields & Relationships → **New**.

| Field Label | API Name (exact) | Data Type | Settings |
|---|---|---|---|
| Publication Category | `PublicationCategory__c` | **Picklist** (recommended) or Text(255) | For a picklist, add **every value** that Party Publication's **Publication Category** field uses (Object Manager → Party Publication → Publication Category → Values). |

This field is **required** for the migration. Publication has no standard field for the category, so this is the only place the value can go.

### 1c. Check the other picklists (no new fields)

The script copies these values as they are. If a value is missing from the target picklist, the affected records fail with the platform's error, and you add the value and rerun. Comparing the lists now saves a rerun.

| Party Publication field | Must exist in | Error if missing |
|---|---|---|
| Status | Publication → **Status** | `PUBLICATION_CREATE_FAILED` |
| Listing Platform Type | Publication → **Listing Platform Type** | `PUBLICATION_CREATE_FAILED` |
| Party Role Type | Publication Contributor → **Contributor Role** | `CONTRIBUTOR_CREATE_FAILED` |
| Publication Category | Publication → **Publication Category** (1b) | `CUSTOM_FIELD_WRITE_FAILED` |

**Party types.** Contributor can point only at the party types in your org's **Contributor domain** (Object Manager → Publication Contributor → Contributor → lookup/domain setting). If a Party Publication row's Party is a type that isn't in the domain (for example an Individual), the Contributor insert for that record is rejected and the record is marked `Failed` with `CONTRIBUTOR_CREATE_FAILED` (the platform message says the Contributor ID is of an incorrect type). Contributors are inserted with partial success, so the other records are not affected. Add the type to the domain before the run, or leave those records to fail and handle them separately.

---

## Step 2: Check the running user's permissions

The migration runs as **the user who starts it** (a System Administrator is fine). Before it processes anything, it checks that this user has the access below. If something is missing, it stops without changing data and the summary email names it. You can run the same check in Step 3c.

| The user needs | Path |
|---|---|
| Create, edit and **delete** on **Publication** and **Publication Contributor**, with edit access to every field the script fills (see [Field mapping](#field-mapping), plus `PublicationCategory__c`) | both |
| Read access to **Party Publication** and its fields | both |
| Read and **edit** on the 5 fields you created in 1a | Path A |
| Read, create and edit on the log object and its 7 fields | Path B |
| The Publications access your org needs (permission set licenses, system permissions) | both |

An administrator usually has all of this. The one common gap is **field-level security on the fields you created in Step 1**: make them visible and editable for the user's profile or a permission set.

> **Why delete?** The script deletes only records it created **in the same run** that it couldn't link back to the PartyPublication record (Path A) or log row (Path B). Without that, an orphaned Publication would be created again on the next run. It never deletes anything else.

### Path A only: turn off your automation on Party Publication during the migration

*Path B: skip this. Party Publication isn't updated.*

Each status update runs your triggers, flows and validation rules on Party Publication (see Step 5). **Deactivate them while the migration runs and activate them again afterwards** (validation rules, record-triggered flows, workflow rules, and Apex triggers; in production you can't edit triggers, so deactivate those in a sandbox rehearsal and plan a quiet window, or ask your developer to add a condition to skip them for the migration user).

If a validation rule blocks the update, the script undoes what it created for that record and lists it in the summary email (Step 8). Your data stays safe, but the record isn't migrated until the rule allows the update.

---

## Step 3: Deploy the Apex classes

**Do Step 0, Step 1 and Step 2 first.** The checks in 3c fail without the fields (Path A) or the log object (Path B).

The source is in `force-app/main/default/classes/`: **17 Apex classes** (13 production, 4 test). Each has a `.cls-meta.xml` file next to it (API version 68.0).

### 3-0. Set the switch (the only code edit you make)

Open `force-app/main/default/classes/PubMigConfig.cls` and find this line:

```apex
public static final Boolean USE_LOG_OBJECT = false;
```

| Your choice (Step 0) | Set it to |
|---|---|
| **Path A**: fields on PartyPublication | `false` (already the default; change nothing) |
| **Path B**: log object | **`true`** |

Save the file **before** you deploy, and don't change it afterwards (see Step 0: choose once). Both tracker classes (`PartyPublicationFieldTracker` and `PubMigLogTracker`) are always deployed. Only the one selected here is used, and the other one just sits there. If the value doesn't match what you created in Step 1, the prerequisite check (3c) names what's missing.

### 3a. What you are deploying

| Class | Purpose | Uses (must exist) |
|---|---|---|
| `PubMigConfig` | **The switch** (`USE_LOG_OBJECT`) and the tracker it selects | `PartyPublicationFieldTracker`, `PubMigLogTracker` |
| `PubMigOutcome` | Result for one record (status, error code, message) | none |
| `PubMigRules` | Matching rules: DOI detection, paper grouping, field mapping | none |
| `PubMigInsertHook` | Empty extension point (interface). Production runs don't use it; tests use it to simulate failures | none |
| `PubMigTracker` | Interface: where migration status is stored | `PubMigOutcome` |
| `PubMigStatusReader` | Interface: lets the pre-flight read each record's status from either tracker | none |
| `PartyPublicationFieldTracker` | **Path A** tracker: stores status in the 5 fields from 1a | `PubMigTracker`, `PubMigStatusReader`, `PubMigOutcome`, `PubMigEngine` |
| `PubMigLogTracker` | **Path B** tracker: stores status in the log object from 1a-B | `PubMigTracker`, `PubMigStatusReader`, `PubMigOutcome`, `PubMigEngine` |
| `PubMigEngine` | Processes one batch of records | `PubMigTracker`, `PubMigRules`, `PubMigOutcome`, `PubMigInsertHook` |
| `PubMigGuard` | Checks fields, permissions and concurrent runs before starting | `PubMigTracker`, `PubMigRules`, `PartyPublicationMigrationBatch` |
| `PubMigSummary` | Counters and the summary email | `PubMigEngine`, `PubMigOutcome` |
| `PartyPublicationMigrationBatch` | **The migration job (entry point)** | the classes above |
| `PubMigPreflightBatch` | **Pre-flight report (entry point, read-only)** | `PubMigRules`, `PubMigOutcome`, `PubMigConfig`, `PubMigStatusReader` |
| `PartyPublicationMigrationBatchTest`, `PubMigPreflightBatchTest`, `PubMigRulesTest`, `PubMigTestData` | Tests and test data | all of the above |

> **Best: deploy all 17 in one deployment** (CLI, VS Code, Workbench, change set). A deployment compiles them together.
> **No deployment tool? You can create them by hand** in a sandbox or developer org: see [3b-manual](#3b-manual-create-the-classes-by-hand-no-cli-no-vs-code). Order matters there, because `PubMigGuard` and `PartyPublicationMigrationBatch` reference each other. Saving one of them first fails with "Invalid type" unless you follow the stub trick in 3b-manual.

### 3b. Deploy

> **Tests are Path A only.** `PartyPublicationMigrationBatchTest`, `PubMigPreflightBatchTest` and `PubMigTestData` create PartyPublication records and read the 5 Path A fields, so they fail in a Path B org. **Path B:** delete those three files (and their `.cls-meta.xml`) before deploying, keep `PubMigRulesTest` (it needs neither path), and see the coverage note after the commands.

**Path A**

```bash
sf org login web --alias target-org            # add --instance-url https://test.salesforce.com for a sandbox
cd partypublication-migration

# Sandbox: deploy and run the tests in one step
sf project deploy start --source-dir force-app --target-org target-org --test-level RunSpecifiedTests \
  --tests PartyPublicationMigrationBatchTest --tests PubMigRulesTest --tests PubMigPreflightBatchTest

# Production: validate first (deploys nothing), then quick-deploy the validated job
sf project deploy validate --source-dir force-app --target-org target-org --test-level RunSpecifiedTests \
  --tests PartyPublicationMigrationBatchTest --tests PubMigRulesTest --tests PubMigPreflightBatchTest
sf project deploy quick --job-id <id from validate> --target-org target-org
```

**Path B**

```bash
cd partypublication-migration/force-app/main/default/classes
rm PartyPublicationMigrationBatchTest.cls* PubMigPreflightBatchTest.cls* PubMigTestData.cls*
cd ../../../..

# Sandbox (no tests are required to deploy to a sandbox)
sf project deploy start --source-dir force-app --target-org target-org --test-level NoTestRun
```

> **Path B in production: no tests cover the log tracker yet.** Salesforce requires 75% Apex coverage to deploy to production. With the Path A tests removed, the migration classes have no coverage of their own. Options: (1) accept that the org-wide coverage from your other tests carries the deployment (`--test-level RunLocalTests`), or (2) write tests for your path before the production deploy, using the Path A tests as a pattern. Run the whole migration in a sandbox first either way.

Without the CLI: in VS Code, right-click the `force-app` folder → **SFDX: Deploy Source to Org**. Or zip the folder and deploy it with Workbench (Migration → Deploy). Or deploy to a sandbox first and promote with an outbound change set (add all 17 classes).

### 3b-manual. Create the classes by hand (no CLI, no VS Code)

Use this when you can't or don't want to use a deployment tool.

> **Where it works.** Sandbox, Developer Edition, scratch or trial org: yes. **Production: no.** Salesforce doesn't let you save Apex in a production org from Setup or the Developer Console. Create the classes in a sandbox first, then move them to production with an **outbound change set** or Workbench (see the end of 3b). Check your org's behavior if you are unsure.

**What you need:** the 17 `.cls` files (not the `.cls-meta.xml` files) open in any text editor. For Path B you need 14, see the table. Do Steps 0–2 first, because the classes won't compile without `Publication`, `PublicationContributor` and the `PartyPublication` fields.

**How to create one class** (repeat for each row below):
1. Setup → Quick Find **Apex Classes** → **New**. (Or Developer Console → File → New → Apex Class, type the name, OK.)
2. Select everything in the editor and paste the **whole content** of the `.cls` file. The class name in the code must match the file name.
3. Click **Save** (Developer Console: Ctrl/Cmd+S). If there are errors, they are shown under the editor. Fix the cause (usually an earlier class is missing), then save again.

Before the first save of `PubMigConfig`, make the 3-0 edit (`USE_LOG_OBJECT = true` for Path B).

**Create them in exactly this order:**

| # | Class | Note |
|---|---|---|
| 1 | `PubMigOutcome` | |
| 2 | `PubMigRules` | |
| 3 | `PubMigInsertHook` | |
| 4 | `PubMigStatusReader` | |
| 5 | `PubMigTracker` | |
| 6 | `PubMigEngine` | |
| 7 | `PartyPublicationFieldTracker` | |
| 8 | `PubMigLogTracker` | |
| 9 | `PubMigConfig` | Make the 3-0 edit first |
| 10 | `PubMigSummary` | |
| 11 | **`PartyPublicationMigrationBatch`: temporary stub** | Paste only this line, not the real code: `public class PartyPublicationMigrationBatch {}` |
| 12 | `PubMigGuard` | Compiles now because the stub exists |
| 13 | **`PartyPublicationMigrationBatch`: real code** | Open the class from step 11, **replace** its content with the real `.cls` file, Save. Don't create a second class |
| 14 | `PubMigPreflightBatch` | |
| 15 | `PubMigTestData` | Path A only |
| 16 | `PubMigRulesTest` | Both paths |
| 17 | `PartyPublicationMigrationBatchTest` | Path A only |
| 18 | `PubMigPreflightBatchTest` | Path A only |

(The stub in step 11 is needed because `PubMigGuard` only uses the class name `PartyPublicationMigrationBatch`, while the real `PartyPublicationMigrationBatch` uses `PubMigGuard`. Neither can be saved first without the stub.)

**Path B:** skip rows 15, 17 and 18. That leaves 14 classes. The test classes are optional in a sandbox, but you need them if you move the classes to production with a change set.

**Check:** Setup → **Apex Classes** → **Compile all classes**. Every class must show as valid. Then do 3c (steps 1 and 3). Run the tests from Setup → **Apex Test Execution** → *Select Tests* (Path A: all three test classes) or from Developer Console → Test → New Run.

> Not tested in an org. I derived the order from the references between the classes. If a save fails with `Invalid type: <name>`, create `<name>` first.

### 3c. Check that it worked

1. Setup → **Apex Classes** lists the 17 classes, none with a red "Not valid" flag.
2. If you didn't run the tests during the deploy, run them now (CLI below; without the CLI use Setup → Apex Test Execution):
   ```bash
   sf apex run test --target-org target-org --wait 10 --result-format human \
     --class-names PartyPublicationMigrationBatchTest --class-names PubMigRulesTest --class-names PubMigPreflightBatchTest
   ```
   Expected: every test passes. The tests create and delete their own data. They don't touch your real records.
3. **Check the prerequisites without running anything.** Developer Console → Debug → **Open Execute Anonymous Window**, tick **Open Log**, run:
   ```apex
   List<String> problems = PubMigGuard.problems(PubMigConfig.tracker(), null);
   System.debug(problems.isEmpty() ? 'OK: all prerequisites met' : String.join(problems, '\n'));
   ```
   In the log, tick **Debug Only** (or filter on `USER_DEBUG`). You want `OK: all prerequisites met`. Otherwise each line names a missing field or object, a wrong field type, or a missing permission. Fix them (Step 1 or Step 2) and run it again. If it says `PublicationMigrationLog__c is missing` and you chose Path A, the switch in 3-0 is set to `true`; if it says `PartyPublication.MigrationStatus__c is missing` and you chose Path B, it is still `false`. This is the same check the migration performs before it starts.

### 3d. If the deployment fails

| Error | Cause | Fix |
|---|---|---|
| `Invalid type: Publication` / `PublicationContributor` | Publications aren't enabled, or the classes' API version is too old | Enable Publications. If it's already enabled, raise `<apiVersion>` in every `*.cls-meta.xml` to your org's current version |
| `No such column 'ListingPlatformType' on entity 'Publication'` | Same as above | Same as above |
| Many migration tests fail with `Expected: N, Actual: 0` | The migration refused to start because a prerequisite is missing | Run `PubMigGuard.problems(...)` from 3c and fix what it lists |
| `Invalid type: PartyPublication` or `HealthcareProvider` (in a test class) | Life Sciences isn't enabled in this org | Deploy to an org that has Life Sciences |
| `Invalid type` on a class that is in this project | You created the classes by hand in the wrong order | Follow the order in 3b-manual (including the stub for `PartyPublicationMigrationBatch`), or deploy all together |
| Test failure `prerequisitesPassInThisOrg` with "Setup incomplete: …" | A Step 1 field is missing or wrong, or the deploying user lacks a Step 2 permission | Fix what the message names |
| **Path B:** test failures in `PartyPublicationMigrationBatchTest` / `PubMigPreflightBatchTest` | Those tests are Path A only | Delete the three Path A test files (3b) |
| Test failures on `Status` / `Contributor Role` values | Party Publication defaults a picklist value that the target picklist doesn't have | Add the value to the target picklist (1c) |
| Production: "code coverage below 75%" | Only the specified tests ran | Use `--test-level RunLocalTests` instead of `RunSpecifiedTests` |

---

## Step 4: Create the list view and report

### 4a. List view "Publication Migration - Failed"

**Path A:** App Launcher → **Party Publications** → list view gear → **New**:

- List Name: `Publication Migration - Failed`; visible to all users who triage
- Filters: **Migration Status equals Failed**
- Columns: Title, Party, Publication Date, Publication Identifier, Migration Error Code, Migration Message

Users can fix records inline from this view (for example, fill in Publication Date), and the next run picks them up.

**Path B:** App Launcher → **Publication Migration Logs** → list view gear → **New**:

- List Name: `Publication Migration - Failed`
- Filters: **Status equals Failed**
- Columns: Log Number, Source Id, Error Code, Message, Source Record (if you created the optional link in 1a-B)

The log row tells you what's wrong; you fix the data **on the Party Publication record** (click Source Record, or paste the Source Id into the URL), then rerun. To see the record's title and date, export the Failed rows and look the Ids up in a Party Publication report.

### 4b. Report "Publication Migration by Error Code"

**Path A:** if the org has no report type for Party Publication, create one first: Setup → Report Types → **New Custom Report Type**: Primary Object **Party Publications**, Label `Party Publications (Migration)`, Category Other, Deployed. Make sure the 5 migration fields are in the field layout.

Then Reports → **New Report** → *Party Publications (Migration)*:

- Filters: All party publications
- Group Rows by: **Migration Status**, then **Migration Error Code**
- Columns: Title, Publication Date, Migration Message
- Save as `Publication Migration by Error Code`

**Path B:** Reports → **New Report** → report type **Publication Migration Logs** (it exists once the object has *Allow Reports* checked):

- Group Rows by: **Status**, then **Error Code**
- Columns: Source Id, Message
- Save as `Publication Migration by Error Code`

---

## Step 5: Read this before running: what the script changes

> **Path B: PartyPublication is not changed at all.** The script only reads it. No field is written, no audit date changes, none of your triggers, flows or validation rules on PartyPublication run, and no change event is published. What the script does write: **new rows in the log object**, and the new **Publication** and **Publication Contributor** records. You can skip the rest of this step, except the last paragraph.

> **Path A: what the script changes on your PartyPublication records**
> The migration script never deletes PartyPublication records and never changes their standard fields or your own custom fields. To track progress and allow safe reruns, it writes to the five migration fields you created in [Step 1a](#1a-path-a-five-fields-on-party-publication) (`PublicationContributor__c`, `MigrationStatus__c`, `MigrationErrorCode__c`, `MigrationMessage__c`, `MigrationGroupKey__c`).
>
> Because these are record updates, Salesforce also:
> | Effect | Detail |
> |---|---|
> | Updates system audit fields | `LastModifiedDate`, `LastModifiedById` and `SystemModstamp` change to the migration run time and the migration user. Reports, list views, integrations, or sync jobs that use these fields (for example "modified since" delta extracts) will see every processed record as modified. |
> | Runs your automation | Apex triggers, record-triggered flows, process builders, workflow rules, and validation rules on PartyPublication run for each update. Duplicate rules don't apply to updates of these fields. |
> | Publishes events | If Change Data Capture is enabled for PartyPublication, a change event is published for each update. Platform events your automation publishes are also sent. |
> | Writes history | Field history rows are written only if **you** enable history tracking on the migration fields. They're new fields, so tracking is off unless you turn it on. |
> | Retries | The script rewrites a record only when a migration value actually changes. Rerunning without data changes doesn't touch already-processed records again. |
>
> **Before running, decide:** accept the updates (recommended for Path A) and consider turning off your automation ([Step 2](#path-a-only-turn-off-your-automation-on-party-publication-during-the-migration)). **If you can't accept any update to PartyPublication, use Path B instead** (Step 0). Don't just remove the writes: the script uses them to know what it already migrated, and without them every rerun creates duplicate Publications and Contributors.

The new Publication and Publication Contributor records are created by the migration user at the time of the run. Their **Created Date** is the run date, not the original record's date. The paper's real date is in **Published Date**.

---

## Step 6: Run the pre-flight report and fix the data

The pre-flight report is **read-only**: it creates and changes nothing. It finds papers that the migration would split into two Publications, so you can fix them first. It looks only at records that still have something to migrate: **Excluded** records and papers whose records are all **Migrated** are left out, so you can also run it again later.

**How to run it**

1. Log in as the user who will run the migration (the one who passes the permission check in 3c).
2. Click the gear icon → **Developer Console**. A new browser window opens.
3. In the Developer Console menu: **Debug → Open Execute Anonymous Window** (shortcut: Ctrl+E, Cmd+E on Mac).
4. Paste this one line, clear any old text, and click **Execute**:

```apex
PubMigPreflightBatch.run();
```

5. Nothing visible happens; the call only queues a background job. Watch it in Setup → **Apex Jobs** (Class = `PubMigPreflightBatch`) until Status is **Completed**.
6. The user who ran it gets an email, subject `Publication migration pre-flight: <n> group(s) to review`, with the findings as a **CSV attachment**. `0 group(s)` means nothing to fix. At most 2,000 findings are attached; the email body gives the total.

How to read the CSV:

| Code | Meaning | What to do |
|---|---|---|
| `MIXED_IDENTIFIER` | Records with the same Title and Publication Date where **some have a Publication Identifier and some don't**. They'd become **2 Publications**. | Fill in the missing identifier on the listed records (copy it from the sibling), then rerun the pre-flight |
| `MULTIPLE_KEYS` | Same Title and Date, but different identifiers or journals | Review only. Often correct (for example, an erratum with its own DOI). Fix typos if you find them |

Repeat (fix the data, run the pre-flight) until `MIXED_IDENTIFIER` is empty.

Also fix before running:

- **Missing Publication Date.** Every record needs its own date (see [How papers are matched](#how-papers-are-matched)). Find them with the list view filter *Publication Date equals (blank)*.
- **Junk identifiers.** `N/A`, `NA`, `none`, `null`, `TBD`, `-`, `0` are treated as blank automatically. Other junk values (for example `unknown`) would merge unrelated papers into one Publication, so clear them or ask your developer to add them to `PubMigRules.PLACEHOLDER_IDENTIFIERS`.
- **Records you don't want migrated.** The script never touches Excluded records.
  - **Path A:** set **Migration Status = Excluded** on the Party Publication record.
  - **Path B:** upsert a log row for each record with **Status = Excluded**. With Data Loader: operation **Upsert** on object *Publication Migration Log*, external ID field `SourceId__c`, CSV columns `SourceId__c` (the 18-character Party Publication Id) and `Status__c` (`Excluded`).

---

## Step 7: Run the migration

### 7a. Before you press the button

- [ ] Step 3c printed `OK: all prerequisites met`.
- [ ] The pre-flight (Step 6) has no `MIXED_IDENTIFIER` findings, and you've dealt with missing dates and junk identifiers.
- [ ] **Path A:** you turned off your automation on Party Publication ([Step 2](#path-a-only-turn-off-your-automation-on-party-publication-during-the-migration)) and read Step 5.
- [ ] The switch in `PubMigConfig` matches your path (3-0). Step 3c confirms it.
- [ ] Optional **pilot** (recommended in a sandbox): mark all but about 20 records of different papers as Excluded (Path A: set Migration Status = Excluded with Data Loader or a list-view mass edit; Path B: upsert Excluded log rows as in Step 6), run once, check the results with Step 8, then undo the exclusions (Path A: set Migration Status back to blank; Path B: delete those log rows) and run again.

### 7b. Start the job

1. Developer Console → **Debug → Open Execute Anonymous Window**.
2. Paste the line below and click **Execute**. (Tick **Open Log** if you want to see the job Id.)

```apex
System.debug(PartyPublicationMigrationBatch.run());   // 200 records per chunk; prints the job Id
```

If your automation on Party Publication is heavy (see [Step 2](#path-a-only-turn-off-your-automation-on-party-publication-during-the-migration)) or a previous run reported governor-limit errors, use smaller chunks:

```apex
Database.executeBatch(new PartyPublicationMigrationBatch(), 50);
```

From the command line: `echo "PartyPublicationMigrationBatch.run();" | sf apex run --target-org target-org`

What happens:

```
 You click Execute ──▶ job is queued (seconds) ──▶ the job runs in the background,
                                                   200 records at a time, each chunk in its own transaction
 start():   checks fields, permissions, concurrent runs.  Any problem → nothing is processed, email says why
 execute(): per chunk: group records by paper → create Publications → create Contributors → write status
 finish():  sends the summary email to the user who started the job
```

### 7c. Watch it

- Setup → **Apex Jobs**, Class `PartyPublicationMigrationBatch`. Status goes Queued → Preparing → Processing → **Completed**. "Batches Processed / Total Batches" is the progress (Total = records ÷ 200, rounded up). "Failures" should be 0.
- Only one migration job can run at a time. A second one stops immediately and says so in its email.
- Don't edit Party Publication records, or run data loads against them, while the job runs.

**To stop it:** Setup → Apex Jobs → **Abort** next to the job (or `System.abortJob('<job Id>');`). Chunks that already finished keep their results; the chunk in progress is rolled back by the platform. Rerunning later is safe. The summary email may not be sent after an abort. Use the Step 8 queries to see where things stand.

### 7d. The summary email

When the job finishes, the user who started it gets an email. Subject: `Publication migration: <n> migrated, <n> failed`.

```
Records processed:          12480
  Migrated:                 12391 (with warnings: 37)
  Failed:                   89
    MISSING_PUBLICATION_DATE: 71
    CONTRIBUTOR_CREATE_FAILED: 18
  Warning PAPER_FIELD_CONFLICT: 37
Publications created:       5120 (removed again by compensation: 3)
Contributors created:       12380 (reused: 11, removed by compensation: 0)
```

| Email says | Meaning | What to do |
|---|---|---|
| Subject `Publication migration did not start`, body **THE RUN DID NOT START** | A prerequisite is missing, or another migration job is running. The body lists each problem. Nothing was created or changed | Fix what it lists (usually Step 1 or Step 2) and run again |
| Subject `Publication migration INCOMPLETE: …`, body **ATTENTION: THE RUN DID NOT COMPLETE** | Some chunks threw an exception. Their records have no status, and nothing was created for them (the chunk was rolled back). The email shows the exception text | Fix the cause the message names, or rerun with smaller chunks (`…(), 50)`) if it mentions a governor limit. Then rerun. The counts above that line don't include those records |
| No email at all | Email deliverability is "System email only" (sandbox), or the job was aborted | Check Setup → Apex Jobs for the final status, then use the queries in Step 8 |

---

## Step 8: Review results, fix, and rerun

> **Path B:** wherever this guide says *Migration Status / Migration Error Code / Migration Message* on Party Publication, read *Status / Error Code / Message* on the record's log row.

1. Open the report (4b) to see failures by error code.
2. Open the list view (4a). Each record's **Migration Message** (Path B: **Message**) says what's wrong and how to fix it.
3. Fix the data, then **run Step 7 again**. Only Failed and not-yet-processed records are processed. Migrated and Excluded records are skipped, and Publications created by earlier runs are reused, so reruns don't create duplicates.

### Error codes (record status = Failed)

| Code | What happened | How to fix |
|---|---|---|
| `MISSING_PUBLICATION_DATE` | The record has no Publication Date | Fill in Publication Date on **this** record |
| `PUBLICATION_CREATE_FAILED` | Salesforce rejected the new Publication; the platform error is in the message. Common cause: a **Status** or **Listing Platform Type** value missing from the Publication picklist (`INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST`). **All records of that paper in the batch** fail together | Act on the platform error (for example, add the picklist value in Object Manager → Publication) |
| `CONTRIBUTOR_CREATE_FAILED` | Salesforce rejected the new Publication Contributor. Common cause: a **Party Role Type** value missing from **Contributor Role** | Act on the platform error (for example, add the value to Contributor Role) |
| `CUSTOM_FIELD_WRITE_FAILED` | `Publication.PublicationCategory__c` rejected the category value (usually a missing picklist value, or the wrong field type) | Add the value to Publication Category, or change the field type (1b) |

### Warnings (record status = Migrated; text in Migration Message)

| Code | Meaning | Action |
|---|---|---|
| `PAPER_FIELD_CONFLICT` | This record's paper fields (named in the message) differ from the Publication, which was created from another record of the same paper. The Publication wasn't changed | Review. If this record's values are the right ones, edit the Publication |
| `OWNER_INACTIVE_REASSIGNED` | The record's owner is inactive, so the new Publication is owned by the user who ran the migration | Reassign the Publication's owner if needed |

### Other sections of the summary email

| Section | Meaning | Action |
|---|---|---|
| "Records whose migration status could NOT be saved" | Usually a validation rule, trigger, or flow on Party Publication blocked the status update. Everything the script created for these records was removed, so they're retried next run | Turn off the rule ([Step 2](#path-a-only-turn-off-your-automation-on-party-publication-during-the-migration)) or fix it, then rerun |
| "ATTENTION: THE RUN DID NOT COMPLETE" | One or more chunks failed and were rolled back (see 7d) | Fix the cause, then rerun |
| "ACTION NEEDED: … could not be removed" | Very rare. The script created a record, couldn't link it, and also couldn't delete it | Delete the listed records manually **before** the next run, or that paper gets a duplicate |

### Check the results (Developer Console → Query Editor)

**Path A**

```sql
-- Overall status
SELECT MigrationStatus__c, MigrationErrorCode__c, COUNT(Id) FROM PartyPublication
GROUP BY MigrationStatus__c, MigrationErrorCode__c

-- Migrated records always have a contributor (expect 0)
SELECT COUNT() FROM PartyPublication WHERE MigrationStatus__c = 'Migrated' AND PublicationContributor__c = null

-- Publications without contributors (expect 0)
SELECT Id, Name FROM Publication WHERE Id NOT IN (SELECT PublicationId FROM PublicationContributor)

-- Not processed yet (expect 0 after the final run, except records you will fix later)
SELECT COUNT() FROM PartyPublication WHERE MigrationStatus__c = null
```

If the second query returns records, someone deleted those contributors or their Publication after migration. To migrate those records again, clear their **Migration Status** and rerun.

**Path B**

```sql
-- Overall status
SELECT Status__c, ErrorCode__c, COUNT(Id) FROM PublicationMigrationLog__c GROUP BY Status__c, ErrorCode__c

-- Migrated rows always have a contributor and a Publication (expect 0)
SELECT COUNT() FROM PublicationMigrationLog__c WHERE Status__c = 'Migrated' AND (PublicationContributor__c = null OR Publication__c = null)

-- Publications without contributors (expect 0)
SELECT Id, Name FROM Publication WHERE Id NOT IN (SELECT PublicationId FROM PublicationContributor)

-- Not processed yet: these two numbers should be equal after the final run, apart from records you will fix later
SELECT COUNT() FROM PartyPublication
SELECT COUNT() FROM PublicationMigrationLog__c
```

If the second query returns rows, someone deleted those contributors or their Publication after migration. To migrate those records again, **delete their log rows** and rerun.

---

## How papers are matched

A PartyPublication record represents **one author of one paper**, so a paper with 3 authors has 3 records. The migration creates **one Publication per paper** and **one Publication Contributor per record**.

| Records | Same paper? |
|---|---|
| Same Publication Identifier (DOI written any way: `10.1038/abc`, `https://doi.org/10.1038/ABC`, `doi:10.1038/abc`) | **Yes** |
| No identifier, same Title + Publication Date + Published On (ignoring capitalization, punctuation and extra spaces) | **Yes** |
| No identifier, same Title but different date or journal | No |
| Different identifiers, same Title | No |
| One record has the identifier and another doesn't | **No: 2 Publications.** The pre-flight report (Step 6) finds these |

- **Which record's values are used?** The **oldest** record of the paper (by Created Date) creates the Publication from its own values. Values are never merged or overwritten. Later records whose values differ get a `PAPER_FIELD_CONFLICT` warning.
- **Same person listed twice on one paper with the same role** → one contributor, shared by both records.
- **Identifiers.** DOI-formatted values go to **Digital Object Identifier** in the bare form (`10.1038/abc`). Everything else (PMID, arXiv, NCT …) goes to **External Identifier** as entered.
- **Publication Date.** *Each PartyPublication record must have its own Publication Date. The migration doesn't copy dates between records, even when they belong to the same publication. Records without a date are marked Failed and are migrated automatically on the next run after you add the date.*
- **Existing Publications.** Only Publications created by this migration are reused. If you already created a paper by hand, the migration creates a second one.

### Field mapping

| Party Publication | → Publication |
|---|---|
| Title | Name and Title |
| Publication Date | Published Date |
| Published On | Original Source Name |
| Summary | Abstract Text |
| Publication Identifier | Digital Object Identifier *or* External Identifier |
| URL | Publication URL |
| Citation Count, Impact Factor, Status, Listing Platform Type | same-named fields |
| Publication Category | Publication Category (`PublicationCategory__c`) |
| Owner | Owner (inactive owner → the running user) |

| Party Publication | → Publication Contributor |
|---|---|
| Party (Healthcare Provider, Individual, or Account) | Contributor |
| Party Role Type | Contributor Role |
| — | Publication = the paper's Publication; Is Equal Contribution = false; Author Sequence = blank |

---

## Step 9 (optional): Move your custom fields, notes, and attachments

The migration doesn't move your own custom fields, notes, or attachments. The migration records connect source and target, so you can move them yourself after the migration. **Path A:** the Publication Contributor lookup on every migrated Party Publication record. **Path B:** the same link on the record's log row (`SourceId__c` → `PublicationContributor__c`):

```
Path A: PartyPublication ──PublicationContributor__c──▶ Publication Contributor ──Publication──▶ Publication
Path B: PartyPublication ◀─SourceId__c─ Log row ──PublicationContributor__c──▶ Publication Contributor ──▶ Publication
                (source)                                (author-level target)                 (paper-level target)
```

The examples below are written for Path A. For Path B, read the log rows first (`SELECT SourceId__c, PublicationContributor__c, PublicationContributor__r.PublicationId FROM PublicationMigrationLog__c WHERE Status__c = 'Migrated' ORDER BY CreatedDate, Id`), then load the matching Party Publication records with `WHERE Id IN :sourceIds` for the custom field values.

### Custom fields

1. **Decide the level.** Paper-level data (for example *Journal Tier*) belongs on Publication. Author-level data (for example *Corresponding Author*) belongs on Publication Contributor.
2. **Create the matching field** on the target object.
3. **Copy the values** after the migration. Pick a rule for paper-level fields, because several records point to one Publication. This example keeps the oldest record's value, the same rule the migration uses:

```apex
// Example follow-up job. Reads PartyPublication, writes targets; never writes PartyPublication.
// Run as a Batch for large volumes.
Map<Id, PublicationContributor> contributorUpdates = new Map<Id, PublicationContributor>();
Map<Id, Publication> publicationUpdates = new Map<Id, Publication>();
for (PartyPublication pp : [
        SELECT Id, JournalTier__c, CorrespondingAuthor__c,
               PublicationContributor__c, PublicationContributor__r.PublicationId
        FROM PartyPublication
        WHERE MigrationStatus__c = 'Migrated' AND PublicationContributor__c != null
        ORDER BY CreatedDate, Id]) {
    contributorUpdates.put(pp.PublicationContributor__c, new PublicationContributor(
        Id = pp.PublicationContributor__c, CorrespondingAuthor__c = pp.CorrespondingAuthor__c));
    Id pubId = pp.PublicationContributor__r.PublicationId;
    if (!publicationUpdates.containsKey(pubId)) {
        publicationUpdates.put(pubId, new Publication(Id = pubId, JournalTier__c = pp.JournalTier__c));
    }
}
update contributorUpdates.values();
update publicationUpdates.values();
```

Alternatives (Path A): Data Loader (export Party Publications with `PublicationContributor__r.PublicationId`, transform, update), or a record-triggered flow when Migration Status changes to Migrated (low volumes only). On Path B use Data Loader on the log rows' `PublicationContributor__r.PublicationId`, or a flow on `PublicationMigrationLog__c` when Status changes to Migrated.

### Notes and attachments

| Source | How to move | Watch out for |
|---|---|---|
| **Files** and **Enhanced Notes** (`ContentDocumentLink` on the Party Publication) | Insert a new `ContentDocumentLink` with `LinkedEntityId` = the Publication (or Contributor). No file copy is needed, and the original link stays | A file can be linked to a record only once. If 3 author records share a file, link it to the Publication once |
| **Legacy Attachments** | Convert to Files (`ContentVersion` with `FirstPublishLocationId` = target), which is recommended, or clone the Attachment with the new `ParentId` | Bodies count toward heap: use small batches (about 10). Both options duplicate storage |
| **Legacy Notes** | Clone Title, Body, Is Private, Owner with the new Parent | — |
| Activities, field history, Chatter | Not covered | History can't be moved |

Usually attach to the **Publication**. Use the **Publication Contributor** only for author-specific files.

---

## Advanced: write your own tracker

Path A and Path B cover most customers. If neither fits (for example you need to keep progress in an external system), a developer can write a class that implements `PubMigTracker` and pass it to the job:

```apex
Database.executeBatch(new PartyPublicationMigrationBatch(new MyTracker()), 200);
```

| Method | Must do |
|---|---|
| `checkPrerequisites()` | Return a list of problems (missing fields, permissions); empty means OK |
| `candidates()` | Return the records to consider, ordered by `CreatedDate, Id` |
| `eligible(ids)` | Of those, return the ones not yet Migrated or Excluded, with their current status (used to skip unchanged rewrites) |
| `existingPublicationByGroupKey(keys)` | Return the Publication already created for each paper key |
| `record(outcomes)` | **Save every outcome permanently.** Return the Ids that couldn't be saved; the job then removes what it created for them |

Optionally also implement `PubMigStatusReader.statusBySource(ids)` so the pre-flight report can skip Excluded and Migrated records. Use `PubMigLogTracker` (writes a separate object) or `PartyPublicationFieldTracker` as the reference.

> **Don't just remove the writes.** The job uses this state to know what it already migrated. Without it, every rerun creates duplicate Publications and Contributors.

---

## Troubleshooting

| Symptom | Likely cause | What to do |
|---|---|---|
| Execute Anonymous: `Variable does not exist` / `Invalid type: PartyPublicationMigrationBatch` | Step 3 not done, or the classes were deployed to a different org | Check Setup → Apex Classes in the org you're logged in to |
| Execute Anonymous: insufficient privileges | The user lacks **Author Apex** | Use a System Administrator |
| Job Status stays **Holding** or **Queued** for a long time | Other batch jobs are ahead of it | Wait, or look at Setup → Apex Jobs for what's running |
| The job finished with `0 processed` | There is nothing left to migrate (everything is Migrated or Excluded), or the run didn't start (read the email) | Query the status counts (Step 8, Path A or Path B query) |
| Record stays blank (never Migrated or Failed) after a run | Its chunk failed and was rolled back, or a validation rule blocked the status write | Read the summary email; turn off the automation ([Step 2](#path-a-only-turn-off-your-automation-on-party-publication-during-the-migration)) |
| Same records fail again after you fixed them | Failed records are retried on the next run only. Fixing does nothing until you rerun | Run Step 7 again |
| Summary email: `Required object PublicationMigrationLog__c is missing` | The switch is `true` but you chose Path A, or you haven't created the object (1a-B) | Match the switch to your path (3-0) and redeploy, or create the object |
| Summary email: `Required field PartyPublication.MigrationStatus__c is missing` | The switch is `false` but you chose Path B | Set `USE_LOG_OBJECT = true` (3-0) and redeploy |
| **Path B:** a record isn't skipped although I marked it Excluded | The log row's `SourceId__c` isn't the 18-character Party Publication Id, or `Status__c` isn't exactly `Excluded` | Check the log row; Source Id must match exactly |
| A paper became 2 Publications | Identifier on some records and not others, or a typo in Title/journal | Run the pre-flight (Step 6) before the migration. Afterwards, merge the two by hand |

---

## Known limitations

| Limitation | Effect | What to do |
|---|---|---|
| A paper with the identifier on some records and not others | 2 Publications | Pre-flight report (Step 6) |
| No fuzzy matching | Typos in Title or journal ("Natrue") split a paper when there's no identifier | Pre-flight `MULTIPLE_KEYS`; fix before running |
| Only Publications created by this script are reused | A paper you created by hand gets a second Publication | Merge manually afterwards |
| Deleting a migrated Publication | Its contributors are deleted and the lookups cleared, but the records stay Migrated | **Path A:** clear Migration Status on those records and rerun. **Path B:** delete their log rows and rerun |
| Changing the matching rules (`PubMigRules`) between runs | Records not yet migrated get different keys and won't find Publications from earlier runs | Change rules only before the first run (the placeholder list can be extended any time before a record is migrated) |
| Switching between Path A and Path B after the first run | The new path can't see what the old path migrated, so every record is migrated again as a duplicate | Choose once (Step 0). To change paths in a sandbox, first do the reset below |
| **Path B** has no automated tests of its own | A production deployment can't rely on tests for the log tracker | See the coverage note in 3b; rehearse in a sandbox |
| No automatic rollback | — | Test in a sandbox first. In a sandbox, delete the created Publications (contributors are deleted with them) and reset the tracking: **Path A** clear the 5 migration fields; **Path B** delete all rows of `PublicationMigrationLog__c` |

---

## Reference: How the migration works (business logic)

You don't need this section to run the migration. Read it when you want to know **what the script does and why**, for example before you approve it or when a result surprises you. Everything here is how the code behaves today.

### R1. What happens in one run

The job reads PartyPublication records oldest first (Created Date, then Id) in chunks of 200. Chunks run one after another, never in parallel. Each chunk goes through the same steps:

```
 chunk of up to 200 PartyPublication records
   │
   ├─ 1. Which of these still need work?          (not Migrated, not Excluded)
   ├─ 2. Validate: Publication Date present?       no → Failed (MISSING_PUBLICATION_DATE)
   ├─ 3. Work out the paper key for each record    (R2)
   ├─ 4. Does a Publication for that key exist?    yes → reuse   no → the oldest record creates it
   ├─ 5. Create the missing Publications
   ├─ 6. Create one Contributor per record         (or reuse an identical one) (R3)
   ├─ 7. Save the result of every record           (R4)
   └─ 8. Clean up anything that could not be saved (R5)
```

Before the first chunk the job checks the prerequisites (fields or log object, permissions) and that no other migration is running. If a check fails, it stops and says why in the summary email.

### R2. How we match papers and avoid duplicate Publications

**Why:** PartyPublication has one record per author. The new model has one Publication per paper. The script has to recognize which records are the same paper. It must never create a second Publication on a rerun.

**How:** every record gets a **paper key**:

| The record has | Key is built from |
|---|---|
| A real Publication Identifier (not blank, not `N/A`, `none`, `TBD`, `-`, `0` …) | the identifier, in lower case. A DOI is cleaned first, so `10.1038/abc`, `https://doi.org/10.1038/ABC` and `doi:10.1038/abc` give the same key |
| No usable identifier but a Publication Date | Title + Publication Date + Published On, lower-cased, punctuation and extra spaces removed |
| Neither | no key; the record fails with `MISSING_PUBLICATION_DATE` |

What this means for common cases:

| Records | Same paper? |
|---|---|
| Same DOI, Title spelled differently | **Yes.** The identifier wins; the later record gets a `PAPER_FIELD_CONFLICT` warning |
| Different identifiers, same Title (for example an erratum with its own DOI) | No |
| No identifier, same Title + Date + Published On | **Yes** |
| No identifier, same Title but different Date or Published On | No |
| One record has an identifier, a sibling has none | **No: 2 Publications** (pre-flight finds these) |

A junk identifier (`N/A` …) is also **not written** to the Publication's DOI or External Identifier fields. The value stays on the PartyPublication record.

The key is stored as a 64-character fingerprint (SHA-256) in `MigrationGroupKey__c` (Path A) or `GroupKey__c` on the log row (Path B).

**Three layers stop duplicates:**

| Situation | What the script does |
|---|---|
| Records of one paper are in the **same chunk** | The oldest record creates the Publication. The others in the chunk use it. |
| Records of one paper are in **different chunks or different runs** | Before creating, the script looks for a record that is already Migrated and has the same key, and uses that record's Publication. Only Publications created by this migration are found this way. |
| The **same person with the same role** appears twice on one paper | One Contributor is created and both records point to it. |

Where a duplicate can still happen (by design):
- One record has a DOI and another record of the same paper has none. They get different keys. The **pre-flight report** (Step 6) finds these before you migrate.
- You already created the paper by hand. The script doesn't look at Publications it didn't create.
- You change the title, date or identifier of a record **after** other records of that paper were migrated. The new key no longer matches the old one.
- You switch between Path A and Path B after the first run (Step 0).
- A typo in the Title or Published On of records without an identifier ("Natrue"). The script does no fuzzy matching, because a wrong merge is silent data corruption while a duplicate is visible and can be fixed by hand.
- Someone **deletes a migrated Publication**. Its Contributors are deleted with it (master-detail) and the links are cleared, but the records stay Migrated. A record of the same paper that is migrated later creates a new Publication. Step 8 has the query that finds the affected records.

**Why the oldest record creates the Publication:** Created Date and Id never change, so the result is the same no matter where the chunk boundaries fall or when a retry happens. (Last Modified Date would not work: Path A's own status writes change it.)

**Why the script doesn't match your existing Publications:** attaching migrated contributors to a Publication a person created by hand is harder to undo than a duplicate. So only Publications created by this migration are reused.

**A record without a Publication Date always fails**, even if another record of the same paper has one. The script never borrows a value from a sibling record.

| Scenario | Result |
|---|---|
| Record A has a date, record B (same DOI) has none | A creates the Publication and is Migrated. B is Failed with `MISSING_PUBLICATION_DATE` |
| You add the date to B and rerun | B gets its Contributor on A's Publication. B's date is not written to the Publication. If it differs from the Publication's date, B gets `PAPER_FIELD_CONFLICT` |
| No record of the paper has a date | All fail. No Publication is created until at least one is fixed |
| No identifier and no date | Fails. After you add the date, the key includes it and the record groups correctly |

The Publication takes its values from the **oldest** record only. Values from other records are never merged. If another record's values differ, it gets a `PAPER_FIELD_CONFLICT` warning in its message and the Publication isn't changed. Details of the field mapping: [How papers are matched](#how-papers-are-matched).

### R3. How a PartyPublication record is linked to its Publication Contributor

**Why:** the Contributor is the author-level record, so there must be exactly one per PartyPublication record, and you must be able to go from the old record to the new ones.

**How:**
- For each valid record the script creates (or reuses) one **Publication Contributor** with: Publication = the paper's Publication, Contributor = the record's **Party**, Contributor Role = the record's **Party Role Type**.
- Author Sequence stays blank (the source has no author order) and Is Equal Contribution is `false`. Any party type (Healthcare Provider, Individual, Account) is copied 1:1 from Party to Contributor; the script does no lookup or resolution. The Contributor's derived lookups fill in automatically.
- **Reuse rule:** if a Contributor with the same Publication + Party + Role already exists, the script links to it instead of creating another one.
- The link is saved on the record's tracking data:

| | Where the link is stored |
|---|---|
| **Path A** | `PublicationContributor__c` lookup on the PartyPublication record |
| **Path B** | `PublicationContributor__c` lookup on the record's log row (and `Publication__c` for the paper) |

```
 PartyPublication ──(lookup, Path A)──▶ Publication Contributor ──master-detail──▶ Publication
 PartyPublication ◀─ SourceId__c ─ Log row ──(lookup, Path B)──▶ Publication Contributor
```

- To find the Publication of a record, follow the Contributor: `PublicationContributor__r.PublicationId`.
- The script **never edits or deletes** a Publication or Contributor that already exists. It only creates new ones.

### R4. How we track the status

**Why:** the script has to remember what it already did, otherwise every rerun would start from zero and create duplicates.

Every record has one state:

| State | Meaning | Who sets it |
|---|---|---|
| (no state) | Not processed yet | n/a |
| **Migrated** | A Publication Contributor exists and is linked. Final. | The script |
| **Failed** | The script could not migrate it. **Error Code** and **Message** say why and how to fix it. | The script |
| **Excluded** | You don't want it migrated. | You |

What is saved for each record: **Status, Error Code, Message, paper key, Contributor link**. (Path A: five fields on PartyPublication. Path B: one row in the log object.)

- **Warnings** (`PAPER_FIELD_CONFLICT`, `OWNER_INACTIVE_REASSIGNED`) are stored in the Message of a **Migrated** record. They don't block anything.
- The script saves the state **after** the Publication and Contributor are created, in the same transaction. A record is therefore never Migrated without a Contributor.
- The script **only writes a record when something changed** compared to the last run. A rerun that finds the same failure for a record leaves it untouched.
- Path A writes only the five migration fields on PartyPublication. Path B writes nothing on PartyPublication.

### R5. What happens when something goes wrong in the middle

| Problem | What the script does | Result |
|---|---|---|
| One record is invalid (no date, Publication or Contributor can't be created) | Marks it **Failed** with a code and message. The rest of the chunk continues. | Fix the data, rerun |
| A Publication can't be created | All records of that paper in the chunk are marked Failed with the same error | One fix, then rerun |
| A Publication or Contributor was created but its state could not be saved (for example one of your validation rules blocks the write on Path A) | **Compensation:** the script deletes what it just created in this run. It never deletes anything from earlier runs. | The record stays unprocessed; the next run retries it with no duplicates. The summary email lists the record Ids that could not be saved |
| A Publication was created but none of its records ended up Migrated (for example every Contributor failed) | The new Publication is deleted too, otherwise nothing would point to it and the rerun would create a second one | Fix the cause, rerun |
| An unexpected error in a chunk | The whole chunk is rolled back, the job continues with the next chunk, and the summary email lists the chunk | The chunk's records stay unprocessed; rerun |
| A governor limit is hit | The platform rolls back that chunk | Rerun |
| You abort the job | Chunks already finished stay. A chunk that is cut off is rolled back by the platform; unprocessed records stay eligible | Rerun continues from there |

### R6. Rerun logic

**Rerunning is always safe.** Start it the same way every time (Step 7b). The script decides per record:

| Record state at the start of the run | What the rerun does |
|---|---|
| No state | Processes it |
| **Failed**, no Contributor linked | **Retries it.** The key is recomputed from the current values, so your fixes (a new date, an identifier) take effect |
| **Migrated** | Skips it, always. Changes you make to the PartyPublication record afterwards are **not** copied to the Publication |
| **Excluded** | Skips it, always |

What a rerun does with the papers:
- If the paper already has a Publication from an earlier run, the retried record **joins** that Publication and gets its own Contributor.
- If it doesn't, the oldest unprocessed record of the paper creates it.
- Rerun after a run with no new data to fix: it reports `0 processed` and changes nothing.

How to redo a record on purpose:

| I want to … | Path A | Path B |
|---|---|---|
| Retry a Failed record | Fix the data, rerun | Same |
| Migrate an Excluded record | Clear Migration Status, rerun | Delete its log row, rerun |
| Migrate a Migrated record again (for example its Publication was deleted) | Clear Migration Status **and** the Contributor lookup, rerun | Delete its log row, rerun |

### R7. What the script never does

- Never deletes or edits PartyPublication records (Path A writes only the five migration fields; Path B writes nothing).
- Never edits or deletes an existing Publication or Contributor.
- Never merges values from several records into one Publication.
- Never creates Publication Venue, Contributor Affiliation, notes or attachments (Step 9).
- Never runs two migrations at once.

### R8. Why the script is built this way (decisions)

| Decision | Choice | Why |
|---|---|---|
| What is created | Only Publication and Publication Contributor | Publication Venue and Contributor Affiliation need data the source doesn't have |
| Several records of one paper | One Publication, one Contributor per record | The source repeats the paper once per author; the target stores the paper once |
| Match your hand-made Publications | No | Safer to leave a visible duplicate than to attach migrated people to a record you own |
| Second key (Title + Date) when a DOI is missing | No | A wrong merge is silent; a duplicate is visible. The pre-flight report finds the cases before you run |
| Borrow a missing date from a sibling | No | Each record keeps its own data; you fix the record |
| Update existing Publications and Contributors | Never | Protects edits you make after the migration |
| Delete anything | Only records created in the same transaction (compensation) | Never your data |
| Keep the original Created Date and creator | No | New records get the run date and the migration user; the paper's real date is in Published Date. No "Set Audit Fields" permission is needed |
| Migrate your custom fields, notes and attachments | No, but Step 9 shows how | The Contributor link makes it possible, and the fields differ per customer |
| One bad record fails the job | No | Each record fails on its own with a code and a fix, and the rest continue |
| Where the status is kept | Your choice: Path A or Path B | Some customers can't accept updates on PartyPublication (Step 0) |
| Check target picklist values in advance (Status, Role, Listing Platform Type) | No | The platform rejects a missing value when the record is created, and the record fails with the platform's message. Add the value, rerun |
| Delivery | This guide plus the Apex source, no package | You own the code and can change it |
