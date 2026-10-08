<script lang="ts">
  // The rendered card with an editing overlay.
  //   click: select; Shift/Ctrl+click: add or remove; drag on empty space:
  //   select by rectangle; Alt+click: the layer underneath.
  //   drag: move (all selected layers); handles: resize; round handle above
  //   the box: rotate (Shift: 15 degree steps); polygon points: reshape.
  // Snaps to the canvas and other layers; hold Ctrl to place freely.
  // A click on a layer inside a group picks what `pick` maps it to (the
  // group); a double click passes `deep` to reach the layer itself.
  // Reports gestures; the parent edits the design.
  import type { Bounds, Gesture, HandleMode, Placed } from '../design';

  let {
    image,
    layout,
    selected,
    handles,
    locked,
    stale = false,
    interactive = true,
    onselect,
    ongesture,
    pick = (id: string) => id,
    oncontext = undefined,
  }: {
    image: ImageData | null;
    layout: Placed[];
    selected: string[];
    handles: (id: string) => HandleMode;
    locked: Set<string>;
    stale?: boolean;
    interactive?: boolean;
    onselect: (ids: string[]) => void;
    ongesture: (g: Gesture, phase: 'start' | 'move' | 'end') => void;
    /** The layer a click on `id` selects, or null when it cannot be picked. */
    pick?: (id: string, deep: boolean) => string | null;
    /** Right click; `id` is the layer under the pointer, if any. */
    oncontext?: (e: MouseEvent, id: string | null) => void;
  } = $props();

  let wrap: HTMLDivElement | undefined = $state();
  let canvas: HTMLCanvasElement | undefined = $state();
  let svg: SVGSVGElement | undefined = $state();
  let fit = $state(true);
  let zoom = $state(1);
  let avail = $state({ w: 0, h: 0 });

  const W = $derived(image?.width ?? 0);
  const H = $derived(image?.height ?? 0);
  const scale = $derived(fit && W && H && avail.w > 0 ? Math.min((avail.w - 32) / W, (avail.h - 32) / H, 4) : zoom);
  const px = $derived(1 / (scale || 1));

  $effect(() => {
    if (!canvas || !image) return;
    canvas.width = image.width;
    canvas.height = image.height;
    canvas.getContext('2d')!.putImageData(image, 0, 0);
  });

  $effect(() => {
    if (!wrap) return;
    const ro = new ResizeObserver(() => (avail = { w: wrap!.clientWidth, h: wrap!.clientHeight }));
    ro.observe(wrap);
    return () => ro.disconnect();
  });

  function setZoom(z: number) {
    zoom = Math.max(0.05, Math.min(8, z));
    fit = false;
  }

  function onwheel(e: WheelEvent) {
    if (!e.ctrlKey && !e.metaKey) return;
    e.preventDefault();
    setZoom(scale * (e.deltaY < 0 ? 1.1 : 1 / 1.1));
  }

  // ------------------------------------------------------------ geometry

  const rad = (deg: number) => (deg * Math.PI) / 180;

  /** Canvas point into the unrotated frame of `b`. */
  function toLocal(b: Placed, x: number, y: number) {
    if (!b.rotate) return { x, y };
    const a = -rad(b.rotate);
    const dx = x - (b.px ?? 0);
    const dy = y - (b.py ?? 0);
    return { x: (b.px ?? 0) + Math.cos(a) * dx - Math.sin(a) * dy, y: (b.py ?? 0) + Math.sin(a) * dx + Math.cos(a) * dy };
  }

  /** A canvas vector into the unrotated frame of `b`. */
  function vecLocal(b: Placed, dx: number, dy: number) {
    if (!b.rotate) return { x: dx, y: dy };
    const a = -rad(b.rotate);
    return { x: Math.cos(a) * dx - Math.sin(a) * dy, y: Math.sin(a) * dx + Math.cos(a) * dy };
  }

  /** Axis-aligned bounds of `b` after rotation (for snapping and rectangles). */
  function aabb(b: Placed): Bounds {
    if (!b.rotate) return b;
    const a = rad(b.rotate);
    const c = Math.cos(a);
    const s = Math.sin(a);
    const xs: number[] = [];
    const ys: number[] = [];
    for (const [x, y] of [
      [b.x, b.y],
      [b.x + b.w, b.y],
      [b.x, b.y + b.h],
      [b.x + b.w, b.y + b.h],
    ]) {
      const dx = x - (b.px ?? 0);
      const dy = y - (b.py ?? 0);
      xs.push((b.px ?? 0) + c * dx - s * dy);
      ys.push((b.py ?? 0) + s * dx + c * dy);
    }
    const x0 = Math.min(...xs);
    const y0 = Math.min(...ys);
    return { x: x0, y: y0, w: Math.max(...xs) - x0, h: Math.max(...ys) - y0 };
  }

  function transform(b: Placed) {
    return b.rotate ? `rotate(${b.rotate} ${b.px ?? 0} ${b.py ?? 0})` : undefined;
  }

  // ------------------------------------------------------------ hit testing

  type Hit = { id: string; b: Placed };
  let hover: string | null = $state(null);

  function toCanvas(e: PointerEvent) {
    const r = svg!.getBoundingClientRect();
    return { x: (e.clientX - r.left) / scale, y: (e.clientY - r.top) / scale };
  }

  /** Group boxes are not hit themselves; their layers are, and map to them. */
  const isGroupBox = (b: Placed) => handles(b.id) === 'group';

  function boxOf(id: string, fallback: Placed): Placed {
    return id === fallback.id ? fallback : (layout.find((b) => b.id === id) ?? fallback);
  }

  function hitsAt(x: number, y: number, deep = false): Hit[] {
    const seen = new Set<string>();
    const out: Hit[] = [];
    const m = 3 * px;
    for (let i = layout.length - 1; i >= 0; i--) {
      const b = layout[i];
      if (!b.visible || locked.has(b.id) || isGroupBox(b)) continue;
      const p = toLocal(b, x, y);
      if (p.x >= b.x - m && p.x <= b.x + b.w + m && p.y >= b.y - m && p.y <= b.y + b.h + m) {
        const id = pick(b.id, deep);
        if (id === null || seen.has(id) || locked.has(id)) continue;
        seen.add(id);
        out.push({ id, b: boxOf(id, b) });
      }
    }
    return out;
  }

  const selSet = $derived(new Set(selected));
  const single = $derived(selected.length === 1 ? selected[0] : null);
  const primary = $derived(single ? layout.find((b) => b.id === single) : undefined);

  // ------------------------------------------------------------ dragging

  type Drag = {
    kind: 'move' | 'resize' | 'point' | 'rotate' | 'marquee';
    ids: string[];
    sx: number;
    sy: number;
    start?: Placed;
    /** Every instance of the dragged layers when the drag began. */
    boxes: Placed[];
    handle?: string;
    index?: number;
    started: boolean;
    dx: number;
    dy: number;
    to?: Bounds;
    angle?: number;
    /** Marquee: the selection it started from (Shift adds to it). */
    base?: string[];
  };
  let drag = $state<Drag | null>(null);
  /** The last gesture, drawn until the next render arrives. */
  let settling = $state<Drag | null>(null);
  let guides: { x?: number; y?: number }[] = $state([]);
  let marquee: Bounds | null = $state(null);

  $effect(() => {
    void layout;
    settling = null;
  });

  /** Layout when the drag began; layers that follow the dragged ones must not attract them. */
  let snapLayout: Placed[] = [];

  function snapTargets(axis: 'x' | 'y', skip: Set<string>) {
    const size = axis === 'x' ? W : H;
    const t = [0, size / 2, size];
    for (const b of snapLayout) {
      if (skip.has(b.id) || !b.visible) continue;
      const r = aabb(b);
      const a = axis === 'x' ? r.x : r.y;
      const s = axis === 'x' ? r.w : r.h;
      t.push(a, a + s / 2, a + s);
    }
    return t;
  }

  function snap(values: number[], targets: number[], noSnap: boolean): { d: number; at: number | null } {
    if (noSnap) return { d: 0, at: null };
    const thr = 6 * px;
    let best: { d: number; at: number | null } = { d: 0, at: null };
    for (const v of values)
      for (const t of targets) {
        const d = t - v;
        if (Math.abs(d) < thr && (best.at === null || Math.abs(d) < Math.abs(best.d))) best = { d, at: t };
      }
    return best;
  }

  function union(bs: Bounds[]): Bounds | null {
    if (!bs.length) return null;
    const x0 = Math.min(...bs.map((b) => b.x));
    const y0 = Math.min(...bs.map((b) => b.y));
    const x1 = Math.max(...bs.map((b) => b.x + b.w));
    const y1 = Math.max(...bs.map((b) => b.y + b.h));
    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
  }

  function pointerdown(e: PointerEvent) {
    if (!interactive || e.button !== 0 || !svg) return;
    const p = toCanvas(e);
    const t = e.target as Element;
    const handle = t.getAttribute('data-handle');
    const vertex = t.getAttribute('data-vertex');
    svg.setPointerCapture(e.pointerId);
    snapLayout = layout;
    const mine = (id: string) => layout.filter((b) => b.id === id);
    if (handle && primary && single) {
      const kind = handle === 'rot' ? 'rotate' : 'resize';
      drag = { kind, ids: [single], sx: p.x, sy: p.y, start: primary, boxes: mine(single), handle, started: false, dx: 0, dy: 0 };
      return;
    }
    if (vertex !== null && primary && single) {
      drag = { kind: 'point', ids: [single], sx: p.x, sy: p.y, start: primary, boxes: mine(single), index: Number(vertex), started: false, dx: 0, dy: 0 };
      return;
    }
    const toggle = e.shiftKey || e.ctrlKey || e.metaKey;
    const hits = hitsAt(p.x, p.y);
    if (!hits.length) {
      drag = { kind: 'marquee', ids: [], sx: p.x, sy: p.y, boxes: [], started: false, dx: 0, dy: 0, base: toggle ? selected : [] };
      return;
    }
    let pick: Hit | undefined;
    const cur = hits.findIndex((h) => selSet.has(h.id));
    if (e.altKey && cur >= 0) pick = hits[(cur + 1) % hits.length];
    else if (cur >= 0 && !e.altKey) pick = hits[cur];
    else pick = hits[0];
    let ids: string[];
    if (toggle) {
      ids = selSet.has(pick.id) ? selected.filter((x) => x !== pick!.id) : [...selected, pick.id];
      onselect(ids);
      if (!ids.includes(pick.id)) return;
    } else if (e.altKey || !selSet.has(pick.id)) {
      ids = [pick.id];
      onselect(ids);
    } else ids = selected;
    const movable = ids.filter((id) => handles(id) !== 'none');
    if (movable.length) {
      drag = { kind: 'move', ids: movable, sx: p.x, sy: p.y, start: pick.b, boxes: layout.filter((b) => movable.includes(b.id)), started: false, dx: 0, dy: 0 };
    }
  }

  function gestureOf(d: Drag): Gesture | null {
    const id = d.ids[0];
    switch (d.kind) {
      case 'resize':
        return { mode: 'resize', id, from: d.start!, to: d.to ?? d.start!, angle: d.start!.rotate ?? 0 };
      case 'point':
        return { mode: 'point', id, index: d.index!, dx: d.dx, dy: d.dy };
      case 'rotate':
        return { mode: 'rotate', id, angle: d.angle ?? d.start!.rotate ?? 0 };
      case 'move':
        return { mode: 'move', ids: d.ids, dx: d.dx, dy: d.dy };
      default:
        return null;
    }
  }

  /** New unrotated bounds for a resize handle dragged by the local vector (rx, ry). */
  function resized(d: Drag, rx: number, ry: number, keepAspect: boolean, noSnap: boolean): Bounds {
    const s = d.start!;
    const h = d.handle!;
    const right = s.x + s.w;
    const bottom = s.y + s.h;
    let x0 = s.x;
    let x1 = right;
    let y0 = s.y;
    let y1 = bottom;
    const g: { x?: number; y?: number }[] = [];
    if (h.includes('w')) x0 = s.x + rx;
    if (h.includes('e')) x1 = right + rx;
    if (h.includes('n')) y0 = s.y + ry;
    if (h.includes('s')) y1 = bottom + ry;
    // Snapping only makes sense when the edges are axis-aligned.
    const canSnap = !noSnap && !s.rotate;
    const skip = new Set(d.ids);
    if (canSnap && (h.includes('w') || h.includes('e'))) {
      const sn = snap([h.includes('w') ? x0 : x1], snapTargets('x', skip), false);
      if (h.includes('w')) x0 += sn.d;
      else x1 += sn.d;
      if (sn.at !== null) g.push({ x: sn.at });
    }
    if (canSnap && (h.includes('n') || h.includes('s'))) {
      const sn = snap([h.includes('n') ? y0 : y1], snapTargets('y', skip), false);
      if (h.includes('n')) y0 += sn.d;
      else y1 += sn.d;
      if (sn.at !== null) g.push({ y: sn.at });
    }
    let w = Math.max(1, Math.round(x1 - x0));
    let hh = Math.max(1, Math.round(y1 - y0));
    if (keepAspect && s.w > 0 && s.h > 0) {
      const ratio = s.w / s.h;
      const horiz = h.includes('w') || h.includes('e');
      const vert = h.includes('n') || h.includes('s');
      if (horiz && (!vert || w / s.w >= hh / s.h)) hh = Math.max(1, Math.round(w / ratio));
      else w = Math.max(1, Math.round(hh * ratio));
    }
    let x = h.includes('w') ? right - w : s.x;
    let y = h.includes('n') ? bottom - hh : s.y;
    if (keepAspect && !h.includes('w') && !h.includes('e')) x = s.x + (s.w - w) / 2;
    if (keepAspect && !h.includes('n') && !h.includes('s')) y = s.y + (s.h - hh) / 2;
    guides = g;
    return { x: Math.round(x), y: Math.round(y), w, h: hh };
  }

  function pointermove(e: PointerEvent) {
    if (!svg) return;
    const p = toCanvas(e);
    if (!drag) {
      if (interactive) hover = hitsAt(p.x, p.y)[0]?.id ?? null;
      return;
    }
    const rx = p.x - drag.sx;
    const ry = p.y - drag.sy;
    if (!drag.started) {
      if (Math.hypot(rx, ry) * scale < 3) return;
      drag.started = true;
      const g = gestureOf(drag);
      if (g) ongesture(g, 'start');
    }
    const noSnap = e.ctrlKey || e.metaKey;
    switch (drag.kind) {
      case 'marquee': {
        const r = { x: Math.min(drag.sx, p.x), y: Math.min(drag.sy, p.y), w: Math.abs(rx), h: Math.abs(ry) };
        marquee = r;
        const inside = new Set<string>();
        for (const b of layout) {
          if (!b.visible || locked.has(b.id) || isGroupBox(b)) continue;
          const a = aabb(b);
          if (!(a.x < r.x + r.w && a.x + a.w > r.x && a.y < r.y + r.h && a.y + a.h > r.y)) continue;
          const id = pick(b.id, false);
          if (id !== null && !locked.has(id)) inside.add(id);
        }
        const next = [...new Set([...(drag.base ?? []), ...inside])];
        if (next.join() !== selected.join()) onselect(next);
        return;
      }
      case 'move': {
        const b = union(drag.boxes.map(aabb))!;
        const skip = new Set(drag.ids);
        const sx = snap([b.x + rx, b.x + rx + b.w / 2, b.x + rx + b.w], snapTargets('x', skip), noSnap);
        const sy = snap([b.y + ry, b.y + ry + b.h / 2, b.y + ry + b.h], snapTargets('y', skip), noSnap);
        drag.dx = Math.round(rx + sx.d);
        drag.dy = Math.round(ry + sy.d);
        guides = [...(sx.at !== null ? [{ x: sx.at }] : []), ...(sy.at !== null ? [{ y: sy.at }] : [])];
        break;
      }
      case 'resize': {
        const v = vecLocal(drag.start!, rx, ry);
        drag.to = resized(drag, v.x, v.y, handles(drag.ids[0]) === 'aspect' || e.shiftKey, noSnap);
        break;
      }
      case 'rotate': {
        const s = drag.start!;
        const cx = s.px ?? s.x + s.w / 2;
        const cy = s.py ?? s.y + s.h / 2;
        // Turn by the angle the pointer swept around the pivot.
        const swept = Math.atan2(p.y - cy, p.x - cx) - Math.atan2(drag.sy - cy, drag.sx - cx);
        let a = (s.rotate ?? 0) + (swept * 180) / Math.PI;
        if (e.shiftKey) a = Math.round(a / 15) * 15;
        a = Math.round(((a % 360) + 540) % 360) - 180;
        drag.angle = a;
        break;
      }
      case 'point': {
        const v = vecLocal(drag.start!, rx, ry);
        drag.dx = Math.round(v.x);
        drag.dy = Math.round(v.y);
        break;
      }
    }
    const g = gestureOf(drag);
    if (g) ongesture(g, 'move');
  }

  function pointerup() {
    if (drag?.started) {
      const g = gestureOf(drag);
      if (g) {
        ongesture(g, 'end');
        settling = drag;
      }
    } else if (drag?.kind === 'marquee' && !drag.base?.length) {
      onselect([]);
    }
    drag = null;
    guides = [];
    marquee = null;
  }

  // ------------------------------------------------------------ drawing

  const active = $derived(drag?.started && drag.kind !== 'marquee' ? drag : settling);
  // While a gesture is shown, draw from the boxes it started with, not from
  // renders that arrive during the drag (they already include part of it).
  const drawn = $derived.by(() => {
    const d = active;
    const fromDrag = d ? d.boxes : [];
    const dragged = new Set(d?.ids ?? []);
    return [...fromDrag, ...layout.filter((b) => selSet.has(b.id) && !dragged.has(b.id))];
  });
  const drawnPrimary = $derived(single ? drawn.find((b) => b.id === single) : undefined);

  function sameInstance(a: Placed, b: Placed) {
    return (a.instance ?? -1) === (b.instance ?? -1);
  }

  /** Box and rotation of `b` as the current gesture shows it. */
  function shown(b: Placed): Placed {
    const d = active;
    if (!d || !d.ids.includes(b.id)) return b;
    if (d.kind === 'move') return { ...b, x: b.x + d.dx, y: b.y + d.dy, px: (b.px ?? 0) + d.dx, py: (b.py ?? 0) + d.dy };
    if (d.kind === 'resize' && d.to && sameInstance(b, d.start!)) return { ...b, ...d.to };
    if (d.kind === 'rotate' && d.angle !== undefined) return { ...b, rotate: d.angle, px: b.px ?? b.x + b.w / 2, py: b.py ?? b.y + b.h / 2 };
    return b;
  }

  function shownPoints(b: Placed): [number, number][] {
    const pts = b.points ?? [];
    const d = active;
    if (!d || !d.ids.includes(b.id)) return pts;
    if (d.kind === 'move') return pts.map(([x, y]) => [x + d.dx, y + d.dy]);
    if (d.kind === 'point') return pts.map(([x, y], i) => (i === d.index ? [x + d.dx, y + d.dy] : [x, y]));
    return pts;
  }

  const handleNames = $derived.by(() => {
    if (!single) return [];
    const m = handles(single);
    if (m === 'box' || m === 'aspect') return ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w'];
    if (m === 'text') return ['e', 'w'];
    return [];
  });

  /** Double click: select the layer itself, even inside a group. */
  function dblclick(e: MouseEvent) {
    if (!interactive || !svg) return;
    const r = svg.getBoundingClientRect();
    const hit = hitsAt((e.clientX - r.left) / scale, (e.clientY - r.top) / scale, true)[0];
    if (hit) onselect([hit.id]);
  }

  function contextmenu(e: MouseEvent) {
    if (!interactive || !oncontext || !svg) return;
    e.preventDefault();
    const r = svg.getBoundingClientRect();
    const id = hitsAt((e.clientX - r.left) / scale, (e.clientY - r.top) / scale)[0]?.id ?? null;
    if (id && !selSet.has(id)) onselect([id]);
    oncontext(e, id);
  }
  const canRotate = $derived(!!single && handles(single) !== 'none');

  function handlePos(name: string, b: Bounds) {
    const x = name.includes('w') ? b.x : name.includes('e') ? b.x + b.w : b.x + b.w / 2;
    const y = name.includes('n') ? b.y : name.includes('s') ? b.y + b.h : b.y + b.h / 2;
    return { x, y };
  }

  // Resize cursors follow the rotation, in 45 degree steps.
  const cursorOrder = ['ns', 'nesw', 'ew', 'nwse'];
  const handleAngle: Record<string, number> = { n: 0, ne: 45, e: 90, se: 135, s: 180, sw: 225, w: 270, nw: 315 };
  function cursorFor(h: string, rot: number) {
    const a = (((handleAngle[h] + rot) % 360) + 360) % 360;
    return cursorOrder[Math.round(a / 45) % 4] + '-resize';
  }
</script>

<div class="stage-wrap" bind:this={wrap} {onwheel}>
  {#if image}
    <div class="stage" class:stale style:width="{W * scale}px" style:height="{H * scale}px">
      <canvas bind:this={canvas} style:width="{W * scale}px" style:height="{H * scale}px"></canvas>
      <svg
        bind:this={svg}
        class:interactive
        viewBox="0 0 {W} {H}"
        width={W * scale}
        height={H * scale}
        role="application"
        aria-label="Card canvas"
        onpointerdown={pointerdown}
        onpointermove={pointermove}
        onpointerup={pointerup}
        onpointercancel={pointerup}
        onpointerleave={() => (hover = null)}
        ondblclick={dblclick}
        oncontextmenu={contextmenu}>
        {#if interactive}
          {#each layout as b}
            {#if b.id === hover && !selSet.has(b.id)}
              <rect class="hover" transform={transform(b)} x={b.x} y={b.y} width={b.w} height={b.h} />
            {/if}
          {/each}
          {#each drawn as b}
            {@const s = shown(b)}
            <g transform={transform(s)}>
              {#if b.points?.length}
                <polygon class="sel" class:hidden={!b.visible} points={shownPoints(b).map((p) => p.join(',')).join(' ')} />
              {/if}
              <rect class="sel" class:hidden={!b.visible} class:secondary={b !== drawnPrimary} x={s.x} y={s.y} width={Math.max(s.w, 0)} height={Math.max(s.h, 0)} />
            </g>
          {/each}
          {#if drawnPrimary && !drag?.started}
            {@const s = shown(drawnPrimary)}
            <g transform={transform(s)}>
              {#if canRotate}
                <line class="stem" x1={s.x + s.w / 2} x2={s.x + s.w / 2} y1={s.y} y2={s.y - 24 * px} />
                <circle class="handle rot" data-handle="rot" cx={s.x + s.w / 2} cy={s.y - 24 * px} r={5 * px}>
                  <title>Rotate (Shift: 15° steps)</title>
                </circle>
              {/if}
              {#each handleNames as h}
                {@const p = handlePos(h, s)}
                <rect class="handle" data-handle={h} style:cursor={cursorFor(h, s.rotate ?? 0)} x={p.x - 4 * px} y={p.y - 4 * px} width={8 * px} height={8 * px} />
              {/each}
              {#if handles(drawnPrimary.id) === 'polygon'}
                {#each shownPoints(drawnPrimary) as p, i}
                  <circle class="handle" data-vertex={i} cx={p[0]} cy={p[1]} r={5 * px} />
                {/each}
              {/if}
            </g>
          {/if}
          {#each guides as g}
            {#if g.x !== undefined}<line class="guide" x1={g.x} x2={g.x} y1={0} y2={H} />{/if}
            {#if g.y !== undefined}<line class="guide" y1={g.y} y2={g.y} x1={0} x2={W} />{/if}
          {/each}
          {#if marquee}
            <rect class="marquee" x={marquee.x} y={marquee.y} width={marquee.w} height={marquee.h} />
          {/if}
          {#if active?.kind === 'rotate' && active.angle !== undefined && drawnPrimary}
            <text class="angle" x={(drawnPrimary.px ?? 0) + 12 * px} y={(drawnPrimary.py ?? 0) - 12 * px} font-size={13 * px}>{active.angle}°</text>
          {/if}
        {/if}
      </svg>
    </div>
  {/if}
  <div class="zoom">
    <button onclick={() => setZoom(scale / 1.25)} title="Zoom out">−</button>
    <button class="pct" onclick={() => setZoom(1)} title="Actual size">{Math.round(scale * 100)}%</button>
    <button onclick={() => setZoom(scale * 1.25)} title="Zoom in">+</button>
    <button class:on={fit} onclick={() => (fit = true)} title="Fit to the window">Fit</button>
  </div>
</div>

<style>
  .stage-wrap {
    position: relative;
    flex: 1;
    overflow: auto;
    min-height: 0;
    display: grid;
    place-items: center;
    padding: 16px;
    background: repeating-conic-gradient(var(--check-a) 0 25%, var(--check-b) 0 50%) 0 0 / 20px 20px;
  }
  .stage {
    position: relative;
    box-shadow: 0 2px 12px rgba(0, 0, 0, 0.35);
    grid-area: 1 / 1;
  }
  .stage.stale canvas {
    opacity: 0.45;
    filter: grayscale(0.6);
  }
  canvas,
  svg {
    position: absolute;
    inset: 0;
    display: block;
  }
  svg {
    overflow: visible;
    touch-action: none;
  }
  rect,
  polygon,
  line,
  circle {
    vector-effect: non-scaling-stroke;
  }
  .hover {
    fill: none;
    stroke: var(--accent);
    stroke-width: 1;
    stroke-dasharray: 4 3;
  }
  .sel {
    fill: none;
    stroke: var(--accent);
    stroke-width: 1.5;
  }
  .sel.secondary {
    stroke-width: 1;
    opacity: 0.7;
  }
  .sel.hidden {
    stroke-dasharray: 6 4;
  }
  polygon.sel {
    stroke-dasharray: 3 3;
  }
  .handle {
    fill: #fff;
    stroke: var(--accent);
    stroke-width: 1.5;
  }
  circle.handle {
    cursor: move;
  }
  circle.rot {
    cursor: grab;
  }
  .stem {
    stroke: var(--accent);
    stroke-width: 1;
  }
  .guide {
    stroke: #ff3d8b;
    stroke-width: 1;
  }
  .marquee {
    fill: color-mix(in srgb, var(--accent) 12%, transparent);
    stroke: var(--accent);
    stroke-width: 1;
    stroke-dasharray: 4 3;
  }
  .angle {
    fill: var(--accent);
    paint-order: stroke;
    stroke: #fff;
    stroke-width: 3px;
    font-family: system-ui, sans-serif;
  }
  .zoom {
    position: sticky;
    bottom: 0;
    justify-self: end;
    align-self: end;
    display: flex;
    gap: 2px;
    background: var(--bg);
    border: 1px solid var(--line);
    border-radius: 6px;
    padding: 2px;
    grid-area: 1 / 1;
    margin: -8px;
  }
  .zoom button {
    padding: 2px 8px;
    border: 0;
  }
  .zoom .pct {
    min-width: 52px;
    font-variant-numeric: tabular-nums;
  }
  .zoom .on {
    color: var(--accent);
  }
</style>
