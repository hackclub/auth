import { SearchDropdown, createSearchBehavior } from "./shared.jsx"

const SingleIdentityPicker = function(cx) {
  this.name = "identity_id"
  this.placeholder = "Search identities..."
  this.selected = null
  this.required = false

  this.query = ""
  this.results = []
  this.selectedIndex = 0
  this.isOpen = false
  this.isLoading = false

  const state = this

  const { handlers, mount, selectItem } = createSearchBehavior(state, {
    onSelect: (item) => { state.selected = item }
  })

  const clearSelection = () => {
    state.selected = null
  }

  cx.mount = () => mount(cx.root)

  return (
    <div class="picker-container picker-single">
      {use(state.selected, state.name).map(([selected, name]) => 
        selected ? <input type="hidden" name={name} value={selected.id} /> : null
      )}
      
      {use(state.required, state.selected).map(([required, selected]) => 
        required && !selected ? <input type="hidden" name="__picker_required" required /> : null
      )}

      {use(state.selected).map(selected => {
        if (selected) {
          return (
            <div class="picker-single-selected">
              <div class="picker-single-text">
                <span class="picker-single-label">{selected.label}</span>
                {selected.sublabel ? <span class="picker-single-sublabel">{selected.sublabel}</span> : null}
              </div>
              <button type="button" class="picker-single-clear" on:click={clearSelection}>✕</button>
            </div>
          )
        }
        return (
          <div class="picker-search">
            <div class="picker-search-wrapper">
              <div class="picker-search-icon">⌕</div>
              <input
                type="text"
                class="picker-search-input"
                placeholder={state.placeholder}
                autocomplete="off"
                prop:value={use(state.query)}
                on:input={handlers.onInput}
                on:focus={handlers.onFocus}
                on:blur={handlers.onBlur}
                on:keydown={handlers.onKeyDown}
              />
            </div>
            <SearchDropdown
              isOpen={use(state.isOpen)}
              query={use(state.query)}
              results={use(state.results)}
              isLoading={use(state.isLoading)}
              selectedIndex={use(state.selectedIndex)}
              icon="⭢"
              onSelectItem={selectItem}
            />
          </div>
        )
      })}
    </div>
  )
}

export { SingleIdentityPicker }
