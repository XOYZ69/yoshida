#!/bin/sh
# Double-click on macOS to start the editor (opens Terminal).
cd "$(dirname "$0")"
(sleep 1 && open "http://localhost:8080") &
exec ./start.sh
