// Keeping a project and a folder on disk in step: what changed outside the
// editor, and what to do when a linked folder is reconnected. No browser APIs
// here, so everything in this file runs under node for the tests.

import type { Files } from "../project";

/**
 * A cheap fingerprint per file path (size and modification time), taken
 * without reading the file. Equal fingerprints mean "not touched".
 */
export type Sigs = Map<string, string>;

export function signatureOf(size: number, modified: number): string {
	return `${size}:${modified}`;
}

export type SigDiff = { added: string[]; changed: string[]; removed: string[] };

/** What happened to the folder since `known` was taken. */
export function diffSigs(known: Sigs, now: Sigs): SigDiff {
	const out: SigDiff = { added: [], changed: [], removed: [] };
	for (const [p, s] of now) {
		const before = known.get(p);
		if (before === undefined) out.added.push(p);
		else if (before !== s) out.changed.push(p);
	}
	for (const p of known.keys()) if (!now.has(p)) out.removed.push(p);
	return out;
}

export function hasSigChanges(d: SigDiff): boolean {
	return d.added.length + d.changed.length + d.removed.length > 0;
}

export function sameBytes(a: Uint8Array, b: Uint8Array): boolean {
	if (a.byteLength !== b.byteLength) return false;
	for (let i = 0; i < a.byteLength; i++) if (a[i] !== b[i]) return false;
	return true;
}

/** Paths whose content differs between two file sets. */
export type FileDiff = {
	/** Only in the first set (`mine`). */
	onlyMine: string[];
	/** Only in the second set (`theirs`). */
	onlyTheirs: string[];
	/** In both, with different content. */
	differ: string[];
};

export function diffFiles(mine: Files, theirs: Files): FileDiff {
	const out: FileDiff = { onlyMine: [], onlyTheirs: [], differ: [] };
	for (const [p, d] of mine) {
		const o = theirs.get(p);
		if (!o) out.onlyMine.push(p);
		else if (!sameBytes(d, o)) out.differ.push(p);
	}
	for (const p of theirs.keys()) if (!mine.has(p)) out.onlyTheirs.push(p);
	return out;
}

export const diffCount = (d: FileDiff) =>
	d.onlyMine.length + d.onlyTheirs.length + d.differ.length;

/** The read side of a linked folder, as far as change detection needs it. */
export type FolderReader = {
	scan(): Promise<Sigs>;
	readFiles(paths: string[]): Promise<Files>;
};

export type ExternalChanges = {
	/** Fingerprints of the folder now: the new baseline once the user decides. */
	sigs: Sigs;
	/** Paths whose content really differs from the project's copy. */
	changed: string[];
};

/**
 * Looks for changes made outside the editor. A file whose fingerprint moved
 * but whose content is the one the project already has (a `touch`, a save
 * without edits, our own write seen late) is not reported. `local` is the
 * project's files; `known` the fingerprints after the last sync.
 * Returns null when no fingerprint moved; `changed` is empty when they moved
 * without a difference in content.
 */
export async function findExternalChanges(
	folder: FolderReader,
	local: Files,
	known: Sigs,
): Promise<ExternalChanges | null> {
	const sigs = await folder.scan();
	const d = diffSigs(known, sigs);
	if (!hasSigChanges(d)) return null;
	const moved = [...d.added, ...d.changed];
	const now = await folder.readFiles(moved);
	const changed: string[] = [];
	for (const p of moved) {
		const mine = local.get(p);
		const theirs = now.get(p);
		if (theirs && (!mine || !sameBytes(mine, theirs))) changed.push(p);
	}
	for (const p of d.removed) if (local.has(p)) changed.push(p);
	return { sigs, changed };
}

/** What to do when a project that was linked to a folder is opened again. */
export type ReconnectPlan =
	| { kind: "same"; sigs: Sigs }
	// Only the project changed since the last sync: write its changes out.
	| { kind: "push"; sigs: Sigs; diff: FileDiff }
	// The folder changed too (or nothing is known about it): the user decides.
	| { kind: "ask"; sigs: Sigs; diff: FileDiff };

/**
 * `local` is the project as stored in the browser, `folder` what is on disk
 * now, `stored` the fingerprints saved at the last sync (null: none).
 */
export function planReconnect(
	local: Files,
	folder: Files,
	folderSigs: Sigs,
	stored: Sigs | null,
): ReconnectPlan {
	const diff = diffFiles(local, folder);
	if (!diffCount(diff)) return { kind: "same", sigs: folderSigs };
	const untouched = stored && !hasSigChanges(diffSigs(stored, folderSigs));
	return { kind: untouched ? "push" : "ask", sigs: folderSigs, diff };
}
