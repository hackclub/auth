const Section = function(cx) {
  return (
    <div class="kbar-section">
      <div class="kbar-section-label">{this.title}</div>
      {cx.children}
    </div>
  )
}

export { Section }
