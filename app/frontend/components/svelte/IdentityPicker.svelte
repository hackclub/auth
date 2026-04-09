<script>
  import { onMount, onDestroy } from 'svelte';

  let { name = 'identity_id', multiple = false, required = false, placeholder = '', selected: initialSelected = null } = $props();

  if (!placeholder) placeholder = multiple ? 'Search to add...' : 'Search identities...';

  let selectedSingle = $state(multiple ? null : initialSelected);
  let selectedMultiple = $state(multiple ? (initialSelected || []) : []);
  let query = $state('');
  let results = $state([]);
  let selectedIndex = $state(0);
  let isOpen = $state(false);
  let isLoading = $state(false);

  let searchTimeout;
  let wrapperEl;
  let inputEl;
  let cleanup;

  function isPublicId(q) { return q.toLowerCase().startsWith('ident!'); }

  function doSearch(q) {
    if (searchTimeout) clearTimeout(searchTimeout);
    const minLen = isPublicId(q) ? 9 : 2;
    if (q.length < minLen) { results = []; isLoading = false; return; }
    isLoading = true;
    searchTimeout = setTimeout(async () => {
      try {
        const res = await fetch(`/backend/identity_picker/search?q=${encodeURIComponent(q)}`);
        if (!res.ok) throw new Error('Search failed');
        const data = await res.json();
        const excludeIds = new Set(selectedMultiple.map(s => s.id));
        results = data.filter(r => !excludeIds.has(r.id));
        selectedIndex = 0;
      } catch (err) {
        console.error('Identity search failed:', err);
        results = [];
      } finally {
        isLoading = false;
      }
    }, isPublicId(q) ? 100 : 150);
  }

  function selectItem(item) {
    if (multiple) {
      selectedMultiple = [...selectedMultiple, item];
    } else {
      selectedSingle = item;
    }
    query = '';
    results = [];
    isOpen = false;
    if (inputEl) inputEl.value = '';
    setTimeout(() => inputEl?.focus(), 0);
  }

  function removeItem(item) {
    selectedMultiple = selectedMultiple.filter(s => s.id !== item.id);
  }

  function clearSelection() {
    selectedSingle = null;
  }

  function handleInput(e) {
    query = e.target.value;
    selectedIndex = 0;
    isOpen = true;
    doSearch(query);
  }

  function handleFocus() {
    isOpen = true;
    if (query.length >= 2) doSearch(query);
  }

  function handleBlur() {
    setTimeout(() => {
      if (!wrapperEl?.contains(document.activeElement)) isOpen = false;
    }, 150);
  }

  function handleKeyDown(e) {
    if (e.key === 'Escape') { e.preventDefault(); isOpen = false; inputEl?.blur(); }
    else if (e.key === 'ArrowDown') { e.preventDefault(); selectedIndex = Math.min(selectedIndex + 1, results.length - 1); }
    else if (e.key === 'ArrowUp') { e.preventDefault(); selectedIndex = Math.max(selectedIndex - 1, 0); }
    else if (e.key === 'Enter') { e.preventDefault(); const item = results[selectedIndex]; if (item) selectItem(item); }
  }

  onMount(() => {
    function handleClickOutside(e) {
      if (!wrapperEl?.contains(e.target)) isOpen = false;
    }
    document.addEventListener('click', handleClickOutside);
    cleanup = () => document.removeEventListener('click', handleClickOutside);
  });

  onDestroy(() => cleanup?.());
</script>

<div class="picker-container" class:picker-single={!multiple} class:picker-multiple={multiple}>
  <!-- Hidden inputs -->
  {#if multiple}
    {#each selectedMultiple as item}
      <input type="hidden" name="{name}[]" value={item.id} />
    {/each}
    {#if required && selectedMultiple.length === 0}
      <input type="hidden" name="__picker_required" required />
    {/if}
  {:else}
    {#if selectedSingle}
      <input type="hidden" {name} value={selectedSingle.id} />
    {:else if required}
      <input type="hidden" name="__picker_required" required />
    {/if}
  {/if}

  <!-- Multiple: selected items -->
  {#if multiple}
    <div class="picker-multiple-list">
      {#each selectedMultiple as item}
        <div class="picker-multiple-item">
          <div class="picker-multiple-text">
            <span class="picker-multiple-label">{item.label}</span>
            {#if item.sublabel}<span class="picker-multiple-sublabel">{item.sublabel}</span>{/if}
          </div>
          <button type="button" class="picker-multiple-remove" onclick={() => removeItem(item)}>-</button>
        </div>
      {/each}
    </div>
  {/if}

  <!-- Single: selected display -->
  {#if !multiple && selectedSingle}
    <div class="picker-single-selected">
      <div class="picker-single-text">
        <span class="picker-single-label">{selectedSingle.label}</span>
        {#if selectedSingle.sublabel}<span class="picker-single-sublabel">{selectedSingle.sublabel}</span>{/if}
      </div>
      <button type="button" class="picker-single-clear" onclick={clearSelection}>✕</button>
    </div>
  {:else}
    <!-- Search input -->
    <div class="picker-search" bind:this={wrapperEl}>
      <div class="picker-search-wrapper">
        <div class="picker-search-icon">{multiple ? '+' : '⌕'}</div>
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
        />
      </div>

      {#if isOpen}
        <div class="picker-dropdown">
          {#if isLoading}
            <div class="picker-status">Loading...</div>
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
                  <div class="picker-result-icon">{multiple ? '+' : '⭢'}</div>
                  <div class="picker-result-text">
                    <span class="picker-result-label">{result.label}</span>
                    {#if result.sublabel}<span class="picker-result-sublabel">{result.sublabel}</span>{/if}
                  </div>
                </div>
              {/each}
            </div>
          {:else if query.length >= 2}
            <div class="picker-status">No results found</div>
          {:else if query.length > 0}
            <div class="picker-status">Type at least 2 characters...</div>
          {/if}
        </div>
      {/if}
    </div>
  {/if}
</div>
