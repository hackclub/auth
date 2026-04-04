<script>
  import { onMount } from 'svelte';

  const themes = [
    { id: 'gruvbox-dark-hard', label: 'Dark', dark: true },
    { id: 'vitesse-light-soft', label: 'Light', dark: false },
  ];

  let current = $state('gruvbox-dark-hard');

  function apply(id) {
    current = id;
    document.documentElement.setAttribute('data-webtui-theme', id);
    localStorage.setItem('hca-theme', id);
  }

  function toggle() {
    const next = current === themes[0].id ? themes[1].id : themes[0].id;
    apply(next);
  }

  function isDark() {
    return themes.find(t => t.id === current)?.dark ?? true;
  }

  onMount(() => {
    const saved = localStorage.getItem('hca-theme');
    if (saved && themes.some(t => t.id === saved)) {
      apply(saved);
    }
  });
</script>

<button size-="small" onclick={toggle} title={isDark() ? 'Switch to light' : 'Switch to dark'}>
  {isDark() ? '☀' : '☾'}
</button>
