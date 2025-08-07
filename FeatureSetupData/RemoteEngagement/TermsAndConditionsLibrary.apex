List<ContentWorkspace> libraries = [SELECT Id FROM ContentWorkspace WHERE DeveloperName = 'Terms_and_Conditions'];
if (libraries.size() > 0) {
    System.debug('Terms and Conditions library already exists');
} else {
    ContentWorkspace library = new ContentWorkspace();
    library.Name = 'Terms and Conditions';
    library.Description = 'Library containing terms and conditions documents';
    library.DeveloperName = 'Terms_and_Conditions';
    insert library;
    System.debug('Terms and Conditions library created successfully');

    //Share library with guest user
    List<User> guestUsers = [SELECT Id, Name FROM User WHERE UserType = 'Guest' and Name = 'Hcps Site Guest User'];
    User guestUser = guestUsers[0]; //Assuming there is one guest user
    ContentWorkspacePermission permission = [SELECT Id, Name FROM ContentWorkspacePermission WHERE Name = 'Viewer'];
    ContentWorkspaceMember member = new ContentWorkspaceMember();
    member.ContentWorkspaceId = library.Id;
    member.MemberId = guestUser.Id;
    member.ContentWorkspacePermissionId = permission.Id;
    insert member;
    System.debug('Terms and Conditions library shared with guest user successfully');
}