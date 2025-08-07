# ActivityHistory Data Loading Guide

This folder contains comprehensive sample data for the ActivityHistory module in Life Sciences Cloud, including presentation entities and content management.

## Data Loading Process

Due to the complexity of ContentDocument relationships with PresentationPage, the data loading requires a **3-step process**:

### Step 1: Load Core Data + ContentVersions
```bash
sfdx force:data:tree:import --plan data/ActivityHistory/ActivityHistory-plan-step1.json --target-org [YOUR_ORG]
```

This loads all core entities:
- Account, ContactPointAddress, Visit, LifeScienceEmail, ProviderVisit
- Product2, Location, LifeSciMarketableProduct, ProductItem, ProductDisbursement
- ProviderVisitProdDetailing, ProviderAffiliation
- Case, Inquiry, InquiryQuestion, AssessmentTask
- LifeSciEmailTemplate, LifeSciEmailTmplSnapshot
- **ContentVersion records** (which auto-create ContentDocument records)

### Step 2: Create PresentationPages with ContentDocuments
```bash
sfdx force:apex:execute --target-org [YOUR_ORG] -f data/ActivityHistory/CreatePresentationPagesWithContent.apex
```

This script:
- Queries ContentVersions created in Step 1
- Maps ContentVersion titles to ContentDocumentIds
- Creates PresentationPage records with proper ContentDocumentId references
- Handles both ZIP and PDF type pages

### Step 3: Create Presentation Relationships
```bash
sfdx force:apex:execute --target-org [YOUR_ORG] -f data/ActivityHistory/CreatePresentationRelationships.apex
```

This script:
- Queries PresentationPages created in Step 2
- Creates Presentation records (Sample Medicine A, Sample Medicine B, Healthcare Provider Education)
- Creates PresentationLinkedPage records linking presentations to pages
- Creates PresentationForum records linking presentations to visits

## Why This 3-Step Approach?

The presentation entities have complex dependencies that cannot be handled by standard data loading:

1. **PresentationPage** requires ContentDocumentId (only available after ContentVersions are created)
2. **PresentationLinkedPage** requires both PresentationId and PresentationPageId
3. **PresentationForum** requires PresentationId and Visit references
4. Data loading cannot resolve nested references like `@ContentVersionRef.ContentDocumentId`

## Data Structure

### Entities Included (54+ records in Step 1, additional created by scripts):

**Core Business Entities:**
- **Account** (2): Healthcare centers
- **ContactPointAddress** (3): Contact information  
- **Visit** (3): Provider visits
- **LifeScienceEmail** (2): Email transactions
- **ProviderVisit** (1): Provider visit details

**Product Management:**
- **Product2** (2): Pharmaceutical products
- **Location** (1): Warehouse location
- **LifeSciMarketableProduct** (2): Marketable products
- **ProductItem** (2): Product inventory
- **ProductDisbursement** (2): Product distributions
- **ProviderVisitProdDetailing** (2): Product detailing
- **ProviderAffiliation** (1): Provider relationships

**Case Management:**
- **Case** (3): Support cases (linked to accounts)
- **Inquiry** (3): Medical inquiries (linked via cases)
- **InquiryQuestion** (5): Inquiry questions
- **AssessmentTask** (5): Assessment tasks

**Email Templates:**
- **LifeSciEmailTemplate** (5): Email templates (linked to products)
- **LifeSciEmailTmplSnapshot** (8): Email template versions

**Content & Presentations (created by scripts):**
- **ContentVersion** (9): File content with Base64 data
- **PresentationPage** (9): Presentation pages (linked to content)
- **Presentation** (3): Presentation containers
- **PresentationLinkedPage** (9): Page-to-presentation links
- **PresentationForum** (5): Presentation-to-visit links

### Key Relationships:
- Cases → Accounts (direct association)
- Inquiries → Cases → Accounts (indirect association)
- PresentationPages → ContentDocuments (via ContentDocumentId)
- Presentations → PresentationPages (via PresentationLinkedPage)
- Presentations → Visits (via PresentationForum)
- Email Templates → Products (via ProductId)

## Content Files

The ContentVersion records contain Base64-encoded sample content:
- **ZIP files**: Simple text files with relevant healthcare content
- **PDF files**: Minimal valid PDF structure with healthcare information

## Files in This Directory

### Working Solution Files:
- **ActivityHistory-plan-step1.json** - Core data loading plan ✅
- **CreatePresentationPagesWithContent.apex** - Step 2 script ✅
- **CreatePresentationRelationships.apex** - Step 3 script ✅
- **ActivityHistory-plan.json** - Original complete plan (reference)

### Data Files:
All JSON files containing sample data for each entity type (Account.json, Visit.json, Case.json, etc.)

## Troubleshooting

### Common Issues:

1. **ContentDocumentId Required Error**: 
   - Ensure you run Step 1 first to create ContentVersions
   - ContentDocumentIds are auto-generated and cannot be hardcoded

2. **Field Security Errors**:
   - Some fields are not createable via data loading
   - The scripts handle these limitations automatically

3. **Reference Resolution Errors**:
   - Follow the exact 3-step process
   - Each step depends on the previous step's completion

### Verification Queries:

```sql
-- Check Step 1 completion
SELECT COUNT(Id) FROM ContentVersion WHERE CreatedDate = TODAY

-- Check Step 2 completion  
SELECT COUNT(Id) FROM PresentationPage WHERE CreatedDate = TODAY

-- Check Step 3 completion
SELECT COUNT(Id) FROM Presentation WHERE CreatedDate = TODAY
SELECT COUNT(Id) FROM PresentationLinkedPage WHERE CreatedDate = TODAY
SELECT COUNT(Id) FROM PresentationForum WHERE CreatedDate = TODAY

-- Verify ContentDocument linking
SELECT Name, ContentDocumentId FROM PresentationPage WHERE ContentDocumentId != null
```

## Cleanup

To remove all ActivityHistory records from your org:
```bash
# Use bulk delete for each object type in reverse dependency order
# See the deletion scripts or contact your admin for bulk cleanup procedures
```

## Notes

- All sample data uses realistic healthcare scenarios
- Product associations are properly maintained across all entities
- The 3-step process is the only reliable method for loading presentation entities
- ContentDocumentIds vary between orgs and cannot be predetermined 