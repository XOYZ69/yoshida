<script lang="ts">
// Draws every `title` in the app as a themed tooltip (like the expression
// autocomplete popup) instead of the browser's plain one. While an element
// is hovered its title moves to data-tip, so the browser shows nothing;
// it is put back when the pointer leaves, presses or the page scrolls.
// Mounted once in App.

let tip = $state<{
	text: string;
	left: number;
	top: number;
	ready: boolean;
} | null>(null);
let el: HTMLDivElement | undefined = $state();
let target: HTMLElement | null = null;
let timer: ReturnType<typeof setTimeout> | undefined;
/** Shown recently: the next tooltip appears without the delay. */
let warmUntil = 0;

function restore() {
	if (!target) return;
	const text = target.dataset.tip;
	if (text !== undefined && !target.hasAttribute("title"))
		target.setAttribute("title", text);
	delete target.dataset.tip;
	target = null;
}

function hide() {
	clearTimeout(timer);
	if (tip) warmUntil = Date.now() + 400;
	tip = null;
	restore();
}

function show() {
	if (!target?.isConnected) return hide();
	const text = target.dataset.tip?.trim();
	if (!text) return;
	const r = target.getBoundingClientRect();
	tip = { text, left: r.left, top: r.bottom + 6, ready: false };
	// Measure once drawn, then keep it inside the window (above the element
	// when there is no room below).
	requestAnimationFrame(() => {
		if (!el || !tip || !target) return;
		const t = el.getBoundingClientRect();
		let left = r.left + r.width / 2 - t.width / 2;
		left = Math.max(6, Math.min(left, window.innerWidth - t.width - 6));
		let top = r.bottom + 6;
		if (top + t.height > window.innerHeight - 6) top = r.top - t.height - 6;
		tip = { text, left, top: Math.max(6, top), ready: true };
	});
}

function over(e: PointerEvent) {
	if (e.pointerType === "touch") return;
	const found = (e.target as Element | null)?.closest?.(
		"[title], [data-tip]",
	) as HTMLElement | null;
	if (found === target) return;
	hide();
	if (!found) return;
	const title = found.getAttribute("title");
	if (title !== null) {
		found.dataset.tip = title;
		found.removeAttribute("title");
	}
	target = found;
	timer = setTimeout(show, Date.now() < warmUntil ? 60 : 450);
}

function out(e: PointerEvent) {
	if (!target) return;
	const to = e.relatedTarget as Node | null;
	if (to && target.contains(to)) return;
	hide();
}
</script>

<svelte:document onpointerover={over} onpointerout={out} />
<svelte:window
  onpointerdowncapture={hide}
  onkeydowncapture={hide}
  onscrollcapture={hide}
  onblur={hide} />

{#if tip}
  <div bind:this={el} class="yx-tip" role="tooltip" style:left="{tip.left}px" style:top="{tip.top}px" style:visibility={tip.ready ? null : 'hidden'}>{tip.text}</div>
{/if}
