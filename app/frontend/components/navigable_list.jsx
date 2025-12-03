const NavigableList = function(cx) {
  this.selectedIndex = -1
  this.items = []
  
  const state = this

  const getItems = () => {
    return Array.from(cx.root.querySelectorAll('[data-navigable-item]'))
  }

  const updateSelection = () => {
    const items = getItems()
    items.forEach((item, idx) => {
      if (idx === state.selectedIndex) {
        item.classList.add('selected')
        item.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
      } else {
        item.classList.remove('selected')
      }
    })
  }

  const handleKeyDown = (e) => {
    const items = getItems()
    if (items.length === 0) return

    if (e.key === 'j' || e.key === 'ArrowDown') {
      e.preventDefault()
      if (state.selectedIndex < 0) {
        state.selectedIndex = 0
      } else {
        state.selectedIndex = Math.min(state.selectedIndex + 1, items.length - 1)
      }
      updateSelection()
    } else if (e.key === 'k' || e.key === 'ArrowUp') {
      e.preventDefault()
      if (state.selectedIndex < 0) {
        state.selectedIndex = items.length - 1
      } else {
        state.selectedIndex = Math.max(state.selectedIndex - 1, 0)
      }
      updateSelection()
    } else if (e.key === 'Enter') {
      const selectedItem = items[state.selectedIndex]
      if (selectedItem) {
        const link = selectedItem.querySelector('a') || selectedItem.closest('a')
        if (link) {
          e.preventDefault()
          link.click()
        }
      }
    } else if (e.key === 'g') {
      e.preventDefault()
      state.selectedIndex = 0
      updateSelection()
    } else if (e.key === 'G') {
      e.preventDefault()
      state.selectedIndex = items.length - 1
      updateSelection()
    }
  }

  cx.mount = () => {
    document.addEventListener('keydown', (e) => {
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT') {
        return
      }
      if (e.metaKey || e.ctrlKey) return
      handleKeyDown(e)
    })
    
    const items = getItems()
    items.forEach((item, idx) => {
      item.addEventListener('mouseenter', () => {
        state.selectedIndex = idx
        updateSelection()
      })
    })
  }

  return (
    <div class="navigable-list">
      {cx.children}
    </div>
  )
}

export { NavigableList }
export default NavigableList
