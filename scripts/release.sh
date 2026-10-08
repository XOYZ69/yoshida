#!/bin/sh
# Builds the release bundle: CLI and server for five platforms, the WASM
# module and the web editor, plus start scripts.
#
#   scripts/release.sh [OUT_DIR]      (default: release/)
#
# Needs Zig 0.16.0 and Node 22 with web/node_modules installed.
set -eu
cd "$(dirname "$0")/.."
OUT=${1:-release}
rm -rf "$OUT"
mkdir -p "$OUT/bin"

zig build test
(cd web && npm run wasm && npm run examples && npm run build)
cp -r web/dist "$OUT/web"

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

cp -r examples schema README.md THIRD_PARTY.md "$OUT/"
cp scripts/start.sh scripts/start.bat scripts/start.command "$OUT/"
chmod +x "$OUT/start.sh" "$OUT/start.command"
echo "release written to $OUT"
