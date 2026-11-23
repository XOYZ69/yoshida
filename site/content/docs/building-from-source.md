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
zig build wasm                        # zig-out/web/yoshida.wasm and expr.wasm

./zig-out/bin/yoshida check examples/poker
./zig-out/bin/yoshida render examples/poker --out out --date 2026-10-11
```

`zig build run -- check examples/poker` runs the CLI from the build.

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
npm run dev         # http://localhost:5173 (proxies /api to localhost:8080), keeps running
npm run build       # static site in web/dist, deployable to any static host
npm run check       # svelte-check (types)
```

Run `npm run dev` in its own terminal, since it keeps running. The end-to-end tests (`npm run test:ui`) need Playwright's Chromium (`npx playwright install chromium`, once) and the built editor on port 4173 (`npx vite preview --port 4173 --strictPort`); see [Testing](@/docs/testing.md).

For `npm run dev` with server rendering, also run the server in another terminal: `./zig-out/bin/yoshida-server --port 8080 --web web/dist`.

The editor is Svelte 5 + Vite + TypeScript. The build uses relative URLs (`base: './'`), so the result runs from any sub-path of a static host and from the yoshida server.

## Server

```sh
./zig-out/bin/yoshida-server --port 8080 --web web/dist
```

Options and environment variables: [Server and Docker](@/docs/server-and-docker.md).

## Desktop app

`desktop/` is a [Tauri 2](https://tauri.app) shell around the editor, not part of the releases yet; what it does and how to use it is on [Desktop App](@/docs/desktop-app.md). It needs Rust, the Tauri CLI (`cargo install tauri-cli --version "^2"`, only for `cargo tauri build` and `dev`) and the system packages Tauri lists for your platform (WebKitGTK 4.1 on Linux).

```sh
zig build -Doptimize=ReleaseFast
(cd web && npm ci && npm run wasm && npm run examples && npm run build)
mkdir -p desktop/src-tauri/binaries
cp zig-out/bin/yoshida-server "desktop/src-tauri/binaries/yoshida-server-$(rustc -vV | sed -n 's/host: //p')"
cd desktop/src-tauri && cargo tauri build
```

`cargo tauri dev` shows the Vite dev server (`npm run dev` in `web/`) instead of starting the sidecar. `desktop/README.md` has the details.

## Docker

```sh
docker build -t yoshida .
docker run -p 8080:8080 yoshida
```

## Format check and tests

Before opening a pull request:

```sh
node scripts/version.mjs check
zig fmt --check build.zig src
zig build test
zig build
./zig-out/bin/yoshida fmt --check examples
cd web && npm run wasm && npm run check && npm run test:unit
```

[CI](@/docs/ci-and-deployment.md) runs these steps too, and also checks and renders every example, builds the editor, runs the browser tests and builds the website with Zola (which fails on a broken link or anchor), all described in [Testing](@/docs/testing.md).

## Dev builds

A build can be stamped as a preview, so nobody mistakes it for a release. Set the channel when you build:

```sh
zig build -Dchannel=dev                 # one build
YOSHIDA_CHANNEL=dev npm run wasm        # the environment variable reaches every build step
YOSHIDA_CHANNEL=dev sh scripts/release.sh
docker build --build-arg YOSHIDA_CHANNEL=dev -t yoshida:dev .
YOSHIDA_CHANNEL=dev docker compose up --build
```

With a channel, `yoshida version` prints `yoshida 0.6.2 (format 1) dev build`, the server's `/api/capabilities` and the WASM `info` call report `"channel": "dev"`, the editor shows a red **DEV** stamp beside the version, and the website (built with `YOSHIDA_CHANNEL` set) shows the stamp beside the logo and asks search engines not to index it. The editor and the website also get a red tab icon (`favicon-dev.svg`), so a preview is told apart from the release in a row of tabs. Without one, nothing changes. The `dev` branch is built this way for the preview site, see [CI and Deployment](@/docs/ci-and-deployment.md#the-dev-preview).

## The release bundle

```sh
scripts/release.sh release
```

Runs the tests, builds the web editor and the website (editor in `web/editor/`, as in Docker), cross-compiles the CLI and server for five platforms, and copies the examples, schemas, `README.md`, `LICENSE`, `THIRD_PARTY.md` (from [Third-Party Notices](@/docs/third-party-notices.md)) and the start scripts (`start.sh`, `start.bat`, `start.command`) next to them.

## Project layout

See [Architecture](@/docs/architecture.md) for what each folder holds.
