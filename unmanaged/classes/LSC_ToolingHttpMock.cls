@IsTest
public class LSC_ToolingHttpMock implements HttpCalloutMock {
    private final Boolean failPatch;
    private final Boolean failQuery;
    private final Set<String> knownDeveloperNames;
    private final String knownId;

    public LSC_ToolingHttpMock() {
        this(false);
    }
    public LSC_ToolingHttpMock(Boolean failPatch) {
        this.failPatch = failPatch == null ? false : failPatch;
        this.failQuery = false;
        // Use one known record mapping
        this.knownDeveloperNames = new Set<String>{
            'AccountSearchSettings_OrgLevel',
            'Known_DevName'
        };
        this.knownId = 'a01XX0000000001AAE';
    }
    public LSC_ToolingHttpMock(Boolean failPatch, Boolean failQuery) {
        this.failPatch = failPatch == null ? false : failPatch;
        this.failQuery = failQuery == null ? false : failQuery;
        // Use one known record mapping
        this.knownDeveloperNames = new Set<String>{
            'AccountSearchSettings_OrgLevel',
            'Known_DevName'
        };
        this.knownId = 'a01XX0000000001AAE';
    }

    public HTTPResponse respond(HTTPRequest req) {
        HttpResponse res = new HttpResponse();
        String method = req.getMethod();
        String url = req.getEndpoint();

        // Tooling query
        if (method == 'GET' && url != null && url.contains('/tooling/query/')) {
            if (failQuery) {
                res.setStatusCode(404);
                res.setStatus('404 Not Found');
                res.setBody('[{"errorCode":"NOT_FOUND","message":"The requested resource does not exist"}]');
                return res;
            }
            // Return records array with one known mapping if any known name present in query
            String body = '{"totalSize":1,"done":true,"records":[{"Id":"' + knownId + '","DeveloperName":"AccountSearchSettings_OrgLevel"}]}';
            // If query does not include known devnames, return empty set
            Boolean containsKnown = false;
            for (String dn : knownDeveloperNames) {
                if (url.contains(EncodingUtil.urlEncode('\'' + dn + '\'', 'UTF-8'))) {
                    containsKnown = true;
                    break;
                }
            }
            if (!containsKnown) {
                body = '{"totalSize":0,"done":true,"records":[]}';
            }
            res.setStatusCode(200);
            res.setBody(body);
            return res;
        }

        // Tooling PATCH
        if (method == 'PATCH' && url != null && url.contains('/tooling/sobjects/LifeSciConfigRecord/')) {
            if (failPatch) {
                res.setStatusCode(400);
                res.setStatus('400 Bad Request');
                res.setBody('{"message":"Bad Request"}');
                return res;
            }
            // Simulate success
            res.setStatusCode(204); // No Content
            res.setStatus('204 No Content');
            return res;
        }

        // Default: Not Found for anything unexpected
        res.setStatusCode(404);
        res.setStatus('404 Not Found');
        res.setBody('{"errorCode":"NOT_FOUND","message":"Unknown endpoint in mock"}');
        return res;
    }
}


