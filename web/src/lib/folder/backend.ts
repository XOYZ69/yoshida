// Where a project's folder lives. The editor talks to these two types only,
// so a desktop shell can add a native backend (real paths, file watching)
// next to the browser one without touching the editor.

import type { Files } from "../project";
import type { FolderReader, Sigs } from "./sync";

export type Permission = "granted" | "prompt" | "denied";

/** A folder the project is linked to. */
export type FolderLink = FolderReader & {
	/** Id of the backend that made this link. */
	readonly backend: string;
	/** Short name for the interface (the folder's own name). */
	readonly name: string;
	/**
	 * What to keep so the link can be opened again later: structured-cloneable
	 * (it is stored in IndexedDB), and only meaningful to the backend that made it.
	 */
	readonly ref: unknown;
	/**
	 * Whether the folder may be read and written now. With `request`, asks the
	 * user when it is not; browsers only allow that from a click or key press.
	 */
	permission(request?: boolean): Promise<Permission>;
	/** Every project file and its fingerprint. */
	read(): Promise<{ files: Files; sigs: Sigs }>;
	/** Writes a file (creating folders) and returns its new fingerprint. */
	write(path: string, data: Uint8Array): Promise<string>;
	/** Deletes a file; a file that is already gone is fine. */
	remove(path: string): Promise<void>;
};

export type FolderBackend = {
	/** Stored with the link, to find the backend that can open it again. */
	readonly id: string;
	/** False in a browser without the File System Access API. */
	supported(): boolean;
	/** Lets the user pick a folder. Rejects with an `AbortError` when cancelled. */
	pick(): Promise<FolderLink>;
	/** The link for a stored `ref`. */
	open(ref: unknown): FolderLink;
};

const backends: FolderBackend[] = [];

/** Adds a backend. The first one that is `supported()` is used to pick folders. */
export function registerFolderBackend(b: FolderBackend) {
	backends.push(b);
}

/** The backend that picks new folders, or null when none works here. */
export function activeBackend(): FolderBackend | null {
	return backends.find((b) => b.supported()) ?? null;
}

export function backendById(id: string): FolderBackend | null {
	return backends.find((b) => b.id === id) ?? null;
}

/** What is saved about a link, apart from the project's files. */
export type FolderRecord = {
	backend: string;
	ref: unknown;
	/** Fingerprints at the last sync, as [path, fingerprint] pairs. */
	sigs: [string, string][];
};
