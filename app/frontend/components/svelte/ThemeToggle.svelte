<script>
  import { onMount } from 'svelte';

  let theme = $state('catppuccin-mocha');

  onMount(() => {
    const saved = localStorage.getItem('hca-theme');
    if (saved) {
      theme = saved;
      document.documentElement.setAttribute('data-webtui-theme', theme);
    }
  });

  function toggle() {
    theme = theme === 'catppuccin-mocha' ? 'catppuccin-latte' : 'catppuccin-mocha';
    document.documentElement.setAttribute('data-webtui-theme', theme);
    localStorage.setItem('hca-theme', theme);
  }
</script>

<button type="button" onclick={toggle} title="Toggle theme">
  {theme === 'catppuccin-mocha' ? '☀' : '☾'}
</button>
