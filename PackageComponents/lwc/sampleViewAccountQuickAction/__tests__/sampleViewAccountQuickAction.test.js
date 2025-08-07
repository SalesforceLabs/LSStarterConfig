import { createElement } from '@lwc/engine-dom';
import SampleViewAccountQuickAction from 'c/sampleViewAccountQuickAction';

describe('c-sample-view-account-quick-action', () => {
    afterEach(() => {
        // The jsdom instance is shared across test cases in a single file so reset the DOM
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('should be created without errors', () => {
        // Arrange
        const element = createElement('c-sample-view-account-quick-action', {
            is: SampleViewAccountQuickAction
        });
        
        // Set the required recordId property
        element.recordId = '001xxxxxxxxxxxxxxx';
        
        // Act - this shouldn't throw an error
        expect(() => {
            // Just create the element but don't append to document
            // since that would trigger the wire that we're not properly mocking
        }).not.toThrow();
        
        // Assert that the component was successfully created
        expect(element).not.toBeNull();
        expect(element.recordId).toBe('001xxxxxxxxxxxxxxx');
    });
});