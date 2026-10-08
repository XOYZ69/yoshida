<script lang="ts">
  // Draws the context menu opened with openMenu().
  import { closeMenu, overlay, type MenuItem } from './overlay.svelte';

  let el: HTMLDivElement | undefined = $state();
  let pos = $state({ left: 0, top: 0 });
  let active = $state(-1);

  const m = $derived(overlay.menu);
  const actionable = (it: MenuItem) => 'action' in it && !it.disabled;

  $effect(() => {
    const cur = m;
    if (!cur || !el) return;
    active = -1;
    const r = el.getBoundingClientRect();
    pos = {
      left: Math.max(4, Math.min(cur.x, window.innerWidth - r.width - 4)),
      top: Math.max(4, Math.min(cur.y, window.innerHeight - r.height - 4)),
    };
    el.focus();
  });

  function run(it: MenuItem) {
    if (!('action' in it) || it.disabled) return;
    closeMenu();
    it.action();
  }

  function onkeydown(e: KeyboardEvent) {
    const cur = overlay.menu;
    if (!cur) return;
    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      closeMenu();
      return;
    }
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      const n = cur.items.length;
      let i = active;
      for (let k = 0; k < n; k++) {
        i = (i + (e.key === 'ArrowDown' ? 1 : n - 1) + n) % n;
        if (actionable(cur.items[i])) break;
      }
      active = i;
    } else if (e.key === 'Enter' && active >= 0) {
      e.preventDefault();
      run(cur.items[active]);
    }
  }
</script>

<svelte:window
  onkeydowncapture={onkeydown}
  onpointerdowncapture={(e) => {
    if (overlay.menu && el && !el.contains(e.target as Node)) closeMenu();
  }}
  onblur={closeMenu}
  onresize={closeMenu} />

{#if m}
  <div bind:this={el} class="menu" role="menu" tabindex="-1" style:left="{pos.left}px" style:top="{pos.top}px" oncontextmenu={(e) => e.preventDefault()}>
    {#each m.items as it, i}
      {#if 'separator' in it}
        <div class="sep" role="separator"></div>
      {:else if 'heading' in it}
        <div class="heading">{it.heading}</div>
      {:else}
        <button
          role="menuitem"
          class:active={i === active}
          class:danger={it.danger}
          disabled={it.disabled}
          onpointerenter={() => (active = i)}
          onclick={() => run(it)}>
          <span class="icon">{it.icon ?? ''}</span>
          <span class="label">{it.label}</span>
          {#if it.detail}<span class="detail">{it.detail}</span>{/if}
          {#if it.shortcut}<kbd>{it.shortcut}</kbd>{/if}
        </button>
      {/if}
    {/each}
  </div>
{/if}

<style>
  .menu {
    position: fixed;
    z-index: 900;
    min-width: 210px;
    padding: 4px;
    background: var(--bg);
    border: 1px solid var(--line);
    border-radius: 8px;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.25);
    outline: none;
    font-size: 13px;
    max-height: calc(100vh - 8px);
    max-width: min(420px, calc(100vw - 8px));
    overflow: auto;
  }
  .heading {
    padding: 6px 8px 2px;
    font-size: 11px;
    letter-spacing: 0.05em;
    text-transform: uppercase;
    color: var(--muted);
  }
  button {
    all: unset;
    box-sizing: border-box;
    width: 100%;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 5px 8px;
    border-radius: 5px;
    cursor: pointer;
    color: var(--fg);
  }
  button.active:not(:disabled) {
    background: var(--sel);
  }
  button:disabled {
    opacity: 0.45;
    cursor: default;
  }
  button.danger {
    color: var(--err);
  }
  .icon {
    width: 16px;
    text-align: center;
    color: var(--muted);
  }
  .label {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .detail {
    font-size: 11px;
    color: var(--muted);
    white-space: nowrap;
  }
  kbd {
    font-family: var(--mono);
    font-size: 11px;
    color: var(--muted);
  }
  .sep {
    height: 1px;
    background: var(--line);
    margin: 4px 2px;
  }
</style>
