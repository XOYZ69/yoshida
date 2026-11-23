// Optional, privacy-first usage statistics. They go only to the server that
// hosts this editor (never anywhere else), are off when the editor is opened
// as plain files, and nothing is sent before the start-up notice was shown
// and confirmed. There is no ID in this browser: a ping carries only the
// level, the server counts visitors with a salted hash it replaces every day.
//
// Everything that is sent is also written to a local log you can read in the
// settings panel and download.

import { download } from "../project";
import { hostWord } from "../desktop.ts";
import {
	effectiveLevel,
	eventsBody,
	forcedLevel,
	isLevel,
	type Kind,
	type Level,
	type LogEntry,
	MAX_QUEUE,
	NOTICE_VERSION,
	needsNotice,
	type Prefs,
	parseLog,
	parsePrefs,
	pingBody,
	sendLevel,
	type ServerTelemetry,
	suggestedLevel,
	trimLog,
	validEvent,
} from "./core";

const PREFS_KEY = "yoshida.telemetry";
const LOG_KEY = "yoshida.telemetry.log";
const FLUSH_MS = 8000;

function read(key: string): unknown {
	try {
		const s = localStorage.getItem(key);
		return s ? JSON.parse(s) : null;
	} catch {
		return null;
	}
}

function write(key: string, value: unknown) {
	try {
		localStorage.setItem(key, JSON.stringify(value));
	} catch {
		// Storage blocked: the choice lasts for this page only.
	}
}

export const telemetry = $state<{
	server: ServerTelemetry | null;
	prefs: Prefs;
	log: LogEntry[];
	settingsOpen: boolean;
}>({
	server: null,
	prefs: parsePrefs(read(PREFS_KEY)),
	log: parseLog(read(LOG_KEY)),
	settingsOpen: false,
});

let pinged = false;
let queue: LogEntry[] = [];
const onceSeen = new Set<string>();
let timer: ReturnType<typeof setTimeout> | null = null;
let saveTimer: ReturnType<typeof setTimeout> | null = null;

/** The level in force right now (after the server's lock). */
export function currentLevel(): Level {
	return effectiveLevel(telemetry.server, telemetry.prefs);
}

/** The server locks the level (off or basic). */
export function lockedLevel(): Level | null {
	return forcedLevel(telemetry.server);
}

/** The notice (or the banner for a locked level) must be shown. */
export function noticeDue(): boolean {
	return needsNotice(telemetry.server, telemetry.prefs);
}

export function defaultLevel(): Level {
	return suggestedLevel(telemetry.server);
}

/** Whether the connected server collects at all. */
export function available(): boolean {
	return !!telemetry.server?.enabled;
}

function savePrefs() {
	write(PREFS_KEY, telemetry.prefs);
}

function saveLogSoon() {
	if (saveTimer) return;
	saveTimer = setTimeout(() => {
		saveTimer = null;
		write(LOG_KEY, telemetry.log);
	}, 400);
}

function record(entry: LogEntry) {
	telemetry.log = trimLog([...telemetry.log, entry]);
	saveLogSoon();
}

/** Called once the capabilities of the server are known. */
export function initTelemetry(server: ServerTelemetry | null | undefined) {
	telemetry.server = server?.enabled ? server : null;
	startSession();
}

export function setLevel(level: Level) {
	if (!isLevel(level) || lockedLevel()) return;
	telemetry.prefs = { ...telemetry.prefs, level };
	savePrefs();
	startSession();
}

/** The notice was read: from now on the level in force may be used. */
export function confirmNotice(level?: Level) {
	if (level && !lockedLevel()) telemetry.prefs.level = level;
	telemetry.prefs = { ...telemetry.prefs, notice: NOTICE_VERSION };
	savePrefs();
	startSession();
}

function url(path: string): string {
	return `api/telemetry/${path}`;
}

/** One anonymous ping per editor session, once the notice was confirmed. */
function startSession() {
	if (pinged) return;
	const level = sendLevel(telemetry.server, telemetry.prefs);
	if (level === "off") return;
	pinged = true;
	const entry: LogEntry = {
		t: new Date().toISOString(),
		kind: "ping",
		name: "session",
		level,
		status: "queued",
	};
	record(entry);
	fetch(url("ping"), {
		method: "POST",
		body: pingBody(level),
		headers: { "content-type": "application/json" },
		credentials: "omit",
		referrerPolicy: "no-referrer",
		cache: "no-store",
		keepalive: true,
	})
		.then((r) => settle([entry], r.ok))
		.catch(() => settle([entry], false));
}

function settle(entries: LogEntry[], ok: boolean) {
	for (const e of entries) {
		const live = telemetry.log.find((x) => x.t === e.t && x.name === e.name && x.kind === e.kind);
		if (live) live.status = ok ? "sent" : "failed";
	}
	saveLogSoon();
}

/** Counts a feature use, an export or an error code, at the advanced level only. */
export function track(kind: Kind, name: string): boolean {
	if (!validEvent(kind, name)) return false;
	if (sendLevel(telemetry.server, telemetry.prefs) !== "advanced") return false;
	if (queue.length >= MAX_QUEUE) return false;
	const entry: LogEntry = {
		t: new Date().toISOString(),
		kind,
		name,
		level: "advanced",
		status: "queued",
	};
	queue.push(entry);
	record(entry);
	timer ??= setTimeout(flush, FLUSH_MS);
	return true;
}

/**
 * Like track, once per session and name (errors: the same problem is checked after every edit).
 * A name that was not counted, because the level was lower then, can still be counted later.
 */
export function trackOnce(kind: Kind, name: string) {
	const key = `${kind}:${name}`;
	if (onceSeen.has(key)) return;
	if (track(kind, name)) onceSeen.add(key);
}

export function flush(beacon = false) {
	if (timer) clearTimeout(timer);
	timer = null;
	if (!queue.length) return;
	const batch = queue;
	queue = [];
	const body = eventsBody(batch);
	if (beacon && typeof navigator.sendBeacon === "function") {
		settle(batch, navigator.sendBeacon(url("events"), new Blob([body], { type: "text/plain" })));
		return;
	}
	fetch(url("events"), {
		method: "POST",
		body,
		headers: { "content-type": "application/json" },
		credentials: "omit",
		referrerPolicy: "no-referrer",
		cache: "no-store",
		keepalive: true,
	})
		.then((r) => settle(batch, r.ok))
		.catch(() => settle(batch, false));
}

if (typeof document !== "undefined") {
	document.addEventListener("visibilitychange", () => {
		if (document.visibilityState === "hidden") {
			flush(true);
			if (saveTimer) {
				clearTimeout(saveTimer);
				saveTimer = null;
				write(LOG_KEY, telemetry.log);
			}
		}
	});
}

export function clearLog() {
	telemetry.log = [];
	write(LOG_KEY, []);
}

export function openSettings() {
	telemetry.settingsOpen = true;
}

export function closeSettings() {
	telemetry.settingsOpen = false;
}

/** Saves the local log and the settings as one JSON file. Nothing is requested from the server. */
export function downloadData() {
	const data = {
		about:
			`Everything this editor sent (or queued) to the server that hosts it, as logged in ${hostWord()}. Times exist only here; the server receives no timestamps and no ID.`,
		generated: new Date().toISOString(),
		settings: {
			server_collects: available(),
			level_in_force: currentLevel(),
			level_chosen: telemetry.prefs.level,
			locked_by_server: lockedLevel(),
			server_default: telemetry.server?.default ?? null,
			retention_days: telemetry.server?.retention_days ?? null,
			notice_version_confirmed: telemetry.prefs.notice,
		},
		events: telemetry.log,
	};
	download(
		"yoshida-telemetry-log.json",
		new TextEncoder().encode(JSON.stringify(data, null, "\t")),
		"application/json",
	);
}
