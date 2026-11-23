+++
title = "Layer: barcode"
description = "Barcodes and 2D codes made on the fly from text: Code 128, EAN, UPC, Code 39, ITF, Codabar, Code 93, QR, Data Matrix, Aztec and PDF417."
+++

One layer for every kind of code. The text is a [template](@/docs/expressions-templates.md), so every card can carry its own number, link or id, and `format` says what kind of code it becomes. The [`qr` layer](@/docs/layer-qr.md) is the same thing with `format` fixed to `qr`.

```json
{
  "id": "ean",
  "type": "barcode",
  "format": "ean13",
  "text": "{ean}",
  "box": { "x": 40, "y": 520, "w": 220, "h": 110 },
  "label": true
}
```

Plus the [fields every layer has](@/docs/layers.md).

| Field | Kind | Default | Meaning |
| --- | --- | --- | --- |
| `format` | enum | required | `qr`, `code128`, `ean13`, `ean8`, `upca`, `code39`, `itf`, `itf14`, `codabar`, `code93`, `datamatrix`, `aztec` or `pdf417`; or an expression that gives one. See [Formats](#formats) |
| `text` | text ([template](@/docs/expressions-templates.md)) | required | What the code holds |
| `box` | `{ x, y, w, h }`, all number | required | Position and size. `x`, `y` refer to the point chosen by `anchor`. See [Size](#size) |
| `color` | color | `#000000FF` | The dark bars or modules |
| `fill` | color | `#FFFFFFFF` | The area behind the code, quiet zone included. `#00000000` for none |
| `margin` | number | what the format asks for | Quiet zone in modules, 0 to 16. 1D codes get it left and right only |
| `check` | enum | `auto` | Check digits: `auto`, `add` or `none`. See [Check digits](#check-digits) |
| `label` | bool | on for `ean13`, `ean8`, `upca` and `itf14`, else off | 1D codes: draw the human-readable text under the bars. See [Label](#label) |
| `label_text` | text | the encoded text | 1D codes: text shown instead, with `{...}` placeholders |
| `label_color` | color | same as `color` | 1D codes: color of the text |
| `label_gap` | number | a quarter of `size` | 1D codes: space between bars and text, in pixels |
| `font` | name from `fonts` | `default` | 1D codes: font of the text |
| `size` | number | 8 modules, at most 30 % of the box height | 1D codes: text size in pixels. Without it the text also shrinks to fit the bars |
| `align` | `left`, `center`, `right` or `justify` | `center` | 1D codes: where the text sits under the bars; `justify` spreads the characters over the bars. EAN and UPC digits always sit under their bars |
| `level` | enum | `medium` | QR only: error correction `low`, `medium`, `quartile` or `high` |
| `mode` | enum | `auto` | QR only: how the text is cut into segments. See [QR segments](#qr-segments) |
| `style`, `eye`, `eye_color`, `logo`, `logo_src` | | | QR only: the [look of the code and its logo](@/docs/layer-qr.md#style). `style` also works for Data Matrix and Aztec |
| `ecc` | number | Aztec 23, PDF417 by size | Aztec: the least share of error correction in percent of the data, 0 to 90. PDF417: error correction level 0 to 8 (2 to 5 by default, lower if the text only just fits) |

A field that the chosen format does not read is warning 1115, so `"logo"` on a Code 128 does not go unnoticed. (With `format` an expression the layer cannot know and says nothing.)

## Formats

| `format` | Holds | Check | Quiet zone | Notes |
| --- | --- | --- | --- | --- |
| `code128` | all ASCII (0 to 127) | built in | 10 | Sets A, B and C are switched by yoshida for the fewest symbols, so digit runs take half the width. The usual choice for ids and codes with letters |
| `ean13` | 13 digits | digit 13 | 11 | Retail. Give 12 digits to have the 13th added, or all 13 to have them checked. Also ISBN-13 |
| `ean8` | 8 digits | digit 8 | 7 | Small retail items. 7 digits get the 8th added |
| `upca` | 12 digits | digit 12 | 9 | North American retail. 11 digits get the 12th added |
| `code39` | digits, `A-Z`, `-` `.` space `$` `/` `+` `%` | optional (`add`) | 10 | Lower case is read as capitals. Wide, but readable by every scanner |
| `itf` | digits, an even number of them | optional (`add`) | 10 | Interleaved 2 of 5. An odd count gets a leading 0 (hint 3213) |
| `itf14` | 14 digits | digit 14 | 10 | Cartons and cases (GTIN-14), with bearer bars. 13 digits get the 14th added |
| `codabar` | digits and `-` `$` `:` `/` `.` `+` | none | 10 | Libraries and labs. A start and a stop letter `A` to `D` frame the text; without them `A` and `B` are added |
| `code93` | digits, `A-Z`, `-` `.` space `$` `/` `+` `%` | built in (two) | 10 | Denser than Code 39 |
| `qr` | any text | built in | 4 | See [QR](@/docs/layer-qr.md) |
| `datamatrix` | any text | built in | 2 | Square symbols from 10 x 10 to 144 x 144 modules, at most 1558 codewords (about 3116 digits, or 1556 letters). Very small, good for tiny labels |
| `aztec` | any text | built in | 1 | Compact and full range, 15 to 151 modules. No large quiet zone needed |
| `pdf417` | any text | built in | 2 | Stacked rows, 3 to 90 rows of 1 to 30 columns, at most 929 codewords (about 1800 letters or 2700 digits). Wide: it is fitted into the box by width and height, so give it a wide box. Text, byte and numeric compaction are chosen per stretch of text |

Text beyond ASCII (umlauts, symbols) is read as UTF-8 by Data Matrix, Aztec and PDF417 readers as well as by QR. The 1D formats hold the characters listed above; anything else is error 3111 with a hint to a format that holds it.

## Size

The symbol is fitted into `box` with a **whole number of pixels per module**, so its edges stay sharp, and centred.

- **1D codes** use the box width for the bars (quiet zones included) and the whole box height for bars and label together. The `@code.bounds` of the layer are that width and the height of the box.
- **Square codes** (QR, Aztec, Data Matrix) fit the smaller of `w` and `h`.
- **PDF417** is fitted by width and height separately, so it fills a wide box.

The module count depends on the text, so a longer text makes smaller modules. A module narrower than one pixel is warning 3204. With a canvas `dpi`, a module narrower than 0.25 mm in print (QR: 0.5 mm) is warning 3208, and low contrast or a lighter code than its background is warning 3205.

## Label

1D codes can print their text under the bars:

```json
{ "id": "sku", "type": "barcode", "format": "code128", "text": "{sku}", "label": true,
  "font": "mono", "size": 16, "align": "justify", "label_color": "#444444",
  "box": { "x": 40, "y": 600, "w": 300, "h": 90 } }
```

- EAN-13, EAN-8, UPC-A and ITF-14 draw their digits the standard way: each digit under its own bars, the guard bars running down beside them. Their label is on unless you say `"label": false`.
- For the other formats, `"label": true` draws the text under the bars, aligned by `align`. `label_text` replaces it, for example with a name or a number with spaces in it.
- The text takes space from the box height. If the box is too short for bars and text, the label is left out (warning 3214); a label wider than the bars is warning 3214 too.
- The quiet zone has to hold the digits that EAN-13 and UPC-A print outside the bars (the first digit, and for UPC-A the last): do not set `margin` below 9.

## Check digits

`check` controls the check digit of the formats that have one:

- `auto` (default): EAN-13, EAN-8, UPC-A and ITF-14 add the check digit when the text is one digit short, and verify it when the text is complete. A wrong check digit is error 3112 and names the right one.
- `add`: does the same, and also appends the optional check of Code 39 (mod 43) and ITF (mod 10).
- `none`: leaves the digits exactly as given. EAN, UPC and ITF-14 then need all their digits, and are not verified.

Code 128, Code 93, QR, Data Matrix and Aztec have their own check data built in; `check` is ignored there (warning 1115).

## QR segments

QR codes cut the text into segments: numeric (3.3 bits per digit), alphanumeric (5.5 bits for digits, capitals and space `$%*+-./:`) and byte (8 bits). `mode` chooses:

- `auto`: the cut with the fewest bits. A code of digits, or a link with a long number in it, gets smaller. The default for `barcode`.
- `byte`: everything as bytes, as the `qr` layer always did. The default for `qr`, so existing cards stay exactly as they were.
- `numeric`, `alphanumeric`: one segment of that kind. Text that does not fit is error 3111.

## Limits

- Text that does not fit the symbol is error 3108 for QR (with its capacity) and 3111 for the other formats.
- Text with characters the format cannot hold, or the wrong number of digits, is error 3111; a wrong check digit or digit count for EAN, UPC and ITF-14 is error 3112.

## Exports

In PNG files the modules are exact pixels. In [SVG files and vector PDFs](@/docs/command-line.md#svg) the code stays a vector, and the label is glyphs. With `--scale` the module size is rounded at the export resolution, so the code stays sharp there too. [Effects](@/docs/effects.md), `rotate` and `opacity` work as on any layer.

## Reading values

`@code.bounds.*` and `@code.box.*`, `@code.text`, `@code.color`, `@code.fill`. See [Names and references](@/docs/expressions-names-and-references.md).

## Checking that a code reads

yoshida's tests decode every format back with [ZXing](https://github.com/zxing-cpp/zxing-cpp): `python3 scripts/barcode-roundtrip.py` renders each format to PNG, SVG and PDF and reads them again. Run it after changing anything about a code, and always test a printed code with the scanner it is meant for.

## Example: a card with an EAN and a link

```json
"params": {
  "ean": { "type": "text", "default": "400638133393" },
  "url": { "type": "text", "default": "https://example.com/" }
}
```

```json
{ "id": "ean", "type": "barcode", "format": "ean13", "text": "{ean}",
  "box": { "x": 40, "y": 560, "w": 190, "h": 100 } },
{ "id": "link", "type": "barcode", "format": "qr", "text": "{url}", "margin": 1,
  "box": { "x": 300, "y": 560, "w": 100, "h": 100 } }
```
