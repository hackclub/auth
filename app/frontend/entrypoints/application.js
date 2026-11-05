import "../js/alpine.js";
import "../js/lightswitch.js";
import "../js/click-to-copy";
import "../js/otp-input.js";
import "../js/persona-verify.js";
import "../js/camera-capture.js";
import "../js/confirm-dialog.js";

import htmx from "htmx.org"
window.htmx = htmx

// Add CSRF token to all HTMX requests
document.addEventListener('htmx:configRequest', (event) => {
  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
  if (csrfToken) {
    event.detail.headers['X-CSRF-Token'] = csrfToken;
  }
});


// Copy error ID to clipboard
document.addEventListener('click', function (e) {
  const el = e.target.closest('[data-error-id]')
  if (!el) return
  navigator.clipboard.writeText(el.dataset.errorId).then(() => {
    const feedback = el.nextElementSibling || el.parentElement?.querySelector('.copy-feedback')
    if (feedback) {
      feedback.hidden = false
      setTimeout(() => { feedback.hidden = true }, 2000)
    }
  }).catch(err => console.error('Failed to copy:', err))
})