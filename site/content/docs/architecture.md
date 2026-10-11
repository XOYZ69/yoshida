+++
title = "Architecture"
+++

One **I/O-free core** implements the file format and the renderer. Three front ends wrap it. All of them produce the same pixels.

```txt
                 +-----------------------------+
                 |  core (src/core, Zig)       |
                 |  load, check, evaluate,     |
                 |  rasterize, encode PNG      |
                 +--+-----------+-----------+--+
                    |           |           |
              src/cli      src/server   src/wasm
              yoshida      yoshida-     WebAssembly in a
              (native)     server       Web Worker (web/)
                           (native)
```

## The core

The core never touches the disk or the network. Each front end hands it a `project.Vfs` (read a path, list paths): the CLI reads the project folder, the browser and the server keep files in a `MemFs` (an in-memory file system).

```txt
build.zig, build.zig.zon
src/core/        the I/O-free core (module "yoshida")
  root.zig         public API
  json.zig         JSON parser that keeps byte positions (for line:col in diagnostics)
  diag.zig         diagnostics list, text and JSON output, "did you mean" suggestions
  value.zig        values, types, colors
  expr.zig         expression lexer, Pratt parser, type checker, evaluator, templates
  design.zig       design loader: params, layers, extends, compile-time checks
  project.zig      virtual file system, manifest, sets, JSON and CSV card data
  render.zig       per-card evaluation (lazy @layer references, cycle detection), drawing
  raster.zig       16-bit premultiplied bitmaps, anti-aliased shapes, images, effects, PNG encoder
  text.zig         stb_truetype fonts, wrapping, alignment, justify, max_lines
  api.zig          JSON project summary and layer layout shared by WASM and server
  fmt.zig          canonical JSON formatter (yoshida fmt)
  c.zig            bindings and the libc shims the C code needs
  assets/          bundled default font (Lato, OFL)
src/c/           stb_image, stb_truetype (public domain / MIT) and simplewebp (BSD-3-Clause), compiled without libc
src/cli/         CLI
src/server/      HTTP server and zip writer
src/wasm/        WebAssembly exports
schema/          JSON Schemas for the three file kinds
scripts/         release.sh (cross-compiled bundle) and the start scripts it ships
web/             Svelte 5 + Vite + TypeScript editor
examples/        converted designs plus feature-tour
```

### Pipeline

1. **`project.load`** reads the manifest, finds card files and designs, and loads each design once. Parsing keeps byte positions so every diagnostic has file, line and column.
2. **`design.load`** parses params and layers, resolves `extends`, type-checks every expression against the params and layers it can see, and reports problems with codes (see [Diagnostics](@/docs/diagnostics.md)).
3. **`render.renderCard`** evaluates a card: layer fields are evaluated lazily by dependency so `@layer` references work in any order; cycles are detected. Then it draws.
4. **`raster`** draws anti-aliased shapes, text and images into 16-bit premultiplied bitmaps, applies effects, composites, and encodes PNG (8- or 16-bit).

The C code (`stb_image`, `stb_truetype`, `simplewebp`) is compiled freestanding with small libc shims, so the binaries are static and the same code runs in WebAssembly. Notes for contributors: Zig `@min(65535, x)` narrows to `u16`, which overflows in `ReleaseSmall` WebAssembly builds, so cast first.

## Front ends

| Front end | Source | Role |
| --- | --- | --- |
| `yoshida` CLI | `src/cli/main.zig` | `check`, `render`, `fmt`; reads a project folder; downloads `https://` images |
| `yoshida-server` | `src/server/` | Static server for the editor plus `POST /api/render` ([Server API](@/docs/server-api.md)) |
| WebAssembly | `src/wasm/main.zig` | A module with a JSON request interface ([WASM Interface](@/docs/wasm-interface.md)) |
| Web editor | `web/` | Svelte 5 app; runs the module in a Web Worker so the UI never blocks and card data never leaves the browser |

## The web editor

`web/src/` is organised as:

- `App.svelte`: the application shell (state, undo, keyboard, panels).
- `lib/engine.ts`, `lib/worker.ts`: talk to the WASM module in a Web Worker; the worker fetches `https://` images the core reports as missing.
- `lib/design.ts`, `lib/cards.ts`, `lib/project.ts`, `lib/paths.ts`: reading and editing designs, card files and project files (renames rewrite references).
- `lib/store.ts`: IndexedDB autosave.
- `lib/builder/`: layer tree, stage (canvas overlay), inspector, params panel, fields.
- `lib/expr/`: the expression editor (highlighting, completion, signature help, reference).
- `lib/ui/`: dialogs, menus, select, color picker, file browser, card browser and card list, splitters.

The editor never parses expressions itself for rendering; it asks the core. The `layout` option of the `render` request returns the resolved bounds of every layer for the canvas overlay.

## Testing

- `zig build test`: unit tests in the core (parsers, formatter, loader, expressions, rendering).
- `web/tests/ui.mjs` and `web/tests/ui-organise.mjs`: end-to-end tests in Chromium with Playwright.
- CI also checks that the examples format, check and render. See [CI and Deployment](@/docs/ci-and-deployment.md).
