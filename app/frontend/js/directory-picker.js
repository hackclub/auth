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

    this.input.addEventListener('keyup', (e) => this._onKeyup(e));
    this.input.addEventListener('keydown', (e) => this._onKeydown(e));
    this.input.addEventListener('paste', (e) => this._onPaste(e));
    this.input.addEventListener('blur', () => {
      // delay so click on dropdown registers
      setTimeout(() => this._closeDropdown(), 150);
    });
  }

  _onKeyup(e) {
    // ignore nav keys handled in keydown
    if (['ArrowDown', 'ArrowUp', 'Enter', 'Escape'].includes(e.key)) return;

    // user is typing — invalidate any previous picker selection so a stale
    // hidden-input value can't silently win over what they're actually typing
    this.hiddenInput.value = '';

    clearTimeout(this.debounceTimer);
    const q = this.input.value.trim();

    if (q.length < MIN_CHARS) {
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

    // detect bulk paste: contains commas or newlines
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
    this._closeDropdown();
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
    this.input.value = result.sublabel || result.label;
    this.hiddenInput.value = result.id || '';
    this._closeDropdown();
  }

  _closeDropdown() {
    if (this.dropdown) {
      this.dropdown.remove();
      this.dropdown = null;
    }
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

        // find exact or best match
        const match = data.find(r =>
          r.sublabel && r.sublabel.toLowerCase() === item.email.toLowerCase()
        ) || data[0];

        if (match) {
          let html = `<span>${this._esc(match.label)}</span> <span style="${STYLES.sublabel}">${this._esc(match.sublabel || '')}</span>`;
          if (match.new_directory_person) {
            html += ` <span style="${STYLES.badge}">new</span>`;
          }
          item.row.innerHTML = html;
          resolved.push(match);
        } else {
          item.row.innerHTML = `<span style="${STYLES.bulkUnresolved}">${this._esc(item.email)} — not found</span>`;
        }
      } catch {
        item.row.innerHTML = `<span style="${STYLES.bulkUnresolved}">${this._esc(item.email)} — error</span>`;
      }
    }

    // if exactly one resolved, select it immediately
    if (resolved.length === 1) {
      setTimeout(() => {
        container.remove();
        this._selectResult(resolved[0]);
      }, 1200);
    } else if (resolved.length > 1) {
      // for multi-results, let user pick or submit the first email
      // set input to comma-separated emails for the form
      this.input.value = resolved.map(r => r.sublabel || r.label).join(', ');
      // auto-close after a moment
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
