// The rules of the optional telemetry, without any browser or Svelte API so
// they can be unit tested: which level is in force, which events are valid,
// the local log and the request bodies. See state.svelte.ts for the side
// effects and docs/telemetry for the user-facing description.

export type Level = "off" | "basic" | "advanced";
export const LEVELS: readonly Level[] = ["off", "basic", "advanced"];

/** Event groups. Error names are the four-digit diagnostic codes. */
export type Kind = "feature" | "export" | "error";
export const KINDS: readonly Kind[] = ["feature", "export", "error"];

/** What GET /api/capabilities says under "telemetry". */
export type ServerTelemetry = {
	enabled: boolean;
	default?: Level;
	/** A level the server locks. Only "off" or "basic". */
	force?: Level | null;
	/** null: kept forever. */
	retention_days?: number | null;
};

/** The person's own choices, kept in this browser. */
export type Prefs = {
	/** null: never chosen, the server default applies. */
	level: Level | null;
	/** The notice version that was shown and confirmed; 0 for none. */
	notice: number;
};

/** Bump when the text of what is collected changes: the notice shows again. */
export const NOTICE_VERSION = 1;

export const MAX_LOG = 500;
export const MAX_QUEUE = 100;
export const NAME_RE = /^[a-z0-9._-]{1,40}$/;

export function isLevel(v: unknown): v is Level {
	return v === "off" || v === "basic" || v === "advanced";
}

/** The level the server forces, if any. Anything but off/basic is ignored: a server can only take data away. */
export function forcedLevel(t: ServerTelemetry | null | undefined): Level | null {
	if (!t?.enabled) return null;
	return t.force === "off" || t.force === "basic" ? t.force : null;
}

/** The level in force: the server's lock, else the person's choice, else the server's default. */
export function effectiveLevel(
	t: ServerTelemetry | null | undefined,
	prefs: Prefs,
): Level {
	if (!t?.enabled) return "off";
	const forced = forcedLevel(t);
	if (forced) return forced;
	return prefs.level ?? (isLevel(t.default) ? t.default : "basic");
}

/** The level the notice preselects. */
export function suggestedLevel(t: ServerTelemetry | null | undefined): Level {
	return forcedLevel(t) ?? (isLevel(t?.default) ? t!.default! : "basic");
}

export function noticeSeen(prefs: Prefs): boolean {
	return prefs.notice === NOTICE_VERSION;
}

/** The notice (or the forced banner) is due when the server collects and it was not confirmed yet. */
export function needsNotice(
	t: ServerTelemetry | null | undefined,
	prefs: Prefs,
): boolean {
	return !!t?.enabled && !noticeSeen(prefs);
}

/** Nothing is sent before the notice was shown and confirmed. */
export function sendLevel(
	t: ServerTelemetry | null | undefined,
	prefs: Prefs,
): Level {
	return noticeSeen(prefs) ? effectiveLevel(t, prefs) : "off";
}

export function validEvent(kind: string, name: string): boolean {
	if (!(KINDS as readonly string[]).includes(kind)) return false;
	if (!NAME_RE.test(name)) return false;
	return kind !== "error" || /^[0-9]{4}$/.test(name);
}

export type LogEntry = {
	/** ISO time, kept in this browser only. */
	t: string;
	kind: "ping" | Kind;
	name: string;
	level: Level;
	status: "queued" | "sent" | "failed";
};

export function trimLog(log: LogEntry[], max = MAX_LOG): LogEntry[] {
	return log.length > max ? log.slice(log.length - max) : log;
}

/** Entries read back from storage: unknown shapes are dropped. */
export function parseLog(raw: unknown): LogEntry[] {
	if (!Array.isArray(raw)) return [];
	const out: LogEntry[] = [];
	for (const e of raw) {
		if (!e || typeof e !== "object") continue;
		const { t, kind, name, level, status } = e as Record<string, unknown>;
		if (typeof t !== "string" || typeof name !== "string") continue;
		if (kind !== "ping" && !(KINDS as readonly string[]).includes(String(kind)))
			continue;
		if (!isLevel(level)) continue;
		if (status !== "queued" && status !== "sent" && status !== "failed")
			continue;
		out.push({ t, kind: kind as LogEntry["kind"], name, level, status });
	}
	return trimLog(out);
}

export function parsePrefs(raw: unknown): Prefs {
	const r = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
	return {
		level: isLevel(r.level) ? r.level : null,
		notice: typeof r.notice === "number" ? r.notice : 0,
	};
}

/** The body of POST /api/telemetry/ping. */
export function pingBody(level: Level): string {
	return JSON.stringify({ level });
}

/** The body of POST /api/telemetry/events. Only the group and the name leave the browser. */
export function eventsBody(events: { kind: string; name: string }[]): string {
	return JSON.stringify({ events: events.map((e) => ({ k: e.kind, n: e.name })) });
}

/** Every feature and export name the editor reports, with what it means; the settings panel lists them. */
export const KNOWN_EVENTS: { kind: Kind; name: string; about: string }[] = [
	{ kind: "feature", name: "layer.add.*", about: "A layer of a type was added (rect, ellipse, text, image, polygon, group, divider)" },
	{ kind: "feature", name: "design.new", about: "A design was created" },
	{ kind: "feature", name: "example.open", about: "An example project was opened" },
	{ kind: "feature", name: "project.export", about: "The project file was exported" },
	{ kind: "feature", name: "functions.open", about: "The function reference was opened" },
	{ kind: "feature", name: "fonts.open", about: "The Fonts window was opened" },
	{ kind: "export", name: "png, zip, pdf, jpeg, webp, svg", about: "An export in this format was started" },
	{ kind: "error", name: "four-digit code", about: "A project problem with this code showed up (once per session and code)" },
];
