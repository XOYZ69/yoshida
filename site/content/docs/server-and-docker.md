+++
title = "Server and Docker"
+++

`yoshida-server` is a small static HTTP server. It serves the built editor and, when enabled, renders a whole card set on the machine it runs on and returns a zip of PNGs (the "hybrid" mode, handy for home labs and big sets). It uses the same core as the CLI and the browser, so the pixels are identical.

```txt
yoshida-server [--host ADDR] [--port N] [--web DIR] [--no-render]
               [--max-cards N] [--max-body-mb N] [--threads N]
```

| Option | Environment variable | Default | Meaning |
| --- | --- | --- | --- |
| `--host` | `YOSHIDA_HOST` | `0.0.0.0` | Address to listen on |
| `--port` | `YOSHIDA_PORT` | `8080` | Port |
| `--web` | `YOSHIDA_WEB` | `web` | Folder with the built editor (`web/dist` from a source build, `web/` in the release zip) |
| `--no-render` | `YOSHIDA_RENDER=0` | rendering on | Serve the editor only; `POST /api/render` answers 403 and the editor hides the **Render on server** switch |
| `--max-cards` | `YOSHIDA_MAX_CARDS` | `1000` | Largest set the server will render in one request |
| `--max-body-mb` | `YOSHIDA_MAX_BODY_MB` | `200` | Largest request body |
| `--threads` | `YOSHIDA_THREADS` | all CPUs | Worker threads used to render a set |

Command-line options win over environment variables.

## Running the release zip

The start scripts run the server for you: `./start.sh`, `start.command` or `start.bat`. They pass `--host 127.0.0.1`, so the editor is reachable from your own computer only. To let other machines in, run the binary directly:

```sh
bin/x86_64-linux/yoshida-server --host 0.0.0.0 --web web
```

The server has no authentication and no TLS. Put it behind a reverse proxy (and an access control of your choice) before exposing it beyond a trusted network.

## Docker

The `Dockerfile` is a multi-stage build: Zig 0.16.0 (from the `ziglang` package on PyPI) builds the two static binaries and the WASM module, Node 22 builds the editor, Zola builds the website, and the final image is `scratch` with just `yoshida`, `yoshida-server` and the website, with the editor in `/editor/` and the docs in `/docs/`. It runs as an unprivileged user (`65534:65534`).

```sh
docker build -t yoshida .
docker run -p 8080:8080 yoshida                       # editor + server render
docker run -p 8080:8080 -e YOSHIDA_RENDER=0 yoshida   # editor only (render in the browser)
```

The image sets `YOSHIDA_WEB=/web` and `YOSHIDA_PORT=8080` and exposes port 8080. All other options are environment variables (table above).

### Docker Compose

`compose.yaml` spells the options out:

```yaml
services:
  yoshida:
    build: .
    image: yoshida:latest
    ports:
      - "8080:8080"
    environment:
      YOSHIDA_RENDER: "1"        # 0: editor only, rendering stays in the browser
      YOSHIDA_MAX_CARDS: "1000"
      YOSHIDA_MAX_BODY_MB: "200"
      # YOSHIDA_THREADS: "4"     # default: all CPUs
    restart: unless-stopped
```

```sh
docker compose up
```

The image also contains the `yoshida` CLI at `/yoshida`, which you can run with `docker run --rm -v "$PWD:/p" --entrypoint /yoshida yoshida render /p/my-cards`.

## Using server rendering from the editor

When the editor is served by `yoshida-server` with rendering enabled, the toolbar shows a **Render on server** switch next to the export buttons. Switched on, **ZIP** and **PDF** upload the project's files to `POST /api/render` and download the result; otherwise rendering happens in the browser. See [Saving, Images and Privacy](@/docs/saving-images-and-privacy.md) for what is and is not sent.

The progress window shows each step (pack, upload with the bytes sent, render on the server with the cards done, download, save) and an activity log; the same lines go to the browser console as `[yoshida] …`. The cards done come from [`GET /api/render/progress`](@/docs/server-api.md#get-api-render-progress).

The server logs every render request on stderr (`docker logs`), for example:

```text
render #3: receiving 4.2 MB
render #3: 31 files, set 'boards', 120 cards as png on 8 thread(s)
render #3: 12/120 cards
…
render #3: done, 120 cards in 9412 ms, sending 38.0 MB of zip
```

Refused and failed requests are logged too (over `--max-body-mb` or `--max-cards`, unknown set, a project with errors).

The server never downloads images from URLs; upload images with the project instead (an unreachable URL is error 4001).

## HTTP API

The API is small and documented in [Server API](@/docs/server-api.md): `GET /api/capabilities`, `POST /api/render`, and static files for everything else. You can call it from your own tools.
