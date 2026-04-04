<script>
  import { onMount, onDestroy } from 'svelte';

  let cleanup;

  onMount(() => {
    function isInputFocused() {
      const el = document.activeElement;
      return el && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA' || el.tagName === 'SELECT');
    }

    function handleKeyDown(e) {
      if (e.metaKey || e.ctrlKey) return;
      // Don't capture keys when ninja-keys or a dialog is open
      const ninja = document.querySelector('ninja-keys');
      if (ninja?.opened) return;
      if (document.querySelector('dialog[open]')) return;

      const dataEl = document.getElementById('keyboard-shortcuts-data');
      if (!dataEl) return;

      let shortcuts = {};
      try { shortcuts = JSON.parse(dataEl.textContent); }
      catch { return; }

      if (e.key === 'Backspace' && !isInputFocused() && shortcuts.back) {
        e.preventDefault();
        window.location.href = shortcuts.back;
        return;
      }

      if (isInputFocused()) return;

      if (e.key === 'a' && shortcuts.approve_ysws) {
        e.preventDefault();
        if (confirm('approve and mark ysws eligible?')) {
          const forms = document.querySelectorAll(`form[action="${shortcuts.approve_ysws}"]`);
          const form = Array.from(forms).find(f => f.querySelector('input[value="true"][name="ysws_eligible"]'));
          if (form) form.submit();
        }
        return;
      }

      if (e.key === 'A' && shortcuts.approve_not_ysws) {
        e.preventDefault();
        if (confirm('approve but mark ysws ineligible?')) {
          const forms = document.querySelectorAll(`form[action="${shortcuts.approve_not_ysws}"]`);
          const form = Array.from(forms).find(f => f.querySelector('input[value="false"][name="ysws_eligible"]'));
          if (form) form.submit();
        }
        return;
      }

      if (e.key === 'r' && shortcuts.focus_reject) {
        e.preventDefault();
        const select = document.querySelector('select[name="rejection_reason"]');
        if (select) select.focus();
        return;
      }

      if (e.key === 'e' && shortcuts.edit) {
        e.preventDefault();
        window.location.href = shortcuts.edit;
        return;
      }

      if (e.key === 'n') {
        const nextLink = document.querySelector('.pagination a[rel="next"]');
        if (nextLink) { e.preventDefault(); window.location.href = nextLink.href; }
        return;
      }

      if (e.key === 'p') {
        const prevLink = document.querySelector('.pagination a[rel="prev"]');
        if (prevLink) { e.preventDefault(); window.location.href = prevLink.href; }
      }
    }

    document.addEventListener('keydown', handleKeyDown);
    cleanup = () => document.removeEventListener('keydown', handleKeyDown);
  });

  onDestroy(() => cleanup?.());
</script>
