/**
 * Alpine data component for a tabbed panel with hash fragment deep linking.
 *
 * Usage:
 *   <div x-data="tabPanel({ tabs: ['general', 'groups', 'team', 'activity'], default: 'general' })">
 *     <button @click="select('general')" :class="{ active: active === 'general' }">General</button>
 *     <div x-show="active === 'general'">...</div>
 *   </div>
 */
export function tabPanel({ tabs, default: defaultTab }) {
  return {
    tabs,
    active: defaultTab,

    init() {
      const hash = window.location.hash.slice(1)
      if (hash && this.tabs.includes(hash)) {
        this.active = hash
      }
      window.addEventListener('hashchange', () => {
        const h = window.location.hash.slice(1)
        if (h && this.tabs.includes(h)) this.active = h
      })
    },

    select(tab) {
      this.active = tab
      history.replaceState(null, '', '#' + tab)
    },

    is(tab) {
      return this.active === tab
    }
  }
}
