+++
title = "Contributing"
description = "How to report, propose and send changes: setup, checks, PR titles, labels and releases."
+++

Bug reports, feature wishes, docs fixes and code are all welcome. For anything bigger than a small fix, open an issue first so the direction is agreed before you spend time on it. The short version of this page is [`CONTRIBUTING.md`](https://github.com/XOYZ69/yoshida/blob/master/CONTRIBUTING.md) in the repository.

## Issues

Pick a form when you open an issue: **Bug report**, **Feature wish**, **Documentation** or **Maintenance**. The form prefills the title (`bug: `, `feat: `, `docs: `, `chore: `) and the label.

## Set up and check

[Building from Source](@/docs/building-from-source.md) installs everything you need (Zig 0.16.0, Node 22, Zola 0.23 for the website). Before a pull request, run what CI runs: see [Format check and tests](@/docs/building-from-source.md#format-check-and-tests) and [Testing](@/docs/testing.md). [Architecture](@/docs/architecture.md) shows where each part of the code lives.

When you change something users can see, update the page in `site/content/docs/` that describes it. Zola fails the build on a broken link or anchor, so `cd site && zola build --output-dir ../public` tells you.

## Pull requests

**Title.** A conventional title: `type(scope): description`.

| Type | Section of the release notes |
| --- | --- |
| `feat` | New features |
| `fix` | Bug fixes |
| `perf` | Performance |
| `docs` | Documentation |
| `refactor`, `chore`, `ci`, `build`, `test`, `style`, `revert` | Maintenance |

A `!` before the colon (`feat(api)!: remove v1`) marks a breaking change. The scope is optional and names the area (`web`, `core`, `cli`, `server`, `site`). Examples: `feat(web): add a ruler`, `fix: keep the selection after undo`. The `PR title` check fails on other titles, and the title becomes the line in the release notes, so write it for a user.

**Branches.** `feat/short-name`, `fix/short-name`, `docs/...`, `chore/...`.

**Labels.** The type label comes from the title and the `area/*` labels from the changed files, both automatically. Add `skip-changelog` to keep a PR out of the release notes.

**Release note.** Optional: one user-facing sentence in the `release-note` block of the PR template adds a line under Highlights. A comment on the PR previews the notes.

**Merging.** Pull requests are squash merged: the PR title becomes the one commit on `master`, and the full discussion and every commit stay on the PR page.

## Releases

See [Releases](@/docs/ci-and-deployment.md#releases) for bumping the version, the release notes and the introduction file.

## License

Contributions are licensed under the [MIT License](https://github.com/XOYZ69/yoshida/blob/master/LICENSE). Bundled fonts and libraries keep their own licenses, see [Third-Party Notices](@/docs/third-party-notices.md).
