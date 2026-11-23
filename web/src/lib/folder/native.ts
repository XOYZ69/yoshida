// The native backend: the desktop app (desktop/, Tauri 2). The Rust side has
// the commands below; a folder is a real path, picked with the system dialog,
// and there are no permission prompts. The bridge is the Tauri IPC, which is
// only there inside the app, so in a browser this backend is unsupported and
// the browser backend is used instead. It is registered first, so it wins in
// the app even where the webview also has a folder picker (WebView2).
//
// Commands (desktop/src-tauri/src/main.rs):
//   pick_folder()                       -> { root, name } | null (cancelled)
//   read_folder({ root })               -> [{ path, size, modified }]
//   read_file({ root, path })           -> raw bytes; rejects "NotFound: ..."
//   write_file(bytes, headers x-root, x-path) -> { size, modified }
//   remove_file({ root, path })         -> null (a missing file is fine)

import {
	type FolderBackend,
	type FolderLink,
	registerFolderBackend,
} from "./backend.ts";
import { type Sigs, signatureOf } from "./sync.ts";

/** The part of the Tauri IPC this backend uses; tests pass a fake. */
export type NativeBridge = {
	invoke(
		cmd: string,
		args?: Record<string, unknown> | Uint8Array,
		options?: { headers: Record<string, string> },
	): Promise<unknown>;
};

/** What is stored for a native link: the folder's absolute path. */
export type NativeRef = { root: string };

type Entry = { path: string; size: number; modified: number };
type Stat = { size: number; modified: number };

const sigOf = (s: Stat) => signatureOf(s.size, s.modified);

const nameOf = (root: string) =>
	root
		.replace(/[\\/]+$/, "")
		.split(/[\\/]/)
		.pop() || root;

const isNotFound = (e: unknown) => String(e).startsWith("NotFound");

const toBytes = (v: unknown): Uint8Array =>
	v instanceof Uint8Array
		? v
		: v instanceof ArrayBuffer
			? new Uint8Array(v)
			: new Uint8Array(v as number[]);

/** A link for a folder path: also what the tests drive with a fake bridge. */
export function linkForRoot(bridge: NativeBridge, root: string): FolderLink {
	const scan = async (): Promise<Sigs> => {
		const entries = (await bridge.invoke("read_folder", { root })) as Entry[];
		return new Map(entries.map((e) => [e.path, sigOf(e)]));
	};

	const readFiles = async (paths: string[]) => {
		const files = new Map<string, Uint8Array>();
		await Promise.all(
			paths.map(async (path) => {
				try {
					files.set(
						path,
						toBytes(await bridge.invoke("read_file", { root, path })),
					);
				} catch (e) {
					if (!isNotFound(e)) throw e;
				}
			}),
		);
		return files;
	};

	return {
		backend: "native",
		name: nameOf(root),
		ref: { root } satisfies NativeRef,
		// The app reads and writes the folder as the user; nothing to confirm.
		permission: async () => "granted",
		scan,
		readFiles,
		async read() {
			const sigs = await scan();
			const files = await readFiles([...sigs.keys()]);
			// A file deleted between the listing and the read is not there.
			for (const p of sigs.keys()) if (!files.has(p)) sigs.delete(p);
			return { files, sigs };
		},
		async write(path, data) {
			const stat = (await bridge.invoke("write_file", data, {
				headers: {
					"x-root": encodeURIComponent(root),
					"x-path": encodeURIComponent(path),
				},
			})) as Stat;
			return sigOf(stat);
		},
		async remove(path) {
			await bridge.invoke("remove_file", { root, path });
		},
	};
}

type TauriWindow = Window & { __TAURI_INTERNALS__?: Partial<NativeBridge> };

/** The Tauri IPC when running in the desktop app, otherwise null. */
export function tauriBridge(): NativeBridge | null {
	if (typeof window === "undefined") return null;
	const t = (window as TauriWindow).__TAURI_INTERNALS__;
	return typeof t?.invoke === "function" ? (t as NativeBridge) : null;
}

export function createNativeBackend(
	getBridge: () => NativeBridge | null,
): FolderBackend {
	const missing = () =>
		new Error("This folder can only be opened in the desktop app.");
	// Outside the app a stored native link still opens (for its name); using it fails.
	const absent: NativeBridge = { invoke: () => Promise.reject(missing()) };
	const bridge = () => getBridge() ?? absent;
	return {
		id: "native",
		supported: () => getBridge() !== null,
		async pick() {
			const b = getBridge();
			if (!b) throw missing();
			const picked = (await b.invoke("pick_folder")) as { root: string } | null;
			if (!picked)
				throw new DOMException("No folder was picked.", "AbortError");
			return linkForRoot(b, picked.root);
		},
		open: (ref) => linkForRoot(bridge(), (ref as NativeRef).root),
	};
}

export const nativeBackend = createNativeBackend(tauriBridge);

registerFolderBackend(nativeBackend);
