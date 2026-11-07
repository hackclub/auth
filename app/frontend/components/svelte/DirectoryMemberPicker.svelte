<script>
  import { onMount, onDestroy } from 'svelte';

  let { searchUrl = '/directory/picker/search', placeholder = 'email or ident!…', name = 'identifiers' } = $props();

  let selected = $state([]);
  let query = $state('');
  let results = $state([]);
  let selectedIndex = $state(0);
  let isOpen = $state(false);
  let isLoading = $state(false);

  let searchTimeout;
  let wrapperEl;
  let inputEl;
  let cleanup;

  function isPublicId(q) { return q.startsWith('ident!') && q.length > 6; }
  function isEmail(q) { return q.includes('@') && q.includes('.'); }

  // Accept raw input as a chip (ident! or unresolved email)
  function commitRawInput() {
    const q = query.trim();
    if (!q) return false;

    if (isPublicId(q) || isEmail(q)) {
      const alreadySelected = selected.some(s => s.value === q);
      if (!alreadySelected) {
        selected = [...selected, { value: q, label: q, sublabel: null, resolved: isEmail(q) ? 'pending' : 'ident' }];
      }
      query = '';
      results = [];
      isOpen = false;
      if (inputEl) inputEl.value = '';
      // Try to resolve emails in the background
      if (isEmail(q)) resolveChip(q);
      return true;
    }
    return false;
  }

  async function resolveChip(value) {
    try {
      const res = await fetch(`${searchUrl}?q=${encodeURIComponent(value)}&scope=people`);
      if (!res.ok) return;
      const data = await res.json();
      const match = data.find(r => r.sublabel?.toLowerCase() === value.toLowerCase()) || data[0];
      if (match) {
        selected = selected.map(s =>
          s.value === value ? { ...s, label: match.label, sublabel: match.sublabel, resolved: 'found', new: !!match.new_directory_person } : s
        );
      } else {
        selected = selected.map(s =>
          s.value === value ? { ...s, resolved: 'not-found' } : s
        );
      }
    } catch {
      // leave as pending
    }
  }

  function selectItem(item) {
    const value = item.sublabel || item.label;
    const alreadySelected = selected.some(s => s.value === value);
    if (!alreadySelected) {
      selected = [...selected, { value, label: item.label, sublabel: item.sublabel, resolved: 'found', new: !!item.new_directory_person }];
    }
    query = '';
    results = [];
    isOpen = false;
    if (inputEl) inputEl.value = '';
    setTimeout(() => inputEl?.focus(), 0);
  }

  function removeItem(item) {
    selected = selected.filter(s => s.value !== item.value);
  }

  function doSearch(q) {
    if (searchTimeout) clearTimeout(searchTimeout);
    // Don't search for ident! in the picker (privacy: bypasses autocomplete)
    if (isPublicId(q)) { results = []; isLoading = false; return; }
    if (q.length < 3 && !q.includes('@')) { results = []; isLoading = false; return; }
    isLoading = true;
    searchTimeout = setTimeout(async () => {
      try {
        const res = await fetch(`${searchUrl}?q=${encodeURIComponent(q)}&scope=people`);
        if (!res.ok) throw new Error('Search failed');
        const data = await res.json();
        const excludeValues = new Set(selected.map(s => s.value));
        results = data.filter(r => !excludeValues.has(r.sublabel || r.label));
        selectedIndex = 0;
      } catch (err) {
        console.error('Directory picker search failed:', err);
        results = [];
      } finally {
        isLoading = false;
      }
    }, 150);
  }

  function handleInput(e) {
    query = e.target.value;
    selectedIndex = 0;
    isOpen = true;
    doSearch(query);
  }

  function handleFocus() {
    isOpen = true;
    if (query.length >= 3) doSearch(query);
  }

  function handleBlur() {
    setTimeout(() => {
      if (!wrapperEl?.contains(document.activeElement)) {
        commitRawInput();
        isOpen = false;
      }
    }, 150);
  }

  function handleKeyDown(e) {
    if (e.key === 'Escape') { e.preventDefault(); isOpen = false; inputEl?.blur(); }
    else if (e.key === 'ArrowDown' && isOpen) { e.preventDefault(); selectedIndex = Math.min(selectedIndex + 1, results.length - 1); }
    else if (e.key === 'ArrowUp' && isOpen) { e.preventDefault(); selectedIndex = Math.max(selectedIndex - 1, 0); }
    else if (e.key === 'Enter') {
      e.preventDefault();
      if (isOpen && results.length > 0 && selectedIndex >= 0) {
        selectItem(results[selectedIndex]);
      } else {
        commitRawInput();
      }
    }
    else if (e.key === 'Backspace' && query === '' && selected.length > 0) {
      selected = selected.slice(0, -1);
    }
    else if (e.key === ',' || e.key === 'Tab') {
      if (query.trim()) {
        e.preventDefault();
        commitRawInput();
      }
    }
  }

  function handlePaste(e) {
    const text = (e.clipboardData || window.clipboardData)?.getData('text');
    if (!text) return;
    // Detect bulk paste: contains commas or newlines
    if (/[,\n]/.test(text)) {
      e.preventDefault();
      const items = text.split(/[,\n]+/).map(s => s.trim()).filter(s => s.length > 0);
      for (const item of items) {
        const alreadySelected = selected.some(s => s.value === item);
        if (!alreadySelected) {
          if (isPublicId(item)) {
            selected = [...selected, { value: item, label: item, sublabel: null, resolved: 'ident' }];
          } else {
            selected = [...selected, { value: item, label: item, sublabel: null, resolved: 'pending' }];
            resolveChip(item);
          }
        }
      }
      query = '';
      if (inputEl) inputEl.value = '';
    }
  }

  onMount(() => {
    function handleClickOutside(e) {
      if (!wrapperEl?.contains(e.target)) { commitRawInput(); isOpen = false; }
    }
    document.addEventListener('click', handleClickOutside);
    cleanup = () => document.removeEventListener('click', handleClickOutside);
  });

  onDestroy(() => cleanup?.());
</script>

<div class="picker-container picker-multiple" bind:this={wrapperEl}>
  {#each selected as item}
    <input type="hidden" name="{name}[]" value={item.value} />
  {/each}

  <div class="picker-multiple-list">
    {#each selected as item}
      <div class="picker-multiple-item" class:picker-chip-new={item.new} class:picker-chip-notfound={item.resolved === 'not-found'} class:picker-chip-ident={item.resolved === 'ident'}>
        <div class="picker-multiple-text">
          <span class="picker-multiple-label">{item.label}</span>
          {#if item.sublabel && item.sublabel !== item.label}
            <span class="picker-multiple-sublabel">{item.sublabel}</span>
          {/if}
          {#if item.new}
            <span class="picker-chip-badge">new</span>
          {/if}
          {#if item.resolved === 'ident'}
            <span class="picker-chip-badge">id</span>
          {/if}
        </div>
        <button type="button" class="picker-multiple-remove" onclick={() => removeItem(item)}>✕</button>
      </div>
    {/each}

    <div class="picker-search">
      <div class="picker-search-wrapper">
        <input
          type="text"
          class="picker-search-input"
          {placeholder}
          autocomplete="off"
          bind:this={inputEl}
          oninput={handleInput}
          onfocus={handleFocus}
          onblur={handleBlur}
          onkeydown={handleKeyDown}
          onpaste={handlePaste}
        />
      </div>

      {#if isOpen}
        <div class="picker-dropdown">
          {#if isLoading}
            <div class="picker-status">searching…</div>
          {:else if results.length > 0}
            <div class="picker-results-list">
              {#each results as result, idx}
                <!-- svelte-ignore a11y_no_static_element_interactions -->
                <div
                  class="picker-result-item"
                  class:selected={idx === selectedIndex}
                  onclick={() => selectItem(result)}
                  onmouseenter={() => { selectedIndex = idx; }}
                >
                  <div class="picker-result-icon">+</div>
                  <div class="picker-result-text">
                    <span class="picker-result-label">{result.label}</span>
                    {#if result.sublabel}<span class="picker-result-sublabel">{result.sublabel}</span>{/if}
                  </div>
                  {#if result.new_directory_person}
                    <span class="picker-chip-badge">new to directory</span>
                  {/if}
                </div>
              {/each}
            </div>
          {:else if query.length >= 3}
            <div class="picker-status">no results — press Enter to add as-is</div>
          {:else if isPublicId(query)}
            <div class="picker-status">press Enter to add this ident</div>
          {/if}
        </div>
      {/if}
    </div>
  </div>

  {#if selected.length > 0}
    <div class="picker-submit-hint">
      {selected.length} {selected.length === 1 ? 'person' : 'people'} selected
    </div>
  {/if}
</div>

<style>
  .picker-container { position: relative; }

  .picker-multiple-list {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
    align-items: center;
  }

  .picker-multiple-item {
    display: inline-flex;
    align-items: center;
    gap: 4px;
    padding: 2px 8px;
    border: 1px solid var(--background2, #3c3836);
    border-radius: 3px;
    background: var(--background1, #282828);
    font-size: 0.9em;
  }

  .picker-multiple-text {
    display: flex;
    align-items: baseline;
    gap: 6px;
  }

  .picker-multiple-label { color: var(--foreground0, #ebdbb2); }
  .picker-multiple-sublabel { color: var(--foreground2, #928374); font-size: 0.85em; }

  .picker-multiple-remove {
    background: none;
    border: none;
    color: var(--foreground2, #928374);
    cursor: pointer;
    padding: 0 2px;
    font-size: 0.8em;
    line-height: 1;
  }
  .picker-multiple-remove:hover { color: var(--red, #fb4934); }

  .picker-search { position: relative; }

  .picker-search-input {
    width: 100%;
    background: var(--background1, #282828);
    color: var(--foreground0, #ebdbb2);
    border: 1px solid var(--background2, #3c3836);
    padding: 6px 8px;
    font-family: inherit;
    font-size: inherit;
    outline: none;
  }
  .picker-search-input:focus { border-color: var(--foreground2, #928374); }

  .picker-dropdown {
    position: absolute;
    top: 100%;
    left: 0;
    right: 0;
    z-index: 100;
    background: var(--background1, #282828);
    border: 1px solid var(--background2, #3c3836);
    border-top: none;
    max-height: 240px;
    overflow-y: auto;
  }

  .picker-result-item {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 10px;
    cursor: pointer;
    color: var(--foreground0, #ebdbb2);
  }
  .picker-result-item:hover, .picker-result-item.selected {
    background: var(--background2, #3c3836);
  }

  .picker-result-icon {
    color: var(--foreground2, #928374);
    font-size: 0.85em;
    flex-shrink: 0;
  }

  .picker-result-text {
    display: flex;
    flex-direction: column;
    gap: 1px;
    min-width: 0;
  }

  .picker-result-label { font-size: 0.9em; }
  .picker-result-sublabel { font-size: 0.8em; color: var(--foreground2, #928374); }

  .picker-status {
    padding: 8px 10px;
    color: var(--foreground2, #928374);
    font-size: 0.85em;
    font-style: italic;
  }

  .picker-chip-badge {
    font-size: 0.75em;
    padding: 0 4px;
    border-radius: 3px;
    background: var(--background2, #3c3836);
    color: var(--foreground2, #928374);
  }
  .picker-chip-notfound {
    opacity: 0.6;
    text-decoration: line-through;
  }
  .picker-chip-ident :global(.picker-multiple-label) {
    font-family: monospace;
    font-size: 0.9em;
  }
  .picker-submit-hint {
    font-size: 0.85em;
    color: var(--foreground2, #928374);
    padding: 4px 0;
  }
</style>
