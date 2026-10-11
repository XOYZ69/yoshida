+++
title = "CI and Deployment"
+++

Two GitHub Actions workflows live in `.github/workflows/`. They share the Zig setup in `.github/actions/setup-zig`, which installs Zig 0.16.0 from PyPI (the `ziglang` package ships the official release binaries) and caches Zig's build cache.

| Workflow | Runs on | What it does |
| --- | --- | --- |
| `ci.yml` | every pull request, manually, and when called by `deploy.yml` | Checks and tests, below |
| `deploy.yml` | every push to `master`, and manually | Runs all of `ci.yml` first, then builds the site and publishes `web/dist` to GitHub Pages |

## `ci.yml`

Three jobs:

**Core and CLI**

1. `zig fmt --check build.zig src`
2. `zig build test` (the core's unit tests)
3. `zig build`
4. `yoshida fmt --check examples` (the examples are in canonical format)
5. `yoshida check` on every example
6. `yoshida render --offline` on every example that does not load images from the web (those are skipped so a remote site cannot break the build)

**Build for each release target**: `x86_64-linux-musl`, `aarch64-linux-musl`, `x86_64-macos`, `aarch64-macos`, `x86_64-windows-gnu`, each with `-Doptimize=ReleaseFast -Dstrip=true`.

**Web editor**: `npm ci`, build the WASM module, copy the examples, `svelte-check`, `vite build`, install Chromium for Playwright, then the end-to-end tests `web/tests/ui.mjs` and `web/tests/ui-organise.mjs` against `vite preview`. Screenshots of a failed run are uploaded as the `ui-test-results` artifact (kept 7 days).

Pull-request runs cancel older runs of the same PR.

## `deploy.yml`

On every push to `master`:

1. Run `ci.yml` as a reusable workflow.
2. **Build the site**: Zig, Node 22, `npm ci`, `npm run wasm`, `npm run examples -- --public`, `npm run build`, upload `web/dist` as the Pages artifact.
3. **Deploy** to GitHub Pages.

Only one deployment runs at a time; a newer push waits instead of cancelling a deployment that is already running.

### One-time setup

In the repository: **Settings → Pages → Build and deployment → Source: GitHub Actions**.

The site works from the Pages sub-path (`https://<user>.github.io/<repo>/`) because the build uses relative URLs. The default branch is assumed to be `master`; if yours is `main`, change `branches: [master]` in `deploy.yml`.

### What the public site contains

The site is static: rendering runs in the visitor's browser (WebAssembly) and projects are stored in the visitor's browser only. See [Saving, Images and Privacy](@/docs/saving-images-and-privacy.md).

The public build copies the examples with `npm run examples -- --public`, which leaves out the files listed in `examples/.public-exclude`: the commercial fonts that were copied from the old Python version for private testing. Those example designs then use the bundled Lato font and show warning 4005. See [Third-Party Notices](@/docs/third-party-notices.md).

## Run the end-to-end test locally

```sh
cd web
npm run wasm && npm run examples && npm run build
npx vite preview --port 4173 &
npm run test:ui
```

`npm run test:ui` runs `tests/ui.mjs` and `tests/ui-organise.mjs` with Playwright in Chromium. Pass the preview URL as an argument if it is not the default.

## Releases

`scripts/release.sh [OUT_DIR]` builds the release bundle: the CLI and server for the five platforms, the WASM module, and the website with the web editor in `editor/` (the same layout as Docker and GitHub Pages), plus the start scripts, the examples, the schemas, `README.md`, and `THIRD_PARTY.md` (a copy of [Third-Party Notices](@/docs/third-party-notices.md)). It needs Zig 0.16.0, Zola 0.23 and Node 22 with `web/node_modules` installed. See [Building from Source](@/docs/building-from-source.md).

A bundle made from the full examples contains commercial fonts and is **for private use only**.
