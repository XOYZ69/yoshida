import assert from "node:assert/strict";
import {
	BARCODE_FORMATS,
	formatInfo,
	ignores,
	minWidth,
	quietZone,
} from "../src/lib/barcode.ts";

// Fields a format does not read, as the renderer's warning 1115 sees them.
assert.equal(ignores("qr", "level"), false);
assert.equal(ignores("code128", "level"), true);
assert.equal(ignores("code128", "logo"), true);
assert.equal(ignores("code128", "check"), true);
assert.equal(ignores("ean13", "check"), false);
assert.equal(ignores("ean13", "label"), false);
assert.equal(ignores("ean13", "style"), true);
assert.equal(ignores("qr", "label"), true);
assert.equal(ignores("qr", "font"), true);
assert.equal(ignores("datamatrix", "style"), false);
assert.equal(ignores("datamatrix", "eye"), true);
assert.equal(ignores("aztec", "ecc"), false);
assert.equal(ignores("qr", "ecc"), true);
assert.equal(ignores("code39", "check"), false);
assert.equal(ignores("somethingelse", "level"), false);

assert.equal(BARCODE_FORMATS.length, 13);
assert.equal(formatInfo("pdf417")?.soon, true);
assert.equal(quietZone("ean13"), 11);
assert.equal(quietZone("code128"), 10);

// 95 modules + 2 * 11 at 300 dpi: 3 px a module for 0.25 mm.
assert.equal(minWidth("ean13", 95, 11, 300).px, 117 * 3);
assert.equal(minWidth("qr", 29, 4, null).px, 37 * 2);
console.log("barcode fields ok");
