import { createElement } from '@lwc/engine-dom';
import SubscribeToEvents from 'c/subscribeToEvents';
import { onError } from 'lightning/empApi';

// Mock the lightning/empApi module
jest.mock('lightning/empApi', () => {
    return {
        subscribe: jest.fn().mockResolvedValue({ channel: 'mockChannel' }),
        unsubscribe: jest.fn().mockImplementation((subscription, callback) => {
            callback(true);
            return Promise.resolve();
        }),
        onError: jest.fn(),
        setDebugFlag: jest.fn(),
        isEmpEnabled: jest.fn().mockReturnValue(true),
    };
});

describe('c-subscribe-to-events', () => {
    afterEach(() => {
        // The jsdom instance is shared across test cases in a single file so reset the DOM
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        // Clear mock calls between tests
        jest.clearAllMocks();
    });

    it('should be created without errors', () => {
        // Arrange & Act
        const element = createElement('c-subscribe-to-events', {
            is: SubscribeToEvents
        });

        // Assert - Make sure no errors are thrown
        expect(() => document.body.appendChild(element)).not.toThrow();
    });

    it('should register error listener on initialization', () => {
        // Arrange & Act
        const element = createElement('c-subscribe-to-events', {
            is: SubscribeToEvents
        });
        document.body.appendChild(element);

        // Assert
        expect(onError).toHaveBeenCalled();
    });
    
    it('should render lightning-card with title', () => {
        // Arrange & Act
        const element = createElement('c-subscribe-to-events', {
            is: SubscribeToEvents
        });
        document.body.appendChild(element);
        
        // Assert
        const cardElement = element.shadowRoot.querySelector('lightning-card');
        expect(cardElement).not.toBeNull();
        expect(cardElement.title).toBe('Platform Event Capture (EmpApi)');
    });
}); 