// The browser backend: the File System Access API (Chromium). A folder is a
// FileSystemDirectoryHandle, which the browser lets us keep in IndexedDB;
// after a reload the user only has to confirm access again with one click.
// Firefox and Safari have no folder picker, so there the backend reports
// itself unsupported and the editor falls back to .yoshida files.

import { skipDirs } from "../project.ts";
import {
	type FolderBackend,
	type FolderLink,
	type Permission,
	registerFolderBackend,
} from "./backend.ts";
import { type Sigs, signatureOf } from "./sync.ts";

type Dir = FileSystemDirectoryHandle;

// queryPermission / requestPermission are not in TypeScript's DOM types yet.
type WithPermission = Dir & {
	queryPermission?: (o: { mode: "readwrite" }) => Promise<Permission>;
	requestPermission?: (o: { mode: "readwrite" }) => Promise<Permission>;
};

type PickerWindow = Window & {
	showDirectoryPicker?: (o: {
		mode: "readwrite";
	}) => Promise<FileSystemDirectoryHandle>;
};

const sigOf = (f: File) => signatureOf(f.size, f.lastModified);

async function dirOf(root: Dir, path: string, create: boolean): Promise<Dir> {
	let dir = root;
	for (const p of path.split("/").slice(0, -1))
		dir = await dir.getDirectoryHandle(p, { create });
	return dir;
}

/** A link for a directory handle: also what the tests drive with a fake one. */
export function linkForHandle(handle: Dir): FolderLink {
	const root = handle as WithPermission;

	async function walk(visit: (path: string, file: File) => void) {
		const go = async (dir: Dir, prefix: string) => {
			for await (const [name, entry] of dir.entries()) {
				if (entry.kind === "directory") {
					if (!skipDirs.has(name)) await go(entry as Dir, `${prefix}${name}/`);
				} else
					visit(prefix + name, await (entry as FileSystemFileHandle).getFile());
			}
		};
		await go(handle, "");
	}

	return {
		backend: "browser",
		name: handle.name,
		ref: handle,

		async permission(request = false) {
			const mode = { mode: "readwrite" } as const;
			if (!root.queryPermission) return "granted";
			let p = await root.queryPermission(mode);
			if (p !== "granted" && request && root.requestPermission)
				p = await root.requestPermission(mode);
			return p;
		},

		async read() {
			const files = new Map<string, Uint8Array>();
			const sigs: Sigs = new Map();
			const pending: Promise<void>[] = [];
			await walk((path, file) => {
				sigs.set(path, sigOf(file));
				pending.push(
					file.arrayBuffer().then((b) => void files.set(path, new Uint8Array(b))),
				);
			});
			await Promise.all(pending);
			return { files, sigs };
		},

		async scan() {
			const sigs: Sigs = new Map();
			await walk((path, file) => void sigs.set(path, sigOf(file)));
			return sigs;
		},

		async readFiles(paths) {
			const files = new Map<string, Uint8Array>();
			for (const path of paths) {
				try {
					const dir = await dirOf(handle, path, false);
					const fh = await dir.getFileHandle(path.split("/").pop() as string);
					files.set(path, new Uint8Array(await (await fh.getFile()).arrayBuffer()));
				} catch (e) {
					if ((e as Error).name !== "NotFoundError") throw e;
				}
			}
			return files;
		},

		async write(path, data) {
			const dir = await dirOf(handle, path, true);
			const fh = await dir.getFileHandle(path.split("/").pop() as string, {
				create: true,
			});
			const w = await fh.createWritable();
			await w.write(data as Uint8Array<ArrayBuffer>);
			await w.close();
			return sigOf(await fh.getFile());
		},

		async remove(path) {
			try {
				const dir = await dirOf(handle, path, false);
				await dir.removeEntry(path.split("/").pop() as string);
			} catch (e) {
				if ((e as Error).name !== "NotFoundError") throw e;
			}
		},
	};
}

export const browserBackend: FolderBackend = {
	id: "browser",
	supported: () =>
		typeof window !== "undefined" &&
		typeof (window as PickerWindow).showDirectoryPicker === "function",
	async pick() {
		const pick = (window as PickerWindow).showDirectoryPicker;
		if (!pick) throw new Error("This browser cannot open folders for writing.");
		return linkForHandle(await pick.call(window, { mode: "readwrite" }));
	},
	open: (ref) => linkForHandle(ref as Dir),
};

registerFolderBackend(browserBackend);
