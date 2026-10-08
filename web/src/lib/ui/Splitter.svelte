<script lang="ts">
  // Drag handle between two panels. `size` is the panel's current size in
  // px; `sign` is -1 when dragging towards the start makes it bigger (a
  // panel on the right or at the bottom). Double-click resets.
  import { dragFrom } from './drag';

  let {
    axis,
    size,
    sign = 1,
    min = 120,
    max = 1200,
    label,
    onresize,
    onreset,
    ondone,
  }: {
    axis: 'x' | 'y';
    size: () => number;
    sign?: 1 | -1;
    min?: number;
    max?: number;
    label: string;
    onresize: (px: number) => void;
    onreset: () => void;
    ondone?: () => void;
  } = $props();

  function down(e: PointerEvent) {
    const start = size();
    dragFrom(
      e,
      (dx, dy) => onresize(Math.round(Math.max(min, Math.min(max, start + sign * (axis === 'x' ? dx : dy))))),
      ondone,
    );
  }

  function key(e: KeyboardEvent) {
    const step = e.shiftKey ? 40 : 10;
    const less = axis === 'x' ? 'ArrowLeft' : 'ArrowUp';
    const more = axis === 'x' ? 'ArrowRight' : 'ArrowDown';
    if (e.key !== less && e.key !== more) return;
    e.preventDefault();
    const d = (e.key === more ? step : -step) * sign;
    onresize(Math.max(min, Math.min(max, size() + d)));
    ondone?.();
  }
</script>

<!-- A focusable separator: arrow keys resize, like dragging. -->
<!-- svelte-ignore a11y_no_noninteractive_tabindex, a11y_no_noninteractive_element_interactions -->
<div
  class="split {axis}"
  role="separator"
  aria-orientation={axis === 'x' ? 'vertical' : 'horizontal'}
  aria-label={label}
  tabindex="0"
  title="{label}: drag to resize, double-click to reset"
  onpointerdown={down}
  ondblclick={() => {
    onreset();
    ondone?.();
  }}
  onkeydown={key}>
</div>

<style>
  .split {
    position: relative;
    z-index: 5;
    background: transparent;
    touch-action: none;
    outline: none;
  }
  .split.x {
    cursor: col-resize;
    width: 100%;
    height: 100%;
  }
  .split.y {
    cursor: row-resize;
    width: 100%;
    height: 100%;
  }
  .split::after {
    content: '';
    position: absolute;
    background: transparent;
    transition: background 0.12s;
  }
  .split.x::after {
    inset: 0 1px;
  }
  .split.y::after {
    inset: 1px 0;
  }
  .split:hover::after,
  .split:focus-visible::after {
    background: var(--accent);
  }
</style>
