#!/bin/sh
# #34/AK3: baut die Prüfseite der Web-Anbindung (tool/web_core_check.dart) nach app/build/web_check.
# Danach: Server «web-check» aus .claude/launch.json (oder python3 -m http.server -d app/build/web_check),
# Seite öffnen und «Prüfung starten» drücken.
set -e
cd "$(dirname "$0")/.."
tool/build_web_core.sh
flutter build web -t tool/web_core_check.dart -o build/web_check --no-wasm-dry-run 2>&1 | tail -2
cp ../core/tests/audio/sine440.m4a build/web_check/
