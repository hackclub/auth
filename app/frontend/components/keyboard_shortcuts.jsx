const KeyboardShortcuts = function(cx) {
  const state = this
  
  const isInputFocused = () => {
    const el = document.activeElement
    return el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT')
  }

  const handleKeyDown = (e) => {
    if (e.metaKey || e.ctrlKey) return
    
    const dataEl = document.getElementById("keyboard-shortcuts-data")
    if (!dataEl) return
    
    let shortcuts = {}
    try {
      shortcuts = JSON.parse(dataEl.textContent)
    } catch (err) {
      return
    }

    // Backspace for back navigation (never when input focused)
    if (e.key === 'Backspace' && !isInputFocused() && shortcuts.back) {
      e.preventDefault()
      window.location.href = shortcuts.back
      return
    }

    // All other shortcuts require no input focus
    if (isInputFocused()) return

    // Approve shortcuts
    if (e.key === 'a' && shortcuts.approve_ysws) {
      e.preventDefault()
      if (confirm('approve and mark ysws eligible?')) {
        const forms = document.querySelectorAll(`form[action="${shortcuts.approve_ysws}"]`)
        const form = Array.from(forms).find(f => f.querySelector('input[value="true"][name="ysws_eligible"]'))
        if (form) form.submit()
      }
      return
    }

    if (e.key === 'A' && shortcuts.approve_not_ysws) {
      e.preventDefault()
      if (confirm('approve but mark ysws ineligible?')) {
        const forms = document.querySelectorAll(`form[action="${shortcuts.approve_not_ysws}"]`)
        const form = Array.from(forms).find(f => f.querySelector('input[value="false"][name="ysws_eligible"]'))
        if (form) form.submit()
      }
      return
    }

    // Focus reject form
    if (e.key === 'r' && shortcuts.focus_reject) {
      e.preventDefault()
      const select = document.querySelector('select[name="rejection_reason"]')
      if (select) select.focus()
      return
    }

    // Edit shortcut
    if (e.key === 'e' && shortcuts.edit) {
      e.preventDefault()
      window.location.href = shortcuts.edit
      return
    }

    // Next/prev page (pagination) - auto-detect from pagination links
    if (e.key === 'n') {
      const nextLink = document.querySelector('.pagination a[rel="next"]')
      if (nextLink) {
        e.preventDefault()
        window.location.href = nextLink.href
        return
      }
    }

    if (e.key === 'p') {
      const prevLink = document.querySelector('.pagination a[rel="prev"]')
      if (prevLink) {
        e.preventDefault()
        window.location.href = prevLink.href
        return
      }
    }
  }

  cx.mount = () => {
    document.addEventListener('keydown', handleKeyDown)
  }

  return <div style="display:none"></div>
}

export { KeyboardShortcuts }
export default KeyboardShortcuts
