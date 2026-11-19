#!/bin/sh
# #35: baut die Prüfseite der Speicher-Schicht (tool/web_store_check.dart) nach app/build/web_store_check.
# Danach: Server «web-store-check» aus .claude/launch.json (oder python3 -m http.server -d app/build/web_store_check),
# Seite öffnen, «Prüfung starten» drücken, nach dem Neuladen noch einmal.
set -e
cd "$(dirname "$0")/.."
tool/build_web_core.sh
flutter build web -t tool/web_store_check.dart -o build/web_store_check --no-wasm-dry-run 2>&1 | tail -2
