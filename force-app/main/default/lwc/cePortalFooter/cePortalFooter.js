import { LightningElement } from 'lwc';
import SchibstedGroteskFont from '@salesforce/resourceUrl/Schibsted_Grotesk_Font';

export default class CePortalFooter extends LightningElement {
    fontUrl = SchibstedGroteskFont;

    connectedCallback() {
        // Load Schibsted Grotesk font
        this.loadFont();
    }

    loadFont() {
        // Inject @font-face rules dynamically using the static resource URL
        const style = document.createElement('style');
        style.textContent = `
            @font-face {
                font-family: 'Schibsted Grotesk';
                src: url('${this.fontUrl}/SchibstedGrotesk-Regular.woff2') format('woff2'),
                     url('${this.fontUrl}/SchibstedGrotesk-Regular.woff') format('woff'),
                     url('${this.fontUrl}/SchibstedGrotesk-Regular.ttf') format('truetype'),
                     url('${this.fontUrl}/Regular.woff2') format('woff2'),
                     url('${this.fontUrl}/Regular.woff') format('woff'),
                     url('${this.fontUrl}/Regular.ttf') format('truetype');
                font-weight: 400;
                font-style: normal;
                font-display: swap;
            }
            @font-face {
                font-family: 'Schibsted Grotesk';
                src: url('${this.fontUrl}/SchibstedGrotesk-Medium.woff2') format('woff2'),
                     url('${this.fontUrl}/SchibstedGrotesk-Medium.woff') format('woff'),
                     url('${this.fontUrl}/SchibstedGrotesk-Medium.ttf') format('truetype'),
                     url('${this.fontUrl}/Medium.woff2') format('woff2'),
                     url('${this.fontUrl}/Medium.woff') format('woff'),
                     url('${this.fontUrl}/Medium.ttf') format('truetype');
                font-weight: 500;
                font-style: normal;
                font-display: swap;
            }
            @font-face {
                font-family: 'Schibsted Grotesk';
                src: url('${this.fontUrl}/SchibstedGrotesk-Bold.woff2') format('woff2'),
                     url('${this.fontUrl}/SchibstedGrotesk-Bold.woff') format('woff'),
                     url('${this.fontUrl}/SchibstedGrotesk-Bold.ttf') format('truetype'),
                     url('${this.fontUrl}/Bold.woff2') format('woff2'),
                     url('${this.fontUrl}/Bold.woff') format('woff'),
                     url('${this.fontUrl}/Bold.ttf') format('truetype');
                font-weight: 700;
                font-style: normal;
                font-display: swap;
            }
        `;
        document.head.appendChild(style);
    }
}

