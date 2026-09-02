import Alpine from 'alpinejs'
import { webauthnRegister } from './webauthn-registration.js'
import { webauthnAuth } from './webauthn-authentication.js'
import { stepUpWebauthn } from './webauthn-step-up.js'
import { passkeyLogin } from './passkey-login.js'
import { passkeySetup } from './passkey-setup.js'
import { scopeEditor } from './scope-editor.js'

Alpine.data('webauthnRegister', webauthnRegister)
Alpine.data('webauthnAuth', webauthnAuth)
Alpine.data('stepUpWebauthn', stepUpWebauthn)
Alpine.data('passkeyLogin', passkeyLogin)
Alpine.data('passkeySetup', passkeySetup)
Alpine.data('scopeEditor', scopeEditor)

window.Alpine = Alpine
Alpine.start()