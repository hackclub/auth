// directory-picker.js — vanilla search-as-you-type picker for directory entities
// attaches to <input data-directory-picker data-scope="..." data-url="...">

const MIN_CHARS = 3;
const DEBOUNCE_MS = 200;

const STYLES = {
  dropdown: `
    position: absolute; z-index: 999; left: 0; right: 0; top: 100%;
    background: var(--background, #282828); border: 1px solid var(--foreground2, #928374);
    max-height: 240px; overflow-y: auto; margin-top: 2px;
  `,
  item: `
    padding: 4px 8px; cursor: pointer; color: var(--foreground, #ebdbb2);
    display: flex; align-items: center; gap: 8px;
  `,
  itemHover: `
    background: var(--background2, #3c3836);
  `,
  sublabel: `
    color: var(--foreground2, #928374); font-size: 0.85em;
  `,
  badge: `
    font-size: 0.75em; padding: 1px 6px; border-radius: 3px;
    background: var(--yellow, #d79921); color: var(--background, #282828);
    white-space: nowrap;
  `,
  selected: `
    display: inline-flex; align-items: center; gap: 6px;
    background: var(--background2, #3c3836); padding: 2px 8px; border-radius: 3px;
    color: var(--foreground, #ebdbb2);
  `,
  clear: `
    all: unset; cursor: pointer; color: var(--red, #fb4934); font-size: 0.85em;
  `,
  bulkContainer: `
    position: absolute; z-index: 999; left: 0; right: 0; top: 100%;
    background: var(--background, #282828); border: 1px solid var(--foreground2, #928374);
    max-height: 300px; overflow-y: auto; margin-top: 2px; padding: 6px 8px;
  `,
  bulkItem: `
    padding: 2px 0; color: var(--foreground, #ebdbb2); font-size: 0.9em;
  `,
  bulkResolving: `
    color: var(--foreground2, #928374); font-style: italic;
  `,
  bulkUnresolved: `
    color: var(--red, #fb4934);
  `,
};

class DirectoryPicker {
  constructor(input) {
    this.input = input;
    this.url = input.dataset.url || '/directory/picker/search';
    this.scope = input.dataset.scope || 'all';
    this.fieldName = input.name;
    this.debounceTimer = null;
    this.dropdown = null;
    this.selectedIndex = -1;
    this.results = [];
    this.abortController = null;

    // wrap in a relative container for dropdown positioning
    this.wrapper = document.createElement('span');
    this.wrapper.style.cssText = 'position: relative; display: inline-flex; align-items: center; flex: 1;';
    input.parentNode.insertBefore(this.wrapper, input);
    this.wrapper.appendChild(input);

    // hidden input carries the selected ID
    this.hiddenInput = document.createElement('input');
    this.hiddenInput.type = 'hidden';
    this.hiddenInput.name = this.fieldName + '_id';
    this.wrapper.appendChild(this.hiddenInput);

    this.input.addEventListener('input', () => {
      // any input method (typing, paste, drag) invalidates previous selection
      this.hiddenInput.value = '';
      this._onInput();
    });
    this.input.addEventListener('keydown', (e) => this._onKeydown(e));
    this.input.addEventListener('paste', (e) => this._onPaste(e));
    this.input.addEventListener('blur', () => {
      // delay so click on dropdown registers
      setTimeout(() => this._closeDropdown(), 150);
    });
  }

  // search on `input`, not keyup: paste, autofill and IME/mobile keyboards don't
  // reliably fire key events, and arrow/enter keys don't change the value anyway
  _onInput() {
    clearTimeout(this.debounceTimer);
    const q = this.input.value.trim();

    if (q.length < MIN_CHARS && !q.includes('@')) {
      this._closeDropdown();
      return;
    }

    this.debounceTimer = setTimeout(() => this._search(q), DEBOUNCE_MS);
  }

  _onKeydown(e) {
    if (!this.dropdown) return;

    if (e.key === 'ArrowDown') {
      e.preventDefault();
      this.selectedIndex = Math.min(this.selectedIndex + 1, this.results.length - 1);
      this._highlightItem();
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      this.selectedIndex = Math.max(this.selectedIndex - 1, 0);
      this._highlightItem();
    } else if (e.key === 'Enter' && this.selectedIndex >= 0) {
      e.preventDefault();
      this._selectResult(this.results[this.selectedIndex]);
    } else if (e.key === 'Escape') {
      this._closeDropdown();
    }
  }

  _onPaste(e) {
    const text = (e.clipboardData || window.clipboardData).getData('text');
    if (!text) return;

    if (/[,\n]/.test(text)) {
      e.preventDefault();
      const emails = text.split(/[,\n]+/).map(s => s.trim()).filter(s => s.length > 0);
      if (emails.length > 0) {
        this._resolveBulk(emails);
      }
    }
  }

  async _search(q) {
    if (this.abortController) this.abortController.abort();
    this.abortController = new AbortController();

    try {
      const url = `${this.url}?q=${encodeURIComponent(q)}&scope=${encodeURIComponent(this.scope)}`;
      const resp = await fetch(url, { signal: this.abortController.signal });
      if (!resp.ok) return;
      const data = await resp.json();
      this.results = data;
      this.selectedIndex = -1;
      this._renderDropdown();
    } catch (e) {
      if (e.name !== 'AbortError') console.error('directory-picker search error:', e);
    }
  }

  _renderDropdown() {
    // only drop the old element here — _closeDropdown() would also wipe the results we're about to render
    this._removeDropdownEl();
    this.selectedIndex = -1;
    if (this.results.length === 0) return;

    this.dropdown = document.createElement('div');
    this.dropdown.style.cssText = STYLES.dropdown;

    this.results.forEach((r, i) => {
      const item = document.createElement('div');
      item.style.cssText = STYLES.item;
      item.dataset.index = i;

      const nameSpan = document.createElement('span');
      nameSpan.textContent = r.label;
      item.appendChild(nameSpan);

      if (r.sublabel) {
        const sub = document.createElement('span');
        sub.style.cssText = STYLES.sublabel;
        sub.textContent = r.sublabel;
        item.appendChild(sub);
      }

      if (r.new_directory_person) {
        const badge = document.createElement('span');
        badge.style.cssText = STYLES.badge;
        badge.textContent = 'will be brought into the directory';
        item.appendChild(badge);
      }

      item.addEventListener('mouseenter', () => {
        this.selectedIndex = i;
        this._highlightItem();
      });
      item.addEventListener('mousedown', (e) => {
        e.preventDefault(); // keep focus on input
        this._selectResult(r);
      });

      this.dropdown.appendChild(item);
    });

    this.wrapper.appendChild(this.dropdown);
  }

  _highlightItem() {
    if (!this.dropdown) return;
    const items = this.dropdown.children;
    for (let i = 0; i < items.length; i++) {
      items[i].style.cssText = STYLES.item + (i === this.selectedIndex ? STYLES.itemHover : '');
    }
  }

  _selectResult(result) {
    this._setValue(result.sublabel || result.label);
    this.hiddenInput.value = result.id || '';
    this._closeDropdown();
  }

  // programmatic value changes don't fire `change`, and forms listen for it (people/show
  // builds its action URL from the picked slug)
  _setValue(value) {
    this.input.value = value;
    this.input.dispatchEvent(new Event('change', { bubbles: true }));
  }

  _removeDropdownEl() {
    if (this.dropdown) {
      this.dropdown.remove();
      this.dropdown = null;
    }
  }

  _closeDropdown() {
    this._removeDropdownEl();
    this.results = [];
    this.selectedIndex = -1;
  }

  async _resolveBulk(emails) {
    this._closeDropdown();
    this.input.value = '';

    const container = document.createElement('div');
    container.style.cssText = STYLES.bulkContainer;

    const items = emails.map(email => {
      const row = document.createElement('div');
      row.style.cssText = STYLES.bulkItem;
      row.innerHTML = `<span style="${STYLES.bulkResolving}">${this._esc(email)} — resolving…</span>`;
      container.appendChild(row);
      return { email, row };
    });

    this.wrapper.appendChild(container);

    const resolved = [];

    for (const item of items) {
      try {
        const url = `${this.url}?q=${encodeURIComponent(item.email)}&scope=${encodeURIComponent(this.scope)}`;
        const resp = await fetch(url);
        if (!resp.ok) throw new Error('fetch failed');
        const data = await resp.json();

        // only an exact, unambiguous match counts — the search is an unordered ILIKE,
        // so data[0] is whatever postgres felt like ("Ops" → "devops")
        const needle = item.email.toLowerCase();
        const exact = data.filter(r =>
          [r.id, r.label, r.sublabel].some(v => v && String(v).toLowerCase() === needle)
        );

        if (exact.length === 1) {
          const match = exact[0];
          let html = `<span>${this._esc(match.label)}</span> <span style="${STYLES.sublabel}">${this._esc(match.sublabel || '')}</span>`;
          if (match.new_directory_person) {
            html += ` <span style="${STYLES.badge}">new</span>`;
          }
          item.row.innerHTML = html;
          resolved.push(match);
        } else if (data.length > 0) {
          const why = exact.length > 1 ? 'ambiguous' : 'no exact match';
          item.row.innerHTML = `<span style="${STYLES.bulkUnresolved}">${this._esc(item.email)} — ${why}, ${data.length} similar</span>`;
          item.candidates = exact.length > 1 ? exact : data;
        } else {
          item.row.innerHTML = `<span style="${STYLES.bulkUnresolved}">${this._esc(item.email)} — not found</span>`;
        }
      } catch {
        item.row.innerHTML = `<span style="${STYLES.bulkUnresolved}">${this._esc(item.email)} — error</span>`;
      }
    }

    // a single pasted value with no exact match: show its candidates and let the user pick
    if (items.length === 1 && items[0].candidates) {
      container.remove();
      this.input.value = items[0].email;
      this.results = items[0].candidates;
      this._renderDropdown();
      this.input.focus();
      return;
    }

    // if the paste was exactly one value and it resolved, select it — but never quietly
    // pick one item out of a multi-line paste and drop the rest
    if (items.length === 1 && resolved.length === 1) {
      setTimeout(() => {
        container.remove();
        this._selectResult(resolved[0]);
      }, 1200);
    } else if (resolved.length > 0) {
      this._setValue(resolved.map(r => r.sublabel || r.label).join(', '));
      setTimeout(() => container.remove(), 3000);
    } else {
      setTimeout(() => container.remove(), 2000);
    }
  }

  _esc(str) {
    const d = document.createElement('div');
    d.textContent = str;
    return d.innerHTML;
  }
}

document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('[data-directory-picker]').forEach(input => {
    new DirectoryPicker(input);
  });
});
