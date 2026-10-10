// Pointer dragging for splitters, window title bars and resize grips.

/** Calls `move` with the distance from the pointer-down point until the button is released. */
export function dragFrom(
	e: PointerEvent,
	move: (dx: number, dy: number) => void,
	end?: () => void,
) {
	if (e.button !== 0) return;
	e.preventDefault();
	const x0 = e.clientX;
	const y0 = e.clientY;
	const el = e.currentTarget as HTMLElement;
	el.setPointerCapture(e.pointerId);
	const onMove = (m: PointerEvent) => move(m.clientX - x0, m.clientY - y0);
	const onUp = () => {
		el.removeEventListener("pointermove", onMove);
		el.removeEventListener("pointerup", onUp);
		el.removeEventListener("pointercancel", onUp);
		document.body.classList.remove("dragging-ui");
		end?.();
	};
	el.addEventListener("pointermove", onMove);
	el.addEventListener("pointerup", onUp);
	el.addEventListener("pointercancel", onUp);
	document.body.classList.add("dragging-ui");
}

/** A JSON value kept in this browser's localStorage (per-browser UI state only). */
export function loadPref<T>(key: string, fallback: T): T {
	try {
		const raw = localStorage.getItem(key);
		return raw ? { ...fallback, ...JSON.parse(raw) } : fallback;
	} catch {
		return fallback;
	}
}

export function savePref(key: string, value: unknown) {
	try {
		localStorage.setItem(key, JSON.stringify(value));
	} catch {
		/* private mode or full storage: sizes are not remembered */
	}
}
