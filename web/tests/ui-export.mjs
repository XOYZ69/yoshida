// End-to-end checks for exporting: the quick PNG / ZIP / PDF buttons, and
// the export dialog (one card, a design, all designs; PNG 8 and 16 bit,
// JPEG, WebP, SVG, vector and image PDF with and without crop marks; the
// quality slider; resolution; its keyboard handling and remembered settings;
// the Render on server switch, with a mocked server).
//
//   node tests/ui-export.mjs [http://localhost:4173/]
import { readFile } from "node:fs/promises";
import { unzipSync } from "fflate";
import { chromium } from "playwright";

const base =
	process.argv[2] ?? process.env.BASE_URL ?? "http://localhost:4173/";

const b = await chromium.launch();
const ctx = await b.newContext({
	viewport: { width: 1500, height: 950 },
	acceptDownloads: true,
});
const p = await ctx.newPage();
const logs = [];
let failed = 0;
p.on("pageerror", (e) => logs.push(`pageerror: ${e.message}`));
p.on(
	"console",
	(m) =>
		m.type() === "error" &&
		!/api\/capabilities|status of 404|status of 502/.test(
			m.text() + m.location().url,
		) &&
		logs.push(`console: ${m.text()}`),
);
const ok = (name, cond, extra = "") => {
	if (!cond) failed++;
	console.log(`${cond ? "PASS" : "FAIL"} ${name} ${extra}`);
};
const rendered = () =>
	p.waitForFunction(
		() =>
			/rendered in/.test(document.querySelector(".status")?.textContent ?? ""),
		null,
		{ timeout: 30000 },
	);
const dialog = '[role=dialog][aria-labelledby="export-title"]';
const exportButton = '.exports button:has-text("Export…")';

/** Clicks and returns the downloaded file's name and bytes. */
async function download(click) {
	const [dl] = await Promise.all([
		p.waitForEvent("download", { timeout: 240000 }),
		click(),
	]);
	return {
		name: dl.suggestedFilename(),
		data: await readFile(await dl.path()),
	};
}

async function openDialog() {
	await p.click(exportButton);
	await p.waitForSelector(dialog);
}

/** Sets the dialog: scope, formats (others unchecked) and the resolution. */
async function choose(scope, formats, scale = 1) {
	await p.check(`${dialog} input[name=export-scope][value=${scope}]`);
	for (const f of ["PNG", "JPEG", "WebP", "SVG", "PDF"]) {
		const box = p.locator(`${dialog} label.opt:has-text("${f}") input`);
		if (await box.isDisabled()) continue;
		await box.setChecked(formats.includes(f));
	}
	await p.click(
		`${dialog} [aria-label=Resolution] button:has-text("${scale}x")`,
	);
}

/** Picks the option labelled `text` in the dialog's dropdown `name`. */
async function pick(name, text) {
	await p.click(`${dialog} button[aria-label="${name}"]`);
	await p
		.locator(`${dialog} [role=listbox] [role=option]:has-text("${text}")`)
		.click();
}

/** Runs the export with Enter and waits for the download. */
const exportNow = () =>
	download(async () => {
		await p.locator(`${dialog} input[name=export-scope]:checked`).focus();
		await p.keyboard.press("Enter");
	});

const pngInfo = (d) => ({
	png: d.subarray(1, 4).toString() === "PNG",
	w: d.readUInt32BE(16),
	h: d.readUInt32BE(20),
	depth: d[24],
});

/** Width and height from a JPEG's SOF marker. */
function jpegSize(d) {
	let i = 2;
	while (i < d.length) {
		const m = d[i + 1];
		const len = d.readUInt16BE(i + 2);
		if (m >= 0xc0 && m <= 0xc3)
			return { h: d.readUInt16BE(i + 5), w: d.readUInt16BE(i + 7) };
		i += 2 + len;
	}
	return null;
}

const mediaBoxes = (pdf) =>
	[
		...pdf.toString("latin1").matchAll(/\/MediaBox \[0 0 ([\d.]+) ([\d.]+)\]/g),
	].map((m) => [Number(m[1]), Number(m[2])]);
const pageCount = (pdf) =>
	Number(/\/Count (\d+)/.exec(pdf.toString("latin1"))?.[1] ?? 0);
const hasImages = (pdf) => pdf.toString("latin1").includes("/Subtype /Image");

await p.goto(base);
await rendered();
// The quick buttons work as before.
let f = await download(() => p.click('.exports button:has-text("PNG")'));
const cardId = f.name.replace(/\.png$/, "");
const quickPng = f.data;
let info = pngInfo(f.data);
ok(
	"quick PNG: the card at design size",
	info.png &&
		info.w === 750 &&
		info.h === 1050 &&
		info.depth === 8 &&
		f.name.endsWith(".png"),
	`${f.name} ${info.w}x${info.h}`,
);
f = await download(() => p.click('.exports button:has-text("ZIP")'));
let zip = unzipSync(f.data);
let names = Object.keys(zip);
ok(
	"quick ZIP: every card of the design as PNG",
	f.name === "poker-numbers.zip" &&
		names.length === 40 &&
		names.every((n) => /^numbers\/[^/]+\.png$/.test(n)),
	`${f.name} ${names.length}`,
);
f = await download(() => p.click('.exports button:has-text("PDF")'));
const quickPdf = f.data;
ok(
	"quick PDF: one image page per card, no crop marks without a bleed",
	pageCount(f.data) === 40 &&
		hasImages(f.data) &&
		mediaBoxes(f.data).every(([w, h]) => w === 180 && h === 252),
	`${f.name} ${JSON.stringify(mediaBoxes(f.data)[0])}`,
);
await p.waitForSelector(".progress", { state: "detached", timeout: 10000 });

// Keyboard: focus moves in, Escape closes and gives the focus back.
await openDialog();
ok(
	"the dialog takes the focus",
	await p.evaluate(
		(sel) => document.querySelector(sel)?.contains(document.activeElement),
		dialog,
	),
);
await p.keyboard.press("Escape");
await p.waitForSelector(dialog, { state: "detached" });
await p.waitForTimeout(100);
ok(
	"Escape closes it and the focus returns to the button",
	await p.evaluate(
		() => document.activeElement?.textContent?.trim() === "Export…",
	),
);

// Escape and Enter in an open dropdown or color picker stay in it.
const openList = async (name) => {
	await p.click(`${dialog} button[aria-label="${name}"]`);
	await p.waitForFunction(
		() => document.activeElement?.getAttribute("role") === "listbox",
	);
};
await openDialog();
await openList("Bit depth");
await p.keyboard.press("Escape");
const afterEscape = await p.isVisible(dialog);
await openList("Bit depth");
await p.keyboard.press("ArrowDown");
await p.keyboard.press("Enter");
const afterEnter = await p.isVisible(dialog);
const depth = await p.innerText(`${dialog} button[aria-label="Bit depth"]`);
await p.locator(`${dialog} label.opt:has-text("JPEG") input`).setChecked(true);
await p.click(`${dialog} button[aria-label^="JPEG background"]`);
const picker = `${dialog} [role=dialog][aria-label="Color picker"]`;
const pickerOpened = await p.isVisible(picker);
await p.keyboard.press("Escape");
ok(
	"Escape and Enter in a dropdown or the color picker do not close the dialog",
	afterEscape &&
		afterEnter &&
		depth === "16 bit" &&
		pickerOpened &&
		!(await p.isVisible(picker)) &&
		(await p.isVisible(dialog)),
	`${afterEscape} ${afterEnter} ${depth} ${pickerOpened}`,
);
await p.keyboard.press("Escape");
await p.waitForSelector(dialog, { state: "detached" });

// One card as JPEG at 2x.
await openDialog();
await choose("card", ["JPEG"], 2);
ok(
	"the dialog shows the pixel size",
	/1500 × 2100 px/.test(await p.locator(dialog).innerText()),
);
ok(
	"the summary names the one file",
	(await p.locator(`${dialog} .summary`).innerText()) ===
		`1 file: ${cardId}.jpg`,
	await p.locator(`${dialog} .summary`).innerText(),
);
f = await exportNow();
const size = jpegSize(f.data);
ok(
	"one card as JPEG at 2x",
	f.name === `${cardId}.jpg` &&
		f.data[0] === 0xff &&
		f.data[1] === 0xd8 &&
		f.data[2] === 0xff &&
		size?.w === 1500 &&
		size?.h === 2100,
	`${f.name} ${JSON.stringify(size)}`,
);
ok(
	"the JPEG keeps the print size (600 dpi at 2x)",
	f.data[13] === 1 && f.data.readUInt16BE(14) === 600,
	`${f.data[13]} ${f.data.readUInt16BE(14)}`,
);

// A design as PNG + JPEG in one ZIP.
await openDialog();
await choose("design", ["PNG", "JPEG"]);
ok(
	"summary for two formats",
	(await p.locator(`${dialog} .summary`).innerText()) ===
		"40 cards × 2 formats, 80 files in poker-numbers.zip",
	await p.locator(`${dialog} .summary`).innerText(),
);
f = await exportNow();
names = Object.keys(unzipSync(f.data));
ok(
	"a design as PNG and JPEG",
	f.name === "poker-numbers.zip" &&
		names.length === 80 &&
		names.filter((n) => /^numbers\/[^/]+\.png$/.test(n)).length === 40 &&
		names.filter((n) => /^numbers\/[^/]+\.jpg$/.test(n)).length === 40,
	`${names.length}`,
);

// All designs.
await openDialog();
await choose("all", ["PNG", "PDF"]);
f = await exportNow();
zip = unzipSync(f.data);
names = Object.keys(zip);
const pngs = names.filter((n) => n.endsWith(".png"));
const pdfs = names.filter((n) => n.endsWith(".pdf"));
const folders = new Set(pngs.map((n) => n.split("/")[0]));
ok(
	"all designs: a folder of PNGs and a PDF per design",
	f.name === "poker.zip" &&
		pngs.length === 55 &&
		folders.size === pdfs.length &&
		pdfs.every((n) => folders.has(n.replace(/\.pdf$/, ""))) &&
		pageCount(Buffer.from(zip["numbers.pdf"])) === 40,
	`${pngs.length} PNG, ${[...folders].join(" ")}, ${pdfs.join(" ")}`,
);

// PDF: vector pages by default, crop marks Off and On, or image pages.
const pdfWith = async (marks, pages = "Vector") => {
	await openDialog();
	await choose("design", ["PDF"]);
	await pick("Crop marks", marks);
	await pick("Pages", pages);
	return (await exportNow()).data;
};
const off = await pdfWith("Off");
const on = await pdfWith("On");
const offText = off.toString("latin1");
const onText = on.toString("latin1");
ok(
	"vector PDF of a design: 40 pages of paths and glyphs, no images",
	offText.startsWith("%PDF-1.4") &&
		/\/Count 40\b/.test(offText) &&
		!hasImages(off) &&
		offText.includes("/Subtype /Form"),
	`${off.length} bytes`,
);
ok(
	"vector PDF pages: 180 x 252 pt, 219.84 x 291.84 pt with crop marks",
	(offText.match(/\/MediaBox \[0 0 180\.0000 252\.0000\]/g) ?? []).length ===
		40 &&
		(onText.match(/\/MediaBox \[0 0 219\.8400 291\.8400\]/g) ?? []).length ===
			40,
	`${JSON.stringify(mediaBoxes(off)[0])} ${JSON.stringify(mediaBoxes(on)[0])}`,
);
ok(
	"the vector PDF is under a fifth of the image PDF",
	off.length < quickPdf.length / 5,
	`${off.length} vs ${quickPdf.length} bytes`,
);
const img = await pdfWith("On", "Image");
ok(
	"Pages: Image gives image pages of the same size",
	pageCount(img) === 40 &&
		hasImages(img) &&
		mediaBoxes(img).every(
			([w, h]) => Math.abs(w - 219.84) < 0.01 && Math.abs(h - 291.84) < 0.01,
		),
	JSON.stringify(mediaBoxes(img)[0]),
);

// 16-bit PNG at 2x, with the smallest compression.
await openDialog();
await choose("card", ["PNG"], 2);
await pick("Bit depth", "16 bit");
await pick("Compression", "Smallest");
ok(
	"the 16 bit hint is shown",
	/PNG has no 10 bit mode/.test(await p.locator(dialog).innerText()),
);
f = await exportNow();
info = pngInfo(f.data);
ok(
	"16-bit PNG at 2x",
	info.png && info.depth === 16 && info.w === 1500 && info.h === 2100,
	`${f.name} depth ${info.depth} ${info.w}x${info.h}`,
);

// WebP (Chromium can encode it).
await openDialog();
await p.waitForFunction(
	(sel) =>
		!document
			.querySelector(sel)
			?.innerText.includes("Checking whether this browser can write WebP"),
	dialog,
);
const webpBox = p.locator(`${dialog} label.opt:has-text("WebP") input`);
if (await webpBox.isDisabled()) ok("WebP is offered in Chromium", false);
else {
	await choose("card", ["WebP"]);
	await p
		.locator(`${dialog} label:has-text("Lossless") input`)
		.setChecked(true);
	f = await exportNow();
	const head = f.data.subarray(0, 16).toString("latin1");
	ok(
		"one card as lossless WebP",
		f.name === `${cardId}.webp` &&
			head.startsWith("RIFF") &&
			head.slice(8, 12) === "WEBP" &&
			f.data.includes(Buffer.from("VP8L")),
		`${f.name} ${f.data.length} bytes`,
	);
}

// The settings are kept after a reload.
await p.reload();
await rendered();
await openDialog();
ok(
	"settings are kept after a reload",
	(await p.isChecked(`${dialog} input[name=export-scope][value=card]`)) &&
		(await p.isChecked(`${dialog} label.opt:has-text("WebP") input`)) &&
		!(await p.isChecked(`${dialog} label.opt:has-text("PNG") input`)) &&
		(await p.isChecked(`${dialog} label:has-text("Lossless") input`)) &&
		(await p.innerText(`${dialog} button[aria-label="Bit depth"]`)) ===
			"16 bit" &&
		(await p.getAttribute(
			`${dialog} [aria-label=Resolution] button:has-text("1x")`,
			"aria-checked",
		)) === "true",
);
await p.keyboard.press("Escape");

// The quick PNG button still writes an 8-bit PNG at design size.
f = await download(() => p.click('.exports button:has-text("PNG")'));
info = pngInfo(f.data);
ok(
	"the quick PNG ignores the dialog's settings",
	info.depth === 8 && info.w === 750,
	`depth ${info.depth} ${info.w}`,
);
await p.waitForSelector(".progress", { state: "detached", timeout: 10000 });

// One card as SVG, drawn by the browser and compared with its PNG.
await openDialog();
await choose("card", ["SVG"]);
f = await exportNow();
const svg = f.data.toString("utf8");
ok(
	"one card as SVG",
	f.name === `${cardId}.svg` &&
		svg.startsWith('<?xml version="1.0" encoding="UTF-8"?>') &&
		svg.includes("<svg ") &&
		svg.includes('width="63.5mm" height="88.9mm" viewBox="0 0 750 1050"'),
	`${f.name} ${f.data.length} bytes`,
);
ok(
	"the SVG parses",
	await p.evaluate(
		(text) =>
			!new DOMParser()
				.parseFromString(text, "image/svg+xml")
				.querySelector("parsererror"),
		svg,
	),
);
const diff = await p.evaluate(
	async ([text, png64]) => {
		const [w, h] = [750, 1050];
		const pixels = async (blob) => {
			const img = new Image();
			img.src = URL.createObjectURL(blob);
			await img.decode();
			const c = document.createElement("canvas");
			c.width = w;
			c.height = h;
			const g = c.getContext("2d");
			g.fillStyle = "#fff";
			g.fillRect(0, 0, w, h);
			g.drawImage(img, 0, 0, w, h);
			return g.getImageData(0, 0, w, h).data;
		};
		const a = await pixels(new Blob([text], { type: "image/svg+xml" }));
		const png = Uint8Array.from(atob(png64), (ch) => ch.charCodeAt(0));
		const b = await pixels(new Blob([png], { type: "image/png" }));
		// Mean difference per channel, and the worst 16 x 16 tile.
		const [tw, th] = [Math.floor(w / 16), Math.floor(h / 16)];
		const tiles = new Float64Array(tw * th);
		let sum = 0;
		for (let y = 0; y < h; y++)
			for (let x = 0; x < w; x++) {
				const i = (y * w + x) * 4;
				const d =
					Math.abs(a[i] - b[i]) +
					Math.abs(a[i + 1] - b[i + 1]) +
					Math.abs(a[i + 2] - b[i + 2]);
				sum += d;
				if (x >> 4 < tw && y >> 4 < th) tiles[(y >> 4) * tw + (x >> 4)] += d;
			}
		return {
			mean: sum / (w * h * 3),
			worst: Math.max(...tiles) / (16 * 16 * 3),
		};
	},
	[svg, quickPng.toString("base64")],
);
ok(
	"the SVG looks like the PNG (mean < 1, worst 16 × 16 tile < 20)",
	diff.mean < 1 && diff.worst < 20,
	`mean ${diff.mean.toFixed(3)} worst ${diff.worst.toFixed(2)}`,
);

// A design as SVG files in one ZIP.
await openDialog();
await choose("design", ["SVG"]);
f = await exportNow();
names = Object.keys(unzipSync(f.data));
ok(
	"a design as SVG",
	f.name === "poker-numbers.zip" &&
		names.length === 40 &&
		names.every((n) => /^numbers\/[^/]+\.svg$/.test(n)),
	`${names.length}`,
);

// Quality: a slider in steps of 5, and a field for any value.
await openDialog();
await choose("card", ["JPEG"]);
const jpegRange = p.locator(
	`${dialog} input[type=range][aria-label="JPEG quality"]`,
);
const jpegField = p.locator(
	`${dialog} input[type=number][aria-label="JPEG quality, exact value"]`,
);
await jpegField.fill("90");
await jpegField.dispatchEvent("change");
await jpegRange.focus();
await p.keyboard.press("ArrowLeft");
await p.keyboard.press("ArrowLeft");
const afterKeys = await jpegField.inputValue();
await jpegField.fill("92");
await jpegField.dispatchEvent("change");
const exact = await jpegField.inputValue();
const slider = await jpegRange.inputValue();
ok(
	"JPEG quality: the slider moves in steps of 5, the field takes any value",
	afterKeys === "80" && exact === "92" && slider === "90",
	`${afterKeys} ${exact} ${slider}`,
);
await p.keyboard.press("Escape");

// A large canvas: resolutions over 10000 pixels a side are disabled.
await p.click(".project-btn");
await p.locator('.menu [role=menuitem]:has-text("board-game")').click();
await rendered();
await p.click('.progress button:has-text("Close")').catch(() => {});
await p
	.waitForSelector(".progress", { state: "detached", timeout: 5000 })
	.catch(() => {});
await openDialog();
const scalesDisabled = () =>
	p.$$eval(`${dialog} [aria-label=Resolution] button`, (bs) =>
		JSON.stringify(bs.map((x) => x.disabled)),
	);
await choose("card", ["PNG"], 2);
let disabled = await scalesDisabled();
ok(
	"3x and 4x are disabled for a 4961 × 3508 canvas",
	disabled === "[false,false,true,true]" &&
		/9922 × 7016 px/.test(await p.locator(dialog).innerText()),
	disabled,
);
await choose("card", ["SVG"], 2);
disabled = await scalesDisabled();
ok(
	"vector files have no pixel limit: every resolution is offered",
	disabled === "[false,false,false,false]" &&
		/Vector files use it only for the parts that stay pixels/.test(
			await p.locator(dialog).innerText(),
		),
	disabled,
);
ok(
	"without a server the dialog has no Render on server switch",
	(await p.locator(`${dialog} label.switch`).count()) === 0 &&
		/Everything is rendered in this browser/.test(
			await p.locator(dialog).innerText(),
		),
);
await p.keyboard.press("Escape");

// A server that renders (mocked): the dialog has the Render on server switch,
// the same setting as the toolbar switch, and whole designs go to the server.
let renderBody = null;
await p.route("**/api/capabilities", (r) =>
	r.fulfill({
		contentType: "application/json",
		body: JSON.stringify({
			version: "test",
			format: 1,
			render: true,
			max_cards: 5000,
			max_body_mb: 64,
		}),
	}),
);
await p.route("**/api/render/progress*", (r) =>
	r.fulfill({ contentType: "application/json", body: '{"found":false}' }),
);
await p.route("**/api/render", (r) => {
	renderBody = JSON.parse(r.request().postData() ?? "{}");
	r.fulfill({ contentType: "application/pdf", body: "%PDF-1.7\n%%EOF\n" });
});
await p.goto(base);
await rendered();
const toolbarSwitch = p.locator('.exports label.switch input[role="switch"]');
const dialogSwitch = p.locator(`${dialog} label.switch input[role="switch"]`);
const whereNote = () =>
	p
		.locator(`${dialog} fieldset:has(legend:text-is("Where")) .note`)
		.innerText();
await openDialog();
ok(
	"with a server the dialog has the switch, off like the toolbar's",
	(await dialogSwitch.count()) === 1 &&
		!(await dialogSwitch.isChecked()) &&
		/Render on server/.test(
			await p.locator(`${dialog} label.switch`).innerText(),
		) &&
		/Everything is rendered in this browser/.test(await whereNote()),
);
await choose("design", ["PDF"], 2);
await pick("Pages", "Vector");
await dialogSwitch.check();
ok(
	"switching it on in the dialog switches the toolbar too",
	(await toolbarSwitch.isChecked()) &&
		/Rendered on the server/.test(await whereNote()),
	await whereNote(),
);
await p.check(`${dialog} input[name=export-scope][value=card]`);
ok(
	"one card still renders in the browser, and the dialog says so",
	/One card always renders in this browser/.test(await whereNote()),
	await whereNote(),
);
await p.check(`${dialog} input[name=export-scope][value=design]`);
f = await exportNow();
ok(
	"the design's PDF is rendered on the server",
	f.name.endsWith(".pdf") &&
		renderBody?.format === "pdf" &&
		renderBody?.vector === true &&
		renderBody?.scale === 2,
	`${f.name} ${JSON.stringify({ format: renderBody?.format, vector: renderBody?.vector, scale: renderBody?.scale })}`,
);
await p
	.waitForSelector(".progress", { state: "detached", timeout: 10000 })
	.catch(() => {});
await toolbarSwitch.uncheck();
await openDialog();
ok(
	"the toolbar switch shows in the dialog",
	!(await dialogSwitch.isChecked()) &&
		/Everything is rendered in this browser/.test(await whereNote()),
);
await p.keyboard.press("Escape");

ok("no page errors", logs.length === 0, logs.join(" | "));
await b.close();
console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
