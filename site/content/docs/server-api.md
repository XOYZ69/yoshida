+++
title = "Server API"
description = "The HTTP API of yoshida-server."
+++

`yoshida-server` serves the editor and a small HTTP API. See [Server and Docker](@/docs/server-and-docker.md) for running it.

| Method and path         | Request                                                                    | Response                                                                               |
| ----------------------- | -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `GET /api/capabilities` |                                                                            | `{ "version", "format", "render", "max_cards", "max_body_mb" }`                        |
| `POST /api/render`      | `{ "files": { path: base64 }, "set", "date", "now", "utc_offset", "format": "png" \| "png16" \| "pdf" \| "svg", "vector", "scale", "crop_marks", "compression" }` | `application/zip` with `<set>/<card id>.png` (`.svg` for `svg`), or `application/pdf` for `pdf`, or 422 with `{ "error", "diagnostics" }` |
| `GET /api/render/progress?job=<id>` |                                                               | `{ "found", "stage", "done", "total" }` for a render sent with `x-yoshida-job: <id>` |
| `GET /*`                |                                                                            | Static files from `--web`                                                              |

The API also answers under `/editor/api/`, where the editor's calls land when it is served from `/editor/`. A folder asked for without its trailing slash (`/editor`) redirects to `/editor/`. A missing static file answers 404 with `--web`'s `404.html` when there is one, otherwise with a JSON error.

The editor shows the **Render on server** switch only when `capabilities.render` is `true`.

## `GET /api/capabilities`

```json
{
	"version": "0.6.2",
	"format": 1,
	"render": true,
	"max_cards": 1000,
	"max_body_mb": 200
}
```

## `POST /api/render`

Request body (JSON):

| Field    | Meaning                                                                                                                                                        |
| -------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `files`  | Object of project path to **base64-encoded** file content. The whole project: manifest, designs, card files, images, fonts. Paths must stay inside the project |
| `set`    | Name of the set to render. **Required in practice**: an omitted or unknown name is 404                                                                         |
| `date`   | Used when `now` is not sent: `render.date` is this date, `render.time` is `00:00:00` and `render.now` is that date at midnight UTC. With neither `date` nor `now`, the server's current UTC instant is used. Format `YYYY-MM-DD` |
| `now`    | UTC instant `YYYY-MM-DDTHH:MM:SSZ`: `render.now`. `render.date` and `render.time` are it shifted by `utc_offset`. Overrides `date`. A malformed value is **400** |
| `utc_offset` | Hours from UTC, -14 to 14, fractions allowed. Replaces the project's `utc_offset`. Outside that range is **400** |
| `format` | `png` (8-bit, default), `png16`, `pdf` (one PDF, one page per card) or `svg` (one [SVG file](@/docs/command-line.md#svg) per card)                                |
| `vector` | Optional. `true` with `"format": "pdf"` draws the pages as vectors instead of images (see [Command Line: PDF](@/docs/command-line.md#pdf)). Default `false`. Not a boolean, or `true` with another format, is **400** |
| `scale`  | Optional, a number from 1 to 4. For `png`, `png16` and the image `pdf`: render at this many times the canvas size (default 1); the PNG dpi grows with it and PDF pages keep their size, and a side over 10000 pixels is a 422 with error 5001. For `svg` and the vector `pdf`: pixels per canvas pixel for the parts that stay pixels (layers with a convolution filter), default 2. Anything else is **400** |
| `crop_marks` | Optional, `pdf` only (image or vector). `true` puts each page on a white sheet with crop marks at the trim line, like `--crop-marks`; default `false`. Not a boolean is **400** |
| `compression` | Optional, PNG only. `fast`, `default` (default) or `smallest`: the deflate effort. The pixels are the same. Anything else is **400** |

Response:

- **200** `application/zip` (stored, not compressed) with one `<set>/<card id>.png` per card (`<set>/<card id>.svg` with `"format": "svg"`) and `Content-Disposition: attachment; filename="<set>.zip"`. With `"format": "pdf"`: `application/pdf`, `filename="<set>.pdf"`, one page per card (see [Command Line: PDF](@/docs/command-line.md#pdf)).
- **422** `application/json` `{ "error": "the project has errors", "diagnostics": [...] }` when loading or rendering reported errors. No zip is produced. Diagnostics are described in [Diagnostics](@/docs/diagnostics.md#json-shape).

Other statuses (all with `{ "error": "..." }`):

| Status | When                                                                                                      |
| ------ | --------------------------------------------------------------------------------------------------------- |
| 400    | Body is not JSON, `files` is missing or not an object, a file is not base64, a path leaves the project, or `now`, `utc_offset`, `vector`, `scale`, `crop_marks` or `compression` is invalid |
| 403    | Rendering is disabled (`--no-render`)                                                                     |
| 404    | Unknown set, unknown `/api/...` path                                                                      |
| 405    | `POST /api/render` with another method; non-GET/HEAD for static files                                     |
| 413    | Request body above `--max-body-mb`, or the set has more cards than `--max-cards`                          |
| 500    | Out of memory while rendering                                                                             |

The server renders cards in parallel (`--threads`); a vector PDF is drawn on one thread, since vector pages are quick to make. It never downloads images from URLs; an unreachable URL is error 4001, so include the images in `files`.

An optional `x-yoshida-job: <id>` header (up to 16 hex digits, not 0) makes the request's progress readable with `GET /api/render/progress`. Every request is logged on stderr, see [Server and Docker](@/docs/server-and-docker.md#using-server-rendering-from-the-editor).

## `GET /api/render/progress`

`?job=<id>` names a render sent with `x-yoshida-job: <id>`. The answer is never cached:

```json
{ "found": true, "stage": "rendering", "done": 12, "total": 120 }
```

| `stage`     | Meaning                                         |
| ----------- | ----------------------------------------------- |
| `receiving` | Reading the request body                        |
| `loading`   | Decoding the files and loading the project      |
| `rendering` | Drawing the cards; `done` of `total` are drawn  |
| `packing`   | Building the zip or the PDF                     |
| `finished`  | The response was sent                           |
| `failed`    | The request ended with an error (see its reply) |

An unknown id answers `{ "found": false }`. The server keeps the last 32 renders; a finished one stays readable until its slot is reused.

## Example

```sh
python3 - <<'EOF' > request.json
import base64, json, pathlib
root = pathlib.Path("examples/poker")
files = {str(p.relative_to(root)): base64.b64encode(p.read_bytes()).decode()
         for p in root.rglob("*") if p.is_file()}
print(json.dumps({"files": files, "set": "courts", "date": "2026-10-08"}))
EOF

curl -sS -X POST --data-binary @request.json http://localhost:8080/api/render -o cards.zip
```

## Static files

Everything else is served from `--web`. The server maps `/` to `index.html`, sends `Cache-Control: no-cache`, and sets the content type from the file extension.
