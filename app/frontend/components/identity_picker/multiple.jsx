import { SearchDropdown, createSearchBehavior } from "./shared.jsx"

const MultipleIdentityPicker = function(cx) {
  this.name = "identity_ids"
  this.placeholder = "Search to add..."
  this.selected = []
  this.required = false

  this.query = ""
  this.results = []
  this.selectedIndex = 0
  this.isOpen = false
  this.isLoading = false

  const state = this

  const { handlers, mount, selectItem } = createSearchBehavior(state, {
    onSelect: (item) => { state.selected = [...state.selected, item] },
    getExcludeIds: () => state.selected.map(s => s.id)
  })

  const removeItem = (item) => {
    state.selected = state.selected.filter(s => s.id !== item.id)
  }

  cx.mount = () => mount(cx.root)

  return (
    <div class="picker-container picker-multiple">
      {use(state.selected, state.name).map(([selected, name]) => 
        selected.map(item => (
          <input type="hidden" name={`${name}[]`} value={item.id} />
        ))
      )}
      
      {use(state.required, state.selected).map(([required, selected]) => 
        required && selected.length === 0 ? <input type="hidden" name="__picker_required" required /> : null
      )}

      <div class="picker-multiple-list">
        {use(state.selected).map(selected => 
          selected.map(item => (
            <div class="picker-multiple-item">
              <div class="picker-multiple-text">
                <span class="picker-multiple-label">{item.label}</span>
                {item.sublabel ? <span class="picker-multiple-sublabel">{item.sublabel}</span> : null}
              </div>
              <button type="button" class="picker-multiple-remove" on:click={() => removeItem(item)}>−</button>
            </div>
          ))
        )}
      </div>

      <div class="picker-search">
        <div class="picker-search-wrapper">
          <div class="picker-search-icon">+</div>
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
          icon="+"
          onSelectItem={selectItem}
        />
      </div>
    </div>
  )
}

export { MultipleIdentityPicker }
