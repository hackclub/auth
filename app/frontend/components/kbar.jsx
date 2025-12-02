// this is monstrous i'm so sorry
const Kbar = function() {
  this.isOpen = false
  this.query = ""
  this.shortcuts = []
  this.prefixes = {}
  this.searchScopes = []
  this.searchResults = []
  this.selectedIndex = 0
  this.resultsVersion = 0
  this.publicIdLookup = null // { query, loading, data, notFound }
  this.activeScope = null // { key, label } - when drilling down into a search
  this.isExiting = false

  let searchTimeout = null
  let publicIdTimeout = null
  const state = this
  let resultsContainer = null
  let backdropEl = null
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

  const fetchPublicIdDetails = (query, prefixData) => {
    if (publicIdTimeout) clearTimeout(publicIdTimeout)
    
    // Check if hashid part is long enough (at least 3 chars after the !)
    const hashPart = query.split("!")[1] || ""
    if (hashPart.length < 3) {
      state.publicIdLookup = { query, loading: false, data: null, notFound: true }
      state.resultsVersion++
      return
    }

    state.publicIdLookup = { query, loading: true, data: null, notFound: false }
    state.resultsVersion++

    publicIdTimeout = setTimeout(async () => {
      try {
        const res = await fetch(`/backend/kbar/search?q=${encodeURIComponent(query)}`)
        if (!res.ok || !res.headers.get("content-type")?.includes("application/json")) {
          throw new Error("Non-JSON response")
        }
        const results = await res.json()
        if (state.publicIdLookup?.query !== query) return // stale
        
        if (results.length > 0) {
          state.publicIdLookup = { query, loading: false, data: results[0], notFound: false }
        } else {
          state.publicIdLookup = { query, loading: false, data: null, notFound: true }
        }
        state.resultsVersion++
      } catch (err) {
        console.error("Public ID lookup failed:", err)
        if (state.publicIdLookup?.query === query) {
          state.publicIdLookup = { query, loading: false, data: null, notFound: true }
          state.resultsVersion++
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
    state.resultsVersion++
    backdropEl.classList.add("open")
    setTimeout(() => {
      if (inputEl) {
        inputEl.value = ""
        inputEl.focus()
      }
    }, 10)
  }

  const updateScopeUI = () => {
    const wrapper = backdropEl?.querySelector(".kbar-search-wrapper")
    const existingBadge = wrapper?.querySelector(".kbar-scope-badge")
    const iconEl = wrapper?.querySelector(".kbar-search-icon")
    if (existingBadge) existingBadge.remove()

    if (state.activeScope && wrapper && inputEl) {
      const badge = document.createElement("div")
      badge.className = "kbar-scope-badge"
      badge.textContent = state.activeScope.label
      badge.onclick = exitScope
      wrapper.insertBefore(badge, inputEl)
      inputEl.placeholder = `Search ${state.activeScope.label}...`
      if (iconEl) iconEl.textContent = "⌕"
    } else if (inputEl) {
      inputEl.placeholder = "Search or type a shortcode..."
      if (iconEl) iconEl.textContent = "⊹"
    }
  }

  const exitScope = () => {
    state.activeScope = null
    state.query = ""
    state.searchResults = []
    state.selectedIndex = 0
    state.resultsVersion++
    updateScopeUI()
    if (inputEl) {
      inputEl.value = ""
      inputEl.focus()
    }
  }

  const enterScope = (scope) => {
    const previousQuery = state.query
    state.activeScope = scope
    state.searchResults = []
    state.selectedIndex = 0
    state.resultsVersion++
    updateScopeUI()
    
    // Keep the query and trigger search
    if (inputEl) {
      inputEl.focus()
    }
    if (previousQuery.length >= 2) {
      // Trigger search with existing query
      searchTimeout = setTimeout(async () => {
        try {
          const url = `/backend/kbar/search?q=${encodeURIComponent(previousQuery)}&scope=${scope.key}`
          const res = await fetch(url)
          if (!res.ok) throw new Error("Search failed")
          state.searchResults = await res.json()
          state.resultsVersion++
        } catch (err) {
          console.error("Scoped search failed:", err)
          state.searchResults = []
          state.resultsVersion++
        }
      }, 50)
    }
  }

  const closeModal = () => {
    state.isOpen = false
    state.query = ""
    state.searchResults = []
    state.resultsVersion++
    backdropEl.classList.remove("open")
  }

  const navigate = (path, shortcode = null) => {
    if (shortcode?.code === "EXIT") {
      state.isExiting = true
      state.resultsVersion++
      setTimeout(() => {
        window.location.href = path
      }, 1200)
    } else {
      closeModal()
      window.location.href = path
    }
  }

  const getAllItems = () => {
    const items = []

    // If in a scope, just show search results
    if (state.activeScope) {
      state.searchResults.forEach(r => items.push({ ...r, isSearch: true }))
      return items
    }

    // Public ID match
    const publicIdMatch = getPublicIdMatch()
    if (publicIdMatch) {
      items.push({ ...publicIdMatch, isPublicId: true })
    }

    // Filtered shortcuts
    const filtered = state.shortcuts.filter(s => {
      if (!state.query) return true
      return s.code.toLowerCase().includes(state.query.toLowerCase()) ||
             s.label.toLowerCase().includes(state.query.toLowerCase())
    })
    filtered.forEach(s => items.push({ ...s, isShortcut: true }))

    // Search scope drilldowns (always visible when no query or 2+ chars, but not when public ID)
    if (!publicIdMatch) {
      const showAllScopes = !state.query || state.query.length >= 2
      const filteredScopes = state.searchScopes.filter(scope => {
        if (showAllScopes) return true
        // For 1 char, filter by label match
        return scope.label.toLowerCase().includes(state.query.toLowerCase()) ||
               "search".includes(state.query.toLowerCase())
      })
      filteredScopes.forEach(scope => items.push({ 
        ...scope, 
        isScope: true,
        searchQuery: state.query.length >= 2 ? state.query : null
      }))
    }

    return items
  }

  const handleKeyDown = (e) => {
    if (!state.isOpen) return

    const items = getAllItems()

    if (e.key === "Escape") {
      e.preventDefault()
      if (state.activeScope) {
        exitScope()
      } else {
        closeModal()
      }
    } else if (e.key === "Backspace" && state.query === "" && state.activeScope) {
      e.preventDefault()
      exitScope()
    } else if (e.key === "ArrowDown") {
      e.preventDefault()
      state.selectedIndex = Math.min(state.selectedIndex + 1, items.length - 1)
      state.resultsVersion++
      scrollToSelected()
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      state.selectedIndex = Math.max(state.selectedIndex - 1, 0)
      state.resultsVersion++
      scrollToSelected()
    } else if (e.key === "Enter") {
      e.preventDefault()
      const item = items[state.selectedIndex]
      if (!item) return

      if (item.isScope) {
        enterScope(item)
      } else if (item.isPublicId) {
        const lookup = state.publicIdLookup
        const isDisabled = lookup?.query === state.query && lookup?.notFound
        if (!isDisabled) {
          const path = lookup?.data?.path || item.path
          navigate(path)
        }
      } else if (item.isShortcut) {
        navigate(item.path, item)
      } else {
        navigate(item.path)
      }
    }
  }

  const scopeShortcuts = {
    "?i": "identities",
    "?a": "oauth_apps"
  }

  const scopeShortcutHints = {
    "identities": "?i",
    "oauth_apps": "?a"
  }

  const handleInput = (e) => {
    state.query = e.target.value
    state.selectedIndex = 0
    state.resultsVersion++

    if (searchTimeout) clearTimeout(searchTimeout)

    // Check for scope shortcuts like ?i or ?a
    const scopeKey = scopeShortcuts[state.query.toLowerCase()]
    if (scopeKey) {
      const scope = state.searchScopes.find(s => s.key === scopeKey)
      if (scope) {
        state.query = ""
        if (inputEl) inputEl.value = ""
        enterScope(scope)
        return
      }
    }

    // Short-circuit to identity search for emails or Slack IDs
    const looksLikeEmail = state.query.includes("@")
    const looksLikeSlackId = /^[UW][A-Z0-9]{8,}$/i.test(state.query)
    if ((looksLikeEmail || looksLikeSlackId) && !state.activeScope) {
      const identityScope = state.searchScopes.find(s => s.key === "identities")
      if (identityScope) {
        enterScope(identityScope)
        return
      }
    }

    // If in a scope, search within that scope
    if (state.activeScope) {
      if (state.query.length >= 2) {
        searchTimeout = setTimeout(async () => {
          try {
            const url = `/backend/kbar/search?q=${encodeURIComponent(state.query)}&scope=${state.activeScope.key}`
            const res = await fetch(url)
            if (!res.ok) throw new Error("Search failed")
            state.searchResults = await res.json()
            state.resultsVersion++
          } catch (err) {
            console.error("Scoped search failed:", err)
            state.searchResults = []
            state.resultsVersion++
          }
        }, 150)
      } else {
        state.searchResults = []
      }
      return
    }

    // Check for public ID pattern and trigger background lookup
    const publicIdMatch = getPublicIdMatch()
    if (publicIdMatch) {
      if (state.publicIdLookup?.query !== state.query) {
        fetchPublicIdDetails(state.query, state.prefixes[publicIdMatch.prefix])
      }
      state.searchResults = []
      return
    } else {
      if (publicIdTimeout) clearTimeout(publicIdTimeout)
      state.publicIdLookup = null
    }

    // No auto-search outside of scopes
    state.searchResults = []
  }

  const handleBackdropClick = (e) => {
    if (e.target === e.currentTarget) {
      closeModal()
    }
  }

  const scrollToSelected = () => {
    setTimeout(() => {
      const selected = resultsContainer?.querySelector(".selected")
      if (selected) {
        selected.scrollIntoView({ block: "nearest" })
      }
    }, 0)
  }

  const renderResults = () => {
    if (!resultsContainer) return
    
    resultsContainer.innerHTML = ""

    // Show goodbye message when exiting
    if (state.isExiting) {
      const goodbye = document.createElement("div")
      goodbye.className = "kbar-goodbye"
      goodbye.textContent = "bye, i'll miss you!"
      resultsContainer.appendChild(goodbye)
      return
    }

    let idx = 0

    // If in a scope, only show search results
    if (state.activeScope) {
      if (state.searchResults.length > 0) {
        state.searchResults.forEach((r) => {
          const currentIdx = idx++
          const item = document.createElement("a")
          item.href = r.path
          item.className = state.selectedIndex === currentIdx ? "kbar-result-item selected" : "kbar-result-item"
          item.onclick = (e) => { e.preventDefault(); navigate(r.path) }
          item.onmouseenter = () => { state.selectedIndex = currentIdx; state.resultsVersion++ }

          const icon = document.createElement("div")
          icon.className = "kbar-result-icon"
          icon.textContent = "⭢"

          const text = document.createElement("div")
          text.className = "kbar-result-text"
          
          const labelSpan = document.createElement("span")
          labelSpan.className = "kbar-result-label"
          labelSpan.textContent = r.label
          text.appendChild(labelSpan)

          if (r.sublabel) {
            const sublabel = document.createElement("span")
            sublabel.className = "kbar-result-sublabel"
            sublabel.textContent = r.sublabel
            text.appendChild(sublabel)
          }

          item.appendChild(icon)
          item.appendChild(text)
          resultsContainer.appendChild(item)
        })
      } else if (state.query.length >= 2) {
        const hint = document.createElement("div")
        hint.className = "kbar-section-label"
        hint.textContent = "No results"
        resultsContainer.appendChild(hint)
      } else {
        const hint = document.createElement("div")
        hint.className = "kbar-section-label"
        hint.textContent = `Type to search ${state.activeScope.label}...`
        resultsContainer.appendChild(hint)
      }
      return
    }

    const publicIdMatch = getPublicIdMatch()
    if (publicIdMatch) {
      const lookup = state.publicIdLookup
      const isNotFound = lookup?.query === state.query && lookup?.notFound
      const isLoading = lookup?.query === state.query && lookup?.loading
      const fetchedData = lookup?.query === state.query ? lookup?.data : null

      const currentIdx = idx++
      const item = document.createElement("a")
      const targetPath = fetchedData?.path || publicIdMatch.path
      item.href = targetPath
      
      let className = "kbar-result-item"
      if (state.selectedIndex === currentIdx) className += " selected"
      if (isNotFound) className += " disabled"
      item.className = className
      
      if (!isNotFound) {
        item.onclick = (e) => { e.preventDefault(); navigate(targetPath) }
      } else {
        item.onclick = (e) => { e.preventDefault() }
      }
      item.onmouseenter = () => { state.selectedIndex = currentIdx; state.resultsVersion++ }

      const icon = document.createElement("div")
      icon.className = "kbar-result-icon"
      icon.textContent = isNotFound ? "✕" : "⭢"

      const text = document.createElement("div")
      text.className = "kbar-result-text"
      
      const labelSpan = document.createElement("span")
      labelSpan.className = "kbar-result-label"
      if (isNotFound) {
        labelSpan.textContent = `${publicIdMatch.model} not found`
      } else {
        labelSpan.textContent = `Go to ${publicIdMatch.model}`
      }
      text.appendChild(labelSpan)

      const sublabel = document.createElement("span")
      sublabel.className = "kbar-result-sublabel"
      if (isNotFound) {
        sublabel.textContent = publicIdMatch.fullId
      } else if (fetchedData) {
        const parts = [fetchedData.label, fetchedData.sublabel].filter(Boolean)
        sublabel.textContent = parts.join(" · ")
      } else if (isLoading) {
        sublabel.textContent = "loading..."
      } else {
        sublabel.textContent = publicIdMatch.fullId
      }
      text.appendChild(sublabel)

      item.appendChild(icon)
      item.appendChild(text)
      resultsContainer.appendChild(item)
    }

    // Shortcuts first
    const filtered = state.shortcuts.filter(s => {
      if (!state.query) return true
      return s.code.toLowerCase().includes(state.query.toLowerCase()) ||
             s.label.toLowerCase().includes(state.query.toLowerCase())
    })

    if (filtered.length > 0) {
      const label = document.createElement("div")
      label.className = "kbar-section-label"
      label.textContent = "Shortcuts"
      resultsContainer.appendChild(label)

      filtered.forEach((s) => {
        const currentIdx = idx++
        const item = document.createElement("a")
        item.href = s.path
        item.className = state.selectedIndex === currentIdx ? "kbar-result-item selected" : "kbar-result-item"
        item.onclick = (e) => { e.preventDefault(); navigate(s.path, s) }
        item.onmouseenter = () => { state.selectedIndex = currentIdx; state.resultsVersion++ }

        const icon = document.createElement("div")
        icon.className = "kbar-result-icon"
        icon.textContent = s.icon

        const text = document.createElement("div")
        text.className = "kbar-result-text"

        const labelSpan = document.createElement("span")
        labelSpan.className = "kbar-result-label"
        labelSpan.textContent = s.label
        text.appendChild(labelSpan)

        const shortcode = document.createElement("span")
        shortcode.className = "kbar-result-shortcode"
        shortcode.textContent = `[ ${s.code} ]`
        text.appendChild(shortcode)

        item.appendChild(icon)
        item.appendChild(text)
        resultsContainer.appendChild(item)
      })
    }

    // Search scope drilldowns (always visible when no query or 2+ chars, but not when public ID)
    if (!publicIdMatch) {
      const showAllScopes = !state.query || state.query.length >= 2
      const filteredScopes = state.searchScopes.filter(scope => {
        if (showAllScopes) return true
        return scope.label.toLowerCase().includes(state.query.toLowerCase()) ||
               "search".includes(state.query.toLowerCase())
      })

      if (filteredScopes.length > 0) {
        const label = document.createElement("div")
        label.className = "kbar-section-label"
        label.textContent = "Search"
        resultsContainer.appendChild(label)

        filteredScopes.forEach((scope) => {
          const currentIdx = idx++
          const item = document.createElement("div")
          item.className = state.selectedIndex === currentIdx ? "kbar-result-item selected" : "kbar-result-item"
          item.onclick = () => enterScope(scope)
          item.onmouseenter = () => { state.selectedIndex = currentIdx; state.resultsVersion++ }

          const icon = document.createElement("div")
          icon.className = "kbar-result-icon"
          icon.textContent = "⌕"

          const text = document.createElement("div")
          text.className = "kbar-result-text"
          
          const labelSpan = document.createElement("span")
          labelSpan.className = "kbar-result-label"
          labelSpan.textContent = `Search ${scope.label}`
          text.appendChild(labelSpan)

          if (state.query.length >= 2) {
            const sublabel = document.createElement("span")
            sublabel.className = "kbar-result-sublabel"
            sublabel.textContent = `for "${state.query}"`
            text.appendChild(sublabel)
          }

          const hint = scopeShortcutHints[scope.key]
          if (hint) {
            const shortcode = document.createElement("span")
            shortcode.className = "kbar-result-shortcode"
            shortcode.textContent = `( ${hint} )`
            text.appendChild(shortcode)
          }

          item.appendChild(icon)
          item.appendChild(text)
          resultsContainer.appendChild(item)
        })
      }
    }
  }

  this.mount = () => {
    backdropEl = this.root
    resultsContainer = this.root.querySelector(".kbar-results")
    inputEl = this.root.querySelector(".kbar-search-input")
    
    const dataEl = document.getElementById("kbar-data")
    if (dataEl) {
      try {
        const data = JSON.parse(dataEl.textContent)
        state.shortcuts = data.shortcuts || []
        state.prefixes = data.prefixes || {}
        state.searchScopes = data.searchScopes || []
        state.resultsVersion++
      } catch (err) {
        console.error("Failed to parse kbar data:", err)
      }
    }

    useChange(use(this.resultsVersion), renderResults)

    window.openKbar = openModal

    document.addEventListener("keydown", (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key === "k") {
        e.preventDefault()
        if (state.isOpen) {
          closeModal()
        } else {
          openModal()
        }
      }
      handleKeyDown(e)
    })
  }

  return (
    <div class="kbar-backdrop" on:click={handleBackdropClick}>
      <div class="kbar-modal">
        <div class="kbar-header">
          <div class="kbar-left"></div>
          <div class="kbar-title">Go anywhere</div>
          <div class="kbar-right"></div>
        </div>
        <div class="kbar-body">
          <div class="kbar-search-wrapper">
            <div class="kbar-search-icon">⊹</div>
            <input
              type="text"
              class="kbar-search-input"
              placeholder="Search or type a shortcode..."
              on:input={handleInput}
            />
          </div>
          <div class="kbar-results"></div>
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
