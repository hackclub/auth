// session revoker form: show only the selected adapter's fields, and disable the others so
// they aren't submitted. plain DOM so it works under both the app and directory layouts.
function sync(form) {
  const adapter = form.querySelector('[data-revoker-adapter]')?.value;
  form.querySelectorAll('[data-revoker-fields]').forEach((fieldset) => {
    const active = fieldset.dataset.revokerFields === adapter;
    fieldset.hidden = !active;
    fieldset.disabled = !active;
  });
}

document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('form[data-revoker-form]').forEach(sync);
});

document.addEventListener('change', (e) => {
  if (!e.target.matches('[data-revoker-adapter]')) return;
  const form = e.target.closest('form[data-revoker-form]');
  if (form) sync(form);
});
