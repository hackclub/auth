import htmx from 'htmx.org';
import { setup_copy } from '../js/click-to-copy.js';
import { mount } from 'svelte';
import CommandPalette from '../components/svelte/CommandPalette.svelte';
import HintsModal from '../components/svelte/HintsModal.svelte';
import KeyboardShortcuts from '../components/svelte/KeyboardShortcuts.svelte';
import IdentityPicker from '../components/svelte/IdentityPicker.svelte';
import NavigableList from '../components/svelte/NavigableList.svelte';
import ThemeToggle from '../components/svelte/ThemeToggle.svelte';

window.htmx = htmx;

document.addEventListener('DOMContentLoaded', () => {
  setup_copy();

  // Apply saved theme before anything renders
  const savedTheme = localStorage.getItem('hca-theme');
  if (savedTheme) {
    document.documentElement.setAttribute('data-webtui-theme', savedTheme);
  }

  // Mount global singletons
  const paletteTarget = document.createElement('div');
  document.body.appendChild(paletteTarget);
  mount(CommandPalette, { target: paletteTarget });

  const hintsTarget = document.createElement('div');
  document.body.appendChild(hintsTarget);
  mount(HintsModal, { target: hintsTarget });

  const shortcutsTarget = document.createElement('div');
  document.body.appendChild(shortcutsTarget);
  mount(KeyboardShortcuts, { target: shortcutsTarget });

  // Mount theme toggle into action bar if present
  const themeSlot = document.getElementById('theme-toggle-slot');
  if (themeSlot) {
    mount(ThemeToggle, { target: themeSlot });
  }

  // Mount per-page components
  document.querySelectorAll('[data-identity-picker]').forEach((el) => {
    const dataEl = el.querySelector('.picker-initial-data');
    let props = {};
    if (dataEl) {
      try { props = JSON.parse(dataEl.textContent); } catch (e) {}
    }
    mount(IdentityPicker, { target: el, props });
  });

  document.querySelectorAll('[data-navigable-list]').forEach((el) => {
    const wrapper = document.createElement('div');
    el.parentNode.insertBefore(wrapper, el);
    wrapper.appendChild(el);
    mount(NavigableList, { target: wrapper, props: { listEl: el } });
  });

  // Global / key → focus search
  document.addEventListener('keydown', (e) => {
    if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT') return;
    if (e.metaKey || e.ctrlKey) return;
    if (e.key === '/') {
      e.preventDefault();
      const searchInput = document.querySelector('input[type="search"]');
      if (searchInput) searchInput.focus();
    }
  });

  // Mount tab views
  document.querySelectorAll('[data-tab-view]').forEach(async (el) => {
    const { mount: mountSvelte } = await import('svelte');
    const { default: TabView } = await import('../components/svelte/TabView.svelte');
    const tabsJson = el.dataset.tabView;
    let tabs = [];
    try { tabs = JSON.parse(tabsJson); } catch (e) {}
    mountSvelte(TabView, { target: el, props: { tabs } });
  });
});
