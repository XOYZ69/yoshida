+++
title = "WASM Interface"
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
| `result_bin_ptr()`, `result_bin_len()`            | Read the binary answer (an image)                            |

Typical use: put the project files with `vfs_put`, call `request` with a UTF-8 JSON string, read the JSON (and the binary, for renders) from the result pointers.

## Requests

```json
{ "op": "info" }
{ "op": "check" }
{ "op": "render", "set": "name", "card": 0, "date": "2026-10-07",
  "preview": true, "format": "rgba", "layout": true }
{ "op": "check_cards", "set": "name", "date": "2026-10-07" }
{ "op": "pdf", "set": "name", "date": "2026-10-07", "crop_marks": false }
```

### `info`

Returns `{ "version": "0.5.0", "format": 1 }`.

### `check`

Returns `{ "diagnostics": [...], "project": {...} }`. The project summary lists the sets with their designs, params, cards and layers; it is written by `src/core/api.zig`, which the editor reads. A list param's `item` maps field names to a type name, or to `{ "type", "options", "default" }` for enum fields and fields with a default. Each diagnostic has the shape described in [Diagnostics](@/docs/diagnostics.md#json-shape).

### `render`

| Field     | Default        | Meaning                                                                            |
| --------- | -------------- | ---------------------------------------------------------------------------------- |
| `set`     | `""`           | Set name (set it: an omitted or unknown name answers `{ "error": "unknown set" }`) |
| `card`    | `0`            | 0-based card index in the set                                                      |
| `date`    | `"1970-01-01"` | Value of `render.date`. The editor sends today's date                              |
| `preview` | `true`         | Missing or undecodable images become a placeholder and a warning                   |
| `format`  | `"rgba"`       | `rgba` (raw 8-bit RGBA for a canvas), `png` or `png16`                             |
| `layout`  | `false`        | Also return the resolved bounds of every layer                                     |

The answer's JSON is:

```json
{
	"width": 842,
	"height": 1228,
	"diagnostics": [],
	"missing_urls": [],
	"layout": []
}
```

and the binary result holds the pixels or the PNG file. `layout` is present only when requested: for each layer and each repeat iteration, the resolved bounds with rotation, pivot, polygon points and the text size after auto-shrink. Layers inside a repeated group appear once per group iteration, with `instance` set to the iteration. The editor draws its selection overlay from it.

### `check_cards`

Evaluates every card of the set without drawing (like `yoshida check`) and returns `{ "pages": 0, "diagnostics": [...] }`. URL images that are not in the file system are skipped.

### `pdf`

Renders every card of the set into one PDF (the binary result) and returns `{ "pages": n, "diagnostics": [...] }`. With `"crop_marks": true`, each page gets a margin with crop marks at the trim line.

### `https://` images

The core never downloads anything. Images given as URLs come back in `missing_urls`; the worker fetches them (when the remote server allows CORS), adds them with `vfs_put` **under the URL as the path**, and renders again.

## Notes

- The module is deterministic: the same files, set, card and date give the same bytes as the CLI and the server.
- Unknown `op` values answer `{ "error": "unknown op" }`.
