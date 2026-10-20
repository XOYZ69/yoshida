#!/usr/bin/env bash
# Creates or updates the yoshida issue and pull request labels. Safe to
# re-run (--force upserts). Needs the gh CLI, logged in with write access.
# Usage: ./scripts/gh-labels.sh   (set REPO to use another repository)
set -euo pipefail
REPO="${REPO:-XOYZ69/yoshida}"

l() { gh label create "$1" --repo "$REPO" --color "$2" --description "$3" --force; }

# Type. A PR title sets one of these automatically (see release-notes.mjs):
# feat enhancement, fix bug, perf performance, docs documentation,
# refactor/chore/ci/build/test/style/revert maintenance, "!" breaking-change.
l enhancement     a2eeef "New feature or improvement (feat)"
l bug             d73a4a "Something isn't working (fix)"
l performance     fef2c0 "Faster or lighter (perf)"
l documentation   0075ca "Improvements or additions to documentation (docs)"
l maintenance     ededed "Refactoring, tooling, CI, tests (refactor, chore, ci, ...)"
l breaking-change b60205 "Changes behaviour or files people already have"
l question        d876e3 "Needs an answer, not a code change"
# Older issues; new ones use enhancement.
l feature_wish    0ac5c5 "Deprecated: use enhancement"

# Area. Pull requests get these automatically from the files they change
# (.github/labeler.yml).
l area/web-editor 1d76db "Browser editor (web/)"
l area/cli        5319e7 "Command line tool (src/cli)"
l area/server     0e8a16 "HTTP server and Docker image"
l area/wasm       fbca04 "WebAssembly build"
l area/format     c5def5 "Design / card data format, schemas and examples"
l area/core       bfdadc "Rendering core"
l area/docs       0075ca "Documentation and website"
l area/ci         ffffff "Workflows, scripts and repo settings"

# Release notes
l skip-changelog  ffffff "Leave this PR out of the release notes"

# Status
l status/needs-info  fef2c0 "Waiting for more details from the reporter"
l status/confirmed   ededed "Reproduced / accepted"
l status/blocked     b60205 "Waiting on something else"
l duplicate          cfd3d7 "This issue or pull request already exists"
l wontfix            ffffff "Will not be worked on"
l "good first issue" 7057ff "Good for newcomers"
l "help wanted"      008672 "Extra attention is needed"
