+++
title = "CI and Deployment"
description = "The GitHub Actions workflows for checks, releases and this website."
+++

The GitHub Actions workflows live in `.github/workflows/`. They share two small actions: `.github/actions/setup-zig` installs Zig 0.16.0 from PyPI (the `ziglang` package ships the official release binaries) and restores Zig's build cache, and `.github/actions/setup-zola` installs Zola.

There are two long-lived branches. `master` is what is released: the site at the root and the GitHub releases. `dev` is the preview: it is published under `/dev/` with a red **DEV** stamp, and it can publish pre-releases.

| Workflow | Runs on | What it does |
| --- | --- | --- |
| `ci.yml` | every pull request, manually, and when called by `deploy.yml` | Checks and tests, below |
| `deploy.yml` | every push to `master` or `dev`, every published, edited or deleted release, and manually | Runs all of `ci.yml` for the pushed branch, then builds the site from `master` and the preview from `dev` and publishes both to GitHub Pages |
| `site.yml` | called by `deploy.yml`, once per branch | Builds the editor and the website of one branch |
| `release.yml` | every successful `deploy.yml` run on `master` or `dev`, and manually | Publishes a GitHub release when the version has no tag yet, see [Releases](#releases) |
| `pr-title.yml` | every pull request to `master` or `dev` | Fails unless the PR title is conventional (`type(scope): description`) and sets the matching type label |
| `release-notes-preview.yml` | every pull request to `master` or `dev` | Comments the release notes the PR will produce |
| `labeler.yml` | every pull request to `master` or `dev` | Adds `area/*` labels from the files the PR changes (`.github/labeler.yml`) |
| `stats.yml` | once a day, and manually | Collects the numbers for the [Stats](@/stats.md) page, see [Public stats](#public-stats) |

## `ci.yml`

Five jobs. A pull request that only changes docs, the website content or repo metadata skips the target builds and the browser tests (job **Changed files** decides); pushes, manual runs and releases always run everything.

**Core and CLI**

1. `node scripts/version.mjs check` (every copy of the version matches `build.zig.zon`, see [Releases](#releases))
2. `node scripts/llms.mjs check` (`llms.txt` and `llms-full.txt` match the schemas and sources, see [Formatting and Schemas](@/docs/formatting-and-schemas.md#for-ai-agents-llms-txt))
3. `zig fmt --check build.zig src`
4. `zig build test` (the core's unit tests)
5. `zig build -Doptimize=ReleaseSafe` (safety checks stay on, and the examples render about ten times faster than with a debug build)
6. `yoshida fmt --check examples` (the examples are in canonical format)
7. `yoshida check` on every example
8. `yoshida render --offline` on every example that does not load images from the web (those are skipped so a remote site cannot break the build; a link in a QR code does not count)

**Build for each release target**: `x86_64-linux-musl`, `aarch64-linux-musl`, `x86_64-macos`, `aarch64-macos`, `x86_64-windows-gnu`, each with `-Doptimize=ReleaseFast -Dstrip=true`.

**Web editor**: `npm ci`, build the WASM module, copy the examples, `svelte-check`, `npm run test:unit`, `vite build`, install Chromium for Playwright (the download is cached by Playwright version), then `npm run test:ui` (every `web/tests/ui*.mjs` file, see [Testing](@/docs/testing.md)) against `vite preview`. Screenshots of a failed run are uploaded as the `ui-test-results` artifact (kept 7 days).

**Website**: builds the site with Zola, which fails on any broken internal link or anchor in the docs.

Pull-request runs cancel older runs of the same PR.

**Caches.** Zig's build cache is kept per job, and per target in the five-target build. Runs on `master` and `dev` save it; pull requests only read the newest one of their base branch, so a busy pull request does not push the shared caches out of the repository's 10 GB. `npm` downloads and the Playwright browser are cached by lock file and version.

## `deploy.yml`

GitHub Pages holds one site, so every run publishes both branches together: `master` at the root and `dev` under `/dev/`.

1. **Checks**: on a push, run `ci.yml` as a reusable workflow for the pushed branch. A release event, and the run that `release.yml` starts for a new release page, skip them: those commits were checked when they were pushed.
2. **Plan**: read the Pages address and decide what to build. The pushed branch is built at the pushed commit and the other one at its head; any other event builds both heads, so editing the notes of an old release never publishes an old site.
3. **Site** and **Dev preview** (`site.yml`, in parallel): build the editor (Zig, Node 22, `npm ci`, `npm run wasm`, `npm run examples -- --public`, `npm run build`), write one page per GitHub release with `scripts/releases-to-zola.py`, build the website with Zola for its address and copy the editor into `editor/`. The preview is built with `YOSHIDA_CHANNEL=dev`.
4. **Deploy**: put the preview into `dev/` of the site and publish it to GitHub Pages.

Only one deployment runs at a time; a newer push waits instead of cancelling a deployment that is already running.

### The dev preview

<https://yoshida.xoyz.dev/dev/> is the `dev` branch: the same site and editor (`/dev/editor/`), a few commits ahead of the release. It is marked so it is not mistaken for a release: a red **DEV** stamp beside the logo and beside the version in the editor, `dev preview` in the footer, and a `noindex` tag for search engines. The preview editor keeps its saved projects in its own store in the browser, apart from those of the release editor on the same site. How a build gets the stamp is in [Building from Source](@/docs/building-from-source.md#dev-builds).

If the `dev` branch does not build, a push to `master` still publishes the site, without the preview, until `dev` is fixed; a push to `dev` publishes nothing. A repository without a `dev` branch has no preview.

### One-time setup

In the repository: **Settings → Pages → Build and deployment → Source: GitHub Actions**.

For the preview, the `dev` branch must be allowed to deploy: **Settings → Environments → github-pages → Deployment branches and tags**, add `dev` next to `master`. Without it the Deploy job of a push to `dev` is rejected by the environment's protection rule.

The project's site is published at <https://yoshida.xoyz.dev/>, a custom domain set under **Settings → Pages → Custom domain** (with a CNAME record at the DNS provider). The build takes its base URL from the Pages settings, so it works the same on a custom domain and on the default `https://<user>.github.io/<repo>/` of a fork. The default branch is assumed to be `master`; if yours is `main`, change `branches: [master, dev]` in `deploy.yml` and `release.yml`.

### What the public site contains

The site is static: rendering runs in the visitor's browser (WebAssembly) and projects are stored in the visitor's browser only. See [Saving, Images and Privacy](@/docs/saving-images-and-privacy.md).

The public build copies the examples with `npm run examples -- --public`, which leaves out the files listed in `examples/.public-exclude`. The current examples only use fonts that may be shared, so the list is empty; add private fonts or images there if a local example needs them. A design whose font is left out falls back to the bundled Lato font and shows warning 4005. See [Third-Party Notices](@/docs/third-party-notices.md).

## Public stats

The [Stats](@/stats.md) page shows numbers that GitHub counts: stars, forks, release downloads and, optionally, views and clones of the repository. The site and its editor measure nothing.

`stats.yml` runs `node scripts/stats.mjs collect` once a day. The script asks GitHub's API for the current numbers, merges them into the stored history and commits the result as `stats.json` to the `stats` branch, which holds nothing else. The first run creates the branch. The page loads the file from that branch in the visitor's browser (`stats_url` in `site/config.toml`), so a new day needs no deploy.

Two optional settings under **Settings → Secrets and variables → Actions** add more:

| Setting | Kind | What it adds |
| --- | --- | --- |
| `STATS_TRAFFIC_TOKEN` | secret | Views and clones of the repository. A fine-grained personal access token for this repository with the permission **Administration: read-only**; the workflow's own token may not read traffic. GitHub keeps traffic for 14 days, so the days accumulate from the first run on. |
| `YOSHIDA_STATS_URL` | variable | The `/api/stats` address of a self-hosted server whose public stats are shown too. The workflow fetches it, not a visitor's browser. |

GitHub runs schedules from the default branch only and pauses them after 60 days without a commit; start the workflow manually to resume. `node --test scripts/stats.test.mjs` tests the merging and runs in `ci.yml`.

## Run the end-to-end test locally

```sh
cd web
npx playwright install chromium   # once; npm ci does not download a browser
npm run wasm && npm run examples && npm run build
npx vite preview --port 4173 --strictPort &
npm run test:ui
```

`npm run test:ui` runs every `tests/ui*.mjs` file (listed in [Testing](@/docs/testing.md)) with Playwright in Chromium, one after another, until one fails. If the preview is not on `http://localhost:4173/`, set `BASE_URL` (`BASE_URL=http://localhost:5000/ npm run test:ui`); an argument after `--` only reaches the last file.

## Releases

### Version number

The version is set in one place, `.version` in `build.zig.zon`. The Zig build passes it to the core, so `yoshida version`, the server's `/api/capabilities`, the WASM `info` call and the editor header all follow it. A few files cannot read it and keep a copy: `web/package.json`, `web/package-lock.json` and four docs pages. `scripts/version.mjs` updates them all:

```sh
node scripts/version.mjs              # print the version
node scripts/version.mjs minor        # 0.4.0 -> 0.5.0 (also: major, patch, or an exact 0.5.0-rc.1)
node scripts/version.mjs check        # fail if a copy differs from build.zig.zon
```

After a bump the script lists any other line that still names the old version, for a manual look. CI runs `check` on every pull request, and when a GitHub release is published, `deploy.yml` checks that its tag names the version (`v0.6.0`; a bare `0.6.0` is accepted too).

### Publishing a release

To release: bump on a branch, merge the pull request to `master`, and wait. `release.yml` does the rest:

1. It runs after every successful `deploy.yml` run on `master` or `dev`, on the commit that was deployed.
2. If the version in `build.zig.zon` already has a tag, either `v<version>` (such as `v0.6.0`) or the bare `<version>` that releases up to 0.4.0 used (such as `0.4.0`), it stops.
3. Otherwise it checks the version copies against the tag, builds the release bundle with `scripts/release.sh` and zips it as `yoshida-<version>.zip`.
4. It writes the notes with `.github/scripts/release-notes.mjs release`, then creates the tag `v<version>` and the release with the zip attached. A version with a pre-release part, such as `0.6.0-rc.1`, becomes a pre-release.
5. It starts `deploy.yml` without the checks, so the site gets the new release page. A release created by a workflow does not trigger `deploy.yml` by itself.

### Pre-releases from `dev`

To hand out a build before it is released, give `dev` a version with a pre-release part:

```sh
node scripts/version.mjs 0.7.0-rc.1
```

Once that is pushed to `dev` and deployed, `release.yml` tags `v0.7.0-rc.1` on that commit and publishes a GitHub **pre-release** with the bundle, built as a dev build (stamped DEV). It does not replace the latest release, and its notes list what was merged since the last full release. A plain version such as `0.7.0` on `dev` publishes nothing: it is released when it reaches `master`. Before merging to `master`, set the final version (`node scripts/version.mjs 0.7.0`).

### Release notes

The notes are built from the pull requests merged since the last release. Each PR becomes one line, put into a section by the type in its title: `feat` is New features, `fix` Bug fixes, `perf` Performance, `docs` Documentation, `refactor`, `chore`, `ci`, `build`, `test`, `style` and `revert` Maintenance, and `!` before the colon Breaking changes (sections are defined in `.github/release.yml`). `pr-title.yml` rejects titles without a type, so every PR lands in the right section. PRs with the `skip-changelog` label are left out.

Two optional extras make a release read well:

- A `release-note` block in a PR body (see the PR template) adds a sentence under **Highlights**.
- A file `.github/release-intro/<version>.md`, for example `.github/release-intro/0.7.0.md`, becomes the introduction at the top of that release. Add it in the version bump PR.

The release workflow does not need labels: the title decides. The preview comment on each PR shows exactly what its line will look like.

To retry a failed release, run `release.yml` manually from the Actions tab. It releases the version on the head of `master` if that version has no tag yet.

### Release bundle

`scripts/release.sh [OUT_DIR]` builds the release bundle: the CLI and server for the five platforms, the WASM module, and the website with the web editor in `editor/` (the same layout as Docker and GitHub Pages), plus the start scripts, the examples, the schemas, `README.md`, `LICENSE`, `llms.txt` and `llms-full.txt` (the reference for AI agents), and `THIRD_PARTY.md` (a copy of [Third-Party Notices](@/docs/third-party-notices.md)). It needs Zig 0.16.0, Zola 0.23 and Node 22 with `web/node_modules` installed. See [Building from Source](@/docs/building-from-source.md).

The bundle contains the full examples, including their fonts. `release.yml` refuses to publish while `examples/.public-exclude` lists any file, because those files are not meant to be shared; a bundle built from such examples is **for private use only**.
