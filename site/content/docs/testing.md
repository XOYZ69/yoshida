+++
title = "Testing"
description = "The test suites, what each one covers and how to run a single one."
+++

There are four kinds of checks. CI runs all of them (see [CI and Deployment](@/docs/ci-and-deployment.md)).

## Core: `zig build test`

Unit tests inside the Zig sources: parsers, the formatter, the loader, expressions and rendering.

## Examples

```sh
zig build
./zig-out/bin/yoshida fmt --check examples
./zig-out/bin/yoshida check examples/poker
./zig-out/bin/yoshida render examples/poker --offline --out out/poker
```

The examples must be in canonical format (`yoshida fmt examples/<name>` fixes them), check without errors and render.

## Editor unit tests: `npm run test:unit`

Run in `web/`. These need no browser, only the built WASM modules (`npm run wasm`).

| File | Covers |
| --- | --- |
| `tests/expr-core.mjs` | the expression core: tokens, problems, tree, templates, formatter |
| `tests/expr-edit.mjs` | edits made by the formula panel |
| `tests/expr-rewrite.mjs` | the quick actions on expressions |
| `tests/fonts.mjs` | font readers and the Google Fonts catalog |
| `tests/hexcolor.mjs` | the hex colour helper against the core's rules |
| `tests/progress-math.mjs` | export progress and time left |

Run one with the command at the top of the file, for example `node tests/expr-core.mjs`.

## Editor end-to-end tests: `npm run test:ui`

Chromium driven by Playwright against the built editor. `test:ui` runs every `tests/ui*.mjs` file one after another and stops at the first file that fails, so run a single file while you work:

```sh
cd web
npm run wasm && npm run examples && npm run build
npx vite preview --port 4173 &
node tests/ui-organise.mjs http://localhost:4173/
```

| File | Covers |
| --- | --- |
| `ui.mjs` | the editor in a real browser: loading, editing, saving, reload |
| `ui-organise.mjs` | param groups, the Files tab, the card browser, splitters, list rows |
| `ui-view.mjs` | zoom, pan and keeping the card in view |
| `ui-features.mjs` | repeat groups, design functions, enum lists, PDF export, strokes, preset shapes |
| `ui-hover.mjs` | hover info and go to definition in expression fields |
| `ui-review.mjs` | list fields, tabs, tooltips, export progress, rendering on the server |
| `ui-perf.mjs` | proxy renders and export progress on the board game |
| `ui-expr.mjs` | the expression editor: marks, breadcrumb, wrapping, reformat |
| `ui-paths.mjs` | JSON pointers of the inspector fields |
| `ui-formula.mjs` | the formula editor window |
| `ui-fonts.mjs` | the Fonts window, Google Fonts import, uploads |
| `ui-rename.mjs` | renaming fonts and design functions |

A failed run writes screenshots to `web/test-results/`; CI uploads them as the `ui-test-results` artifact. When you change an example, update the tests that read it: several look for specific cards, layers and values of the poker and board game examples.

## Website

`cd site && zola build --output-dir ../public` fails on a broken internal link or anchor.
