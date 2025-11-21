public with sharing class LSC_UpdateQueue implements Queueable, Database.AllowsCallouts {
    private final List<String> developerNames;
    private final Integer startIndex;
    private final Integer chunkSize;

    public LSC_UpdateQueue(List<String> developerNames) {
        this.developerNames = developerNames == null ? new List<String>() : new List<String>(developerNames);
        this.startIndex = 0;
        this.chunkSize = 75;
    }

    public LSC_UpdateQueue(List<String> developerNames, Integer startIndex, Integer chunkSize) {
        this.developerNames = developerNames == null ? new List<String>() : new List<String>(developerNames);
        Integer s = startIndex == null ? 0 : startIndex;
        Integer c = chunkSize == null || chunkSize <= 0 ? 75 : chunkSize;
        if (s < 0) {
            s = 0;
        }
        this.startIndex = s;
        this.chunkSize = c;
    }

    public void execute(QueueableContext context) {
        Integer total = developerNames.size();
        if (total == 0) {
            return;
        }

        Integer endExclusive = startIndex + chunkSize;
        if (endExclusive > total) {
            endExclusive = total;
        }

        // Build current slice
        List<LSC_UpdateRequest> reqs = new List<LSC_UpdateRequest>();
        for (Integer i = startIndex; i < endExclusive; i++) {
            String dn = developerNames[i];
            if (String.isBlank(dn)) {
                continue;
            }
            LSC_UpdateRequest r = new LSC_UpdateRequest();
            r.developerName = dn.trim();
            r.fieldsToUpdate = new Map<String, Object>{ 'IsActive' => true };
            reqs.add(r);
        }
        if (!reqs.isEmpty()) {
            new LSC_ToolingUpdater().updateByDeveloperName(reqs);
        }

        // Chain next slice if any remain
        if (endExclusive < total) {
            System.enqueueJob(new LSC_UpdateQueue(developerNames, endExclusive, chunkSize));
        }
    }
}


