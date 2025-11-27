import Alpine from 'alpinejs'
import { webauthnRegister } from './webauthn-registration.js'
import { webauthnAuth } from './webauthn-authentication.js'

Alpine.data('webauthnRegister', webauthnRegister)
Alpine.data('webauthnAuth', webauthnAuth)

window.Alpine = Alpine
Alpine.start()