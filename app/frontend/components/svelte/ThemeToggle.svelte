<script>
  import { onMount } from 'svelte';

  const themes = [
    { id: 'catppuccin-mocha', label: 'Catppuccin Mocha', dark: true },
    { id: 'catppuccin-macchiato', label: 'Catppuccin Macchiato', dark: true },
    { id: 'catppuccin-frappe', label: 'Catppuccin Frappé', dark: true },
    { id: 'catppuccin-latte', label: 'Catppuccin Latte', dark: false },
    { id: 'nord', label: 'Nord', dark: true },
    { id: 'gruvbox-dark', label: 'Gruvbox Dark', dark: true },
    { id: 'gruvbox-dark-hard', label: 'Gruvbox Dark Hard', dark: true },
    { id: 'gruvbox-dark-soft', label: 'Gruvbox Dark Soft', dark: true },
    { id: 'gruvbox-light', label: 'Gruvbox Light', dark: false },
    { id: 'gruvbox-light-soft', label: 'Gruvbox Light Soft', dark: false },
    { id: 'vitesse-black', label: 'Vitesse Black', dark: true },
    { id: 'vitesse-dark', label: 'Vitesse Dark', dark: true },
    { id: 'vitesse-dark-soft', label: 'Vitesse Dark Soft', dark: true },
    { id: 'vitesse-light', label: 'Vitesse Light', dark: false },
    { id: 'vitesse-light-soft', label: 'Vitesse Light Soft', dark: false },
    { id: 'everforest-dark', label: 'Everforest Dark', dark: true },
    { id: 'everforest-dark-hard', label: 'Everforest Dark Hard', dark: true },
    { id: 'everforest-dark-soft', label: 'Everforest Dark Soft', dark: true },
    { id: 'everforest-light', label: 'Everforest Light', dark: false },
    { id: 'everforest-light-soft', label: 'Everforest Light Soft', dark: false },
  ];

  let current = $state('catppuccin-mocha');
  let isOpen = $state(false);

  function apply(id) {
    current = id;
    document.documentElement.setAttribute('data-webtui-theme', id);
    localStorage.setItem('hca-theme', id);
  }

  function select(id) {
    apply(id);
    isOpen = false;
  }

  function currentTheme() {
    return themes.find(t => t.id === current);
  }

  onMount(() => {
    const saved = localStorage.getItem('hca-theme');
    if (saved && themes.some(t => t.id === saved)) {
      apply(saved);
    }
  });
</script>

<details is-="popover" position-="bottom baseline-right" bind:open={isOpen}>
  <summary tabindex="0" size-="small">
    {currentTheme()?.dark ? '☾' : '☀'} {currentTheme()?.label ?? 'Theme'}
  </summary>
  <column id="theme-options">
    {#each themes as theme}
      <button
        size-="small"
        variant-={theme.id === current ? 'foreground0' : 'background2'}
        onclick={() => select(theme.id)}
      >
        {theme.dark ? '☾' : '☀'} {theme.label}
      </button>
    {/each}
  </column>
</details>

<style>
  #theme-options {
    max-height: 20lh;
    overflow-y: auto;
    min-width: 24ch;
  }
</style>
