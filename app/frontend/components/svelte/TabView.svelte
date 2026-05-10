<script>
  import { onMount, onDestroy } from 'svelte';

  let { tabs = [] } = $props();
  let activeTab = $state('');
  let cleanup;

  onMount(() => {
    // init from URL hash or first tab
    const hash = window.location.hash.slice(1);
    activeTab = tabs.find(t => t.id === hash)?.id || tabs[0]?.id || '';
    showTab(activeTab);

    function handleKeyDown(e) {
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT') return;
      if (e.metaKey || e.ctrlKey) return;

      const num = parseInt(e.key);
      if (num >= 1 && num <= tabs.length) {
        e.preventDefault();
        switchTo(tabs[num - 1].id);
      }
    }

    document.addEventListener('keydown', handleKeyDown);
    cleanup = () => document.removeEventListener('keydown', handleKeyDown);
  });

  onDestroy(() => cleanup?.());

  function switchTo(id) {
    activeTab = id;
    window.location.hash = id;
    showTab(id);
  }

  function showTab(id) {
    document.querySelectorAll('[data-tab]').forEach(el => {
      el.style.display = el.dataset.tab === id ? '' : 'none';
    });
  }
</script>

<div class="tui-tabs" role="tablist">
  {#each tabs as tab, i}
    <button
      role="tab"
      aria-selected={activeTab === tab.id}
      class:active={activeTab === tab.id}
      onclick={() => switchTo(tab.id)}
    >
      <kbd>{i + 1}</kbd> {tab.label}
    </button>
  {/each}
</div>
