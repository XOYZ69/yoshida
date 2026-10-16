+++
title = "Architecture"
description = "One I/O-free core, three front ends, and how they fit together."
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
  exprprint.zig    canonical printer for expressions (minimal parentheses, line breaking)
  exprjson.zig     JSON views of expressions for editors: tokens, tree, problems, catalog
  exprapi.zig      editor queries about one field: its scope and live values
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
src/wasm/        WebAssembly exports: main.zig (yoshida.wasm) and expr.zig (expr.wasm, parser and printer only)
schema/          JSON Schemas for the three file kinds
scripts/         release.sh (cross-compiled bundle) and the start scripts it ships;
                 version.mjs (bump and check the version, see Releases in CI and Deployment);
                 releases-to-zola.py and wiki-to-zola.py (website content);
                 gh-labels.sh (creates the repository labels);
                 font-catalog.mjs (rebuilds web/public/fonts/google-fonts.json)
web/             Svelte 5 + Vite + TypeScript editor
examples/        poker deck and party board game
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
- `lib/expr/`: the expression editor (highlighting, completion, signature help, reference, breadcrumb, formula panel, rewrites). `core.ts` loads `expr.wasm` on the main thread for tokens, syntax trees and formatting; `live.ts` describes the live values the panel asks the worker for.
- `lib/fonts/`: the Fonts window's data. `sfnt.ts` reads font files, `catalog.ts` the Google Fonts catalog and its downloads, `project.ts` the project's fonts and their licenses.
- `lib/fonts/FontsWindow.svelte`: the [Fonts window](@/docs/builder-fonts.md).
- `web/public/fonts/google-fonts.json`: the Google Fonts catalog, built by `scripts/font-catalog.mjs`. It is loaded only when the Google Fonts source is opened.
- `lib/ui/`: dialogs, menus, select, color picker, file browser, card browser and card list, splitters.

The editor never parses expressions itself for rendering; it asks the core. The `layout` option of the `render` request returns the resolved bounds of every layer for the canvas overlay.

## Testing

- `zig build test`: unit tests in the core (parsers, formatter, loader, expressions, rendering).
- `npm run test:unit` and `npm run test:ui` in `web/`: unit checks and end-to-end tests in Chromium with Playwright, see [Testing](@/docs/testing.md).
- CI also checks that the examples format, check and render. See [CI and Deployment](@/docs/ci-and-deployment.md).
