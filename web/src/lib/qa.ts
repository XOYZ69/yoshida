// Card review (QA): a status per card, kept in `qa.json` at the project root
// so it is committed with the project and travels with a linked folder.
// Pure functions only; the editor reads and writes the file through the
// project's normal file path (docs: site/content/docs/qa-review.md).
//
// An approval stores a hash of what the card's render depends on: the card's
// values (and its id when the design reads `card.id`) plus the design inputs
// (see `designFingerprint`). Renamed or moved cards keep their review (`reconcileQa`). When the hash no
// longer matches, the approval counts as stale ("changed since review").

import { formatJson } from "./project.ts";

export const QA_FILE = "qa.json";

/** What a reviewer can record. A card without an entry is unreviewed. */
export type QaMark = "approved" | "needs-changes";

/** What the editor shows: a mark, or one of the two states without a mark. */
export type QaStatus = "unreviewed" | "approved" | "needs-changes" | "stale";

/** A point to address on a card. `x` and `y` pin it to a spot of the card, in canvas pixels. */
export type QaComment = {
	id: string;
	text: string;
	/** Who wrote it and when (UTC, to the minute); both optional. */
	by?: string;
	at?: string;
	x?: number;
	y?: number;
	resolved?: boolean;
};

/**
 * What is recorded about a card: an optional mark with the hash of the card
 * when it was marked, and a list of comments. A card with open comments
 * counts as needing changes.
 */
export type QaEntry = {
	status?: QaMark;
	hash: string;
	/** The hash without the card id, when the design shows the id: how a renamed card is found again. Left out when it equals `hash`. */
	content?: string;
	/** Who set the mark and when. */
	by?: string;
	at?: string;
	comments?: QaComment[];
};

/** Entries by key (the set's card file) and then by card id. */
export type QaDoc = { format: 2; cards: Record<string, Record<string, QaEntry>> };

export const emptyQa = (): QaDoc => ({ format: 2, cards: {} });

/** `JSON.stringify` with object keys sorted, so equal data gives equal text. */
export function stableJson(v: unknown): string {
	if (Array.isArray(v)) return `[${v.map(stableJson).join(",")}]`;
	if (v && typeof v === "object")
		return `{${Object.keys(v)
			.sort()
			.map(
				(k) =>
					`${JSON.stringify(k)}:${stableJson((v as Record<string, unknown>)[k])}`,
			)
			.join(",")}}`;
	return JSON.stringify(v) ?? "null";
}

/** A 53-bit string hash (cyrb53) as 14 hex digits. Not cryptographic; it only has to notice edits. */
export function hashText(s: string): string {
	let h1 = 0xdeadbeef;
	let h2 = 0x41c6ce57;
	for (let i = 0; i < s.length; i++) {
		const c = s.charCodeAt(i);
		h1 = Math.imul(h1 ^ c, 2654435761);
		h2 = Math.imul(h2 ^ c, 1597334677);
	}
	h1 = Math.imul(h1 ^ (h1 >>> 16), 2246822507) ^ Math.imul(h2 ^ (h2 >>> 13), 3266489909);
	h2 = Math.imul(h2 ^ (h2 >>> 16), 2246822507) ^ Math.imul(h1 ^ (h1 >>> 13), 3266489909);
	return (4294967296 * (2097151 & h2) + (h1 >>> 0)).toString(16).padStart(14, "0");
}

/** What a card's render depends on besides its own values. */
export type DesignInputs = { print: string; usesId: boolean };

/** The text of a JSON file with key order and layout removed, so a reformat or a reordering does not count as an edit. */
function normalized(text: string): string {
	try {
		return stableJson(JSON.parse(text));
	} catch {
		return text;
	}
}

/**
 * The design inputs of a set's cards: the design file plus the component
 * files it includes (also through other components), and nothing else, so
 * editing a component only touches the designs that use it. Files are
 * compared by their parsed content, so reformatting changes nothing. Images
 * and fonts are not included. `usesId` is true when any of these files reads
 * `card.id`; only then does a card's id count as part of its content.
 */
export function designFingerprint(
	files: ReadonlyMap<string, Uint8Array>,
	designPath: string,
): DesignInputs {
	const dec = new TextDecoder();
	const seen = new Set<string>();
	const parts: string[] = [];
	let usesId = false;
	const visit = (path: string) => {
		if (seen.has(path)) return;
		seen.add(path);
		const bytes = files.get(path);
		if (!bytes) {
			parts.push(path, "\0missing");
			return;
		}
		const text = dec.decode(bytes);
		parts.push(path, normalized(text));
		if (/\bcard\.id\b/.test(text)) usesId = true;
		for (const m of text.matchAll(/"include"\s*:\s*"([^"]+)"/g)) visit(m[1]);
	};
	visit(designPath);
	return { print: hashText(parts.join("\0")), usesId };
}

/** The hash an approval of this card records: its values and the design inputs, plus its id when the design reads `card.id`. */
export function cardHash(
	card: { id: string; values: Record<string, unknown> },
	inputs: DesignInputs,
): string {
	return hashText(
		`${inputs.print}\0${stableJson(inputs.usesId ? [card.id, card.values] : [card.values])}`,
	);
}

/** The hash of the card without its id: what stays the same when the card is renamed. */
export function contentHash(card: { values: Record<string, unknown> }, inputs: DesignInputs): string {
	return hashText(`${inputs.print}\0${stableJson([card.values])}`);
}

/** One set as the reconciliation sees it: its key in qa.json and its cards with their current hashes. */
export type QaSet = { key: string; cards: { id: string; hash: string; content?: string }[] };

/**
 * Follows renamed and moved cards. A review whose card id is gone from its
 * set is given to a card (in any set) that has no review of its own and the
 * same hash, so renaming an id or moving a card to another set keeps its
 * review. Renaming a card file works the same way, as every card of the old
 * key is looked for under the new one. A card whose values also changed
 * does not match and starts over. Entries that find no card are kept.
 */
export function reconcileQa(doc: QaDoc, sets: QaSet[]): QaDoc {
	const live = new Map(sets.map((s) => [s.key, new Set(s.cards.map((c) => c.id))]));
	const orphans: { key: string; id: string; entry: QaEntry }[] = [];
	for (const [key, byId] of Object.entries(doc.cards))
		for (const [id, entry] of Object.entries(byId))
			if (!live.get(key)?.has(id)) orphans.push({ key, id, entry });
	if (!orphans.length) return doc;
	const cards = Object.fromEntries(
		Object.entries(doc.cards).map(([k, v]) => [k, { ...v }]),
	);
	let changed = false;
	for (const set of sets)
		for (const c of set.cards) {
			if (cards[set.key]?.[c.id]) continue;
			const i = orphans.findIndex((o) => (o.entry.content ?? o.entry.hash) === (c.content ?? c.hash));
			if (i < 0) continue;
			const [o] = orphans.splice(i, 1);
			delete cards[o.key][o.id];
			(cards[set.key] ??= {})[c.id] = o.entry;
			changed = true;
		}
	return changed ? { format: 2, cards } : doc;
}

/** Comments of a card that are not resolved yet. */
export const openComments = (entry: QaEntry | undefined): QaComment[] =>
	(entry?.comments ?? []).filter((c) => !c.resolved);

/**
 * The status of a card, given its entry (if any) and its current hash. Open
 * comments mean "needs changes"; once they are resolved, the mark decides.
 */
export function statusOf(entry: QaEntry | undefined, hash: string): QaStatus {
	if (!entry) return "unreviewed";
	if (openComments(entry).length || entry.status === "needs-changes") return "needs-changes";
	if (!entry.status) return "unreviewed";
	return entry.hash === hash ? "approved" : "stale";
}

/** Cards that still need a look: not reviewed, approved before they changed, or marked as needing changes. Only an up to date approval is done. */
export const needsReview = (s: QaStatus) => s !== "approved";

export const statusLabel: Record<QaStatus, string> = {
	unreviewed: "Unreviewed",
	approved: "Approved",
	"needs-changes": "Needs changes",
	stale: "Changed since review",
};

const str = (v: unknown) => (typeof v === "string" && v ? v : undefined);
const num = (v: unknown) => (typeof v === "number" && Number.isFinite(v) ? Math.round(v) : undefined);

/** Reads qa.json text (format 1 or 2). Anything unreadable gives an empty document; bad entries are dropped. A format 1 note becomes the first comment. */
export function parseQa(text: string | undefined): QaDoc {
	const out = emptyQa();
	let v: unknown;
	try {
		v = text ? JSON.parse(text) : undefined;
	} catch {
		return out;
	}
	const cards = (v as { cards?: unknown } | null)?.cards;
	if (!cards || typeof cards !== "object" || Array.isArray(cards)) return out;
	for (const [key, byId] of Object.entries(cards)) {
		if (!byId || typeof byId !== "object" || Array.isArray(byId)) continue;
		for (const [id, e] of Object.entries(byId)) {
			const x = e as (Partial<QaEntry> & { note?: unknown }) | null;
			if (!x || typeof x !== "object") continue;
			const mark = x.status === "approved" || x.status === "needs-changes" ? x.status : undefined;
			const comments: QaComment[] = [];
			const note = str(x.note);
			if (note) comments.push({ id: "c1", text: note });
			if (Array.isArray(x.comments))
				for (const c of x.comments as Partial<QaComment>[]) {
					const text = str(c?.text);
					if (!text) continue;
					const cid = str(c.id) ?? `c${comments.length + 1}`;
					if (comments.some((o) => o.id === cid)) continue;
					const k: QaComment = { id: cid, text };
					if (str(c.by)) k.by = c.by;
					if (str(c.at)) k.at = c.at;
					const px = num(c.x);
					const py = num(c.y);
					if (px !== undefined && py !== undefined) {
						k.x = px;
						k.y = py;
					}
					if (c.resolved === true) k.resolved = true;
					comments.push(k);
				}
			if (!mark && !comments.length) continue;
			const entry: QaEntry = { hash: typeof x.hash === "string" ? x.hash : "" };
			if (str(x.content)) entry.content = x.content;
			if (mark) entry.status = mark;
			if (str(x.by)) entry.by = x.by;
			if (str(x.at)) entry.at = x.at;
			if (comments.length) entry.comments = comments;
			(out.cards[key] ??= {})[id] = entry;
		}
	}
	return out;
}

/** The canonical text of a document: keys sorted, `yoshida fmt` layout. */
export function writeQa(doc: QaDoc): string {
	const cards: Record<string, Record<string, unknown>> = {};
	for (const key of Object.keys(doc.cards).sort()) {
		const byId = doc.cards[key];
		const ids = Object.keys(byId).sort();
		if (!ids.length) continue;
		cards[key] = {};
		for (const id of ids) {
			const { status, hash, content, by, at, comments } = byId[id];
			cards[key][id] = {
				...(status ? { status } : {}),
				hash,
				...(content && content !== hash ? { content } : {}),
				...(status && by ? { by } : {}),
				...(status && at ? { at } : {}),
				...(comments?.length ? { comments } : {}),
			};
		}
	}
	return formatJson({ format: 2, cards });
}

/** Who and when, as recorded with a mark or a comment. */
export type QaStamp = { by?: string; at?: string };

/** The current time as a stamp value: UTC, to the minute. */
export const stampNow = (d = new Date()) => `${d.toISOString().slice(0, 16)}Z`;

function put(doc: QaDoc, key: string, id: string, entry: QaEntry | undefined): QaDoc {
	const cards = { ...doc.cards, [key]: { ...doc.cards[key] } };
	if (entry && (entry.status || entry.comments?.length)) cards[key][id] = entry;
	else delete cards[key][id];
	return { format: 2, cards };
}

/**
 * The document after recording a mark: `mark` null removes the mark and keeps
 * the comments. The hash is that of the card as reviewed now.
 */
export function withMark(
	doc: QaDoc,
	key: string,
	id: string,
	mark: QaMark | null,
	hash: string,
	stamp: QaStamp = {},
	content?: string,
): QaDoc {
	const old = doc.cards[key]?.[id];
	const entry: QaEntry = { hash: mark ? hash : (old?.hash ?? hash) };
	const c = mark ? content : old?.content;
	if (c && c !== entry.hash) entry.content = c;
	if (mark) {
		entry.status = mark;
		if (stamp.by) entry.by = stamp.by;
		if (stamp.at) entry.at = stamp.at;
	}
	if (old?.comments?.length) entry.comments = old.comments;
	return put(doc, key, id, entry);
}

const nextCommentId = (list: QaComment[]) =>
	`c${Math.max(0, ...list.map((c) => Number(/^c(\d+)$/.exec(c.id)?.[1] ?? 0))) + 1}`;

/** The document with a new comment on the card. Returns the new comment's id too. */
export function withComment(
	doc: QaDoc,
	key: string,
	id: string,
	hash: string,
	fields: { text: string; x?: number; y?: number; content?: string } & QaStamp,
): { doc: QaDoc; id: string } {
	const old = doc.cards[key]?.[id];
	const list = old?.comments ?? [];
	const cid = nextCommentId(list);
	const c: QaComment = { id: cid, text: fields.text };
	if (fields.by) c.by = fields.by;
	if (fields.at) c.at = fields.at;
	if (fields.x !== undefined && fields.y !== undefined) {
		c.x = Math.round(fields.x);
		c.y = Math.round(fields.y);
	}
	const base: QaEntry = old ?? {
		hash,
		...(fields.content && fields.content !== hash ? { content: fields.content } : {}),
	};
	return { doc: put(doc, key, id, { ...base, comments: [...list, c] }), id: cid };
}

/** The document after changing a comment. A comment left without text is removed. */
export function withCommentEdit(
	doc: QaDoc,
	key: string,
	id: string,
	commentId: string,
	patch: Partial<Pick<QaComment, "text" | "x" | "y" | "resolved">>,
): QaDoc {
	const old = doc.cards[key]?.[id];
	if (!old?.comments) return doc;
	const list: QaComment[] = [];
	for (const c of old.comments) {
		if (c.id !== commentId) {
			list.push(c);
			continue;
		}
		const n: QaComment = { ...c, ...patch };
		if (!n.resolved) delete n.resolved;
		if (n.x === undefined || n.y === undefined) {
			delete n.x;
			delete n.y;
		}
		if (n.text.trim()) list.push({ ...n, text: n.text.trim() });
	}
	const next: QaEntry = { ...old };
	if (list.length) next.comments = list;
	else delete next.comments;
	return put(doc, key, id, next);
}

/** The document without one comment. */
export function withoutComment(doc: QaDoc, key: string, id: string, commentId: string): QaDoc {
	const old = doc.cards[key]?.[id];
	if (!old?.comments) return doc;
	const comments = old.comments.filter((c) => c.id !== commentId);
	const next: QaEntry = { ...old };
	if (comments.length) next.comments = comments;
	else delete next.comments;
	return put(doc, key, id, next);
}

/** Counts of each status over a set's cards. */
export function tally(statuses: QaStatus[]): Record<QaStatus, number> {
	const t: Record<QaStatus, number> = {
		unreviewed: 0,
		approved: 0,
		"needs-changes": 0,
		stale: 0,
	};
	for (const s of statuses) t[s]++;
	return t;
}
