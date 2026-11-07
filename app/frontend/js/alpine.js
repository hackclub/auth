import Alpine from '@alpinejs/csp'
import { webauthnRegister } from './webauthn-registration.js'
import { webauthnAuth } from './webauthn-authentication.js'
import { stepUpWebauthn } from './webauthn-step-up.js'
import { scopeEditor } from './scope-editor.js'

Alpine.data('webauthnRegister', webauthnRegister)
Alpine.data('webauthnAuth', webauthnAuth)
Alpine.data('stepUpWebauthn', stepUpWebauthn)
Alpine.data('scopeEditor', scopeEditor)

Alpine.data('oauthCountdown', (initialCount) => ({
  countdown: initialCount,
  authLabel: '',
  ready: initialCount <= 0,
  init() {
    this.authLabel = this.$el.dataset.authLabel || ''
    if (this.countdown > 0) {
      const interval = setInterval(() => {
        this.countdown--
        if (this.countdown <= 0) {
          this.ready = true
          clearInterval(interval)
        }
      }, 1000)
    }
  },
  get buttonLabel() {
    return this.ready ? this.authLabel : 'Wait ' + this.countdown + 's...'
  }
}))

Alpine.data('documentForm', (initialType) => ({
  selectedType: initialType,
  transcriptFileCount: 0,
  studentIdFileCount: 0,
  governmentIdFileCount: 0,
  submitted: false,
  get canSubmit() {
    if (this.selectedType === 'transcript') {
      return this.transcriptFileCount >= 1 && this.studentIdFileCount >= 1
    }
    return this.governmentIdFileCount >= 1
  }
}))

Alpine.data('codeInput', () => ({
  codeValue: '',
  get isComplete() {
    return this.codeValue.replace(/\D/g, '').length === 6
  }
}))

window.Alpine = Alpine
Alpine.start()