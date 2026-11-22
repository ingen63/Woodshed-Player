#!/bin/sh
# Erzeugt das Testaudio für core/tests/audio (#14): 1 s Sinus 440 Hz, Amplitude 0,5, mono, 44,1 kHz,
# als FLAC, MP3 und AAC/M4A (#33, Browser-Dekodierung). WAV-Dateien schreiben die Tests selbst.
# #116 (trimming): 3 s stereo clicks (44.1 kHz, a click of 10 samples +0.9 / 10 samples -0.9 at
# 0.5, 1.0, 2.0 and 2.5 s, silence between) as MP3 (CBR with LAME tag, VBR with Xing tag, MPEG-2 at
# 22.05 kHz, mono with CRC), AAC in ADTS and FLAC (with a Vorbis comment and a seek table).
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
python3 - "$tmp/clicks3.wav" <<'EOF'
import struct, sys, wave
sr, n = 44100, 3 * 44100
s = [0] * n
for t in (0.5, 1.0, 2.0, 2.5):
    c = round(t * sr)
    for k in range(20):
        s[c + k] = 29491 if k < 10 else -29491
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(b"".join(struct.pack("<hh", v, v) for v in s))
EOF
flac --silent --force --best -o "$dir/sine440.flac" "$tmp/sine440.wav"
flac --silent --force -T TITLE=Clicks -o "$dir/clicks3.flac" "$tmp/clicks3.wav"
lame --silent -b 128 "$tmp/clicks3.wav" "$dir/clicks3.mp3"
lame --silent -V 2 "$tmp/clicks3.wav" "$dir/clicks3_vbr.mp3"
lame --silent --resample 22.05 -b 48 "$tmp/clicks3.wav" "$dir/clicks3_22k.mp3"
lame --silent -p -m m -b 64 "$tmp/clicks3.wav" "$dir/clicks3_crc.mp3"
afconvert -f adts -d aac -b 128000 "$tmp/clicks3.wav" "$dir/clicks3.aac"
lame --silent -b 128 "$tmp/sine440.wav" "$dir/sine440.mp3"
afconvert -f m4af -d aac -b 128000 "$tmp/sine440.wav" "$dir/sine440.m4a"
ls -l "$dir"
