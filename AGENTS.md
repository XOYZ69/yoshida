# Working on yoshida as an agent

yoshida makes cards from JSON designs and card data. One I/O-free core in Zig (`src/core`) is used by three front ends: the CLI (`src/cli`), a small server (`src/server`) and the browser editor (`web/`, Svelte, with the core as WebAssembly from `src/wasm`).

## Writing or changing yoshida files (designs, card data)

Read [`llms-full.txt`](llms-full.txt) first. It is the whole file format on one page: every layer type and field, the expression language with all functions, the command line and the diagnostic codes, generated from the JSON Schemas and the sources. [`llms.txt`](llms.txt) is the index of the longer docs pages in `site/content/docs/`.

Then check your work, the tool tells you what is wrong and where:

```sh
zig build                                   # builds zig-out/bin/yoshida
./zig-out/bin/yoshida check examples/forge   # every problem with file, line, code and a hint
./zig-out/bin/yoshida fmt examples/forge     # canonical JSON layout (CI runs fmt --check)
./zig-out/bin/yoshida render examples/forge --out out
```

`examples/forge` is the smallest complete project; copy it to start a new one.

## Changing the code

Needs Zig 0.16.0, Node 22 and, for the website, Zola 0.23.

```sh
zig fmt --check build.zig src && zig build test && zig build
node scripts/version.mjs check      # the version lives in build.zig.zon
node scripts/llms.mjs check         # llms.txt and llms-full.txt are generated
cd web && npm ci && npm run wasm && npm run examples
npm run check && npm run test:unit && npm run build
```

The browser tests (`npm run test:ui`) need `npx vite preview --port 4173 --strictPort` running in `web/`. [CONTRIBUTING.md](CONTRIBUTING.md) has the full list and the pull request rules.

Things that must change together:

- A new or changed **field**: `src/core/design.zig`, `schema/design.schema.json`, the page in `site/content/docs/`, then `node scripts/llms.mjs`.
- A new or changed **expression function**: `src/core/builtins/`, `web/src/lib/expr/catalog.ts`, the functions page in `site/content/docs/`, then `node scripts/llms.mjs`.
- A changed **example**: `yoshida fmt examples`, its `README.md`, and `node scripts/llms.mjs` if it is `examples/forge`.
- The **version**: only with `node scripts/version.mjs <version>`.

Do not edit `llms.txt`, `llms-full.txt` or their copies in `site/static/` by hand. Commits and pull request titles are conventional: `type(scope): description`.
