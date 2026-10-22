+++
title = "WASM Interface"
description = "How the editor talks to the WASM core."
+++

The core is built as `yoshida.wasm` (`zig build wasm`, target `wasm32-freestanding`, `ReleaseSmall`) and copied to the editor's `public/` folder. The editor runs it in a Web Worker (`web/src/lib/worker.ts`, wrapped by `web/src/lib/engine.ts`). You can use the module from your own JavaScript too.

## Exports

| Export                                            | Purpose                                                      |
| ------------------------------------------------- | ------------------------------------------------------------ |
| `alloc(len)`, `free(ptr, len)`                    | Allocate and free memory in the module                       |
| `vfs_put(path_ptr, path_len, data_ptr, data_len)` | Put a file into the module's virtual file system             |
| `vfs_remove(path_ptr, path_len)`                  | Remove a file                                                |
| `vfs_clear()`                                     | Remove all files                                             |
| `request(ptr, len)`                               | Send a JSON request; returns 0 on success, non-zero on error |
| `result_json_ptr()`, `result_json_len()`          | Read the JSON answer                                         |
| `result_bin_ptr()`, `result_bin_len()`            | Read the binary answer (an image, an SVG or a PDF file)      |

Typical use: put the project files with `vfs_put`, call `request` with a UTF-8 JSON string, read the JSON (and the binary, for renders) from the result pointers.

## Requests

```json
{ "op": "info" }
{ "op": "check" }
{ "op": "render", "set": "name", "card": 0, "date": "2026-10-07",
  "preview": true, "format": "rgba", "layout": true }
{ "op": "svg", "set": "name", "card": 0, "date": "2026-10-07", "scale": 2 }
{ "op": "check_cards", "set": "name", "date": "2026-10-07" }
{ "op": "pdf", "set": "name", "date": "2026-10-07", "crop_marks": false,
  "vector": false }
{ "op": "scope", "set": "name", "path": "/layers/3/fill" }
{ "op": "eval", "set": "name", "card": 0, "date": "2026-10-07",
  "path": "/layers/3/fill", "src": "kind == 'dare' ? c_dare : c_plain" }
```

### `info`

Returns `{ "version": "0.6.2", "format": 1 }`.

### `check`

Returns `{ "diagnostics": [...], "project": {...} }`. The project summary lists the sets with their designs, params, cards and layers; it is written by `src/core/api.zig`, which the editor reads. A list param's `item` maps field names to a type name, or to `{ "type", "options", "default" }` for enum fields and fields with a default. Each diagnostic has the shape described in [Diagnostics](@/docs/diagnostics.md#json-shape).

### `render`

| Field     | Default        | Meaning                                                                            |
| --------- | -------------- | ---------------------------------------------------------------------------------- |
| `set`     | `""`           | Set name (set it: an omitted or unknown name answers `{ "error": "unknown set" }`) |
| `card`    | `0`            | 0-based card index in the set                                                      |
| `date`    | `"1970-01-01"` | Used when `now` is not given: `render.date` is this date, `render.time` is `00:00:00` and `render.now` is that date at midnight UTC. The editor sends today's date |
| `now`     | none | UTC instant `YYYY-MM-DDTHH:MM:SSZ`: `render.now`. `render.date` and `render.time` are it shifted by the offset. Overrides `date`. An invalid value is ignored, so the render falls back to `date` at midnight |
| `utc_offset` | project's | Hours from UTC, -14 to 14, replaces the project's `utc_offset`. Other values are ignored |
| `preview` | `true`         | Missing or undecodable images become a placeholder and a warning                   |
| `format`  | `"rgba"`       | `rgba` (raw 8-bit RGBA for a canvas), `png` or `png16`                             |
| `layout`  | `false`        | Also return the resolved bounds of every layer                                     |
| `scale`   | `1`            | Bitmap pixels per canvas pixel. Below 1 a smaller preview render; above 1 a larger export. Each side of the bitmap must stay within 10000 pixels (else error 5001 and no image). Layout and expressions stay in canvas pixels |
| `compression` | `"default"` | PNG deflate effort: `fast`, `default` or `smallest`. The pixels are the same      |

The answer's JSON is:

```json
{
	"width": 842,
	"height": 1228,
	"canvas_width": 842,
	"canvas_height": 1228,
	"dpi": 300,
	"bleed": 0,
	"diagnostics": [],
	"missing_urls": [],
	"layout": []
}
```

and the binary result holds the pixels or the PNG file. `width` and `height` are the bitmap's size (the canvas times `scale`), `dpi` is `canvas.dpi` times `scale` (0 when the design has none) and `bleed` is `canvas.bleed` times `scale`, in bitmap pixels. `layout` is present only when requested: for each layer and each repeat iteration, the resolved bounds with rotation, pivot, polygon points and the text size after auto-shrink. Layers inside a repeated group appear once per group iteration, with `instance` set to the iteration. The editor draws its selection overlay from it.

### `svg`

The card as an [SVG file](@/docs/command-line.md#svg) (the binary result). `set`, `card`, `date`, `now` and `utc_offset` work as for `render`; missing images are errors, as in an export. `scale` (a number from 1 to 4, default 2, clamped) is the resolution in pixels per canvas pixel of the parts that stay pixels: layers and groups with a `sharpen`, `detail`, `edge_enhance` or `find_edges` effect. The answer's JSON is `{ "width", "height", "diagnostics", "missing_urls" }`, with the canvas size in pixels.

### `check_cards`

Evaluates every card of the set without drawing (like `yoshida check`) and returns `{ "pages": 0, "diagnostics": [...] }`. URL images that are not in the file system are skipped.

### `pdf`

Renders every card of the set into one PDF (the binary result) and returns `{ "pages": n, "diagnostics": [...] }`. With `"crop_marks": true`, each page gets a margin with crop marks at the trim line. By default each card is an image on its page, and `"scale"` (default 1) renders the page images that many times larger. With `"vector": true` the pages are drawn as vectors, like the `svg` request, and `scale` works as there. The page size does not change with the scale.

The same PDF can be built one page per request, so the page can show progress and stop between cards (the editor does this): `{ "op": "pdf_begin" }`, then `{ "op": "pdf_page", "set", "card", "date", "now", "crop_marks", "vector", "scale" }` per card (answers `{ "pages", "diagnostics" }`), then `{ "op": "pdf_finish" }` (the PDF as the binary result).

### `scope`

What the expression field at `path` (a JSON Pointer into the set's design file, as in diagnostics) can use. A path that is not an expression or template field answers `{ "error": "no expression field at path" }`.

```json
{
	"want": "color",
	"template": false,
	"axis": "none",
	"units": true,
	"builtins": true,
	"layers": true,
	"params": [{ "name": "kind", "type": "text", "kind": "enum", "options": ["start", "dare"] }],
	"consts": [{ "name": "gap", "type": "number" }],
	"functions": [{ "name": "tile_x", "args": [{ "name": "i", "type": "number" }], "ret": "number" }],
	"locals": [{ "name": "t", "type": "list item", "fields": [{ "name": "kind", "type": "text" }] }],
	"layer_refs": [{ "id": "tile", "kind": "rect", "ref": "index" }]
}
```

`want` is the type the field needs (`null` for constants, function bodies and `repeat.each`). `axis` says what `%` means there. `layers` is false where layer references are not allowed. Each layer reference has `ref`: `ok` (`@id` works), `index` (needs `@id[i]`) or `none` (cannot be referenced from this field).

### `eval`

Evaluates `src` in place of the field at `path` while the card is rendered without drawing, so it sees the card's params, repeat names, function arguments and layer positions. The design itself is not changed.

```json
{
	"hits": 1,
	"value": "#C04A3BFF",
	"type": "color",
	"problems": [],
	"trace": ["#C04A3BFF", "dare", "dare", true, "#C04A3BFF", null]
}
```

- `hits` counts how often the card evaluated the field (repeat iterations, function calls and layout passes); 0 when it never did, for example in a hidden layer or an unused constant. The value and trace come from the first evaluation.
- `trace` holds the value of every syntax tree node in pre-order (the node ids of `expr.wasm`'s `parse`), `null` for nodes that were not evaluated, such as the branch not taken.
- `problems` lists parse and type errors of `src` in this field, or the error that stopped the evaluation. Spans are UTF-16 offsets into `src`.

### `https://` images

The core never downloads anything. Images given as URLs come back in `missing_urls`; the worker fetches them (when the remote server allows CORS), adds them with `vfs_put` **under the URL as the path**, and renders again.

## The expression module

`expr.wasm` (built by the same `zig build wasm` step) holds only the expression parser and printer. It needs no project, so the editor loads it on the main thread and calls it on every keystroke (a parse takes about 0.1 ms). It exports `alloc`, `free`, `request`, `result_ptr` and `result_len`, and answers:

```json
{ "op": "parse", "src": "max(a, 1) * 2", "template": false }
{ "op": "format", "src": "max(a,1)*2", "width": 72 }
{ "op": "catalog" }
```

- `parse` never fails: it returns `tokens` (`[start, end, kind]`), up to 8 `problems` with `code`, `span`, `message` and `hint`, and the syntax tree as `root` (or `holes` for a template). Broken parts become `err` nodes, so the rest of the tree is still there. Every node has an `id` (pre-order), a kind `k` and a `span`.
- `format` returns the canonical text (`{ "text": ... }`) with minimal parentheses and line breaks at `width`, or `"text": null` with the problems when the source does not parse. Number and color literals keep their spelling.
- `catalog` lists the built-in functions with their argument and return types, the built-in names, the fields of each layer kind and the reserved words.

All spans are UTF-16 offsets, the way JavaScript counts string positions.

## Notes

- The module is deterministic: the same files, set, card and date give the same bytes as the CLI and the server, for SVG and vector PDF files too.
- Unknown `op` values answer `{ "error": "unknown op" }`.
