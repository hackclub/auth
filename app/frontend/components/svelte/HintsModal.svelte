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
  id="hints-dialog"
  onclick={(e) => { if (e.target === dialogEl) close(); }}
  onkeydown={() => {}}
>
  <column box-="round" id="hints-content">
    <row align-="center between">
      <span is-="badge" variant-="background0">? Keyboard shortcuts</span>
      <button size-="small" variant-="foreground0" onclick={close}>×</button>
    </row>

    <div is-="separator"></div>

    <column>
      <span style="color: var(--subtext0);">Global</span>
      <column pad-="1 0" style="gap: 0.25lh;">
        <row gap-="1" align-="center">
          <span is-="badge" variant-="background2" style="min-width: 4ch; text-align: center;">⌘K</span>
          Open command bar
        </row>
        <row gap-="1" align-="center">
          <span is-="badge" variant-="background2" style="min-width: 4ch; text-align: center;">?</span>
          Show keyboard shortcuts
        </row>
        <row gap-="1" align-="center">
          <span is-="badge" variant-="background2" style="min-width: 4ch; text-align: center;">/</span>
          Focus search input
        </row>
      </column>
    </column>

    {#if hints.length > 0}
      <div is-="separator"></div>
      <column>
        <span style="color: var(--subtext0);">This page</span>
        <column pad-="1 0" style="gap: 0.25lh;">
          {#each hints as hint}
            <div>{@html hint.content}</div>
          {/each}
        </column>
      </column>
    {/if}

    <div is-="separator"></div>
    <row gap-="2" align-="center" style="color: var(--overlay1);">
      <row gap-="1" align-="center">
        <span is-="badge" variant-="background2">esc</span>
        close
      </row>
    </row>
  </column>
</dialog>

<style>
  #hints-dialog {
    position: fixed;
    z-index: 1000;

    &::backdrop {
      backdrop-filter: grayscale(100%);
      background: rgba(0, 0, 0, 0.3);
    }
  }

  #hints-content {
    --box-border-color: var(--overlay0);
    min-width: 44ch;
    max-width: 64ch;
  }
</style>
