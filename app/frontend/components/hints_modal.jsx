const HintsModal = function(cx) {
  this.isOpen = false
  this.hints = []
  const state = this

  const openModal = () => {
    state.isOpen = true
    markHintsSeen()
  }

  const closeModal = () => {
    state.isOpen = false
  }

  const markHintsSeen = async () => {
    try {
      await fetch('/backend/hints/mark_seen', { 
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        }
      })
    } catch (err) {
      console.error("Failed to mark hints as seen:", err)
    }
  }

  cx.mount = () => {
    const dataEl = document.getElementById("hints-data")
    if (dataEl) {
      try {
        const data = JSON.parse(dataEl.textContent)
        state.hints = data.hints || []
      } catch (err) {
        console.error("Failed to parse hints data:", err)
      }
    }

    window.openHints = openModal

    document.addEventListener("keydown", (e) => {
      if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA" || e.target.tagName === "SELECT") return
      if (e.metaKey || e.ctrlKey) return

      if (e.key === "?") {
        e.preventDefault()
        state.isOpen ? closeModal() : openModal()
      }
      if (e.key === "Escape" && state.isOpen) {
        e.preventDefault()
        closeModal()
      }
    })
  }

  return (
    <div class="hints-backdrop" class:open={use(state.isOpen)} on:click={(e) => e.target === e.currentTarget && closeModal()}>
      <div class="hints-modal">
        <div class="hints-header">
          <div class="hints-left"></div>
          <div class="hints-title">Keyboard shortcuts</div>
          <div class="hints-right"></div>
        </div>
        <div class="hints-body">
          <div class="hints-section">
            <div class="hints-section-label">Global</div>
            <div class="hints-shortcut">
              <kbd>⌘</kbd><kbd>K</kbd>
              <span class="hints-shortcut-label">Open command bar</span>
            </div>
            <div class="hints-shortcut">
              <kbd>?</kbd>
              <span class="hints-shortcut-label">Show keyboard shortcuts</span>
            </div>
            <div class="hints-shortcut">
              <kbd>/</kbd>
              <span class="hints-shortcut-label">Focus search input</span>
            </div>
          </div>
          {use(state.hints).map(hints => hints.length > 0 ? (
            <div class="hints-section">
              <div class="hints-section-label">This page</div>
              {hints.map(hint => (
                <div class="hints-content" innerHTML={hint.content}></div>
              ))}
            </div>
          ) : null)}
          <div class="hints-hint">
            <kbd>Esc</kbd> close
          </div>
        </div>
      </div>
    </div>
  )
}

export { HintsModal }
export default HintsModal
