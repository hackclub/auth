import Alpine from 'alpinejs'
import { webauthnRegister } from './webauthn-registration.js'
import { webauthnAuth } from './webauthn-authentication.js'
import { stepUpWebauthn } from './webauthn-step-up.js'

Alpine.data('webauthnRegister', webauthnRegister)
Alpine.data('webauthnAuth', webauthnAuth)
Alpine.data('stepUpWebauthn', stepUpWebauthn)

window.Alpine = Alpine
Alpine.start()