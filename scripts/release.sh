#!/bin/sh
# Builds the release bundle: CLI and server for five platforms, the WASM
# module, and the website with the web editor in editor/ (the same layout as
# the Docker image and GitHub Pages), plus start scripts.
#
#   scripts/release.sh [OUT_DIR]      (default: release/)
#
# Needs Zig 0.16.0, Zola 0.23 (set ZOLA to use another binary) and Node 22
# with web/node_modules installed.
set -eu
cd "$(dirname "$0")/.."
OUT=${1:-release}
ZOLA=${ZOLA:-zola}
case "$("$ZOLA" --version 2>/dev/null)" in
  "zola 0.23."*) ;;
  *) echo "release.sh needs Zola 0.23 (https://www.getzola.org/), or ZOLA=/path/to/zola" >&2; exit 1 ;;
esac
rm -rf "$OUT"
mkdir -p "$OUT/bin"

zig build test
(cd web && npm run wasm && npm run examples && npm run build)
# Site at /, editor at /editor/. No release pages: those come from GitHub
# Releases when the site is deployed.
web=$(cd "$OUT" && pwd)/web
(cd site && "$ZOLA" build --base-url / --output-dir "$web")
cp -r web/dist "$OUT/web/editor"

for t in x86_64-linux-musl aarch64-linux-musl x86_64-macos aarch64-macos x86_64-windows-gnu; do
  echo "building $t"
  rm -rf zig-out/bin
  zig build -Dtarget="$t" -Doptimize=ReleaseFast -Dstrip=true
  name=$(echo "$t" | sed 's/-musl$//; s/-gnu$//')
  mkdir -p "$OUT/bin/$name"
  cp zig-out/bin/yoshida* "$OUT/bin/$name/"
  rm -f "$OUT/bin/$name"/*.pdb
done
rm -rf zig-out/bin
zig build -Doptimize=ReleaseFast

cp -r examples schema README.md LICENSE "$OUT/"
# The notices live on the docs page; ship them as plain Markdown (front matter
# turned into a heading, Zola's raw markers removed). The bundle's site has them at /docs/third-party-notices/.
sed -e '1,/^+++$/{s/^title = "\(.*\)"$/# \1/p;d;}' -e 's/{% *raw *%}//g; s/{% *endraw *%}//g' \
  site/content/docs/third-party-notices.md > "$OUT/THIRD_PARTY.md"
cp scripts/start.sh scripts/start.bat scripts/start.command "$OUT/"
chmod +x "$OUT/start.sh" "$OUT/start.command"
echo "release written to $OUT"
