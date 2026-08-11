import "../js/alpine.js";
import "../js/lightswitch.js";
import "../js/click-to-copy";
import "../js/otp-input.js";
import "../js/persona-verify.js";

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
window.copyErrorId = function(element) {
  const errorId = element.dataset.errorId;
  const feedback = element.nextElementSibling || element.parentElement.querySelector('.copy-feedback');

  navigator.clipboard.writeText(errorId).then(() => {
    if (feedback) {
      feedback.hidden = false;
      setTimeout(() => { feedback.hidden = true; }, 2000);
    }
  }).catch(err => {
    console.error('Failed to copy:', err);
  });
};

// Delegated listener for Phlex-rendered banners (can't use inline onclick)
document.addEventListener('click', function(e) {
  const element = e.target.closest('[data-error-id]');
  if (element && !element.hasAttribute('onclick')) copyErrorId(element);
});
