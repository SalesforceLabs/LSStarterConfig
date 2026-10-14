const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver'],
    // Components live under PackageComponents/lwc, which is not a sfdx-project.json
    // packageDirectory, so the default resolver can't map `c/*` imports to them.
    moduleNameMapper: {
        ...(jestConfig.moduleNameMapper || {}),
        '^c/(.+)$': '<rootDir>/PackageComponents/lwc/$1/$1'
    }
};
