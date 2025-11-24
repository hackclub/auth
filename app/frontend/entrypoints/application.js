import "../js/alpine.js";
import "../js/lightswitch.js";
import "../js/click-to-copy";
import "../js/otp-input.js";
import htmx from "htmx.org"
window.htmx = htmx

// Add CSRF token to all HTMX requests
document.addEventListener('htmx:configRequest', (event) => {
  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
  if (csrfToken) {
    event.detail.headers['X-CSRF-Token'] = csrfToken;
  }
});