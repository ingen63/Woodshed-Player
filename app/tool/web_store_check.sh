#!/bin/sh
# #35: builds the storage layer check page (tool/web_store_check.dart) into app/build/web_store_check.
# Then: server «web-store-check» from .claude/launch.json (or python3 -m http.server -d app/build/web_store_check),
# open the page, press «Start check», and again after the reload.
set -e
cd "$(dirname "$0")/.."
tool/build_web_core.sh
flutter build web -t tool/web_store_check.dart -o build/web_store_check --no-wasm-dry-run 2>&1 | tail -2
