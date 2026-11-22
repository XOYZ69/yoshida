// End-to-end checks for linking a project to a folder. Chromium cannot show
// the folder picker under automation, so showDirectoryPicker is replaced by
// a function that returns a folder in the browser's private file system
// (the same kind of handle): the editor cannot tell the difference.
//
//   node tests/ui-folder.mjs [http://localhost:4173/]
import { readFile } from "node:fs/promises";
import path from "node:path";
import { chromium } from "playwright";

const base =
	process.argv[2] ?? process.env.BASE_URL ?? "http://localhost:4173/";
let failed = 0;
const b = await chromium.launch();
const ctx = await b.newContext({ viewport: { width: 1440, height: 900 } });
await ctx.addInitScript(() => {
	// Lets a test make the browser forget the permission, as it does between visits.
	const proto = window.FileSystemDirectoryHandle?.prototype;
	if (proto) {
		proto.queryPermission = async () => localStorage.getItem("test-permission") ?? "granted";
		proto.requestPermission = async () => {
			localStorage.setItem("test-permission", "granted");
			return "granted";
		};
	}
	window.showDirectoryPicker = async () => {
		const root = await navigator.storage.getDirectory();
		return root.getDirectoryHandle("linked-test", { create: true });
	};
});
const p = await ctx.newPage();
p.on("pageerror", (e) => console.log("pageerror", e.message));
const ok = (n, c, x = "") => {
	if (!c) failed++;
	console.log(`${c ? "PASS" : "FAIL"} ${n} ${x}`);
};
const rendered = () =>
	p.waitForFunction(
		() =>
			/rendered in/.test(document.querySelector(".status")?.textContent ?? ""),
		null,
		{ timeout: 30000 },
	);
const menu = async (label) => {
	await p.click(".project-btn");
	await p.click(`[role="menuitem"]:has-text("${label}")`);
};
// Files of the linked folder, as paths, from outside the editor's own code.
const disk = () =>
	p.evaluate(async () => {
		const root = await (await navigator.storage.getDirectory()).getDirectoryHandle("linked-test");
		const out = {};
		const walk = async (dir, prefix) => {
			for await (const [name, e] of dir.entries()) {
				if (e.kind === "directory") await walk(e, `${prefix}${name}/`);
				else out[prefix + name] = await (await e.getFile()).text();
			}
		};
		await walk(root, "");
		return out;
	});
const putOnDisk = (file, text) =>
	p.evaluate(
		async ([file, text]) => {
			const root = await (await navigator.storage.getDirectory()).getDirectoryHandle("linked-test");
			const parts = file.split("/");
			let d = root;
			for (const s of parts.slice(0, -1)) d = await d.getDirectoryHandle(s, { create: true });
			const w = await (await d.getFileHandle(parts.at(-1), { create: true })).createWritable();
			await w.write(text);
			await w.close();
		},
		[file, text],
	);
const waitDisk = async (test, ms = 10000) => {
	const end = Date.now() + ms;
	while (Date.now() < end) {
		if (test(await disk())) return;
		await p.waitForTimeout(250);
	}
	throw new Error("the folder never got the expected content");
};
const chip = () => p.textContent('[data-testid="folder-chip"]').catch(() => null);
const waitChip = (re) =>
	p.waitForFunction(
		(src) => new RegExp(src).test(document.querySelector('[data-testid="folder-chip"]')?.textContent ?? ""),
		re.source,
		{ timeout: 15000 },
	);

await p.goto(base);
await p.evaluate(async () => {
	const root = await navigator.storage.getDirectory();
	await root.removeEntry("linked-test", { recursive: true }).catch(() => {});
});
await p.goto(base);
await rendered();
ok("an unlinked project shows no folder chip", (await chip()) === null);

// Link the open project to an empty folder.
await menu("Link to folder");
await waitChip(/in sync/);
const first = await disk();
ok("linking writes the project's files", "yoshida.json" in first && Object.keys(first).length > 5, Object.keys(first).length);
ok("the chip names the folder", /linked-test/.test(await chip()));

// A change in the editor is written without pressing save.
await p.click('.left .tabs button:has-text("Files")');
const png = await readFile(
	path.join(import.meta.dirname, "fixtures/editor-test/assets/images/cards/spell.png"),
).catch(() => Buffer.from("not really a png"));
const chooser = p.waitForEvent("filechooser");
await p.click('.left .bar button[aria-label="Upload files"]');
await (await chooser).setFiles([{ name: "auto-written.png", mimeType: "image/png", buffer: png }]);
await waitDisk((d) => "auto-written.png" in d);
ok("an upload is written to the folder by itself", true);
await waitChip(/in sync/);

// Our own writes are not reported as outside changes.
await p.evaluate(() => window.dispatchEvent(new Event("focus")));
await p.waitForTimeout(800);
ok("no notice after our own write", (await p.$('[data-testid="folder-notice"]')) === null);

// A change from outside (a git pull) is offered for reload.
const manifest = JSON.parse(first["yoshida.json"]);
manifest.name = "Changed outside";
await putOnDisk("yoshida.json", `${JSON.stringify(manifest, null, 2)}\n`);
await p.evaluate(() => window.dispatchEvent(new Event("focus")));
await p.waitForSelector('[data-testid="folder-notice"]', { timeout: 10000 });
const note = await p.textContent('[data-testid="folder-notice"]');
ok("an outside change is reported with its file", /changed outside the editor/.test(note) && /yoshida\.json/.test(note), note);
ok("the chip asks for attention", /needs attention/.test(await chip()));

await p.click('[data-testid="folder-notice"] button:has-text("Reload from folder")');
await p.waitForSelector('[data-testid="folder-notice"]', { state: "detached" });
await waitChip(/in sync/);
await p.evaluate(() => window.dispatchEvent(new Event("focus")));
await p.waitForTimeout(800);
ok("after a reload the folder is the new baseline", (await p.$('[data-testid="folder-notice"]')) === null);

// Keeping the project's version writes it back over the outside change.
await putOnDisk("yoshida.json", `${JSON.stringify({ ...manifest, name: "Second outside edit" }, null, 2)}\n`);
await p.evaluate(() => window.dispatchEvent(new Event("focus")));
await p.waitForSelector('[data-testid="folder-notice"]', { timeout: 10000 });
await p.click('[data-testid="folder-notice"] button:has-text("Keep project version")');
await waitDisk((d) => !d["yoshida.json"].includes("Second outside edit"));
ok("keeping the project version overwrites the outside change", true);

// The link survives a reload of the page.
await p.waitForTimeout(800);
await p.reload();
await rendered();
await waitChip(/linked-test · (in sync|writing)/);
ok("the folder is linked again after a reload", true);

// After a visit that lost the permission, one click brings the link back.
await p.evaluate(() => localStorage.setItem("test-permission", "prompt"));
await p.reload();
await rendered();
await p.waitForSelector('[data-testid="folder-notice"]');
ok("a lost permission is asked for again", /permission/.test(await p.textContent('[data-testid="folder-notice"]')));
await p.click('[data-testid="folder-notice"] button:has-text("Allow access")');
await p.waitForSelector('[data-testid="folder-notice"]', { state: "detached" });
await waitChip(/in sync/);
ok("allowing access reconnects without a prompt about unchanged files", true);

// A folder that changed while the project was closed asks before replacing anything.
await p.evaluate(() => localStorage.setItem("test-permission", "prompt"));
await putOnDisk("yoshida.json", `${JSON.stringify({ ...manifest, name: "Edited while closed" }, null, 2)}\n`);
await p.reload();
await rendered();
await p.click('[data-testid="folder-notice"] button:has-text("Allow access")');
await p.waitForFunction(() => /differs from this project/.test(document.querySelector('[data-testid="folder-notice"]')?.textContent ?? ""));
ok("a folder changed while closed is a conflict", true);
await p.click('[data-testid="folder-notice"] button:has-text("Use folder version")');
await p.waitForSelector('[data-testid="folder-notice"]', { state: "detached" });
await waitChip(/in sync/);
ok("the folder's version can be taken", /Edited while closed/.test((await disk())["yoshida.json"]));

// Unlinking stops the writes and keeps the project.
await menu("Unlink from");
await p.waitForFunction(() => !document.querySelector('[data-testid="folder-chip"]'));
const before = Object.keys(await disk()).length;
await p.click('.left .tabs button:has-text("Files")');
const chooser2 = p.waitForEvent("filechooser");
await p.click('.left .bar button[aria-label="Upload files"]');
await (await chooser2).setFiles([{ name: "after-unlink.png", mimeType: "image/png", buffer: png }]);
await p.waitForSelector('.left li[data-path$="after-unlink.png"]');
await p.waitForTimeout(1500);
ok("after unlinking nothing is written to the folder", Object.keys(await disk()).length === before);

await b.close();
if (failed) process.exit(1);
