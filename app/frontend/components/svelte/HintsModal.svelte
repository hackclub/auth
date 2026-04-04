<script>
  import { onMount, onDestroy } from 'svelte';

  let isOpen = $state(false);
  let hints = $state([]);
  let slugs = $state([]);
  let dialogEl;
  let cleanup;

  function open() {
    isOpen = true;
    dialogEl?.showModal();
    markSeen();
    const banner = document.querySelector('.hints-banner');
    if (banner) banner.style.display = 'none';
  }

  function close() {
    isOpen = false;
    dialogEl?.close();
  }

  async function markSeen() {
    if (slugs.length === 0) return;
    try {
      await fetch('/backend/hints/mark_seen', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content
        },
        body: JSON.stringify({ slugs })
      });
    } catch (err) {
      console.error('Failed to mark hints as seen:', err);
    }
  }

  onMount(() => {
    const dataEl = document.getElementById('hints-data');
    if (dataEl) {
      try {
        const data = JSON.parse(dataEl.textContent);
        hints = data.hints || [];
        slugs = data.slugs || [];
      } catch (err) {
        console.error('Failed to parse hints data:', err);
      }
    }

    window.openHints = open;

    function handleKeyDown(e) {
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA' || e.target.tagName === 'SELECT') return;
      if (e.metaKey || e.ctrlKey) return;

      if (e.key === '?') {
        e.preventDefault();
        isOpen ? close() : open();
      }
      if (e.key === 'Escape' && isOpen) {
        e.preventDefault();
        close();
      }
    }

    document.addEventListener('keydown', handleKeyDown);
    cleanup = () => document.removeEventListener('keydown', handleKeyDown);
  });

  onDestroy(() => cleanup?.());
</script>

<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
<dialog
  bind:this={dialogEl}
  onclick={(e) => { if (e.target === dialogEl) close(); }}
  onkeydown={() => {}}
>
  <article box-="round">
    <h3>Keyboard shortcuts</h3>
    <div is-="separator"></div>

    <section>
      <h4>Global</h4>
      <div><kbd>⌘</kbd><kbd>K</kbd> Open command bar</div>
      <div><kbd>?</kbd> Show keyboard shortcuts</div>
      <div><kbd>/</kbd> Focus search input</div>
    </section>

    {#if hints.length > 0}
      <div is-="separator"></div>
      <section>
        <h4>This page</h4>
        {#each hints as hint}
          <div>{@html hint.content}</div>
        {/each}
      </section>
    {/if}

    <div is-="separator"></div>
    <div style="color: var(--overlay0);"><kbd>Esc</kbd> close</div>
  </article>
</dialog>
