public with sharing class LSC_MetadataSupport {
	// JSON parsing
	public static List<Map<String, Object>> parseJsonRows(String json, String label, LSC_SeedResult result) {
		try {
			Object parsed = System.JSON.deserializeUntyped(json);
			if (parsed instanceof List<Object>) {
				return filterMapRows((List<Object>) parsed);
			} else if (parsed instanceof Map<String, Object>) {
				Map<String, Object> m = (Map<String, Object>) parsed;
				Object recs = m.get('records');
				if (recs instanceof List<Object>) {
					return filterMapRows((List<Object>) recs);
				}
			}
			return new List<Map<String, Object>>();
		} catch (Exception e) {
			result.messages.add('Failed to parse JSON for ' + label + ': ' + e.getMessage());
			return null;
		}
	}

	// Helper to tag messages for top-level aggregation (overload to match tests)
	public static List<String> tagMessages(List<String> messages, String tag) {
		List<String> tagged = new List<String>();
		if (messages != null) {
			for (String m : messages) {
				tagged.add('[' + tag + '] ' + m);
			}
		}
		return tagged;
	}

	// Get SObjectType with and without SeedResult (overload to match tests)
	public static SObjectType getSObjectType(String apiName) {
		Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
		return gd.get(apiName);
	}
	public static SObjectType getSObjectType(String apiName, LSC_SeedResult result) {
		return getSObjectType(apiName);
	}

	// Load Static Resource content (overload to match tests)
	public static String loadStaticResource(String name) {
		try {
			if (!Schema.sObjectType.StaticResource.isAccessible()
				|| !Schema.sObjectType.StaticResource.fields.Body.isAccessible()) {
				return null;
			}
			StaticResource sr = [SELECT Body FROM StaticResource WHERE Name = :name LIMIT 1];
			return sr != null ? sr.Body.toString() : null;
		} catch (Exception e) {
			return null;
		}
	}
	public static String loadStaticResource(String name, LSC_SeedResult result) {
		return loadStaticResource(name);
	}

	private static List<Map<String, Object>> filterMapRows(List<Object> raw) {
		List<Map<String, Object>> out = new List<Map<String, Object>>();
		for (Object o : raw) {
			if (o instanceof Map<String, Object>) {
				out.add((Map<String, Object>) o);
			}
		}
		return out;
	}

	// Builders
	public static List<SObject> buildCategorySObjects(List<Map<String, Object>> rows, SObjectType sobType, List<String> outRefs) {
		List<SObject> out = new List<SObject>();
		for (Map<String, Object> r : rows) {
			String ref = null;
			Object attrs = r.get('attributes');
			if (attrs instanceof Map<String, Object>) {
				Map<String, Object> a = (Map<String, Object>) attrs;
				Object rid = a.get('referenceId');
				if (rid instanceof String) {
					ref = (String) rid;
				}
			}
			r.remove('attributes');
			SObject sob = sobType.newSObject();
			for (String fieldName : r.keySet()) {
				sob.put(fieldName, r.get(fieldName));
			}
			out.add(sob);
			outRefs.add(ref);
		}
		return out;
	}

	public static List<SObject> buildRecordSObjects(List<Map<String, Object>> rows, SObjectType sobType, List<String> outRefs, Map<String, String> categoryRefToId) {
		List<SObject> out = new List<SObject>();
		Map<String, Schema.SObjectField> fieldMap = sobType.getDescribe().fields.getMap();
		for (Map<String, Object> r : rows) {
			String ref = null;
			Object attrs = r.get('attributes');
			if (attrs instanceof Map<String, Object>) {
				Map<String, Object> a = (Map<String, Object>) attrs;
				Object rid = a.get('referenceId');
				if (rid instanceof String) {
					ref = (String) rid;
				}
			}
			r.remove('attributes');
			Object catVal = r.get('LifeScienceMetadataCategoryId');
			if (catVal instanceof String && ((String) catVal).startsWith('@')) {
				String catRef = ((String) catVal).substring(1);
				String catId = categoryRefToId.get(catRef);
				r.put('LifeScienceMetadataCategoryId', catId);
			}
			SObject sob = sobType.newSObject();
			for (String fieldName : r.keySet()) {
				// Only set fields that exist on target SObjectType to avoid SObjectException in tests
				if (fieldMap == null || fieldMap.containsKey(fieldName)) {
					sob.put(fieldName, r.get(fieldName));
				}
			}
			out.add(sob);
			outRefs.add(ref);
		}
		return out;
	}

	public static List<SObject> buildFieldValueSObjects(List<Map<String, Object>> rows, SObjectType sobType, Map<String, String> recordRefToId, List<String> outRefs) {
		List<SObject> out = new List<SObject>();
		Map<String, Schema.SObjectField> fieldMap = sobType.getDescribe().fields.getMap();
		for (Map<String, Object> r : rows) {
			// capture referenceId
			Object attrs = r.get('attributes');
			if (attrs instanceof Map<String, Object>) {
				Map<String, Object> a = (Map<String, Object>) attrs;
				Object rid = a.get('referenceId');
				if (rid instanceof String) {
					outRefs.add((String) rid);
				} else {
					outRefs.add(null);
				}
			} else {
				outRefs.add(null);
			}
			r.remove('attributes');
			Object recVal = r.get('LifeScienceMetadataRecordId');
			if (recVal instanceof String && ((String) recVal).startsWith('@')) {
				String recRef = ((String) recVal).substring(1);
				String recId = recordRefToId.get(recRef);
				r.put('LifeScienceMetadataRecordId', recId);
			}
			SObject sob = sobType.newSObject();
			for (String fieldName : r.keySet()) {
				// Only set fields that exist on target SObjectType to avoid SObjectException in tests
				if (fieldMap == null || fieldMap.containsKey(fieldName)) {
					Object v = r.get(fieldName);
					sob.put(fieldName, coerceValue(fieldMap, fieldName, v));
				}
			}
			out.add(sob);
		}
		return out;
	}

	private static Object coerceValue(Map<String, Schema.SObjectField> fieldMap, String fieldName, Object value) {
		Schema.DescribeFieldResult dfr = null;
		Schema.SObjectField sf = fieldMap != null ? fieldMap.get(fieldName) : null;
		if (sf != null) {
			dfr = sf.getDescribe();
		}
		if (dfr == null || value == null) {
			return value;
		}
		Schema.DisplayType t = dfr.getType();
		if (t == Schema.DisplayType.Boolean) {
			return coerceBoolean(value);
		}
		if (t == Schema.DisplayType.Integer) {
			return coerceInteger(value);
		}
		if (t == Schema.DisplayType.Double || t == Schema.DisplayType.Currency || t == Schema.DisplayType.Percent) {
			return coerceDecimal(value);
		}
		return value;
	}

	private static Object coerceBoolean(Object value) {
		if (value instanceof Boolean) {
			return value;
		}
		if (value instanceof String) {
			String s = ((String) value).trim();
			if ('true'.equalsIgnoreCase(s)) {
				return true;
			}
			if ('false'.equalsIgnoreCase(s)) {
				return false;
			}
		}
		return null;
	}

	private static Object coerceInteger(Object value) {
		if (value instanceof Integer) {
			return value;
		}
		if (value instanceof String) {
			try {
				return Integer.valueOf((String) value);
			} catch (Exception e) {
				return null;
			}
		}
		return null;
	}

	private static Object coerceDecimal(Object value) {
		if (value instanceof Decimal) {
			return value;
		}
		if (value instanceof String) {
			try {
				return Decimal.valueOf((String) value);
			} catch (Exception e) {
				return null;
			}
		}
		return null;
	}

	// DML helpers
	public static void insertBulk(List<SObject> records, LSC_SeedResult result) {
		Database.SaveResult[] sr = Database.insert(records, false);
		for (Integer idx = 0; idx < sr.size(); idx++) {
			if (sr[idx].isSuccess()) {
				result.inserted++;
			} else {
				result.failed++;
				for (Database.Error err : sr[idx].getErrors()) {
					result.messages.add(String.valueOf(err.getStatusCode()) + ': ' + err.getMessage());
					System.debug('DML ERROR: ' + String.valueOf(err.getStatusCode()) + ': ' + err.getMessage());
				}
			}
		}
	}

	public static void insertBulkWithRefMap(List<SObject> records, List<String> refs, Map<String, String> refToId, LSC_SeedResult result) {
		Database.SaveResult[] sr = Database.insert(records, false);
		for (Integer idx = 0; idx < sr.size(); idx++) {
			handleOneResult(sr, idx, refs, refToId, result);
		}
	}

	private static void handleOneResult(Database.SaveResult[] sr, Integer idx, List<String> refs, Map<String, String> refToId, LSC_SeedResult result) {
		Database.SaveResult one = sr[idx];
		if (one.isSuccess()) {
			result.inserted++;
			mapRefIfAny(one, idx, refs, refToId);
			return;
		}
		result.failed++;
		String ctx = buildContext(refs, idx);
		for (Database.Error err : one.getErrors()) {
			String formatted = formatError(ctx, err);
			result.messages.add(formatted);
			System.debug('DML ERROR: ' + formatted);
		}
	}

	private static void mapRefIfAny(Database.SaveResult one, Integer idx, List<String> refs, Map<String, String> refToId) {
		if (refToId == null || refs == null || refs.size() <= idx) {
			return;
		}
		String ref = refs[idx];
		if (ref != null) {
			refToId.put(ref, one.getId());
		}
	}

	private static String buildContext(List<String> refs, Integer idx) {
		if (refs == null || refs.size() <= idx || refs[idx] == null) {
			return 'ref=?';
		}
		return 'ref=' + refs[idx];
	}

	private static String formatError(String ctx, Database.Error err) {
		String fields = '';
		if (err.getFields() != null && err.getFields().size() > 0) {
			fields = String.join(new List<String>(err.getFields()), ',');
		}
		String fieldsPart = fields != '' ? (' fields=[' + fields + ']') : '';
		return ctx + ' ' + String.valueOf(err.getStatusCode()) + ': ' + err.getMessage() + fieldsPart;
	}

	// Duplicate filtering
	public static List<SObject> filterDuplicateCategories(List<SObject> toInsert, List<String> refs, LSC_SeedResult result) {
		if (toInsert == null || toInsert.isEmpty()) {
			return new List<SObject>();
		}
		Set<String> categoryNames = collectCategoryNames(toInsert);
		if (categoryNames.isEmpty()) {
			return toInsert;
		}
		Map<String, String> existing = getExistingCategoryNames(categoryNames, result);
		if (existing.isEmpty()) {
			return toInsert;
		}
		return filterByExisting(toInsert, refs, existing, result);
	}

	private static Set<String> collectCategoryNames(List<SObject> rows) {
		Set<String> names = new Set<String>();
		for (SObject sob : rows) {
			Object n = sob.get('Name');
			if (n instanceof String) {
				names.add((String) n);
			}
		}
		return names;
	}

	private static Map<String, String> getExistingCategoryNames(Set<String> names, LSC_SeedResult result) {
		Map<String, String> existing = new Map<String, String>();
		if (!Schema.sObjectType.LifeSciMetadataCategory.isAccessible()
			|| !Schema.sObjectType.LifeSciMetadataCategory.fields.Name.isAccessible()) {
			result.messages.add('Missing read access to LifeSciMetadataCategory.Name; skipping duplicate pre-check.');
			return existing;
		}
		for (LifeSciMetadataCategory c : [
			SELECT Name
			FROM LifeSciMetadataCategory
			WHERE Name IN :names
			WITH SECURITY_ENFORCED
		]) {
			existing.put(c.Name, c.Name);
		}
		return existing;
	}

	private static List<SObject> filterByExisting(List<SObject> toInsert, List<String> refs, Map<String, String> existing, LSC_SeedResult result) {
		List<SObject> filtered = new List<SObject>();
		for (Integer i = 0; i < toInsert.size(); i++) {
			SObject sob = toInsert[i];
			String nm = (String) sob.get('Name');
			if (nm != null && existing.containsKey(nm)) {
				result.failed++;
				String ref = (refs != null && i < refs.size() ? refs[i] : null);
				String ctx = ref != null ? ('ref=' + ref) : 'ref=?';
				String msg = ctx + ' DUPLICATE_VALUE: Category with Name already exists fields=[Name]';
				result.messages.add(msg);
				System.debug('DML ERROR: ' + msg);
			} else {
				filtered.add(sob);
			}
		}
		return filtered;
	}
}


