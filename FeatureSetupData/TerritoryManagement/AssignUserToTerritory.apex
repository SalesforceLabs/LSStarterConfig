// Get the ID of the current user
Id currentUserId = UserInfo.getUserId();

// Define the ID or Developer Name of the territory you want to assign the user to.
// **Important: Replace this with the actual Territory ID or Developer Name.**

String targetTerritoryDevName = 'DMChicago20A02';

Boolean activateTerritoryModel = true; // Set to true to activate the territory model

try {
    Territory2 targetTerritory;

    if (!String.isBlank(targetTerritoryDevName)) {
        targetTerritory = [SELECT Id FROM Territory2 WHERE DeveloperName = :targetTerritoryDevName LIMIT 1];
    } else {
        System.debug('ERROR: Please provide either a Territory ID or a Territory Developer Name.');
        return;
    }

    if (targetTerritory == null) {
        System.debug('ERROR: Territory not found.');
        return;
    }

    // Check if the user is already assigned to the territory (optional, to prevent duplicates)
    List<UserTerritory2Association> existingAssignments = [
        SELECT Id
        FROM UserTerritory2Association
        WHERE UserId = :currentUserId AND Territory2Id = :targetTerritory.Id
        LIMIT 1
    ];

    if (existingAssignments.isEmpty()) {
        // Create a new UserTerritory2Association record
        UserTerritory2Association assignmentRule = new UserTerritory2Association();
        assignmentRule.Territory2Id = targetTerritory.Id;
        assignmentRule.UserId = currentUserId;

        // Insert the assignment rule
        insert assignmentRule;

        System.debug('SUCCESS: Current user assigned to Territory with ID: ' + targetTerritory.Id);
    } else {
        System.debug('INFO: Current user is already assigned to Territory with ID: ' + targetTerritory.Id);
    }

} catch (DmlException e) {
    System.debug('ERROR: An error occurred while assigning user to territory or activating model.');
    for (Integer i = 0; i < e.getNumDml(); i++) {
        System.debug(e.getDmlMessage(i));
    }
} catch (QueryException e) {
    System.debug('ERROR: An error occurred while querying data.');
    System.debug(e.getMessage());
}