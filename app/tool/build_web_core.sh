#!/bin/sh
# Baut den WASM-Kern (#33) und legt ihn mit JS-Hülle und Worklet nach app/web/wp_core/ (#34), von wo
# `flutter build web` und `flutter run -d chrome` ihn ausliefern. Braucht Emscripten (emcmake).
# Aufruf: app/tool/build_web_core.sh, danach cd app && flutter build web
set -e
cd "$(dirname "$0")/../.."
[ -f core/build-wasm/CMakeCache.txt ] || emcmake cmake -S core -B core/build-wasm -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build core/build-wasm --target wp_core_web 2>&1 | tail -3
mkdir -p app/web/wp_core
cp core/build-wasm/wp_core_web.wasm core/web/wp_core_web.mjs core/web/wp_worklet.js core/web/wp_loader.js app/web/wp_core/
echo "Core is in app/web/wp_core/"
