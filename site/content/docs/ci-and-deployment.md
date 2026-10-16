+++
title = "CI and Deployment"
description = "The GitHub Actions workflows for checks, releases and this website."
+++

The GitHub Actions workflows live in `.github/workflows/`. They share the Zig setup in `.github/actions/setup-zig`, which installs Zig 0.16.0 from PyPI (the `ziglang` package ships the official release binaries) and caches Zig's build cache.

| Workflow | Runs on | What it does |
| --- | --- | --- |
| `ci.yml` | every pull request, manually, and when called by `deploy.yml` | Checks and tests, below |
| `deploy.yml` | every push to `master`, every published, edited or deleted release, and manually | Runs all of `ci.yml` first, then builds the site and publishes it to GitHub Pages |
| `release.yml` | every successful `deploy.yml` run on `master`, and manually | Publishes a GitHub release when the version has no tag yet, see [Releases](#releases) |
| `pr-title.yml` | every pull request to `master` | Fails unless the PR title is conventional (`type(scope): description`) and sets the matching type label |
| `release-notes-preview.yml` | every pull request to `master` | Comments the release notes the PR will produce |

## `ci.yml`

Three jobs:

**Core and CLI**

1. `node scripts/version.mjs check` (every copy of the version matches `build.zig.zon`, see [Releases](#releases))
2. `zig fmt --check build.zig src`
3. `zig build test` (the core's unit tests)
4. `zig build`
5. `yoshida fmt --check examples` (the examples are in canonical format)
6. `yoshida check` on every example
7. `yoshida render --offline` on every example that does not load images from the web (those are skipped so a remote site cannot break the build)

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

The public build copies the examples with `npm run examples -- --public`, which leaves out the files listed in `examples/.public-exclude`. The current examples only use fonts that may be shared, so the list is empty; add private fonts or images there if a local example needs them. A design whose font is left out falls back to the bundled Lato font and shows warning 4005. See [Third-Party Notices](@/docs/third-party-notices.md).

## Run the end-to-end test locally

```sh
cd web
npm run wasm && npm run examples && npm run build
npx vite preview --port 4173 &
npm run test:ui
```

`npm run test:ui` runs `tests/ui.mjs` and `tests/ui-organise.mjs` with Playwright in Chromium. Pass the preview URL as an argument if it is not the default.

## Releases

### Version number

The version is set in one place, `.version` in `build.zig.zon`. The Zig build passes it to the core, so `yoshida version`, the server's `/api/capabilities`, the WASM `info` call and the editor header all follow it. A few files cannot read it and keep a copy: `web/package.json`, `web/package-lock.json` and four docs pages. `scripts/version.mjs` updates them all:

```sh
node scripts/version.mjs              # print the version
node scripts/version.mjs minor        # 0.4.0 -> 0.5.0 (also: major, patch, or an exact 0.5.0-rc.1)
node scripts/version.mjs check        # fail if a copy differs from build.zig.zon
```

After a bump the script lists any other line that still names the old version, for a manual look. CI runs `check` on every pull request, and when a GitHub release is published, `deploy.yml` checks that its tag is `v` plus the version.

### Publishing a release

To release: bump on a branch, merge the pull request to `master`, and wait. `release.yml` does the rest:

1. It runs after every successful `deploy.yml` run on `master`, on the commit that was deployed.
2. If the version in `build.zig.zon` already has a tag (`v0.5.0`, or `0.5.0` like the older releases), it stops.
3. Otherwise it checks the version copies against the tag, builds the release bundle with `scripts/release.sh` and zips it as `yoshida-<version>.zip`.
4. It writes the notes with `.github/scripts/release-notes.mjs release`, then creates the tag `v<version>` and the release with the zip attached. A version with a pre-release part, such as `0.6.0-rc.1`, becomes a pre-release.
5. It starts `deploy.yml`, so the site gets the new release page. A release created by a workflow does not trigger `deploy.yml` by itself.

### Release notes

The notes are built from the pull requests merged since the last release. Each PR becomes one line, put into a section by the type in its title: `feat` is New features, `fix` Bug fixes, `perf` Performance, `docs` Documentation, `refactor`, `chore`, `ci`, `build`, `test` and `style` Maintenance, and `!` before the colon Breaking changes (sections are defined in `.github/release.yml`). `pr-title.yml` rejects titles without a type, so every PR lands in the right section. PRs with the `skip-changelog` label are left out.

Two optional extras make a release read well:

- A `release-note` block in a PR body (see the PR template) adds a sentence under **Highlights**.
- A file `.github/release-intro/<version>.md`, for example `.github/release-intro/0.7.0.md`, becomes the introduction at the top of that release. Add it in the version bump PR.

The release workflow does not need labels: the title decides. The preview comment on each PR shows exactly what its line will look like.

To retry a failed release, run `release.yml` manually from the Actions tab. It releases the version on the head of `master` if that version has no tag yet.

### Release bundle

`scripts/release.sh [OUT_DIR]` builds the release bundle: the CLI and server for the five platforms, the WASM module, and the website with the web editor in `editor/` (the same layout as Docker and GitHub Pages), plus the start scripts, the examples, the schemas, `README.md`, and `THIRD_PARTY.md` (a copy of [Third-Party Notices](@/docs/third-party-notices.md)). It needs Zig 0.16.0, Zola 0.23 and Node 22 with `web/node_modules` installed. See [Building from Source](@/docs/building-from-source.md).

The bundle contains the full examples, including their fonts. `release.yml` refuses to publish while `examples/.public-exclude` lists any file, because those files are not meant to be shared; a bundle built from such examples is **for private use only**.
