// Google Maps callback - fired when the API is fully loaded
window.onGoogleMapsLoaded = function() {
  window.googleMapsReady = true
  window.dispatchEvent(new CustomEvent('google-maps-loaded'))
}

// Override attachShadow to inject custom styles into gmp-place-autocomplete
const originalAttachShadow = Element.prototype.attachShadow;
Element.prototype.attachShadow = function(init) {
  if (this.localName === 'gmp-place-autocomplete') {
    const shadow = originalAttachShadow.call(this, { ...init, mode: 'open' });
    
    const style = document.createElement('style');
    style.textContent = `
      :host {
        background: var(--theme-background-input);
        border: none;
        box-shadow: inset 0 0 0 1px var(--theme-border);
        color: var(--theme-text);
        display: block;
      }
      :host:focus-within {
        outline: none;
        box-shadow: inset 0 0 0 2px var(--theme-focused-foreground);
      }
      .widget-container {
        border: none !important;
        background: transparent !important;
        padding: 0 !important;
      }
      .input-container {
        padding: 0 !important;
        background: transparent !important;
      }
      .focus-ring {
        display: none !important;
      }
      input {
        background: transparent !important;
        border: none !important;
        box-shadow: none !important;
        color: var(--theme-text);
        font-family: var(--font-family-mono);
        font-size: var(--font-size);
        line-height: calc(var(--theme-line-height-base) * 1rem);
        padding: 0 1ch;
      }
      input::placeholder {
        color: var(--theme-border);
      }
    `;
    shadow.appendChild(style);
    return shadow;
  }
  return originalAttachShadow.call(this, init);
};

function createAddressAutocomplete() {
  return {
    callingCodes: {},
    callingCode: '1',
    selectedCountry: 'US',

    init() {
      if (window.googleMapsReady) {
        this.initAutocomplete()
      } else {
        window.addEventListener('google-maps-loaded', () => this.initAutocomplete(), { once: true })
      }
    },

    updateCallingCode(countrySelect) {
      const code = this.callingCodes[countrySelect.value];
      if (code) this.callingCode = code;
      this.updateAutocompleteCountry(countrySelect.value);
    },

    updateAutocompleteCountry(country) {
      this.selectedCountry = country;
      if (country && this.$refs.autocomplete) {
        this.$refs.autocomplete.includedRegionCodes = [country];
      }
    },

    async initAutocomplete() {
      await customElements.whenDefined('gmp-place-autocomplete')

      const autocomplete = this.$refs.autocomplete
      if (!autocomplete) return

      autocomplete.addEventListener('gmp-select', async ({ placePrediction }) => {
        await this.fillAddress(placePrediction)
      })

      // Wait for shadow DOM input to be created
      const input = await this.waitForInput(autocomplete)
      if (input) {
        input.placeholder = 'Address line 1'
        input.focus()
      }
    },

    waitForInput(autocomplete) {
      return new Promise(resolve => {
        const check = () => {
          const input = autocomplete.shadowRoot?.querySelector('input')
          if (input) {
            resolve(input)
          } else {
            requestAnimationFrame(check)
          }
        }
        check()
      })
    },

    async fillAddress(placePrediction) {
      const place = placePrediction.toPlace()
      await place.fetchFields({ fields: ['addressComponents'] })

      if (!place.addressComponents) return

      let streetNumber = ''
      let route = ''
      let postalCode = ''

      for (const component of place.addressComponents) {
        const types = component.types

        if (types.includes('street_number')) {
          streetNumber = component.longText
        }
        if (types.includes('route')) {
          route = component.shortText
        }
        if (types.includes('postal_code')) {
          postalCode = component.longText
        }
        if (types.includes('postal_code_suffix')) {
          postalCode = `${postalCode}-${component.longText}`
        }
        if (types.includes('locality') || types.includes('sublocality_level_1') || types.includes('postal_town')) {
          if (this.$refs.city) this.$refs.city.value = component.longText
        }
        if (types.includes('administrative_area_level_1')) {
          if (this.$refs.state) this.$refs.state.value = component.shortText
        }
        if (types.includes('country')) {
          if (this.$refs.country) {
            this.$refs.country.value = component.shortText
            this.$refs.country.dispatchEvent(new Event('change', { bubbles: true }))
          }
        }
      }

      const line1 = [streetNumber, route].filter(Boolean).join(' ')
      if (this.$refs.line1) this.$refs.line1.value = line1
      if (this.$refs.postalCode && postalCode) this.$refs.postalCode.value = postalCode

      if (this.$refs.line2) this.$refs.line2.focus()
    }
  }
}

document.addEventListener('alpine:init', () => {
  Alpine.data('addressAutocomplete', createAddressAutocomplete)
})

if (window.Alpine) {
  window.Alpine.data('addressAutocomplete', createAddressAutocomplete)
}
