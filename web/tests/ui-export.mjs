// End-to-end checks for exporting: the quick PNG / ZIP / PDF buttons, and
// the export dialog (one card, a design, all designs; PNG 8 and 16 bit,
// JPEG, WebP, SVG, vector and image PDF with and without crop marks; the
// quality slider; the resolution slider and the target dpi, the pixel limit,
// the trim size; its keyboard handling, the reasons Export is off and the
// remembered settings; the Render on server switch, with a mocked server;
// designs with and without a dpi, by the same dpi or the same scale).
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

/**
 * Sets the dialog: scope, formats (others unchecked) and the resolution
 * (opened first when it is folded for vector formats; null leaves it).
 */
async function choose(scope, formats, scale = 1) {
	await p.check(`${dialog} input[name=export-scope][value=${scope}]`);
	for (const f of ["PNG", "JPEG", "WebP", "SVG", "PDF"]) {
		const box = p.locator(`${dialog} label.opt:has-text("${f}") input`);
		if (await box.isDisabled()) continue;
		await box.setChecked(formats.includes(f));
	}
	if (scale === null) return;
	const change = p.locator(`${dialog} .fold button`);
	if (await change.count()) await change.click();
	await p.locator(`${dialog} input[aria-label=Resolution]`).fill(String(scale));
}

/** Picks the option labelled `text` in the dialog's dropdown `name`. */
async function pick(name, text) {
	await p.click(`${dialog} button[aria-label="${name}"]`);
	await p
		.locator(`${dialog} [role=listbox] [role=option]:has-text("${text}")`)
		.click();
}

const exportOff = async () =>
	(await p.getAttribute(`${dialog} button.primary`, "aria-disabled")) ===
	"true";

/** Runs the export with Enter (once the designs are measured) and waits for the download. */
const exportNow = () =>
	download(async () => {
		await p.waitForSelector(
			`${dialog} button.primary:not([aria-disabled="true"])`,
		);
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
await p.keyboard.press("Shift+Tab");
const afterShiftTab = await p.evaluate(
	(sel) => document.querySelector(sel)?.contains(document.activeElement),
	dialog,
);
await p.keyboard.press("Tab");
ok(
	"Shift+Tab from the first control stays in the dialog",
	afterShiftTab &&
		(await p.evaluate(
			() => document.activeElement?.getAttribute("name") === "export-scope",
		)),
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

// A target dpi: the dpi field sets the slider, and the slider the field.
const scaleSlider = p.locator(`${dialog} input[aria-label=Resolution]`);
const dpiField = p.locator(`${dialog} input[aria-label="Target dpi"]`);
const scaleShown = () => p.locator(`${dialog} output.k`).innerText();
const summary = () => p.locator(`${dialog} .summary`).innerText();
await openDialog();
await choose("card", ["JPEG"], 1);
const marks = await p.$$eval(`${dialog} .ticks span`, (els) =>
	els.map((e) => e.textContent).join(" "),
);
ok(
	"the slider's marks show dpi for a design with one",
	marks === "300 600 900 1200",
	marks,
);
const at1 = await dpiField.inputValue();
await dpiField.fill("600");
const at600 = `${await scaleSlider.inputValue()} ${await scaleShown()}`;
await dpiField.fill("450");
const at450 = `${await scaleShown()} ${/1125 × 1575 px/.test(await p.locator(dialog).innerText())}`;
ok(
	"the dpi field shows the design's dpi and sets the scale",
	at1 === "300" && at600 === "2 2x" && at450 === "1.5x true",
	`${at1} | ${at600} | ${at450}`,
);
f = await exportNow();
const size450 = jpegSize(f.data);
ok(
	"one card as JPEG at 450 dpi: 1.5x, and 450 dpi in the file",
	size450?.w === 1125 && size450?.h === 1575 && f.data.readUInt16BE(14) === 450,
	`${JSON.stringify(size450)} ${f.data.readUInt16BE(14)}`,
);
await openDialog();
const reopened = `${await dpiField.inputValue()} ${await scaleShown()}`;
await choose("card", ["PNG"], 1.5);
await scaleSlider.focus();
await p.keyboard.press("ArrowRight");
const arrow = await scaleShown();
const arrowDpi = await dpiField.inputValue();
await p.keyboard.press("PageUp");
const pageUp = await scaleShown();
await p.keyboard.press("PageDown");
const pageDown = await scaleShown();
ok(
	"the target dpi is kept; the slider moves in quarter steps, PageUp and PageDown to whole multiples",
	reopened === "450 1.5x" &&
		arrow === "1.75x" &&
		arrowDpi === "525" &&
		pageUp === "2x" &&
		pageDown === "1x",
	`${reopened} | ${arrow} ${arrowDpi} ${pageUp} ${pageDown}`,
);
await dpiField.fill("2000");
const rangeNote = await p.locator(`${dialog} #export-dpi-range`).innerText();
await dpiField.press("Tab");
ok(
	"a dpi beyond 4x says the range and comes back to 4x (1200 dpi)",
	/300 to 1200 dpi \(1x to 4x\)/.test(rangeNote) &&
		(await dpiField.inputValue()) === "1200" &&
		(await scaleShown()) === "4x",
	`${rangeNote} | ${await dpiField.inputValue()} ${await scaleShown()}`,
);
await dpiField.fill("150");
await dpiField.press("Enter");
const afterFirstEnter = `${await p.isVisible(dialog)} ${await dpiField.inputValue()}`;
await dpiField.fill("");
const emptyReason = await summary();
const emptyOff = await exportOff();
await dpiField.press("Tab");
ok(
	"Enter on a dpi out of range shows the nearest first; an empty field turns Export off",
	afterFirstEnter === "true 300" &&
		/Type a dpi from 300 to 1200 dpi/.test(emptyReason) &&
		emptyOff &&
		(await dpiField.inputValue()) === "300" &&
		!(await exportOff()),
	`${afterFirstEnter} | ${emptyReason} ${emptyOff}`,
);
ok(
	"a format's settings show only while it is chosen",
	(await p.locator(`${dialog} button[aria-label="Bit depth"]`).count()) === 1 &&
		(await p.locator(`${dialog} [aria-label="JPEG quality"]`).count()) === 0 &&
		/Small files, no transparency/.test(await p.locator(dialog).innerText()),
);
await p.locator(`${dialog} label.opt:has-text("PNG") input`).uncheck();
ok(
	"without a format Export is off and the footer says why",
	(await summary()) === "Choose at least one format." && (await exportOff()),
	await summary(),
);
await p.keyboard.press("Escape");

// A design as PNG + JPEG in one ZIP.
await openDialog();
await choose("design", ["PNG", "JPEG"]);
ok(
	"summary for two formats",
	(await summary()) === "80 files in poker-numbers.zip: 40 PNG, 40 JPEG",
	await summary(),
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
	await pick("Pages as", pages);
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
await p.click(`${dialog} button[aria-label="Bit depth"]`);
const option16 = p.locator(
	`${dialog} [role=listbox] [role=option]:has-text("16 bit")`,
);
const hint16 = await option16.innerText();
await option16.click();
await pick("Compression", "Smallest");
ok("16 bit says what it is for", /smoother gradients/.test(hint16), hint16);
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
		(await scaleSlider.inputValue()) === "1" &&
		(await p
			.locator(`${dialog} label.opt:has-text("PNG") input`)
			.setChecked(true)
			.then(() => p.innerText(`${dialog} button[aria-label="Bit depth"]`))) ===
			"16 bit",
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

// A large canvas: over 10000 pixels a side, the dialog says so, Export is
// off, and one click picks the highest resolution that fits.
await p.click(".project-btn");
await p.locator('.menu [role=menuitem]:has-text("board-game")').click();
await rendered();
await p.click('.progress button:has-text("Close")').catch(() => {});
await p
	.waitForSelector(".progress", { state: "detached", timeout: 5000 })
	.catch(() => {});
await openDialog();
const limitWarning = p.locator(`${dialog} .note.warn[role=alert]`);
await choose("card", ["PNG"], 2);
const at2 = await p.locator(`${dialog} .note.size`).innerText();
const limitMark = Number(
	await scaleSlider.evaluate((el) => el.style.getPropertyValue("--lim")),
);
await choose("card", ["PNG"], 3);
const warning = (await limitWarning.count())
	? await limitWarning.innerText()
	: "";
const at3 = await p.locator(`${dialog} .note.size`).innerText();
const overReason = await summary();
const blocked = await exportOff();
await limitWarning.locator('button:has-text("Use 2x")').click();
await p.waitForTimeout(50);
ok(
	"a 4961 × 3508 canvas at 3x is over the limit: Export is off, Use 2x fits it",
	/^14883 × 10524 px/.test(at3) &&
		/Over the limit of 10000 px on each side\. Use 2x, the largest that fits/.test(
			warning,
		) &&
		/Over the limit of 10000 px on each side: lower the resolution/.test(
			overReason,
		) &&
		blocked &&
		(await scaleShown()) === "2x" &&
		(await limitWarning.count()) === 0 &&
		!(await exportOff()),
	`${at3} | ${warning} | ${overReason} ${blocked} ${await scaleShown()}`,
);
ok(
	"after the fix the focus is on the slider",
	await p.evaluate(
		() => document.activeElement?.getAttribute("aria-label") === "Resolution",
	),
);
ok(
	"the size line has the printed size and the trim size inside the bleed",
	at2 === "9922 × 7016 px · prints at 420 × 297 mm, trim 414.1 × 291.1 mm",
	at2,
);
ok(
	"the slider marks the part of its track over the limit (from 10000 / 4961)",
	Math.abs(limitMark - (10000 / 4961 - 1) / 3) < 1e-9,
	String(limitMark),
);
await dpiField.fill("1000");
await dpiField.press("Tab");
const fixDpi = await limitWarning
	.locator("button")
	.innerText()
	.catch(() => "");
await limitWarning.locator("button").click();
ok(
	"targeting a dpi over the limit offers the highest slider stop (600 dpi)",
	fixDpi === "Use 600 dpi, the largest that fits" &&
		(await dpiField.inputValue()) === "600" &&
		!(await exportOff()),
	`${fixDpi} ${await dpiField.inputValue()}`,
);
await choose("card", ["SVG"], null);
const fold = await p.locator(`${dialog} .fold`).innerText();
await p.locator(`${dialog} .fold button`).click();
await p.waitForTimeout(50);
const sliderFocused = await p.evaluate(
	() => document.activeElement?.getAttribute("aria-label") === "Resolution",
);
await scaleSlider.fill("4");
ok(
	"vector files: the resolution folds into a line, Change opens it, and 4x has no limit",
	/SVG and vector PDF are sharp at any size; effects such as sharpen are drawn at 2x/.test(
		fold,
	) &&
		sliderFocused &&
		(await limitWarning.count()) === 0 &&
		!(await exportOff()) &&
		/only effects drawn as pixels/.test(await p.locator(dialog).innerText()),
	fold,
);
ok(
	"without a server the dialog has no Rendering section",
	(await p.locator(`${dialog} label.switch`).count()) === 0 &&
		(await p.locator(`${dialog} .where`).count()) === 0,
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
const whereNote = () => p.locator(`${dialog} .where .note`).innerText();
await openDialog();
ok(
	"with a server the dialog has the switch, off like the toolbar's",
	(await dialogSwitch.count()) === 1 &&
		!(await dialogSwitch.isChecked()) &&
		/Render on server/.test(
			await p.locator(`${dialog} label.switch`).innerText(),
		) &&
		/Everything renders in this browser/.test(await whereNote()),
);
await choose("design", ["PDF"], 2);
await pick("Pages as", "Vector");
await dialogSwitch.check();
ok(
	"switching it on in the dialog switches the toolbar too",
	(await toolbarSwitch.isChecked()) &&
		/The server renders everything/.test(await whereNote()),
	await whereNote(),
);
await p.check(`${dialog} input[name=export-scope][value=card]`);
ok(
	"one card still renders in the browser, and the dialog says so",
	/A single card always renders in this browser/.test(await whereNote()),
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
await openDialog();
await choose("design", ["PDF"]);
await dpiField.fill("450");
f = await exportNow();
ok(
	"with a target dpi the server gets its scale (450 dpi on a 300 dpi design: 1.5)",
	f.name.endsWith(".pdf") && renderBody?.scale === 1.5,
	JSON.stringify(renderBody?.scale),
);
await p
	.waitForSelector(".progress", { state: "detached", timeout: 10000 })
	.catch(() => {});
await toolbarSwitch.uncheck();
await openDialog();
ok(
	"the toolbar switch shows in the dialog",
	!(await dialogSwitch.isChecked()) &&
		/Everything renders in this browser/.test(await whereNote()),
);
await p.keyboard.press("Escape");

// A design without a dpi next to designs with one: All designs asks for the
// same dpi or the same scale and lists the designs, those that come out the
// same in one row.
await p.click(".project-btn");
await p.locator('.menu [role=menuitem]:has-text("New design")').click();
await p.locator('[role=dialog] button:has-text("Add design")').click();
await rendered();
await openDialog();
await choose("all", ["PNG"]);
await dpiField.fill("600");
await p.waitForSelector(`${dialog} .per-design`);
const tableRows = () =>
	p.$$eval(`${dialog} .per-design tr`, (trs) =>
		trs.map((tr) => [...tr.cells].map((c) => c.textContent.trim()).join(" ")),
	);
const sameDpi = p.locator(`${dialog} .mode label:has-text("same dpi") input`);
const sameScale = p.locator(
	`${dialog} .mode label:has-text("same scale") input`,
);
let rows = await tableRows();
const byDpiState = `${await sameDpi.isChecked()} ${await scaleShown()}`;
ok(
	"same dpi: the designs with a dpi reach 600 dpi, the one without stays at 1x",
	byDpiState === "true 1–2x" &&
		rows.length === 3 &&
		rows[0] === "Design Size Scale dpi" &&
		rows.some((r) => /^.+ and 3 more 1500 × 2100 px 2x 600$/.test(r)) &&
		rows.includes("New design 750 × 1050 px 1x no dpi"),
	`${byDpiState} ${JSON.stringify(rows)}`,
);
await sameScale.check();
rows = await tableRows();
ok(
	"same scale: every design at 2x, so their dpi differs",
	(await scaleShown()) === "2x" &&
		rows.length === 3 &&
		rows[0] === "Design Size dpi" &&
		rows.some((r) => /^.+ and 3 more 1500 × 2100 px 600$/.test(r)) &&
		rows.includes("New design 1500 × 2100 px no dpi"),
	JSON.stringify(rows),
);
await scaleSlider.fill("3");
ok(
	"moving the slider keeps the same scale",
	(await sameScale.isChecked()) && !(await sameDpi.isChecked()),
);
await p.keyboard.press("Escape");

ok("no page errors", logs.length === 0, logs.join(" | "));
await b.close();
console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
