#!/bin/sh
# Starts the yoshida website, editor and render server on http://localhost:8080
# (another port: ./start.sh 9000). The editor is at /editor/, the docs at
# /docs/. Stop it with Ctrl+C.
set -eu
cd "$(dirname "$0")"
PORT=${1:-8080}
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) dir=x86_64-linux ;;
  Linux-aarch64 | Linux-arm64) dir=aarch64-linux ;;
  Darwin-x86_64) dir=x86_64-macos ;;
  Darwin-arm64) dir=aarch64-macos ;;
  *) echo "No prebuilt binary for $(uname -s) $(uname -m); build from source (see README.md)." >&2; exit 1 ;;
esac
BIN="bin/$dir"
chmod +x "$BIN/yoshida" "$BIN/yoshida-server" 2>/dev/null || true
# macOS marks downloaded files as quarantined; the binaries are unsigned.
if [ "$(uname -s)" = Darwin ]; then xattr -dr com.apple.quarantine "$BIN" 2>/dev/null || true; fi
echo "Open http://localhost:$PORT/editor/ in your browser (docs: http://localhost:$PORT/docs/)."
exec "$BIN/yoshida-server" --host 127.0.0.1 --port "$PORT" --web web
