// Long-running work (exports, checks) shown in ProgressHost: a blocking
// overlay with a progress bar, the steps, the estimated time left and an
// activity log. App calls begin() and updates the task it gets back.

export type StepState = "todo" | "active" | "done" | "error";

export type Step = {
	label: string;
	state: StepState;
	detail?: string;
	/** Share of the whole task (roughly its share of the time). */
	weight: number;
};

export type LogLine = { at: number; text: string; kind?: "error" };

export type Task = {
	title: string;
	/** Counted work (cards); total 0: no count. */
	done: number;
	total: number;
	unit: string;
	/** 0..1 for work measured in bytes; null when there is a count or nothing to measure. */
	fraction: number | null;
	started: number;
	/** When the counted work of the active step started. */
	workStarted: number | null;
	/** When the unit in flight (the card being rendered) started. */
	unitStarted: number | null;
	/** Time per unit: measured once a unit is done, an estimate before. */
	perUnitMs: number | null;
	/** Expected duration of work that reports no progress (ms), shown as text only. */
	estimateMs: number | null;
	steps: Step[];
	log: LogLine[];
	state: "running" | "done" | "error" | "cancelled";
	error: string;
	cancel: (() => void) | null;
};

export const progress = $state<{ task: Task | null }>({ task: null });

export const formatBytes = (n: number) =>
	n < 1024
		? `${n} B`
		: n < 1024 * 1024
			? `${(n / 1024).toFixed(0)} KB`
			: `${(n / 1024 / 1024).toFixed(1)} MB`;

export const formatMs = (ms: number) => {
	const s = Math.max(0, Math.round(ms / 1000));
	if (s < 60) return `${s} s`;
	const m = Math.floor(s / 60);
	return `${m} min ${String(s % 60).padStart(2, "0")} s`;
};

/** A running task: its methods update what the overlay shows. */
export class Run {
	private t: Task;
	private abort: (() => void) | null = null;

	/** `steps`: labels, or [label, weight] pairs (the default weight is 1). */
	constructor(
		title: string,
		steps: (string | [string, number])[],
		unit = "cards",
	) {
		progress.task = {
			title,
			done: 0,
			total: 0,
			unit,
			fraction: null,
			started: Date.now(),
			workStarted: null,
			unitStarted: null,
			perUnitMs: null,
			estimateMs: null,
			steps: steps.map((st) =>
				typeof st === "string"
					? { label: st, state: "todo", weight: 1 }
					: { label: st[0], state: "todo", weight: st[1] },
			),
			log: [],
			state: "running",
			error: "",
			cancel: null,
		};
		this.t = progress.task;
	}

	/** True while this task is the one shown. */
	get live() {
		return progress.task === this.t;
	}

	get cancelled() {
		return this.t.state === "cancelled";
	}

	/** Starts step `i`; earlier steps count as done. */
	step(i: number, detail?: string) {
		this.t.steps.forEach((s, j) => {
			if (j < i && s.state !== "error") s.state = "done";
			if (j === i) {
				s.state = "active";
				if (detail !== undefined) s.detail = detail;
			}
		});
		this.t.fraction = null;
		this.t.done = 0;
		this.t.total = 0;
		this.t.workStarted = null;
		this.t.unitStarted = null;
		this.t.perUnitMs = null;
		this.t.estimateMs = null;
	}

	detail(i: number, detail: string) {
		const s = this.t.steps[i];
		if (s) s.detail = detail;
	}

	/** `done` of `total` units are finished; the next one starts now. */
	count(done: number, total: number) {
		const now = Date.now();
		if (this.t.workStarted === null) this.t.workStarted = now;
		if (done !== this.t.done || this.t.unitStarted === null) {
			this.t.unitStarted = now;
			// The measured pace replaces the estimate once a unit is done.
			if (done > 0) this.t.perUnitMs = (now - this.t.workStarted) / done;
		}
		this.t.done = done;
		this.t.total = total;
	}

	/** Expected time per unit before the first one is done (ms). */
	perUnit(ms: number | null) {
		if (!this.t.done) this.t.perUnitMs = ms && ms > 0 ? ms : null;
	}

	fraction(f: number | null) {
		this.t.fraction = f === null ? null : Math.max(0, Math.min(1, f));
	}

	/** Expected duration of work that reports no progress; shown as text, not on the bar. */
	estimate(ms: number | null) {
		this.t.workStarted = Date.now();
		this.t.estimateMs = ms;
	}

	log(text: string, kind?: "error") {
		this.t.log.push({ at: Date.now(), text, kind });
		if (this.t.log.length > 200) this.t.log.splice(0, this.t.log.length - 200);
		(kind === "error" ? console.warn : console.info)(`[yoshida] ${text}`);
	}

	/** Shows a Cancel button that calls `fn`. */
	onCancel(fn: (() => void) | null) {
		this.abort = fn;
		this.t.cancel = fn ? () => this.cancel() : null;
	}

	cancel() {
		if (this.t.state !== "running") return;
		this.t.state = "cancelled";
		this.log("Cancelled.");
		this.abort?.();
		this.close(0);
	}

	/** Marks every step done and closes after a moment, so the end is seen. */
	finish(text?: string) {
		if (this.t.state !== "running") return;
		for (const s of this.t.steps) if (s.state !== "error") s.state = "done";
		this.t.state = "done";
		this.t.cancel = null;
		if (text) this.log(text);
		this.close(700);
	}

	/** Keeps the overlay open with the error until the user closes it. */
	fail(message: string) {
		if (this.t.state !== "running") return;
		for (const s of this.t.steps) if (s.state === "active") s.state = "error";
		this.t.state = "error";
		this.t.error = message;
		this.t.cancel = null;
		this.log(message, "error");
	}

	close(after = 0) {
		const t = this.t;
		setTimeout(() => {
			if (progress.task === t) progress.task = null;
		}, after);
	}
}
