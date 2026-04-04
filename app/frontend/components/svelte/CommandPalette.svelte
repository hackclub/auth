<script>
  import { onMount, onDestroy } from 'svelte';
  import 'ninja-keys';

  let ninjaEl;
  let shortcuts = [];
  let prefixes = {};
  let searchScopes = [];
  let activeScope = null;
  let isExiting = false;
  let publicIdTimeout;
  let scopedSearchTimeout;

  const scopeShortcuts = { '?i': 'identities', '?a': 'oauth_apps' };

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

    buildActions();

    window.openKbar = () => ninjaEl?.open();
    window.closeKbar = () => ninjaEl?.close();

    ninjaEl?.addEventListener('change', handleChange);
    ninjaEl?.addEventListener('selected', handleSelected);
  });

  onDestroy(() => {
    ninjaEl?.removeEventListener('change', handleChange);
    ninjaEl?.removeEventListener('selected', handleSelected);
  });

  function buildActions() {
    if (!ninjaEl) return;
    const actions = [];

    // Shortcut actions
    shortcuts.forEach(s => {
      actions.push({
        id: `shortcode-${s.code}`,
        title: s.label,
        icon: `<span style="font-size:1.2em">${s.icon}</span>`,
        section: 'Shortcuts',
        keywords: s.code,
        handler: () => {
          if (s.code === 'EXIT') {
            return handleExit(s.path);
          }
          navigate(s.path);
        }
      });
    });

    // Scope actions
    searchScopes.forEach(scope => {
      const hint = Object.entries(scopeShortcuts).find(([, v]) => v === scope.key)?.[0];
      actions.push({
        id: `scope-${scope.key}`,
        title: `Search ${scope.label}`,
        icon: '<span style="font-size:1.2em">⌕</span>',
        section: 'Search',
        keywords: hint || '',
        handler: () => {
          activeScope = scope;
          ninjaEl.open({ parent: `scope-${scope.key}` });
          return { keepOpen: true };
        },
        children: [`scope-${scope.key}-placeholder`]
      });

      // Placeholder child that gets replaced by search results
      actions.push({
        id: `scope-${scope.key}-placeholder`,
        title: `Type to search ${scope.label}...`,
        parent: `scope-${scope.key}`,
      });
    });

    ninjaEl.data = actions;
  }

  function handleChange(e) {
    const { search } = e.detail;

    // Detect scope shortcuts (?i, ?a)
    const scopeKey = scopeShortcuts[search.toLowerCase()];
    if (scopeKey) {
      const scope = searchScopes.find(s => s.key === scopeKey);
      if (scope) {
        activeScope = scope;
        ninjaEl.open({ parent: `scope-${scope.key}` });
        // Clear the search
        const input = ninjaEl.shadowRoot?.querySelector('input');
        if (input) { input.value = ''; input.dispatchEvent(new Event('input')); }
        return;
      }
    }

    // Auto-detect email or identity ID patterns → enter identities scope
    if (!activeScope && (search.includes('@') || /^[UW][A-Z0-9]{8,}$/i.test(search))) {
      const identityScope = searchScopes.find(s => s.key === 'identities');
      if (identityScope) {
        activeScope = identityScope;
        ninjaEl.open({ parent: `scope-${identityScope.key}` });
        return;
      }
    }

    // If in a scope, do scoped search
    if (activeScope && search.length >= 2) {
      doScopedSearch(search, activeScope.key);
    }

    // Public ID detection
    if (search.includes('!')) {
      const [prefix] = search.toLowerCase().split('!');
      const prefixData = prefixes[prefix];
      if (prefixData) {
        doPublicIdLookup(search, prefix, prefixData);
      }
    }
  }

  function handleSelected(e) {
    const { search, action } = e.detail;

    // If no action selected and search has content, could be a custom query
    if (!action && search) {
      // Check for public ID
      if (search.includes('!')) {
        const [prefix] = search.toLowerCase().split('!');
        const prefixData = prefixes[prefix];
        if (prefixData) {
          navigate(`${prefixData.path}/${search}`);
        }
      }
    }
  }

  async function doScopedSearch(query, scopeKey) {
    if (scopedSearchTimeout) clearTimeout(scopedSearchTimeout);
    scopedSearchTimeout = setTimeout(async () => {
      try {
        const res = await fetch(`/backend/kbar/search?q=${encodeURIComponent(query)}&scope=${scopeKey}`);
        if (!res.ok) throw new Error('Search failed');
        const results = await res.json();
        injectScopeResults(scopeKey, results);
      } catch (err) {
        console.error('Scoped search failed:', err);
      }
    }, 150);
  }

  function injectScopeResults(scopeKey, results) {
    const parentId = `scope-${scopeKey}`;
    // Remove old dynamic results
    const baseActions = ninjaEl.data.filter(a => !a.id.startsWith(`${parentId}-result-`));

    // Remove placeholder
    const withoutPlaceholder = baseActions.filter(a => a.id !== `${parentId}-placeholder`);

    // Add results
    const resultActions = results.map((r, i) => ({
      id: `${parentId}-result-${i}`,
      title: r.label,
      icon: '<span style="font-size:1.2em">⭢</span>',
      parent: parentId,
      keywords: r.sublabel || '',
      handler: () => navigate(r.path)
    }));

    if (resultActions.length === 0) {
      resultActions.push({
        id: `${parentId}-result-empty`,
        title: 'No results',
        parent: parentId,
      });
    }

    // Update parent's children
    const parentAction = withoutPlaceholder.find(a => a.id === parentId);
    if (parentAction) {
      parentAction.children = resultActions.map(a => a.id);
    }

    ninjaEl.data = [...withoutPlaceholder, ...resultActions];
  }

  async function doPublicIdLookup(query, prefix, prefixData) {
    const hashPart = query.split('!')[1] || '';
    if (hashPart.length < 3) return;

    if (publicIdTimeout) clearTimeout(publicIdTimeout);
    publicIdTimeout = setTimeout(async () => {
      try {
        const res = await fetch(`/backend/kbar/search?q=${encodeURIComponent(query)}`);
        if (!res.ok) return;
        const results = await res.json();

        // Remove old public ID results
        const baseActions = ninjaEl.data.filter(a => !a.id.startsWith('publicid-'));

        if (results.length > 0) {
          const r = results[0];
          baseActions.unshift({
            id: 'publicid-result',
            title: `Go to ${prefixData.model}`,
            icon: '<span style="font-size:1.2em">⭢</span>',
            section: 'Lookup',
            keywords: [r.label, r.sublabel].filter(Boolean).join(' '),
            handler: () => navigate(r.path)
          });
        } else {
          baseActions.unshift({
            id: 'publicid-notfound',
            title: `${prefixData.model} not found`,
            icon: '<span style="font-size:1.2em">✕</span>',
            section: 'Lookup',
          });
        }

        ninjaEl.data = baseActions;
      } catch (err) {
        console.error('Public ID lookup failed:', err);
      }
    }, 100);
  }

  function handleExit(path) {
    isExiting = true;
    // Show goodbye message briefly
    const actions = [{
      id: 'exit-goodbye',
      title: "bye, i'll miss you!",
      icon: '<span style="font-size:1.2em">⭠</span>',
      section: '',
    }];
    ninjaEl.data = actions;
    setTimeout(() => { window.location.href = path; }, 400);
    return { keepOpen: true };
  }

  function navigate(path) {
    ninjaEl?.close();
    window.location.href = path;
  }
</script>

<ninja-keys
  bind:this={ninjaEl}
  placeholder="Search or type a shortcode..."
  noAutoLoadMdIcons
  hideBreadcrumbs
></ninja-keys>

<style>
  ninja-keys {
    --ninja-width: 72ch;
    --ninja-font-size: 1rem;
    --ninja-text-color: var(--text, #cdd6f4);
    --ninja-modal-background: var(--base, #1e1e2e);
    --ninja-modal-shadow: 0 4px 30px rgba(0, 0, 0, 0.4);
    --ninja-selected-background: var(--surface0, #313244);
    --ninja-accent-color: var(--lavender, #b4befe);
    --ninja-secondary-background-color: var(--surface0, #313244);
    --ninja-secondary-text-color: var(--overlay1, #7f849c);
    --ninja-overflow-background: rgba(0, 0, 0, 0.5);
    --ninja-separate-border: 1px solid var(--surface1, #45475a);
    --ninja-key-border-radius: 0;
    --ninja-icon-color: var(--overlay1, #7f849c);
    --ninja-group-text-color: var(--overlay0, #6c7086);
    --ninja-footer-background: var(--mantle, #181825);
    --ninja-placeholder-color: var(--overlay0, #6c7086);
    --ninja-top: 15vh;
    --ninja-z-index: 1000;
    --ninja-actions-height: 350px;
    font-family: monospace;
  }
</style>
