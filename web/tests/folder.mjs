// Checks linking a project to a folder: change detection, reconnecting and the
// browser backend, driven with an in-memory stand-in for a directory handle,
// and the desktop app's native backend, driven with a fake Tauri bridge.
//
//   node --experimental-strip-types tests/folder.mjs
import { activeBackend, backendById } from "../src/lib/folder/backend.ts";
// In the editor's order: native first, so it wins where both work.
import { createNativeBackend } from "../src/lib/folder/native.ts";
import { linkForHandle } from "../src/lib/folder/browser.ts";
import {
	diffFiles,
	diffSigs,
	findExternalChanges,
	planReconnect,
} from "../src/lib/folder/sync.ts";

let failed = 0;
const ok = (name, cond, extra = "") => {
	if (!cond) failed++;
	console.log(`${cond ? "PASS" : "FAIL"} ${name} ${extra}`);
};
const enc = new TextEncoder();
const bytes = (s) => enc.encode(s);
const dec = new TextDecoder();

// ---------------------------------------------------------------- fake folder

let clock = 1000;
const notFound = () => Object.assign(new Error("not found"), { name: "NotFoundError" });

function fakeDir(name = "proj") {
	const entries = new Map();
	const dir = {
		kind: "directory",
		name,
		entries,
	};
	dir.entries = async function* () {
		for (const [k, v] of entries) yield [k, v];
	};
	dir.getDirectoryHandle = async (n, o) => {
		let e = entries.get(n);
		if (!e) {
			if (!o?.create) throw notFound();
			e = fakeDir(n);
			entries.set(n, e);
		}
		return e;
	};
	dir.getFileHandle = async (n, o) => {
		let e = entries.get(n);
		if (!e) {
			if (!o?.create) throw notFound();
			e = fakeFile();
			entries.set(n, e);
		}
		return e;
	};
	dir.removeEntry = async (n) => {
		if (!entries.delete(n)) throw notFound();
	};
	return dir;
}

function fakeFile() {
	const f = { kind: "file", data: new Uint8Array(), modified: clock++ };
	f.getFile = async () => ({
		size: f.data.byteLength,
		lastModified: f.modified,
		arrayBuffer: async () => f.data.slice().buffer,
	});
	f.createWritable = async () => {
		let next = new Uint8Array();
		return {
			write: async (d) => void (next = new Uint8Array(d)),
			close: async () => {
				f.data = next;
				f.modified = clock++;
			},
		};
	};
	return f;
}

/** A file put there from outside, as a git checkout would. */
async function outside(root, path, text) {
	const parts = path.split("/");
	let d = root;
	for (const p of parts.slice(0, -1)) d = await d.getDirectoryHandle(p, { create: true });
	const f = await d.getFileHandle(parts.at(-1), { create: true });
	const w = await f.createWritable();
	await w.write(bytes(text));
	await w.close();
}

const project = (obj) => new Map(Object.entries(obj).map(([k, v]) => [k, bytes(v)]));

// ---------------------------------------------------------------- sync.ts

{
	const known = new Map([["a", "1:1"], ["b", "1:1"], ["c", "1:1"]]);
	const now = new Map([["a", "1:1"], ["b", "2:5"], ["d", "1:1"]]);
	const d = diffSigs(known, now);
	ok("diffSigs finds added, changed and removed", d.added.join() === "d" && d.changed.join() === "b" && d.removed.join() === "c");
	const e = diffFiles(project({ a: "x", b: "y", c: "z" }), project({ a: "x", b: "Y", d: "w" }));
	ok("diffFiles compares bytes", e.differ.join() === "b" && e.onlyMine.join() === "c" && e.onlyTheirs.join() === "d");
}

{
	const local = project({ a: "x", b: "y" });
	const sigs = new Map([["a", "1:1"], ["b", "1:2"]]);
	ok("reconnect: equal content is left alone", planReconnect(local, project({ a: "x", b: "y" }), sigs, null).kind === "same");
	const mine = project({ a: "x", b: "edited" });
	ok("reconnect: only the project changed pushes", planReconnect(mine, project({ a: "x", b: "y" }), sigs, sigs).kind === "push");
	const moved = new Map([["a", "1:1"], ["b", "1:9"]]);
	ok("reconnect: folder changed too asks", planReconnect(mine, project({ a: "x", b: "pulled" }), moved, sigs).kind === "ask");
	ok("reconnect: nothing stored asks", planReconnect(mine, project({ a: "x", b: "y" }), sigs, null).kind === "ask");
}

// ---------------------------------------------------------------- browser backend

{
	const root = fakeDir("cards");
	await outside(root, "yoshida.json", "{}");
	await outside(root, "designs/a.design.json", "{}");
	await outside(root, ".git/HEAD", "ref");
	await outside(root, "node_modules/x/y.js", "x");
	const link = linkForHandle(root);
	ok("the link carries the folder's name and backend", link.name === "cards" && link.backend === "browser");
	const { files, sigs } = await link.read();
	ok("read lists project files and skips .git and node_modules", [...files.keys()].sort().join() === "designs/a.design.json,yoshida.json");
	ok("read gives a fingerprint per file", sigs.size === 2 && sigs.get("yoshida.json") === (await link.scan()).get("yoshida.json"));

	const sig = await link.write("cards/new/001.cards.json", bytes("[]"));
	ok("write creates folders and returns the fingerprint", sig === (await link.scan()).get("cards/new/001.cards.json"));
	ok("readFiles reads some files and skips missing ones", (await link.readFiles(["yoshida.json", "nope.json"])).size === 1);
	await link.remove("cards/new/001.cards.json");
	await link.remove("cards/new/001.cards.json");
	ok("remove deletes and tolerates a missing file", !(await link.scan()).has("cards/new/001.cards.json"));

	ok("permission is granted when the browser has no prompt", (await link.permission()) === "granted");
	let asked = 0;
	root.queryPermission = async () => "prompt";
	root.requestPermission = async () => (asked++, "granted");
	ok("permission does not ask unless told to", (await link.permission()) === "prompt" && asked === 0);
	ok("permission asks with request", (await link.permission(true)) === "granted" && asked === 1);
}

// ---------------------------------------------------------------- detecting outside changes

{
	const root = fakeDir();
	await outside(root, "a.json", "one");
	await outside(root, "b.json", "two");
	const link = linkForHandle(root);
	let local = (await link.read()).files;
	let known = (await link.scan());

	ok("no change gives null", (await findExternalChanges(link, local, known)) === null);

	// Our own write is not an outside change.
	const mine = bytes("mine");
	local = new Map(local).set("a.json", mine);
	known = new Map(known).set("a.json", await link.write("a.json", mine));
	ok("our own write is not reported", (await findExternalChanges(link, local, known)) === null);

	// Touched without a change in content.
	await outside(root, "b.json", "two");
	const touched = await findExternalChanges(link, local, known);
	ok("a touched file with the same content is not a change", touched && touched.changed.length === 0);

	// A real edit, an added file and a deleted file.
	await outside(root, "b.json", "pulled");
	await outside(root, "new/c.json", "added");
	await root.removeEntry("a.json");
	const real = await findExternalChanges(link, local, known);
	ok("edited, added and deleted files are reported", real && real.changed.sort().join() === "a.json,b.json,new/c.json");
	ok("the new fingerprints are returned as the next baseline", real.sigs.has("new/c.json") && !real.sigs.has("a.json"));
	ok("the files read are the folder's", dec.decode((await link.readFiles(["b.json"])).get("b.json")) === "pulled");
}

// ---------------------------------------------------------------- native backend

/** The Rust commands of desktop/src-tauri over an in-memory folder. */
function fakeBridge(root = "/home/me/cards") {
	const disk = new Map(); // path -> { data, modified }
	const calls = [];
	const skip = new Set([".git", ".yoshida", "node_modules", "out"]);
	const check = (r, path) => {
		if (r !== root) throw "Forbidden: not a picked folder";
		if (path !== undefined && (path.startsWith("/") || path.split("/").includes("..")))
			throw "Forbidden: path leaves the folder";
	};
	const bridge = {
		disk,
		calls,
		picked: { root, name: root.split("/").pop() },
		async invoke(cmd, args, options) {
			calls.push(cmd);
			switch (cmd) {
				case "pick_folder":
					return bridge.picked;
				case "read_folder":
					check(args.root);
					return [...disk]
						.filter(([p]) => !p.split("/").some((x) => skip.has(x)))
						.map(([path, f]) => ({ path, size: f.data.byteLength, modified: f.modified }));
				case "read_file": {
					check(args.root, args.path);
					const f = disk.get(args.path);
					if (!f) throw `NotFound: ${args.path}`;
					return f.data.slice().buffer;
				}
				case "write_file": {
					const r = decodeURIComponent(options.headers["x-root"]);
					const path = decodeURIComponent(options.headers["x-path"]);
					check(r, path);
					const f = { data: new Uint8Array(args), modified: clock++ };
					disk.set(path, f);
					return { size: f.data.byteLength, modified: f.modified };
				}
				case "remove_file":
					check(args.root, args.path);
					disk.delete(args.path);
					return null;
			}
			throw `unknown command ${cmd}`;
		},
	};
	return bridge;
}

{
	const bridge = fakeBridge();
	bridge.disk.set("yoshida.json", { data: bytes("{}"), modified: clock++ });
	bridge.disk.set(".git/HEAD", { data: bytes("ref"), modified: clock++ });
	const backend = createNativeBackend(() => bridge);
	ok("native: supported only with a bridge", backend.supported() && !createNativeBackend(() => null).supported());

	const link = await backend.pick();
	ok("native: pick links the folder by its path", link.backend === "native" && link.name === "cards" && link.ref.root === "/home/me/cards");
	ok("native: permission is always granted", (await link.permission(true)) === "granted");
	const { files, sigs } = await link.read();
	ok("native: read lists project files", [...files.keys()].join() === "yoshida.json" && sigs.size === 1);

	const sig = await link.write("cards/new/001.cards.json", bytes("[]"));
	ok("native: write returns the fingerprint scan sees", sig === (await link.scan()).get("cards/new/001.cards.json"));
	ok("native: readFiles skips missing files", (await link.readFiles(["yoshida.json", "nope.json"])).size === 1);
	await link.remove("cards/new/001.cards.json");
	await link.remove("cards/new/001.cards.json");
	ok("native: remove tolerates a missing file", !(await link.scan()).has("cards/new/001.cards.json"));

	let err = "";
	await link.write("../escape.json", bytes("x")).catch((e) => (err = String(e)));
	ok("native: a path outside the folder is refused", err.startsWith("Forbidden"));

	const again = backend.open(structuredClone(link.ref));
	ok("native: a stored ref opens the same folder", dec.decode((await again.readFiles(["yoshida.json"])).get("yoshida.json")) === "{}");

	bridge.picked = null;
	const cancelled = await backend.pick().catch((e) => e);
	ok("native: cancelling the dialog is an AbortError", cancelled?.name === "AbortError");

	const changes = await findExternalChanges(again, (await again.read()).files, await again.scan());
	ok("native: change detection works over the bridge", changes === null);

	let used = "";
	await createNativeBackend(() => null).open({ root: "/x" }).read().catch((e) => (used = e.message));
	ok("native: a stored link outside the app fails when used", used.includes("desktop app"));
}

{
	// Which backend picks folders: the native one inside the app.
	globalThis.window = { showDirectoryPicker: async () => fakeDir() };
	ok("in Chromium the browser backend picks", activeBackend()?.id === "browser");
	globalThis.window.__TAURI_INTERNALS__ = fakeBridge();
	ok("in the desktop app the native backend picks", activeBackend()?.id === "native");
	ok("both are found by id", backendById("native") && backendById("browser"));
	delete globalThis.window;
}

if (failed) process.exit(1);
