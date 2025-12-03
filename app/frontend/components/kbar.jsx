// this is monstrous i'm so sorry
import { ResultItem } from "./kbar/result_item.jsx";
import { ScopeItem } from "./kbar/scope_item.jsx";

const scopeShortcuts = { "?i": "identities", "?a": "oauth_apps" }
const scopeShortcutHints = { "identities": "?i", "oauth_apps": "?a" }

const ScopedResults = function(cx) {
  const renderItem = (r, idx) => (
    <ResultItem
      path={r.path}
      selected={use(this.selectedIndex).map(s => s === idx)}
      icon="⭢"
      label={r.label}
      sublabel={r.sublabel}
      onSelect={() => this.onNavigate?.(r.path)}
      onHover={() => { this.selectedIndex = idx }}
    />
  )

  return (
    <div class="kbar-results-list">
      {use(this.results, this.query, this.scopeLabel).map(([results, query, label]) => {
        if (results.length > 0) {
          return results.map((r, idx) => renderItem(r, idx))
        } else if (query.length >= 2) {
          return <div class="kbar-section-label">No results</div>
        } else {
          return <div class="kbar-section-label">Type to search {label}...</div>
        }
      })}
    </div>
  )
}

const MainResults = function(cx) {
  return (
    <div class="kbar-results-list">
      {use(this.publicIdMatch, this.publicIdLookup, this.query).map(([match, lookup, query]) => {
        if (!match) return null
        const isNotFound = lookup?.query === query && lookup?.notFound
        const isLoading = lookup?.query === query && lookup?.loading
        const fetchedData = lookup?.query === query ? lookup?.data : null
        const targetPath = fetchedData?.path || match.path
        const sublabel = isNotFound ? match.fullId 
          : fetchedData ? [fetchedData.label, fetchedData.sublabel].filter(Boolean).join(' · ')
          : isLoading ? 'loading...' : match.fullId

        return (
          <ResultItem
            path={targetPath}
            selected={use(this.selectedIndex).map(s => s === 0)}
            disabled={isNotFound}
            icon={isNotFound ? '✕' : '⭢'}
            label={isNotFound ? `${match.model} not found` : `Go to ${match.model}`}
            sublabel={sublabel}
            onSelect={() => !isNotFound && this.onNavigate?.(targetPath)}
            onHover={() => { this.selectedIndex = 0 }}
          />
        )
      })}

      {use(this.filteredShortcuts).map(shortcuts => shortcuts.length > 0 ? (
        <div class="kbar-section">
          <div class="kbar-section-label">Shortcuts</div>
          {use(this.filteredShortcuts, this.publicIdMatch).map(([shortcuts, hasPublicId]) => 
            shortcuts.map((s, i) => {
              const idx = hasPublicId ? i + 1 : i
              return (
                <ResultItem
                  path={s.path}
                  selected={use(this.selectedIndex).map(sel => sel === idx)}
                  icon={s.icon}
                  label={s.label}
                  shortcode={s.code}
                  onSelect={() => this.onNavigateShortcut?.(s.path, s)}
                  onHover={() => { this.selectedIndex = idx }}
                />
              )
            })
          )}
        </div>
      ) : null)}

      {use(this.filteredScopes).map(scopes => scopes.length > 0 ? (
        <div class="kbar-section">
          <div class="kbar-section-label">Search</div>
          {use(this.filteredScopes, this.filteredShortcuts, this.publicIdMatch).map(([scopes, shortcuts, hasPublicId]) => {
            const offset = (hasPublicId ? 1 : 0) + shortcuts.length
            return scopes.map((scope, i) => {
              const idx = offset + i
              return (
                <ScopeItem
                  label={scope.label}
                  hint={scopeShortcutHints[scope.key]}
                  queryHint={use(this.query).map(q => q.length >= 2 ? q : null)}
                  selected={use(this.selectedIndex).map(sel => sel === idx)}
                  onSelect={() => this.onEnterScope?.(scope)}
                  onHover={() => { this.selectedIndex = idx }}
                />
              )
            })
          })}
        </div>
      ) : null)}
    </div>
  )
}

const Kbar = function(cx) {
  this.isOpen = false
  this.query = ""
  this.shortcuts = []
  this.prefixes = {}
  this.searchScopes = []
  this.searchResults = []
  this.selectedIndex = 0
  this.publicIdLookup = null
  this.activeScope = null
  this.isExiting = false

  let searchTimeout = null
  let publicIdTimeout = null
  const state = this
  let inputEl = null

  const getPublicIdMatch = () => {
    const q = state.query.toLowerCase()
    if (!q.includes("!")) return null
    const [prefix] = q.split("!")
    const prefixData = state.prefixes[prefix]
    if (!prefixData) return null
    return {
      prefix,
      model: prefixData.model,
      path: `${prefixData.path}/${state.query}`,
      fullId: state.query
    }
  }

  const fetchPublicIdDetails = (query) => {
    if (publicIdTimeout) clearTimeout(publicIdTimeout)
    const hashPart = query.split("!")[1] || ""
    if (hashPart.length < 3) {
      state.publicIdLookup = { query, loading: false, data: null, notFound: true }
      return
    }
    state.publicIdLookup = { query, loading: true, data: null, notFound: false }
    publicIdTimeout = setTimeout(async () => {
      try {
        const res = await fetch(`/backend/kbar/search?q=${encodeURIComponent(query)}`)
        if (!res.ok || !res.headers.get("content-type")?.includes("application/json")) throw new Error("Non-JSON response")
        const results = await res.json()
        if (state.publicIdLookup?.query !== query) return
        state.publicIdLookup = results.length > 0 
          ? { query, loading: false, data: results[0], notFound: false }
          : { query, loading: false, data: null, notFound: true }
      } catch (err) {
        console.error("Public ID lookup failed:", err)
        if (state.publicIdLookup?.query === query) {
          state.publicIdLookup = { query, loading: false, data: null, notFound: true }
        }
      }
    }, 100)
  }

  const openModal = () => {
    state.isOpen = true
    state.query = ""
    state.searchResults = []
    state.selectedIndex = 0
    state.publicIdLookup = null
    state.activeScope = null
    setTimeout(() => inputEl?.focus(), 10)
  }

  const closeModal = () => {
    state.isOpen = false
    state.query = ""
    state.searchResults = []
  }

  const exitScope = () => {
    state.activeScope = null
    state.query = ""
    state.searchResults = []
    state.selectedIndex = 0
    setTimeout(() => inputEl?.focus(), 0)
  }

  const enterScope = (scope) => {
    const previousQuery = state.query
    state.activeScope = scope
    state.searchResults = []
    state.selectedIndex = 0
    if (previousQuery.length >= 2) doScopedSearch(previousQuery, scope.key)
  }

  const doScopedSearch = (query, scopeKey) => {
    if (searchTimeout) clearTimeout(searchTimeout)
    searchTimeout = setTimeout(async () => {
      try {
        const res = await fetch(`/backend/kbar/search?q=${encodeURIComponent(query)}&scope=${scopeKey}`)
        if (!res.ok) throw new Error("Search failed")
        state.searchResults = await res.json()
      } catch (err) {
        console.error("Scoped search failed:", err)
        state.searchResults = []
      }
    }, 150)
  }

  const navigate = (path, shortcode = null) => {
    if (shortcode?.code === "EXIT") {
      state.isExiting = true
      setTimeout(() => { window.location.href = path }, 200)
    } else {
      closeModal()
      window.location.href = path
    }
  }

  const getFilteredShortcuts = () => {
    if (!state.query) return state.shortcuts
    const q = state.query.toLowerCase()
    return state.shortcuts.filter(s => s.code.toLowerCase().includes(q) || s.label.toLowerCase().includes(q))
  }

  const getFilteredScopes = () => {
    if (getPublicIdMatch()) return []
    if (!state.query || state.query.length >= 2) return state.searchScopes
    const q = state.query.toLowerCase()
    return state.searchScopes.filter(scope => scope.label.toLowerCase().includes(q) || "search".includes(q))
  }

  const getAllItems = () => {
    const items = []
    if (state.activeScope) {
      state.searchResults.forEach(r => items.push({ ...r, type: 'search' }))
      return items
    }
    const publicIdMatch = getPublicIdMatch()
    if (publicIdMatch) items.push({ ...publicIdMatch, type: 'publicId' })
    getFilteredShortcuts().forEach(s => items.push({ ...s, type: 'shortcut' }))
    getFilteredScopes().forEach(s => items.push({ ...s, type: 'scope' }))
    return items
  }

  const handleKeyDown = (e) => {
    if (!state.isOpen) return
    const items = getAllItems()

    if (e.key === "Escape") {
      e.preventDefault()
      state.activeScope ? exitScope() : closeModal()
    } else if (e.key === "Backspace" && state.query === "" && state.activeScope) {
      e.preventDefault()
      exitScope()
    } else if (e.key === "ArrowDown") {
      e.preventDefault()
      state.selectedIndex = Math.min(state.selectedIndex + 1, items.length - 1)
      scrollToSelected()
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      state.selectedIndex = Math.max(state.selectedIndex - 1, 0)
      scrollToSelected()
    } else if (e.key === "Enter") {
      e.preventDefault()
      const item = items[state.selectedIndex]
      if (!item) return
      if (item.type === 'scope') enterScope(item)
      else if (item.type === 'publicId') {
        const lookup = state.publicIdLookup
        if (!(lookup?.query === state.query && lookup?.notFound)) navigate(lookup?.data?.path || item.path)
      } else if (item.type === 'shortcut') navigate(item.path, item)
      else navigate(item.path)
    }
  }

  const scrollToSelected = () => {
    setTimeout(() => {
      const resultsList = document.querySelector('.kbar-results-list')
      const selected = document.querySelector('.kbar-result-item.selected')
      if (resultsList && selected) {
        selected.scrollIntoView({ block: 'nearest' })
      }
    }, 0)
  }

  const handleInput = (e) => {
    const query = e.target.value
    state.query = query
    state.selectedIndex = 0

    const scopeKey = scopeShortcuts[query.toLowerCase()]
    if (scopeKey) {
      const scope = state.searchScopes.find(s => s.key === scopeKey)
      if (scope) { state.query = ""; enterScope(scope); return }
    }

    if (!state.activeScope) {
      if (query.includes("@") || /^[UW][A-Z0-9]{8,}$/i.test(query)) {
        const identityScope = state.searchScopes.find(s => s.key === "identities")
        if (identityScope) { enterScope(identityScope); return }
      }
    }

    if (state.activeScope && query.length >= 2) doScopedSearch(query, state.activeScope.key)
    else if (state.activeScope) state.searchResults = []

    const publicIdMatch = getPublicIdMatch()
    if (publicIdMatch && state.publicIdLookup?.query !== query) fetchPublicIdDetails(query)
    else if (!publicIdMatch) { if (publicIdTimeout) clearTimeout(publicIdTimeout); state.publicIdLookup = null }
  }

  cx.mount = () => {
    inputEl = cx.root.querySelector(".kbar-search-input")
    const dataEl = document.getElementById("kbar-data")
    if (dataEl) {
      try {
        const data = JSON.parse(dataEl.textContent)
        state.shortcuts = data.shortcuts || []
        state.prefixes = data.prefixes || {}
        state.searchScopes = data.searchScopes || []
      } catch (err) { console.error("Failed to parse kbar data:", err) }
    }
    window.openKbar = openModal
    document.addEventListener("keydown", (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault()
        state.isOpen ? closeModal() : openModal()
      }
      handleKeyDown(e)
    })
  }

  return (
    <div class="kbar-backdrop" class:open={use(state.isOpen)} on:click={(e) => e.target === e.currentTarget && closeModal()}>
      <div class="kbar-modal">
        <div class="kbar-header">
          <div class="kbar-left"></div>
          <div class="kbar-title">Go anywhere</div>
          <div class="kbar-right"></div>
        </div>
        <div class="kbar-body">
          <div class="kbar-search-wrapper">
            {use(state.activeScope).map(scope => scope ? <div class="kbar-scope-badge" on:click={exitScope}>{scope.label}</div> : null)}
            <div class="kbar-search-icon">{use(state.activeScope).map(scope => scope ? "⌕" : "⊹")}</div>
            <input
              type="text"
              class="kbar-search-input"
              placeholder={use(state.activeScope).map(scope => scope ? `Search ${scope.label}...` : "Search or type a shortcode...")}
              on:input={handleInput}
            />
          </div>
          <div class="kbar-results">
            {use(state.isExiting).andThen(<div class="kbar-goodbye">bye, i'll miss you!</div>, null)}
            {use(state.isExiting, state.activeScope).map(([exiting, scope]) => {
              if (exiting) return null
              if (scope) return (
                <ScopedResults
                  results={use(state.searchResults)}
                  query={use(state.query)}
                  scopeLabel={scope.label}
                  selectedIndex={use(state.selectedIndex)}
                  onNavigate={navigate}
                />
              )
              return (
                <MainResults
                  query={use(state.query)}
                  publicIdMatch={use(state.query, state.prefixes).map(() => getPublicIdMatch())}
                  publicIdLookup={use(state.publicIdLookup)}
                  filteredShortcuts={use(state.query, state.shortcuts).map(() => getFilteredShortcuts())}
                  filteredScopes={use(state.query, state.searchScopes).map(() => getFilteredScopes())}
                  selectedIndex={use(state.selectedIndex)}
                  onNavigate={navigate}
                  onNavigateShortcut={navigate}
                  onEnterScope={enterScope}
                />
              )
            })}
          </div>
          <div class="kbar-hint">
            <kbd>↑</kbd> <kbd>↓</kbd> navigate · <kbd>Enter</kbd> select · <kbd>Esc</kbd> close
          </div>
        </div>
      </div>
    </div>
  )
}

export { Kbar }
export default Kbar
