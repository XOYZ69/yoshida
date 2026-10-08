<script lang="ts">
  // Draws the dialog requested through askText / confirmAction.
  import { overlay } from './overlay.svelte';
  import { dragFrom } from './drag';

  let input: HTMLInputElement | undefined = $state();
  let okButton: HTMLButtonElement | undefined = $state();
  let text = $state('');
  let error = $state('');

  const d = $derived(overlay.dialog);
  // Offset from the centred place and the size, both reset for each dialog.
  let dx = $state(0);
  let dy = $state(0);
  let size: { w: number; h: number } | null = $state(null);
  let box: HTMLDivElement | undefined = $state();

  function moveBy(e: PointerEvent) {
    const x0 = dx;
    const y0 = dy;
    dragFrom(e, (mx, my) => {
      dx = x0 + mx;
      dy = y0 + my;
    });
  }

  function resizeBy(e: PointerEvent) {
    if (!box) return;
    const r = box.getBoundingClientRect();
    const [x0, y0] = [dx, dy];
    dragFrom(e, (mx, my) => {
      size = { w: Math.max(300, r.width + mx), h: Math.max(140, r.height + my) };
      // Centred layout: keep the top-left corner where it was.
      dx = x0 + (size.w - r.width) / 2;
      dy = y0 + (size.h - r.height) / 2;
    });
  }

  $effect(() => {
    const cur = d;
    if (!cur) return;
    text = cur.kind === 'text' ? cur.value : '';
    error = '';
    dx = dy = 0;
    size = null;
    requestAnimationFrame(() => {
      if (input) {
        input.focus();
        input.select();
      } else okButton?.focus();
    });
  });

  function close(result: string | boolean | null) {
    const cur = overlay.dialog;
    overlay.dialog = null;
    if (!cur) return;
    if (cur.kind === 'text') cur.resolve(typeof result === 'string' ? result : null);
    else cur.resolve(result === true);
  }

  function submit() {
    const cur = overlay.dialog;
    if (!cur) return;
    if (cur.kind === 'confirm') return close(true);
    const v = text.trim();
    error = cur.validate?.(v) ?? '';
    if (!v && !error) error = 'Please enter a value.';
    if (!error) close(v);
  }

  function onkeydown(e: KeyboardEvent) {
    if (!overlay.dialog) return;
    if (e.key === 'Escape') {
      e.preventDefault();
      e.stopPropagation();
      close(null);
    } else if (e.key === 'Enter' && (e.target as HTMLElement).tagName !== 'BUTTON') {
      e.preventDefault();
      submit();
    }
  }
</script>

<svelte:window onkeydowncapture={onkeydown} />

{#if d}
  <div class="backdrop" role="presentation" onpointerdown={(e) => e.target === e.currentTarget && close(null)}>
    <div
      bind:this={box}
      class="dialog"
      role="dialog"
      aria-modal="true"
      aria-labelledby="dlg-title"
      style:translate="{dx}px {dy}px"
      style:width={size ? `${size.w}px` : null}
      style:height={size ? `${size.h}px` : null}>
      <h2 id="dlg-title" onpointerdown={moveBy}>{d.title}</h2>
      {#if d.message}<p class="msg">{d.message}</p>{/if}
      {#if d.kind === 'text'}
        <input bind:this={input} bind:value={text} placeholder={d.placeholder ?? ''} oninput={() => (error = '')} aria-invalid={!!error} />
        {#if error}<p class="err">{error}</p>{/if}
      {/if}
      <div class="actions">
        <button class="ghost" onclick={() => close(null)}>Cancel</button>
        <button bind:this={okButton} class="primary" class:danger={d.kind === 'confirm' && d.danger} onclick={submit}>{d.confirm}</button>
      </div>
      <div class="grip" role="presentation" onpointerdown={resizeBy}></div>
    </div>
  </div>
{/if}

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 1000;
    background: rgba(10, 10, 15, 0.45);
    display: grid;
    place-items: center;
    animation: fade 0.12s ease-out;
  }
  .dialog {
    width: min(420px, calc(100vw - 32px));
    background: var(--bg);
    color: var(--fg);
    border: 1px solid var(--line);
    border-radius: 12px;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.35);
    padding: 18px 18px 14px;
    display: flex;
    flex-direction: column;
    gap: 10px;
    animation: pop 0.14s ease-out;
  }
  .dialog {
    position: relative;
    max-width: calc(100vw - 16px);
    max-height: calc(100vh - 16px);
    overflow: auto;
  }
  h2 {
    margin: 0;
    font-size: 15px;
    font-weight: 600;
    cursor: move;
    user-select: none;
    touch-action: none;
  }
  .msg {
    overflow: auto;
  }
  .grip {
    position: absolute;
    right: 0;
    bottom: 0;
    width: 14px;
    height: 14px;
    cursor: nwse-resize;
    touch-action: none;
  }
  .actions {
    margin-top: auto !important;
  }
  .msg {
    margin: 0;
    font-size: 13px;
    color: var(--muted);
    white-space: pre-line;
  }
  input {
    font-size: 14px !important;
    padding: 7px 10px !important;
    border-radius: 6px !important;
  }
  input:focus {
    outline: 2px solid var(--accent);
    outline-offset: -1px;
  }
  .err {
    margin: -4px 0 0;
    color: var(--err);
    font-size: 12px;
  }
  .actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    margin-top: 4px;
  }
  .ghost {
    background: transparent;
  }
  .primary {
    background: var(--accent);
    border-color: var(--accent);
    color: #fff;
    font-weight: 600;
  }
  .primary.danger {
    background: var(--err);
    border-color: var(--err);
  }
  @keyframes fade {
    from {
      opacity: 0;
    }
  }
  @keyframes pop {
    from {
      transform: scale(0.96);
      opacity: 0;
    }
  }
</style>
