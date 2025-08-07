String modelDevName = 'LSCTerritoryModel';
Id currentUserId = UserInfo.getUserId();

// Fetch and activate model if needed
Territory2Model model = [SELECT Id, State FROM Territory2Model WHERE DeveloperName = :modelDevName LIMIT 1];
if (model != null && model.State.equalsIgnoreCase('Planning')) {
    try {
        model.State = 'Activating';
        update model;
        System.debug('SUCCESS: Territory model activated');
    } catch (Exception e) {
        System.debug('ERROR: Failed to activate model: ' + e.getMessage());
    }
}
