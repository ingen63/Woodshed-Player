#!/bin/sh
# Erzeugt das Testaudio für core/tests/audio (#14): 1 s Sinus 440 Hz, Amplitude 0,5, mono, 44,1 kHz,
# als FLAC, MP3 und AAC/M4A (#33, Browser-Dekodierung). WAV-Dateien schreiben die Tests selbst.
# Braucht python3, flac, lame und afconvert (macOS).
set -eu
dir="$(cd "$(dirname "$0")/../tests/audio" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
python3 - "$tmp/sine440.wav" <<'EOF'
import math, struct, sys, wave
sr, n = 44100, 44100
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(b"".join(struct.pack("<h", round(0.5 * 32767 * math.sin(2 * math.pi * 440 * i / sr))) for i in range(n)))
EOF
flac --silent --force --best -o "$dir/sine440.flac" "$tmp/sine440.wav"
lame --silent -b 128 "$tmp/sine440.wav" "$dir/sine440.mp3"
afconvert -f m4af -d aac -b 128000 "$tmp/sine440.wav" "$dir/sine440.m4a"
ls -l "$dir"
