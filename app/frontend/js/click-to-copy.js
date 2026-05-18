export function setup_copy() {
  document.querySelectorAll('[data-copy-to-clipboard]:not([data-copy-setup])').forEach(el => {
    el.setAttribute('data-copy-setup', 'true');
    el.addEventListener('click', async (e) => {
      const textToCopy = e.currentTarget.getAttribute('data-copy-to-clipboard');
      try {
        await navigator.clipboard.writeText(textToCopy);
        if (e.currentTarget.hasAttribute('aria-label')) {
          const prev = e.currentTarget.getAttribute('aria-label');
          e.currentTarget.setAttribute('aria-label', 'copied!');
          setTimeout(() => e.currentTarget.setAttribute('aria-label', prev), 1000);
        }
      } catch (err) {
        console.error('Failed to copy text: ', err);
      }
    });
  });
}

document.body.addEventListener('htmx:load', () => setup_copy());
