// data-confirm.js — rails-ujs-style data-confirm, since we ship neither rails-ujs nor turbo
//
// button_to(..., data: { confirm: }) puts data-confirm on the <button> (the <form>
// only gets form: { ... }), f.submit puts it on the <input type=submit>, and
// form_with(..., data: { confirm: }) puts it on the <form>. listening in the capture
// phase on document means a "no" lands before htmx's element listeners or svelte's
// delegated ones ever see the event.

const CLICK_SELECTOR = [
  'a[data-confirm]',
  'button[data-confirm]',
  'input[type=submit][data-confirm]',
  'input[type=image][data-confirm]',
].join(', ');

const HTMX_REQUEST = ['get', 'post', 'put', 'patch', 'delete']
  .flatMap((verb) => [`[hx-${verb}]`, `[data-hx-${verb}]`])
  .join(', ');

// the element htmx fires a request from when this one is clicked/submitted, if any.
// a submit button hands off to its form owner: el.form, not closest('form'), so
// form="..." on the button is honoured.
function htmxDriver(el) {
  if (el.matches(HTMX_REQUEST)) return el;
  const submits = el.type === 'submit' || el.type === 'image';
  if (submits && el.form?.matches(HTMX_REQUEST)) return el.form;
  return null;
}

// htmx asks hx-confirm itself before that request, so let it ask instead of asking twice.
// only the driver's own attribute counts, not an inherited one (hx-disinherit can switch
// that off): worst case is two prompts, never zero.
function htmxWillAsk(el) {
  const driver = htmxDriver(el);
  return !!(driver && (driver.getAttribute('hx-confirm') || driver.getAttribute('data-hx-confirm')));
}

function declined(el) {
  const message = el.getAttribute('data-confirm');
  if (!message || htmxWillAsk(el)) return false;
  return !window.confirm(message);
}

function stop(event) {
  event.preventDefault();
  event.stopImmediatePropagation();
}

document.addEventListener('click', (event) => {
  const el = event.target instanceof Element ? event.target.closest(CLICK_SELECTOR) : null;
  if (el && declined(el)) stop(event);
}, true);

document.addEventListener('submit', (event) => {
  const form = event.target;
  if (form instanceof HTMLFormElement && form.hasAttribute('data-confirm') && declined(form)) stop(event);
}, true);
