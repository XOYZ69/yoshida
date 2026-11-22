// Checks linking a project to a folder: change detection, reconnecting and the
// browser backend, driven with an in-memory stand-in for a directory handle.
//
//   node --experimental-strip-types tests/folder.mjs
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

if (failed) process.exit(1);
