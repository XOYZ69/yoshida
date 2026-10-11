// How far a task is, from the work it reports (no runes, so tests can import
// it with plain Node). The bar is one overall fraction: every step has a
// weight (roughly its share of the time), the active step adds its own
// progress (units counted, or bytes moved), and nothing advances on the
// clock alone, except the unit in flight, which may creep up to 90 % of
// itself when a time per unit is known.

export type WorkStep = {
	weight: number;
	state: "todo" | "active" | "done" | "error";
};

export type Work = {
	steps: WorkStep[];
	/** Counted units of the active step (cards, pages); total 0: no count. */
	done: number;
	total: number;
	/** 0..1 for work measured in bytes; null when not measured. */
	fraction: number | null;
	/** When the unit in flight started. */
	unitStarted: number | null;
	/** Expected time per unit (measured, or estimated before the first one). */
	perUnitMs: number | null;
};

/** Progress of the active step alone, 0..1, or null when it reports none. */
export function stepFraction(w: Work, now: number): number | null {
	if (w.total > 0) {
		let f = w.done / w.total;
		if (w.done < w.total && w.unitStarted !== null && w.perUnitMs) {
			const inFlight = Math.min(0.9, Math.max(0, now - w.unitStarted) / w.perUnitMs);
			f += inFlight / w.total;
		}
		return Math.min(1, f);
	}
	return w.fraction;
}

/** Overall 0..1, or null while nothing measurable has happened yet. */
export function overall(w: Work, now: number): number | null {
	const f = stepFraction(w, now);
	if (!w.steps.length) return f;
	const sum = w.steps.reduce((a, s) => a + s.weight, 0) || 1;
	let acc = 0;
	let measured = false;
	for (const s of w.steps) {
		if (s.state === "done") {
			acc += s.weight;
			measured = true;
		} else if (s.state === "active" && f !== null) {
			acc += s.weight * f;
			measured = true;
		}
	}
	return measured ? Math.min(1, acc / sum) : null;
}

/**
 * Time left (ms) from the pace so far: the time spent since the work began,
 * scaled by the part that is still to do. Null until there is enough to go on.
 */
export function timeLeft(
	f: number | null,
	since: number | null,
	now: number,
): number | null {
	if (f === null || since === null || f < 0.02 || f >= 1) return null;
	const spent = now - since;
	if (spent < 800) return null;
	return (spent * (1 - f)) / f;
}
