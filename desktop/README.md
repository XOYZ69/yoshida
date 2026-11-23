# yoshida desktop

A [Tauri 2](https://tauri.app) shell around the web editor (`web/`). It adds two things a browser tab cannot do:

- **Folders on disk in every webview.** Projects link to real folders, picked with the system dialog, with no permission prompts. This is the `native` backend in `web/src/lib/folder/native.ts`; the Rust side is the commands in `src-tauri/src/main.rs` (`pick_folder`, `read_folder`, `read_file`, `write_file`, `remove_file`). A folder can only be read or written after it was picked in the app (the list is kept in the app's config folder as `folders.json`), and every path must stay inside it.
- **Render on server, locally.** The app starts `yoshida-server` as a sidecar on `127.0.0.1` (port 47810, or a free one when that is taken) with the bundled editor and `--no-telemetry`, and shows the editor from there, so exports render with the native renderer (the editor has no "Render on server" switch in the app, it is always on). Without the sidecar the window shows the bundled editor and renders in the webview.

The editor keeps its projects in the webview's storage, which belongs to the page's origin. That is why the port is fixed: on another port the app starts with an empty project list (the projects are still there on the next start on the usual port).

## Requirements

Rust (stable), the Tauri CLI (`cargo install tauri-cli --version "^2"`) and the [system packages Tauri needs](https://tauri.app/start/prerequisites/) (on Linux: WebKitGTK 4.1, libsoup 3, GTK 3), plus what the editor and server need (Zig 0.16.0, Node 22).

## Build

```sh
# from the repository root
zig build -Doptimize=ReleaseFast                    # zig-out/bin/yoshida-server
(cd web && npm ci && npm run wasm && npm run examples && npm run build)   # web/dist

# the sidecar, named for the target triple as Tauri expects
mkdir -p desktop/src-tauri/binaries
cp zig-out/bin/yoshida-server \
   "desktop/src-tauri/binaries/yoshida-server-$(rustc -vV | sed -n 's/host: //p')"
# on Windows the file ends in .exe

cd desktop/src-tauri
cargo tauri build          # installers in target/release/bundle/
```

`tauri.conf.json` bundles `web/dist` twice: as the window's own pages (`frontendDist`) and as a resource folder `web/`, which is what the sidecar serves. The app's version is read from `web/package.json`, which `scripts/version.mjs` keeps in step.

## Run in development

```sh
(cd web && npm run dev)                          # Vite on :5173
./zig-out/bin/yoshida-server --port 8080 --web web/dist   # optional: Vite proxies /api here
cd desktop/src-tauri && cargo tauri dev
```

In development the app does not start the sidecar; the window shows the Vite dev server, so changes to the editor reload as usual.

## Checks

```sh
cd desktop/src-tauri
cargo fmt --check
cargo test        # path checks (needs binaries/ and web/dist as above, like any build)
```

## Install on Arch Linux

`desktop/packaging/arch/PKGBUILD` builds the app from this checkout: `cd desktop/packaging/arch && makepkg -si`. See the [Desktop App](../site/content/docs/desktop-app.md) page.
