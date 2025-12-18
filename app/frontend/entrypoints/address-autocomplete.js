// Override attachShadow to inject custom styles into gmp-place-autocomplete
const originalAttachShadow = Element.prototype.attachShadow;
Element.prototype.attachShadow = function(init) {
  if (this.localName === 'gmp-place-autocomplete') {
    const shadow = originalAttachShadow.call(this, { ...init, mode: 'open' });
    
    const style = document.createElement('style');
    style.textContent = `
      :host {
        background: transparent !important;
        color-scheme: inherit !important;
      }
      .widget-container {
        border: none !important;
        background: transparent !important;
      }
      .input-container {
        padding: 0 !important;
      }
      .focus-ring {
        display: none !important;
      }
      input {
        font-family: Inter, system-ui, sans-serif !important;
        font-size: 0.9375rem !important;
        padding: 0.5rem 1rem !important;
      }
    `;
    shadow.appendChild(style);
    return shadow;
  }
  return originalAttachShadow.call(this, init);
};

function createAddressAutocomplete() {
  return {
    init() {
      this.initAutocomplete()
    },

    async initAutocomplete() {
      if (typeof google === 'undefined' || !google.maps) {
        setTimeout(() => this.initAutocomplete(), 100)
        return
      }

      await google.maps.importLibrary('places')

      const autocomplete = this.$refs.autocomplete
      if (!autocomplete) return

      autocomplete.addEventListener('gmp-select', async ({ placePrediction }) => {
        await this.fillAddress(placePrediction)
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
      if (this.$refs.postalCode) this.$refs.postalCode.value = postalCode

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
