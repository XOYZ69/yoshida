<script lang="ts">
  // A floating window: drag the title bar to move it, the corner to resize
  // it. Its place and size are remembered per `key` in this browser.
  import type { Snippet } from 'svelte';
  import { dragFrom, loadPref, savePref } from './drag';

  let {
    key,
    title,
    width = 720,
    height = 520,
    minWidth = 320,
    minHeight = 200,
    onclose,
    actions,
    children,
  }: {
    key: string;
    title: string;
    width?: number;
    height?: number;
    minWidth?: number;
    minHeight?: number;
    onclose: () => void;
    actions?: Snippet;
    children: Snippet;
  } = $props();

  const vw = () => window.innerWidth;
  const vh = () => window.innerHeight;
  // Only the first values matter: the window keeps its own place and size afterwards.
  // svelte-ignore state_referenced_locally
  const saved = loadPref(`yoshida.window.${key}`, { x: -1, y: -1, w: width, h: height });
  let w = $state(Math.min(saved.w, vw() - 16));
  let h = $state(Math.min(saved.h, vh() - 16));
  let x = $state(saved.x >= 0 ? saved.x : Math.max(8, (vw() - Math.min(saved.w, vw() - 16)) / 2));
  let y = $state(saved.y >= 0 ? saved.y : Math.max(8, (vh() - Math.min(saved.h, vh() - 16)) / 3));
  clamp();

  function clamp() {
    w = Math.max(minWidth, Math.min(w, vw() - 8));
    h = Math.max(minHeight, Math.min(h, vh() - 8));
    x = Math.max(0, Math.min(x, vw() - Math.min(w, 120)));
    y = Math.max(0, Math.min(y, vh() - 40));
  }

  function remember() {
    savePref(`yoshida.window.${key}`, { x: Math.round(x), y: Math.round(y), w: Math.round(w), h: Math.round(h) });
  }

  function move(e: PointerEvent) {
    if ((e.target as HTMLElement).closest('button, input, [role="button"]')) return;
    const x0 = x;
    const y0 = y;
    dragFrom(
      e,
      (dx, dy) => {
        x = x0 + dx;
        y = y0 + dy;
        clamp();
      },
      remember,
    );
  }

  function resize(e: PointerEvent) {
    const w0 = w;
    const h0 = h;
    dragFrom(
      e,
      (dx, dy) => {
        w = w0 + dx;
        h = h0 + dy;
        clamp();
      },
      remember,
    );
  }

  function maximize() {
    if (w >= vw() - 40 && h >= vh() - 40) {
      w = width;
      h = height;
      x = (vw() - w) / 2;
      y = (vh() - h) / 3;
    } else {
      x = 8;
      y = 8;
      w = vw() - 16;
      h = vh() - 16;
    }
    clamp();
    remember();
  }
</script>

<svelte:window onresize={clamp} />

<div class="win" role="dialog" aria-label={title} style:left="{x}px" style:top="{y}px" style:width="{w}px" style:height="{h}px">
  <div class="title" role="presentation" onpointerdown={move} ondblclick={maximize}>
    <span class="name">{title}</span>
    {@render actions?.()}
    <button class="x" title="Close (Esc)" aria-label="Close" onclick={onclose}>×</button>
  </div>
  <div class="body">{@render children()}</div>
  <div class="grip" role="presentation" title="Drag to resize" onpointerdown={resize}></div>
</div>

<style>
  .win {
    position: fixed;
    z-index: 900;
    display: flex;
    flex-direction: column;
    background: var(--bg);
    color: var(--fg);
    border: 1px solid var(--line);
    border-radius: 10px;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.35);
    overflow: hidden;
  }
  .title {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 8px 6px 14px;
    background: var(--bg-bar);
    border-bottom: 1px solid var(--line);
    cursor: move;
    user-select: none;
    touch-action: none;
  }
  .name {
    font-weight: 600;
    font-size: 13px;
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .x {
    border: 0;
    background: none;
    font-size: 18px;
    line-height: 1;
    padding: 2px 8px;
    color: var(--muted);
  }
  .body {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
  }
  .grip {
    position: absolute;
    right: 0;
    bottom: 0;
    width: 16px;
    height: 16px;
    cursor: nwse-resize;
    touch-action: none;
    background: linear-gradient(135deg, transparent 50%, var(--muted) 50%, var(--muted) 56%, transparent 56%, transparent 70%, var(--muted) 70%, var(--muted) 76%, transparent 76%);
    opacity: 0.6;
  }
</style>
