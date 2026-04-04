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
      <b>Keyboard shortcuts</b>
      <button size-="small" variant-="foreground0" onclick={close}>×</button>
    </row>

    <div is-="separator"></div>

    <column style="gap: 0.5lh;">
      <span style="color: var(--foreground2);">Global</span>
      {#each [{ keys: ['⌘K'], action: 'command bar' }, { keys: ['?'], action: 'this dialog' }, { keys: ['/'], action: 'focus search' }] as shortcut}
        <row gap-="1" align-="center">
          {#each shortcut.keys as key}
            <span is-="badge" variant-="background2">{key}</span>
          {/each}
          {shortcut.action}
        </row>
      {/each}
    </column>

    {#if hints.length > 0}
      <div is-="separator"></div>
      <column style="gap: 0.5lh;">
        <span style="color: var(--foreground2);">This page</span>
        {#each hints as hint}
          {#each hint.shortcuts as shortcut}
            <row gap-="1" align-="center">
              {#each shortcut.keys as key}
                <span is-="badge" variant-="background2">{key}</span>
              {/each}
              {shortcut.action}
            </row>
          {/each}
        {/each}
      </column>
    {/if}

    <div is-="separator"></div>
    <row gap-="1" align-="center" style="color: var(--foreground2);">
      <span is-="badge" variant-="background2">esc</span>
      close
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
    --box-border-color: var(--foreground2);
    min-width: 44ch;
    max-width: 64ch;
  }
</style>
