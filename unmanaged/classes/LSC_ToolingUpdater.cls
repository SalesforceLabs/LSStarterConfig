/**
 * This class is used to update the LifeSciConfigRecord setup records by DeveloperName via Tooling API.
 *
 * See Scripts/apex/LSC_ToolingUpdater.cls for usage notes.
 */
public with sharing class LSC_ToolingUpdater {

    // API version for Tooling API calls
    private String getApiVersion() {
        return '65.0';
    }

    // Entry point: update LifeSciConfigRecord setup records by DeveloperName via Tooling API
    // - Each request specifies DeveloperName and a map of fields to update
    // - Returns a map of DeveloperName -> success/failure message
    public Map<String, String> updateByDeveloperName(List<LSC_UpdateRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return new Map<String, String>();
        }

        // 1) Resolve Ids for all DeveloperNames via Tooling query
        Set<String> devNames = new Set<String>();
        for (LSC_UpdateRequest r : requests) {
            if (r != null && String.isNotBlank(r.developerName)) {
                devNames.add(r.developerName.trim());
            }
        }
        if (devNames.isEmpty()) {
            return new Map<String, String>();
        }

        Map<String, String> developerNameToId = this.fetchIdsByDeveloperName(devNames);

        // 2) PATCH each record using Tooling sObject endpoint
        Map<String, String> results = new Map<String, String>();
        for (LSC_UpdateRequest r : requests) {
            if (r == null || String.isBlank(r.developerName)) {
                continue;
            }
            String devName = r.developerName.trim();
            String recId = developerNameToId.get(devName);
            if (recId == null) {
                results.put(devName, 'Not found');
                continue;
            }
            try {
                this.patchLifeSciConfigRecord(recId, r.fieldsToUpdate);
                results.put(devName, 'Updated');
            } catch (Exception e) {
                results.put(devName, 'Failed: ' + e.getMessage());
            }
        }
        return results;
    }

    // Query Tooling API for LifeSciConfigRecord Ids by DeveloperName
    private Map<String, String> fetchIdsByDeveloperName(Set<String> developerNames) {
        // Build SOQL
        List<String> parts = new List<String>();
        for (String dn : developerNames) {
            // Minimal escaping for single quotes
            parts.add('\'' + dn.replace('\'', '\\\'') + '\'');
        }
        String inClause = String.join(parts, ',');
        String soql = 'SELECT Id, DeveloperName FROM LifeSciConfigRecord WHERE DeveloperName IN (' + inClause + ')';

        // Tooling query endpoint
        String url = this.getBaseUrl() + '/services/data/v' + this.getApiVersion() + '/tooling/query/?q=' + EncodingUtil.urlEncode(soql, 'UTF-8');
        HttpRequest req = this.baseRequest('GET', url);
        Http http = new Http();
        HttpResponse res = http.send(req);
        // If query fails (e.g., 404), include the developer names we attempted
        Integer sc = res.getStatusCode();
        if (sc < 200 || sc > 299) {
            String devList = String.join(new List<String>(developerNames), ', ');
            throw new LSC_ToolingUpdaterException(
                'GET ' + url + ' failed for DeveloperName(s): [' + devList + '] -> '
                + res.getStatus() + ' ' + res.getBody()
            );
        }

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        List<Object> records = (List<Object>) payload.get('records');
        Map<String, String> out = new Map<String, String>();
        for (Object o : records) {
            Map<String, Object> row = (Map<String, Object>) o;
            String id = (String) row.get('Id');
            String devName = (String) row.get('DeveloperName');
            if (id != null && devName != null) {
                out.put(devName, id);
            }
        }
        return out;
    }

    // PATCH LifeSciConfigRecord via Tooling API
    private void patchLifeSciConfigRecord(String recordId, Map<String, Object> fieldsToUpdate) {
        if (String.isBlank(recordId)) {
            throw new LSC_ToolingUpdaterException('Missing recordId');
        }
        if (fieldsToUpdate == null || fieldsToUpdate.isEmpty()) {
            // Nothing to update, treat as success
            return;
        }
        String url = this.getBaseUrl() + '/services/data/v' + this.getApiVersion() + '/tooling/sobjects/LifeSciConfigRecord/' + recordId;
        HttpRequest req = this.baseRequest('PATCH', url);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(fieldsToUpdate));
        Http http = new Http();
        HttpResponse res = http.send(req);
        // Successful PATCH returns 204 No Content
        if (res.getStatusCode() != 204) {
            throw new LSC_ToolingUpdaterException(
                'PATCH ' + url + ' failed (' + res.getStatus() + '): ' + res.getBody()
                + ' | payload=' + JSON.serialize(fieldsToUpdate)
            );
        }
    }

    // Helpers
    private HttpRequest baseRequest(String method, String url) {
        HttpRequest req = new HttpRequest();
        req.setMethod(method);
        req.setEndpoint(url);
        req.setHeader('Authorization', 'Bearer ' + UserInfo.getSessionId());
        req.setHeader('Accept', 'application/json');
        return req;
    }

    private void ensure2xx(HttpResponse res, String prefix) {
        Integer sc = res.getStatusCode();
        if (sc < 200 || sc > 299) {
            throw new LSC_ToolingUpdaterException(prefix + ': ' + res.getStatus() + ' ' + res.getBody());
        }
    }

    private String getBaseUrl() {
        // Use the org domain base URL
        return URL.getOrgDomainUrl().toExternalForm();
    }
}


