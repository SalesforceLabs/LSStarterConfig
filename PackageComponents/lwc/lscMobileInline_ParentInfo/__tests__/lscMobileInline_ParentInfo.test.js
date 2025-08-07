import { createElement } from 'lwc';
import LscMobileInline_ParentInfo from 'c/lscMobileInline_ParentInfo';

// Mock the lightning/navigation module
jest.mock('lightning/navigation', () => {
    return {
        NavigationMixin: jest.fn().mockImplementation(Base => {
            return Base;
        })
    };
});

// Mock the wire adapters
jest.mock('lightning/uiRelatedListApi', () => {
    return {
        getRelatedListRecords: jest.fn()
    };
});

jest.mock('lightning/uiRecordApi', () => {
    return {
        getRecord: jest.fn()
    };
});

// Helper function to wait for any asynchronous DOM updates
async function flushPromises() {
    return Promise.resolve();
}

describe('c-lsc-mobile-inline-parent-info', () => {
    afterEach(() => {
        // The jsdom instance is shared across test cases in a single file so reset the DOM
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        
        // Reset mocks
        jest.clearAllMocks();
    });

    it('displays a loading spinner when initializing', async () => {
        // Create component
        const element = createElement('c-lsc-mobile-inline-parent-info', {
            is: LscMobileInline_ParentInfo
        });
        document.body.appendChild(element);
        
        // The component shows a loading spinner by default
        await flushPromises();
        
        // Verify the loading spinner is displayed
        const spinnerElement = element.shadowRoot.querySelector('lightning-spinner');
        expect(spinnerElement).not.toBeNull();
    });
});