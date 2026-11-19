#!/bin/bash
# Baut den Machbarkeitstest W0 (#32): Engine und Metronom als WebAssembly für die Testseite web/w0/.
# Voraussetzung: Emscripten (emcc), z. B. «brew install emscripten» oder emsdk.
# Aufruf: core/web/build_w0.sh [ausgabeordner]   (Standard: web/w0)
set -euo pipefail
core="$(cd "$(dirname "$0")/.." && pwd)"
out="${1:-$core/../web/w0}"
mkdir -p "$out"

exports='["_w0_init","_w0_alloc_source","_w0_commit_source","_w0_play","_w0_pause","_w0_seek",
"_w0_set_rate","_w0_set_loop","_w0_set_volume","_w0_playing","_w0_position","_w0_duration",
"_w0_loop_passes","_w0_metronome","_w0_tick_deviation_ms","_w0_tick_count","_w0_render"]'

# STANDALONE_WASM: reine .wasm-Datei ohne JS-Hülle, damit sie direkt im AudioWorklet läuft.
em++ -O3 -std=c++17 -msimd128 \
  -I "$core/src" \
  -I "$core/third_party/signalsmith-stretch/include" \
  -I "$core/third_party/signalsmith-linear/include" \
  "$core/web/w0_bridge.cpp" "$core/src/engine.cpp" "$core/src/metronome.cpp" \
  -sSTANDALONE_WASM --no-entry -sFILESYSTEM=0 \
  -sINITIAL_MEMORY=64MB -sALLOW_MEMORY_GROWTH=1 -sMAXIMUM_MEMORY=1GB \
  -sEXPORTED_FUNCTIONS="$(echo "$exports" | tr -d '\n')" \
  -o "$out/w0.wasm"

echo "$out/w0.wasm ($(wc -c < "$out/w0.wasm" | tr -d ' ') Bytes)"
