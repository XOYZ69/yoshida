# Contributing to yoshida

Thanks for helping. Bug reports, feature wishes, docs fixes and code are all welcome. For anything bigger than a small fix, open an issue first so we can agree on the direction before you spend time on it.

The full guide is the [Contributing page](https://yoshida.xoyz.dev/docs/contributing/) on the docs site. This page is the short version.

## Set up

You need Zig 0.16.0, Node 22 and, for the website, Zola 0.23. The C libraries are included.

```sh
zig build test                      # core unit tests
zig build                           # CLI and server in zig-out/bin
cd web && npm ci && npm run wasm && npm run examples && npm run dev
```

See [Building from Source](https://yoshida.xoyz.dev/docs/building-from-source/) for cross-compiling, the WASM module and the website.

## Before you open a pull request

Run what CI runs (see [CI and Deployment](https://yoshida.xoyz.dev/docs/ci-and-deployment/)):

```sh
node scripts/version.mjs check
zig fmt --check build.zig src
zig build test
zig build
./zig-out/bin/yoshida fmt --check examples
for e in examples/*/; do ./zig-out/bin/yoshida check "$e"; done
for e in examples/*/; do ./zig-out/bin/yoshida render "$e" --offline --out "out/$(basename "$e")"; done
(cd site && zola build --output-dir ../public)   # fails on a broken link or anchor
cd web
npm run wasm && npm run examples
npm run check && npm run test:unit && npm run build
```

The browser tests need Playwright's Chromium once (`npx playwright install chromium`) and the built editor running on port 4173: start `npx vite preview --port 4173 --strictPort` in `web/` in a second terminal, then run `npm run test:ui`. [Testing](https://yoshida.xoyz.dev/docs/testing/) explains each suite and how to run a single file.

Changes to a design or example file: format them with `yoshida fmt`. Changes to the format or an expression function: update the matching page in `site/content/docs/`.

## Pull requests

- **Title:** a conventional title, `type(scope): description`, for example `feat(web): add a ruler` or `fix: keep the selection after undo`. Types: feat, fix, perf, docs, refactor, chore, ci, build, test, style, revert. A `!` before the colon marks a breaking change. A check enforces this, and the title becomes the line in the release notes.
- **Branches:** `feat/short-name`, `fix/short-name`, `docs/...`, `chore/...`.
- **Release note:** optional. Write one user-facing sentence in the `release-note` block of the PR template to get a line under Highlights.
- Pull requests are merged with squash, so keep the description useful: it becomes part of the history.
- Keep a PR to one topic. Labels (type and area) are set automatically.

## Releases

A release happens when the version in `build.zig.zon` changes on `master`. Bump it with `node scripts/version.mjs minor` (or `patch`, `major`, or an exact version) in its own PR. To add a hand-written introduction to the release notes, add `.github/release-intro/<version>.md` in that PR. Details: [Releases](https://yoshida.xoyz.dev/docs/ci-and-deployment/#releases).

## Formatting

`biome.json` in the repo root is the editor configuration for web and JSON files; CI does not enforce it. Zig code uses `zig fmt`, design and example files use `yoshida fmt`.

## License

By contributing you agree that your contribution is licensed under the [MIT License](LICENSE). Bundled fonts and libraries keep their own licenses, listed in [Third-Party Notices](https://yoshida.xoyz.dev/docs/third-party-notices/).
