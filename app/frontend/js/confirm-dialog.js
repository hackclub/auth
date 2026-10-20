// Confirm dialog for data-confirm attributes.
// Click targets (buttons, links): shows confirm on click, prevents default if cancelled.
// Form targets: shows confirm on submit, prevents submit if cancelled.

document.addEventListener('click', function (e) {
  const el = e.target.closest('[data-confirm]')
  if (el && el.tagName !== 'FORM') {
    if (!confirm(el.dataset.confirm)) {
      e.preventDefault()
      e.stopImmediatePropagation()
    }
  }
})

document.addEventListener('submit', function (e) {
  const message = e.target.dataset.confirm
  if (message && !confirm(message)) {
    e.preventDefault()
  }
})
