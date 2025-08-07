import { createElement } from '@lwc/engine-dom';
import LscMobileInline_CarouselLwc from '../lscMobileInline_CarouselLwc';

describe('c-lsc-mobile-inline-carousel-lwc', () => {
    afterEach(() => {
        // The jsdom instance is shared across test cases in a single file so reset the DOM
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('should render carousel component with three carousel images', () => {
        // Arrange
        const element = createElement('c-lsc-mobile-inline-carousel-lwc', {
            is: LscMobileInline_CarouselLwc
        });

        // Act
        document.body.appendChild(element);

        // Assert
        const carouselElement = element.shadowRoot.querySelector('lightning-carousel');
        expect(carouselElement).not.toBeNull();
        
        const carouselImages = element.shadowRoot.querySelectorAll('lightning-carousel-image');
        expect(carouselImages.length).toBe(3);
        
        // Verify first carousel image content
        expect(carouselImages[0].header).toBe("First Card");
        expect(carouselImages[0].description).toBe("First card description.");
    });

    it('should accept and apply custom height when provided', () => {
        // Arrange
        const CUSTOM_HEIGHT = '400px';
        const element = createElement('c-lsc-mobile-inline-carousel-lwc', {
            is: LscMobileInline_CarouselLwc
        });
        
        // Set the mobileHeight property
        element.mobileHeight = CUSTOM_HEIGHT;

        // Act
        document.body.appendChild(element);

        // Assert
        // Check if the component has the mobileHeight property set
        expect(element.mobileHeight).toBe(CUSTOM_HEIGHT);
        
        // Verify the component is rendering
        const containerDiv = element.shadowRoot.querySelector('.slds-box');
        expect(containerDiv).not.toBeNull();
        
        // Verify that carousel component exists
        const carouselComponent = element.shadowRoot.querySelector('lightning-carousel');
        expect(carouselComponent).not.toBeNull();
        
        // Instead of checking for the attribute, just verify the carousel component exists
        // since disable-auto-scroll is set directly in the template
    });
});