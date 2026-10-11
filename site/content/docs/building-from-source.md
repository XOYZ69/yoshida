+++
title = "Building from Source"
description = "Build the CLI, the server, the WASM core and the editor yourself."
+++

## Requirements

- **Zig 0.16.0**. `pip install ziglang==0.16.0` is an easy way to get it on any platform (then run it as `python3 -m ziglang`), or download it from ziglang.org.
- **Node 22**, only for the web editor.
- **Zola 0.23**, only for the website (`site/`) and the release bundle.

The C libraries (stb_image, stb_truetype, simplewebp) are included in `src/c/` and compiled by Zig without libc. No other system dependencies.

## Core, CLI and server

```sh
zig build test                        # core unit tests
zig build -Doptimize=ReleaseFast      # zig-out/bin/yoshida and zig-out/bin/yoshida-server
zig build wasm                        # zig-out/web/yoshida.wasm

./zig-out/bin/yoshida check examples/cocktail
./zig-out/bin/yoshida render examples/feature-tour --out out --date 2026-10-07
```

`zig build run -- check examples/cocktail` runs the CLI from the build.

### Cross-compiling

```sh
zig build -Dtarget=aarch64-macos -Doptimize=ReleaseFast -Dstrip=true
```

Any Zig target works. `scripts/release.sh` builds the five release platforms: `x86_64-linux-musl`, `aarch64-linux-musl`, `x86_64-macos`, `aarch64-macos`, `x86_64-windows-gnu`. For Windows on ARM, `zig build -Dtarget=aarch64-windows` works from source.

## Web editor

```sh
cd web
npm install
npm run wasm        # builds the WASM module and copies it into public/
npm run examples    # copies ../examples into public/examples
npm run dev         # http://localhost:5173 (proxies /api to localhost:8080)
npm run build       # static site in web/dist, deployable to any static host
npm run check       # svelte-check (types)
npm run test:ui     # end-to-end tests in Chromium (see CI and Deployment)
```

For `npm run dev` with server rendering, also run the server in another terminal: `./zig-out/bin/yoshida-server --port 8080 --web web/dist`.

The editor is Svelte 5 + Vite + TypeScript. The build uses relative URLs (`base: './'`), so the result runs from any sub-path of a static host and from the yoshida server.

## Server

```sh
./zig-out/bin/yoshida-server --port 8080 --web web/dist
```

Options and environment variables: [Server and Docker](@/docs/server-and-docker.md).

## Docker

```sh
docker build -t yoshida .
docker run -p 8080:8080 yoshida
```

## Format check and tests

Before opening a pull request:

```sh
zig fmt --check build.zig src
zig build test
./zig-out/bin/yoshida fmt --check examples
cd web && npm run check
```

These are the same steps [CI](@/docs/ci-and-deployment.md) runs.

## The release bundle

```sh
scripts/release.sh release
```

Runs the tests, builds the web editor and the website (editor in `web/editor/`, as in Docker), cross-compiles the CLI and server for five platforms, and copies the examples, schemas, `README.md`, `THIRD_PARTY.md` (from [Third-Party Notices](@/docs/third-party-notices.md)) and the start scripts (`start.sh`, `start.bat`, `start.command`) next to them.

## Project layout

See [Architecture](@/docs/architecture.md) for what each folder holds.
