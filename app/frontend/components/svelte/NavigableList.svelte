<script>
  import { onMount, onDestroy } from 'svelte';

  let { listEl } = $props();
  let selectedIndex = -1;
  let cleanup;

  function getItems() {
    return Array.from(listEl.querySelectorAll('[data-navigable-item]'));
  }

  function updateSelection() {
    const items = getItems();
    items.forEach((item, idx) => {
      if (idx === selectedIndex) {
        item.classList.add('selected');
        item.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
      } else {
        item.classList.remove('selected');
      }
    });
  }

  onMount(() => {
    function handleKeyDown(e) {
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT') return;
      if (e.metaKey || e.ctrlKey) return;

      const items = getItems();
      if (items.length === 0) return;

      if (e.key === 'j' || e.key === 'ArrowDown') {
        e.preventDefault();
        selectedIndex = selectedIndex < 0 ? 0 : Math.min(selectedIndex + 1, items.length - 1);
        updateSelection();
      } else if (e.key === 'k' || e.key === 'ArrowUp') {
        e.preventDefault();
        selectedIndex = selectedIndex < 0 ? items.length - 1 : Math.max(selectedIndex - 1, 0);
        updateSelection();
      } else if (e.key === 'Enter') {
        const item = items[selectedIndex];
        if (item) {
          const link = item.querySelector('a') || item.closest('a');
          if (link) { e.preventDefault(); link.click(); }
        }
      } else if (e.key === 'g') {
        e.preventDefault();
        selectedIndex = 0;
        updateSelection();
      } else if (e.key === 'G') {
        e.preventDefault();
        selectedIndex = items.length - 1;
        updateSelection();
      }
    }

    document.addEventListener('keydown', handleKeyDown);

    const items = getItems();
    items.forEach((item, idx) => {
      item.addEventListener('mouseenter', () => {
        selectedIndex = idx;
        updateSelection();
      });
    });

    cleanup = () => document.removeEventListener('keydown', handleKeyDown);
  });

  onDestroy(() => cleanup?.());
</script>
