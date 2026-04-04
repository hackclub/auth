<script>
  import { onMount, onDestroy } from 'svelte';

  let dialogEl;
  let inputEl;
  let resultsContainerEl;
  let cleanup;

  let shortcuts = $state([]);
  let prefixes = $state({});
  let searchScopes = $state([]);
  let query = $state('');
  let activeScope = $state(null);
  let scopedResults = $state([]);
  let publicIdResult = $state(null);
  let activeIndex = $state(0);
  let isExiting = $state(false);

  let scopedSearchTimeout;
  let publicIdTimeout;

  const scopeShortcuts = { '?i': 'identities', '?a': 'oauth_apps' };

  $effect(() => {
    // reset active index when results change
    query;
    scopedResults;
    publicIdResult;
    activeIndex = 0;
  });

  function open() {
    query = '';
    activeScope = null;
    scopedResults = [];
    publicIdResult = null;
    isExiting = false;
    activeIndex = 0;
    dialogEl?.showModal();
    setTimeout(() => inputEl?.focus(), 10);
  }

  function close() {
    dialogEl?.close();
    query = '';
  }

  function getVisibleItems() {
    if (isExiting) return [{ label: "bye, i'll miss you!", icon: '⭠', disabled: true }];

    const items = [];

    if (activeScope) {
      if (scopedResults.length > 0) {
        scopedResults.forEach(r => items.push({ label: r.label, sublabel: r.sublabel, icon: '⭢', path: r.path }));
      } else if (query.length >= 2) {
        items.push({ label: 'No results', disabled: true });
      } else {
        items.push({ label: `Type to search ${activeScope.label}...`, disabled: true });
      }
      return items;
    }

    // Public ID match
    if (publicIdResult) {
      if (publicIdResult.notFound) {
        items.push({ label: `${publicIdResult.model} not found`, icon: '✕', disabled: true });
      } else if (publicIdResult.data) {
        items.push({ label: `Go to ${publicIdResult.model}`, sublabel: [publicIdResult.data.label, publicIdResult.data.sublabel].filter(Boolean).join(' · '), icon: '⭢', path: publicIdResult.data.path });
      } else {
        items.push({ label: `Looking up ${publicIdResult.model}...`, icon: '⭢', disabled: true });
      }
    }

    // Filtered shortcuts
    const q = query.toLowerCase();
    const filtered = q
      ? shortcuts.filter(s => s.code.toLowerCase().includes(q) || s.label.toLowerCase().includes(q))
      : shortcuts;

    if (filtered.length > 0) {
      filtered.forEach(s => items.push({ label: s.label, code: s.code, icon: s.icon, path: s.path, shortcut: s }));
    }

    // Scopes (show when no query or query >= 2)
    if (!publicIdResult) {
      const filteredScopes = q
        ? searchScopes.filter(s => s.label.toLowerCase().includes(q) || 'search'.includes(q))
        : searchScopes;
      filteredScopes.forEach(s => {
        const hint = Object.entries(scopeShortcuts).find(([, v]) => v === s.key)?.[0];
        items.push({ label: `Search ${s.label}`, hint, icon: '⌕', scope: s });
      });
    }

    return items;
  }

  function selectItem(item) {
    if (item.disabled) return;

    if (item.scope) {
      activeScope = item.scope;
      query = '';
      scopedResults = [];
      setTimeout(() => inputEl?.focus(), 0);
      return;
    }

    if (item.shortcut) {
      const s = item.shortcut;
      if (s.code === 'EXIT') {
        isExiting = true;
        setTimeout(() => { window.location.href = s.path; }, 400);
        return;
      }
      if (s.code === 'SRCH') {
        close();
        const si = document.querySelector('input[type="search"]');
        if (si) si.focus();
        return;
      }
      if (s.code === 'HELP') {
        close();
        window.openHints?.();
        return;
      }
    }

    if (item.path) {
      close();
      window.location.href = item.path;
    }
  }

  function handleInput() {
    const q = query;
    activeIndex = 0;

    // Scope shortcuts
    const scopeKey = scopeShortcuts[q.toLowerCase()];
    if (scopeKey) {
      const scope = searchScopes.find(s => s.key === scopeKey);
      if (scope) {
        activeScope = scope;
        query = '';
        scopedResults = [];
        return;
      }
    }

    // Auto-detect email/identity patterns
    if (!activeScope && (q.includes('@') || /^[UW][A-Z0-9]{8,}$/i.test(q))) {
      const identityScope = searchScopes.find(s => s.key === 'identities');
      if (identityScope) {
        activeScope = identityScope;
        return;
      }
    }

    // Scoped search
    if (activeScope && q.length >= 2) {
      doScopedSearch(q, activeScope.key);
    } else if (activeScope) {
      scopedResults = [];
    }

    // Public ID detection
    if (q.includes('!')) {
      const [prefix] = q.toLowerCase().split('!');
      const prefixData = prefixes[prefix];
      if (prefixData) {
        doPublicIdLookup(q, prefixData);
      } else {
        publicIdResult = null;
      }
    } else {
      publicIdResult = null;
      if (publicIdTimeout) clearTimeout(publicIdTimeout);
    }
  }

  function handleKeyDown(e) {
    const items = getVisibleItems();

    if (e.key === 'Escape' || (e.key === 'c' && e.ctrlKey)) {
      e.preventDefault();
      if (activeScope) {
        activeScope = null;
        query = '';
        scopedResults = [];
      } else {
        close();
      }
      return;
    }

    if (e.key === 'Backspace' && query === '' && activeScope) {
      e.preventDefault();
      activeScope = null;
      scopedResults = [];
      return;
    }

    if (e.key === 'ArrowDown' || (e.key === 'n' && e.ctrlKey)) {
      e.preventDefault();
      activeIndex = Math.min(activeIndex + 1, items.length - 1);
      scrollToActive();
      return;
    }

    if (e.key === 'ArrowUp' || (e.key === 'p' && e.ctrlKey)) {
      e.preventDefault();
      activeIndex = Math.max(activeIndex - 1, 0);
      scrollToActive();
      return;
    }

    if (e.key === 'Enter') {
      e.preventDefault();
      const item = items[activeIndex];
      if (item) selectItem(item);
    }
  }

  function scrollToActive() {
    const el = resultsContainerEl?.querySelector('.active');
    if (el) el.scrollIntoView({ block: 'nearest' });
  }

  async function doScopedSearch(q, scopeKey) {
    if (scopedSearchTimeout) clearTimeout(scopedSearchTimeout);
    scopedSearchTimeout = setTimeout(async () => {
      try {
        const res = await fetch(`/backend/kbar/search?q=${encodeURIComponent(q)}&scope=${scopeKey}`);
        if (!res.ok) throw new Error('Search failed');
        scopedResults = await res.json();
      } catch (err) {
        console.error('Scoped search failed:', err);
        scopedResults = [];
      }
    }, 150);
  }

  async function doPublicIdLookup(q, prefixData) {
    const hashPart = q.split('!')[1] || '';
    if (hashPart.length < 3) {
      publicIdResult = { model: prefixData.model, notFound: true };
      return;
    }

    publicIdResult = { model: prefixData.model, loading: true };
    if (publicIdTimeout) clearTimeout(publicIdTimeout);
    publicIdTimeout = setTimeout(async () => {
      try {
        const res = await fetch(`/backend/kbar/search?q=${encodeURIComponent(q)}`);
        if (!res.ok) return;
        const results = await res.json();
        publicIdResult = results.length > 0
          ? { model: prefixData.model, data: results[0] }
          : { model: prefixData.model, notFound: true };
      } catch (err) {
        console.error('Public ID lookup failed:', err);
        publicIdResult = { model: prefixData.model, notFound: true };
      }
    }, 100);
  }

  onMount(() => {
    const dataEl = document.getElementById('kbar-data');
    if (dataEl) {
      try {
        const data = JSON.parse(dataEl.textContent);
        shortcuts = data.shortcuts || [];
        prefixes = data.prefixes || {};
        searchScopes = data.searchScopes || [];
      } catch (err) {
        console.error('Failed to parse kbar data:', err);
      }
    }

    window.openKbar = open;
    window.closeKbar = close;

    function globalKeyDown(e) {
      if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
        e.preventDefault();
        dialogEl?.open ? close() : open();
      }
    }

    document.addEventListener('keydown', globalKeyDown);
    cleanup = () => document.removeEventListener('keydown', globalKeyDown);
  });

  onDestroy(() => cleanup?.());
</script>

<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
<dialog
  bind:this={dialogEl}
  id="command-palette"
  size-="small"
  position-="center"
  container-="fill"
  onclick={(e) => { if (e.target === dialogEl) close(); }}
  onkeydown={() => {}}
>
  <column box-="round" shear-="top" id="palette-content">
    <row align-="center between">
      <span is-="badge" variant-="background0">⌘K Go anywhere</span>
      {#if activeScope}
        <row gap-="1" align-="center">
          <span is-="badge" variant-="lavender">{activeScope.label}</span>
          <button size-="small" variant-="foreground0" onclick={() => { activeScope = null; query = ''; scopedResults = []; }}>×</button>
        </row>
      {:else}
        <button size-="small" variant-="foreground0" onclick={close}>×</button>
      {/if}
    </row>

    <row box-="round" align-="center" gap-="1">
      <span style="color: var(--overlay0);">⌕</span>
      <input
        bind:this={inputEl}
        id="palette-input"
        placeholder={activeScope ? `Search ${activeScope.label}...` : 'Search or type a shortcode...'}
        autocomplete="off"
        bind:value={query}
        oninput={handleInput}
        onkeydown={handleKeyDown}
      />
    </row>

    <div id="palette-results">
      <column id="palette-results-container" bind:this={resultsContainerEl}>
        {#each getVisibleItems() as item, i}
          <!-- svelte-ignore a11y_no_static_element_interactions -->
          <a
            class="palette-result"
            class:active={i === activeIndex}
            class:disabled={item.disabled}
            href={item.path || '#'}
            tabindex="0"
            onclick={(e) => { e.preventDefault(); selectItem(item); }}
            onmouseenter={() => { activeIndex = i; }}
          >
            <span class="palette-result-icon">{item.icon || '·'}</span>
            <span class="palette-result-text">
              {item.label}
              {#if item.sublabel}
                <span class="palette-result-sub">{item.sublabel}</span>
              {/if}
            </span>
            {#if item.code}
              <span is-="badge" variant-="background2">{item.code}</span>
            {/if}
            {#if item.hint}
              <span style="color: var(--overlay0);">{item.hint}</span>
            {/if}
          </a>
        {/each}
      </column>
    </div>

    <row gap-="1" align-="center center" pad-="1 0" style="color: var(--overlay1);">
      <span is-="badge" variant-="background2">↑</span>
      <span is-="badge" variant-="background2">↓</span>
      <span>navigate</span>
      <span style="color: var(--surface2);">·</span>
      <span is-="badge" variant-="background2">↵</span>
      <span>select</span>
      <span style="color: var(--surface2);">·</span>
      <span is-="badge" variant-="background2">esc</span>
      <span>close</span>
    </row>
  </column>
</dialog>

<style>
  #command-palette {
    position: fixed;
    z-index: 1000;

    &::backdrop {
      backdrop-filter: grayscale(100%);
      background: rgba(0, 0, 0, 0.3);
    }
  }

  #palette-content {
    position: absolute;
    inset: 0;
    display: flex;
    flex-direction: column;
    --box-border-color: var(--overlay0);
  }

  #palette-input {
    background-color: var(--background0);
  }

  #palette-results {
    flex-grow: 1;
    overflow: hidden;
    position: relative;
  }

  #palette-results-container {
    position: absolute;
    inset: 0;
    overflow-y: auto;
    padding: 0 1ch;
  }

  .palette-result {
    text-decoration: none;
    color: var(--foreground1);
    display: flex;
    align-items: center;
    padding: 0 1ch;
    gap: 1ch;

    &.active {
      background-color: var(--background1);
      color: var(--foreground0);
    }

    &.disabled {
      color: var(--overlay0);
      pointer-events: none;
    }
  }

  .palette-result-icon {
    flex-shrink: 0;
    width: 2ch;
    text-align: center;
    color: var(--overlay1);
  }

  .palette-result-text {
    flex: 1;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .palette-result-sub {
    color: var(--overlay0);
    margin-left: 1ch;
  }
</style>
