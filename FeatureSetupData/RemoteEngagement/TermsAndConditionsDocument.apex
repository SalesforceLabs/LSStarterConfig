// Get the Terms and Conditions library
ContentWorkspace library = [SELECT Id FROM ContentWorkspace WHERE DeveloperName = 'Terms_and_Conditions'];

List<ContentVersion> existingDocuments = [SELECT Id FROM ContentVersion WHERE Title = 'Terms_en_US' and FirstPublishLocationId = :library.Id];
if (existingDocuments.size() > 0) {
    System.debug('Terms and Conditions document already exists');
} else {
    // Create the Terms document in the library
    ContentVersion cv = new ContentVersion();
    cv.Title = 'Terms_en_US';
    cv.PathOnClient = 'Terms_en_US.html';
    cv.VersionData = Blob.valueOf(getTermsContent());
    cv.FirstPublishLocationId = library.Id;
    cv.Description = 'Terms and Conditions document - English US';
    upsert cv;

    System.debug('Terms and Conditions document created successfully');
}

private String getTermsContent() {
    return '<h1>Terms and Conditions of <code>Life Sciences Hcps Site</code></h1>\n\n' +
    '<p>This document governs the use of our website, and, any other related agreement or legal relationship with us in a legally binding way.</p>\n\n' +
    '<h2>TERMS OF USE</h2>\n' +
    '<p>Unless stated otherwise, the terms in this section apply generally when using our website.</p>\n' +
    '<p>Specific or additional conditions may apply in certain situations and are noted in this document.</p>\n' +
    '<p>By using our website, you confirm the following:</p>\n' +
    '<ul>\n' +
    '<li>Our website and service may only be used within the scope of what is provided for, under these terms and applicable law.</li>\n' +
    '<li>You are solely responsible for ensuring your use of our website and service does not violate any laws, regulations, or third-party rights.</li>\n' +
    '<li>Our website and service may only be used within the scope of what is provided for, under these terms and applicable law.</li>\n' +
    '<li>We reserve the right to protect our interests by denying you access to our website or service, terminating contracts, and reporting any misconduct to the appropriate authorities if you are involved in or suspected of the following</li>\n' +
    '<ul>\n' +
    '<li>violating laws, regulations, or these terms;</li>\n' +
    '<li>infringing on third-party rights;</li>\n' +
    '<li>significantly impairing our legitimate interests;</li>\n' +
    '<li>offending us or any third party.</li>\n' +
    '</ul>\n' +
    '</ul>\n' +
    '<h4>Indemnification</h4>\n' +
    '<p>By using and accessing the service, you agree to defend, indemnify, and hold us, our subsidiaries, affiliates, officers, directors, agents, co-branders, partners, suppliers, and employees harmless from any claims, damages, losses, liabilities, costs, or expenses, including legal fees, arising from:</p>\n' +
    '<ul>\n' +
    '<li>your use of the service, including any data or content you transmit or receive;</li>\n' +
    '<li>your violation of these terms, including any breach of representations and warranties;</li>\n' +
    '<li>your violation of third-party rights, such as privacy or intellectual property rights;</li>\n' +
    '<li>your violation of statutory laws, rules, or regulations;</li>\n' +
    '<li>any content submitted from your account, including third-party access using username, password, or other security measures, including misleading, false, or inaccurate information;</li>\n' +
    '<li>your intentional misconduct; or</li>\n' +
    '<li>any statutory provision by you or your affiliates, officers, directors, agents, co-branders, partners, suppliers, and employees to the extent permitted by law.</li>\n' +
    '</ul>';
}