#!/bin/bash
# Hörvergleich #5: dieselbe Datei mit dem neuen C++-Kern (signalsmith-stretch) und mit
# AVAudioUnitTimePitch (heutige Swift-App) bei 0,5x und 0,25x rendern.
# Aufruf: tools/hoervergleich.sh <datei.mp3> [ausgabeordner] [sekunden]
# Die Ergebnisse landen ausserhalb des Repos (Standard: ~/Desktop/Woodshed-Hoervergleich).
set -euo pipefail
cd "$(dirname "$0")/.."

src="${1:?Aufruf: tools/hoervergleich.sh <datei.mp3> [ausgabeordner] [sekunden]}"
out="${2:-$HOME/Desktop/Woodshed-Hoervergleich}"
secs="${3:-30}"
mkdir -p "$out"

cmake -S core -B core/build -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build core/build --target wp_render -j 8 >/dev/null

for rate in 0.5 0.25; do
  core/build/wp_render "$src" "$out/${rate}x-neu-signalsmith.wav" "$rate" "$secs"
  swift tools/render_timepitch.swift "$src" "$out/${rate}x-alt-apple.wav" "$rate" "$secs"
done
echo "Fertig: $out"
