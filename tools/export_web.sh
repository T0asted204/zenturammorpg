#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/web
"${GODOT:-godot}" --headless --path . --editor --import --quit
"${GODOT:-godot}" --headless --path . --export-release Web build/web/index.html
