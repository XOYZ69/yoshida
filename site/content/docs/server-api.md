+++
title = "Server API"
description = "The HTTP API of yoshida-server."
+++

`yoshida-server` serves the editor and a small HTTP API. See [Server and Docker](@/docs/server-and-docker.md) for running it.

| Method and path         | Request                                                                    | Response                                                                               |
| ----------------------- | -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `GET /api/capabilities` |                                                                            | `{ "version", "format", "render", "max_cards", "max_body_mb" }`                        |
| `POST /api/render`      | `{ "files": { path: base64 }, "set", "date", "format": "png" \| "png16" \| "pdf" }` | `application/zip` with `<set>/<card id>.png` (or `application/pdf` for `pdf`), or 422 with `{ "error", "diagnostics" }` |
| `GET /api/render/progress?job=<id>` |                                                               | `{ "found", "stage", "done", "total" }` for a render sent with `x-yoshida-job: <id>` |
| `GET /*`                |                                                                            | Static files from `--web`                                                              |

The API also answers under `/editor/api/`, where the editor's calls land when it is served from `/editor/`. A folder asked for without its trailing slash (`/editor`) redirects to `/editor/`. A missing static file answers 404 with `--web`'s `404.html` when there is one, otherwise with a JSON error.

The editor shows the **Render on server** switch only when `capabilities.render` is `true`.

## `GET /api/capabilities`

```json
{
	"version": "0.5.0",
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
| `date`   | Value of `render.date`. Default `1970-01-01` when omitted, so pass it for meaningful dates                                                                     |
| `format` | `png` (8-bit, default), `png16`, or `pdf` (one PDF, one page per card)                                                                                         |

Response:

- **200** `application/zip` (stored, not compressed) with one `<set>/<card id>.png` per card and `Content-Disposition: attachment; filename="<set>.zip"`. With `"format": "pdf"`: `application/pdf`, `filename="<set>.pdf"`, one page per card (see [Command Line: PDF](@/docs/command-line.md#pdf)).
- **422** `application/json` `{ "error": "the project has errors", "diagnostics": [...] }` when loading or rendering reported errors. No zip is produced. Diagnostics are described in [Diagnostics](@/docs/diagnostics.md#json-shape).

Other statuses (all with `{ "error": "..." }`):

| Status | When                                                                                                      |
| ------ | --------------------------------------------------------------------------------------------------------- |
| 400    | Body is not JSON, `files` is missing or not an object, a file is not base64, or a path leaves the project |
| 403    | Rendering is disabled (`--no-render`)                                                                     |
| 404    | Unknown set, unknown `/api/...` path                                                                      |
| 405    | `POST /api/render` with another method; non-GET/HEAD for static files                                     |
| 413    | Request body above `--max-body-mb`, or the set has more cards than `--max-cards`                          |
| 500    | Out of memory while rendering                                                                             |

The server renders cards in parallel (`--threads`). It never downloads images from URLs; an unreachable URL is error 4001, so include the images in `files`.

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
root = pathlib.Path("examples/gamecard-simple")
files = {str(p.relative_to(root)): base64.b64encode(p.read_bytes()).decode()
         for p in root.rglob("*") if p.is_file()}
print(json.dumps({"files": files, "set": "drinking-game", "date": "2026-10-08"}))
EOF

curl -sS -X POST --data-binary @request.json http://localhost:8080/api/render -o cards.zip
```

## Static files

Everything else is served from `--web`. The server maps `/` to `index.html`, sends `Cache-Control: no-cache`, and sets the content type from the file extension.
