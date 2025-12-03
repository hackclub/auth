const ResultItem = function(cx) {
  return (
    <a
      href={this.path}
      class:selected={use(this.selected)}
      class:disabled={use(this.disabled)}
      class="kbar-result-item"
      on:click={(e) => { e.preventDefault(); if (!this.disabled) this.onSelect?.() }}
      on:mouseenter={() => this.onHover?.()}
    >
      <div class="kbar-result-icon">{use(this.icon)}</div>
      <div class="kbar-result-text">
        <span class="kbar-result-label">{use(this.label)}</span>
        {use(this.sublabel).map(s => s ? <span class="kbar-result-sublabel">{s}</span> : null)}
        {use(this.shortcode).map(c => c ? <span class="kbar-result-shortcode">[ {c} ]</span> : null)}
      </div>
    </a>
  )
}

export { ResultItem }
