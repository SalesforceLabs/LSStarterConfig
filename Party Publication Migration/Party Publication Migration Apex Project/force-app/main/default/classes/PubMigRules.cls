/**
 * Pure mapping and matching rules (no SOQL, no DML). Design §2, §3.2, §3.3, §4.
 *
 * Customers may edit PLACEHOLDER_IDENTIFIERS. Changing norm() or groupKey() after a partial run
 * changes the keys of not-yet-migrated rows; they will no longer find Publications created
 * under the old keys. Only change those before the first run.
 */
public inherited sharing class PubMigRules {

    /** Customer-created field on Publication (prerequisite, design §1.2). Accessed dynamically. */
    public static final String CATEGORY_FIELD = 'PublicationCategory__c';

    public static final String FIELD_DOI = 'DigitalObjectIdentifier';
    public static final String FIELD_EXTERNAL_ID = 'ExternalIdentifier';

    /** Identifier values treated as blank for grouping and mapping (design §3.3). Compared trimmed, lower-case. */
    public static final Set<String> PLACEHOLDER_IDENTIFIERS = new Set<String>{
        'n/a', 'na', 'none', 'null', 'tbd', '-', '0'
    };

    private static final Pattern DOI_PREFIX = Pattern.compile('(?i)^\\s*(https?://(dx\\.)?doi\\.org/|doi:\\s*)');
    private static final Pattern DOI_BODY = Pattern.compile('^10\\.\\d{4,9}(\\.\\d+)*/\\S+$');

    /**
     * The Publication field that receives PartyPublication.ListingPlatformType: the standard field if the org has it,
     * else the customer-created ListingPlatformType__c, else null (PubMigGuard then stops the run with a clear message).
     * Looked up dynamically so this class compiles in both kinds of org.
     */
    public static final String LISTING_FIELD = findListingField();

    private static String findListingField() {
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Publication.fields.getMap();
        if (fields.containsKey('listingplatformtype')) {
            return 'ListingPlatformType';
        }
        if (fields.containsKey('listingplatformtype__c')) {
            return 'ListingPlatformType__c';
        }
        return null;
    }

    /** Publication fields compared for PAPER_FIELD_CONFLICT (design §3.5). */
    public static final List<String> PAPER_FIELDS = paperFields();

    private static List<String> paperFields() {
        List<String> names = new List<String>{
            'Title', 'PublishedDate', 'OriginalSourceName', 'AbstractText', FIELD_DOI, FIELD_EXTERNAL_ID,
            'PublicationUrl', 'CitationCount', 'ImpactFactor', 'Status', CATEGORY_FIELD
        };
        if (LISTING_FIELD != null) {
            names.add(LISTING_FIELD);
        }
        return names;
    }

    // Listing platforms can hold several values, so they are compared as sets
    private static final Set<String> MULTI_VALUE_FIELDS = new Set<String>{ 'ListingPlatformType', 'ListingPlatformType__c' };

    public class RoutedIdentifier {
        public final String field;
        public final String value;
        public RoutedIdentifier(String field, String value) {
            this.field = field;
            this.value = value;
        }
    }

    // ---------------------------------------------------------------- identifiers (§4)

    public static Boolean isPlaceholder(String raw) {
        return String.isBlank(raw) || PLACEHOLDER_IDENTIFIERS.contains(raw.trim().toLowerCase());
    }

    /** DOI-formatted → DigitalObjectIdentifier (bare DOI); anything else → ExternalIdentifier (trimmed); blank/placeholder → null. */
    public static RoutedIdentifier routeIdentifier(String raw) {
        if (isPlaceholder(raw)) {
            return null;
        }
        String trimmed = raw.trim();
        String bare = DOI_PREFIX.matcher(trimmed).replaceFirst('').trim();
        if (DOI_BODY.matcher(bare).matches()) {
            return new RoutedIdentifier(FIELD_DOI, bare);
        }
        return new RoutedIdentifier(FIELD_EXTERNAL_ID, trimmed);
    }

    // ---------------------------------------------------------------- grouping (§3.2)

    /** lower-case → punctuation to spaces → collapse whitespace → trim. Null-safe. */
    public static String norm(String s) {
        if (s == null) {
            return '';
        }
        return s.toLowerCase().replaceAll('[^\\p{L}\\p{N}]+', ' ').normalizeSpace();
    }

    /** Readable key before hashing. Null when the row can't be grouped (no identifier and no date). */
    public static String rawGroupKey(String identifier, String title, Date publicationDate, String publishedOn) {
        RoutedIdentifier routed = routeIdentifier(identifier);
        if (routed != null) {
            return 'ID|' + routed.value.toLowerCase();
        }
        if (publicationDate == null) {
            return null;
        }
        return 'TD|' + norm(title) + '|' + String.valueOf(publicationDate) + '|' + norm(publishedOn);
    }

    /** SHA-256 hex of rawGroupKey (64 chars), or null. */
    public static String groupKey(String identifier, String title, Date publicationDate, String publishedOn) {
        String raw = rawGroupKey(identifier, title, publicationDate, publishedOn);
        return raw == null ? null : EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(raw)));
    }

    public static String groupKey(PartyPublication row) {
        return groupKey(row.PublicationIdentifier, row.Title, row.PublicationDate, row.PublishedOn);
    }

    // ---------------------------------------------------------------- mapping (§2.1)

    /**
     * Paper-level values of one source row as an (uninserted) Publication. OwnerId is set by the engine.
     * Throws SObjectException if PublicationCategory__c can't hold the value (e.g. wrong field type).
     */
    public static Publication toPublication(PartyPublication src) {
        Publication p = new Publication(
            Name = src.Title,
            Title = src.Title,
            PublishedDate = src.PublicationDate,
            OriginalSourceName = src.PublishedOn,
            AbstractText = src.Summary,
            PublicationUrl = src.Url,
            CitationCount = src.CitationCount,
            ImpactFactor = src.ImpactFactor,
            Status = src.Status
        );
        if (LISTING_FIELD != null) {
            p.put(LISTING_FIELD, src.ListingPlatformType);
        }
        RoutedIdentifier routed = routeIdentifier(src.PublicationIdentifier);
        if (routed != null) {
            p.put(routed.field, routed.value);
        }
        if (src.PublicationCategory != null) {
            p.put(CATEGORY_FIELD, src.PublicationCategory);
        }
        return p;
    }

    /** Inactive user owner → fallback (the running user). Queues and active users are kept. */
    public static Id resolveOwner(Id ownerId, Set<Id> inactiveUserIds, Id fallback) {
        if (ownerId == null || inactiveUserIds.contains(ownerId)) {
            return fallback;
        }
        return ownerId;
    }

    // ---------------------------------------------------------------- conflicts (§3.5)

    /** Paper fields whose values differ between a row's candidate Publication and the actual one. */
    public static List<String> differingFields(SObject candidate, SObject actual) {
        List<String> diffs = new List<String>();
        for (String f : PAPER_FIELDS) {
            if (!sameValue(f, candidate.get(f), actual.get(f))) {
                diffs.add(f);
            }
        }
        return diffs;
    }

    @TestVisible
    private static Boolean sameValue(String field, Object a, Object b) {
        Boolean aBlank = a == null || (a instanceof String && String.isBlank((String) a));
        Boolean bBlank = b == null || (b instanceof String && String.isBlank((String) b));
        if (aBlank || bBlank) {
            return aBlank && bBlank;
        }
        if (a instanceof String && b instanceof String) {
            if (MULTI_VALUE_FIELDS.contains(field)) {
                return sortedValues((String) a).equals(sortedValues((String) b));
            }
            return ((String) a).equals((String) b); // case-sensitive on purpose
        }
        if (isNumber(a) && isNumber(b)) {
            return toDecimal(a) == toDecimal(b); // value comparison: 1.5 == 1.50, Double vs Decimal
        }
        return a == b;
    }

    private static Boolean isNumber(Object o) {
        return o instanceof Decimal || o instanceof Double || o instanceof Long || o instanceof Integer;
    }

    private static Decimal toDecimal(Object o) {
        if (o instanceof Decimal) {
            return (Decimal) o;
        }
        if (o instanceof Double) {
            return Decimal.valueOf((Double) o);
        }
        if (o instanceof Long) {
            return Decimal.valueOf((Long) o);
        }
        return Decimal.valueOf((Integer) o);
    }

    private static String sortedValues(String multi) {
        List<String> parts = multi.split(';');
        parts.sort();
        return String.join(parts, ';');
    }
}
