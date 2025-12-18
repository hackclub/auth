import Alpine from 'alpinejs'

Alpine.data('addressAutocomplete', () => ({
  autocomplete: null,
  
  init() {
    this.initAutocomplete()
  },
  
  initAutocomplete() {
    if (typeof google === 'undefined' || !google.maps || !google.maps.places) {
      setTimeout(() => this.initAutocomplete(), 100)
      return
    }
    
    const input = this.$refs.line1
    if (!input) return
    
    this.autocomplete = new google.maps.places.Autocomplete(input, {
      types: ['address'],
      fields: ['address_components', 'formatted_address']
    })
    
    this.autocomplete.addListener('place_changed', () => this.fillAddress())
  },
  
  fillAddress() {
    const place = this.autocomplete.getPlace()
    if (!place.address_components) return
    
    const components = {}
    for (const component of place.address_components) {
      const type = component.types[0]
      components[type] = {
        long: component.long_name,
        short: component.short_name
      }
    }
    
    const streetNumber = components.street_number?.long || ''
    const route = components.route?.long || ''
    const line1 = [streetNumber, route].filter(Boolean).join(' ')
    
    if (this.$refs.line1) this.$refs.line1.value = line1
    if (this.$refs.line2) this.$refs.line2.value = components.subpremise?.long || ''
    if (this.$refs.city) {
      this.$refs.city.value = components.locality?.long || 
                              components.sublocality_level_1?.long || 
                              components.postal_town?.long || ''
    }
    if (this.$refs.state) {
      this.$refs.state.value = components.administrative_area_level_1?.short || ''
    }
    if (this.$refs.postalCode) {
      this.$refs.postalCode.value = components.postal_code?.long || ''
    }
    if (this.$refs.country) {
      const countryCode = components.country?.short || ''
      this.$refs.country.value = countryCode
      this.$refs.country.dispatchEvent(new Event('change', { bubbles: true }))
    }
  }
}))
