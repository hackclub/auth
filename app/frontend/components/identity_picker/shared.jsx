const SearchResultItem = function(cx) {
  return (
    <div
      class:selected={use(this.selected)}
      class="picker-result-item"
      on:click={() => this.onSelect?.()}
      on:mouseenter={() => this.onHover?.()}
    >
      <div class="picker-result-icon">{this.icon || "⭢"}</div>
      <div class="picker-result-text">
        <span class="picker-result-label">{use(this.label)}</span>
        {use(this.sublabel).map(s => s ? <span class="picker-result-sublabel">{s}</span> : null)}
      </div>
    </div>
  )
}

const createSearchBehavior = (state, options = {}) => {
  const { onSelect, getExcludeIds } = options
  let searchTimeout = null
  let inputEl = null
  let wrapperEl = null

  const isPublicId = (query) => query.toLowerCase().startsWith("ident!")

  const doSearch = (query) => {
    if (searchTimeout) clearTimeout(searchTimeout)
    
    const minLength = isPublicId(query) ? 9 : 2
    if (query.length < minLength) {
      state.results = []
      state.isLoading = false
      return
    }

    state.isLoading = true
    searchTimeout = setTimeout(async () => {
      try {
        const res = await fetch(`/backend/identity_picker/search?q=${encodeURIComponent(query)}`)
        if (!res.ok) throw new Error("Search failed")
        const results = await res.json()
        const excludeIds = getExcludeIds ? getExcludeIds() : []
        const excludeSet = new Set(excludeIds)
        state.results = results.filter(r => !excludeSet.has(r.id))
        state.selectedIndex = 0
      } catch (err) {
        console.error("Identity search failed:", err)
        state.results = []
      } finally {
        state.isLoading = false
      }
    }, isPublicId(query) ? 100 : 150)
  }

  const selectItem = (item) => {
    onSelect?.(item)
    state.query = ""
    state.results = []
    state.isOpen = false
    if (inputEl) inputEl.value = ""
    setTimeout(() => inputEl?.focus(), 0)
  }

  const handlers = {
    onInput: (e) => {
      state.query = e.target.value
      state.selectedIndex = 0
      state.isOpen = true
      doSearch(state.query)
    },
    onFocus: () => {
      state.isOpen = true
      if (state.query.length >= 2) doSearch(state.query)
    },
    onBlur: () => {
      setTimeout(() => {
        if (!wrapperEl?.contains(document.activeElement)) {
          state.isOpen = false
        }
      }, 150)
    },
    onKeyDown: (e) => {
      const results = state.results
      if (e.key === "Escape") {
        e.preventDefault()
        state.isOpen = false
        inputEl?.blur()
      } else if (e.key === "ArrowDown") {
        e.preventDefault()
        state.selectedIndex = Math.min(state.selectedIndex + 1, results.length - 1)
      } else if (e.key === "ArrowUp") {
        e.preventDefault()
        state.selectedIndex = Math.max(state.selectedIndex - 1, 0)
      } else if (e.key === "Enter") {
        e.preventDefault()
        const item = results[state.selectedIndex]
        if (item) selectItem(item)
      }
    }
  }

  const mount = (root) => {
    wrapperEl = root.querySelector(".picker-search")
    inputEl = root.querySelector(".picker-search-input")
    document.addEventListener("click", (e) => {
      if (!wrapperEl?.contains(e.target)) {
        state.isOpen = false
      }
    })
  }

  return { handlers, mount, selectItem }
}

const SearchDropdown = function(cx) {
  return use(this.isOpen, this.query, this.results, this.isLoading).map(([isOpen, query, results, loading]) => {
    if (!isOpen) return null
    
    return (
      <div class="picker-dropdown">
        {loading ? (
          <div class="picker-status">Loading...</div>
        ) : results.length > 0 ? (
          <div class="picker-results-list">
            {results.map((r, idx) => (
              <SearchResultItem
                selected={use(this.selectedIndex).map(s => s === idx)}
                icon={this.icon}
                label={r.label}
                sublabel={r.sublabel}
                onSelect={() => this.onSelectItem(r)}
                onHover={() => { this.selectedIndex = idx }}
              />
            ))}
          </div>
        ) : query.length >= 2 ? (
          <div class="picker-status">No results found</div>
        ) : query.length > 0 ? (
          <div class="picker-status">Type at least 2 characters...</div>
        ) : null}
      </div>
    )
  })
}

export { SearchResultItem, SearchDropdown, createSearchBehavior }
