const ScopeItem = function(cx) {
  return (
    <div
      class:selected={use(this.selected)}
      class="kbar-result-item"
      on:click={() => this.onSelect?.()}
      on:mouseenter={() => this.onHover?.()}
    >
      <div class="kbar-result-icon">⌕</div>
      <div class="kbar-result-text">
        <span class="kbar-result-label">Search {this.label}</span>
        {use(this.queryHint).map(q => q ? <span class="kbar-result-sublabel">for "{q}"</span> : null)}
        {this.hint && <span class="kbar-result-shortcode">( {this.hint} )</span>}
      </div>
    </div>
  )
}

export { ScopeItem }
