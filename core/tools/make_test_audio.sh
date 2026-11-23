#!/bin/sh
# Erzeugt das Testaudio für core/tests/audio (#14): 1 s Sinus 440 Hz, Amplitude 0,5, mono, 44,1 kHz,
# als FLAC, MP3 und AAC/M4A (#33, Browser-Dekodierung). WAV-Dateien schreiben die Tests selbst.
# #116 (trimming): 3 s stereo clicks (44.1 kHz, a click of 10 samples +0.9 / 10 samples -0.9 at
# 0.5, 1.0, 2.0 and 2.5 s, silence between) as MP3 (CBR with LAME tag, VBR with Xing tag, MPEG-2 at
# 22.05 kHz, mono with CRC), AAC in ADTS and FLAC (with a Vorbis comment and a seek table).
# #120: the clicks also as M4A with AAC and with ALAC, tagged (title, artist, album and a PNG cover
# written into the space afconvert leaves after the moov box, so the chunk offsets stay).
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
afconvert -f m4af -d aac -b 128000 "$tmp/clicks3.wav" "$tmp/clicks3.m4a"
afconvert -f m4af -d alac "$tmp/clicks3.wav" "$tmp/clicks3_alac.m4a"
for name in clicks3 clicks3_alac; do
  python3 - "$tmp/$name.m4a" "$dir/$name.m4a" <<'EOF'
import struct, sys, zlib
d = bytearray(open(sys.argv[1], "rb").read())
def box(t, body): return struct.pack(">I", 8 + len(body)) + t + body
def text(t, s): return box(t, box(b"data", struct.pack(">II", 1, 0) + s.encode()))
def chunk(t, body): return struct.pack(">I", len(body)) + t + body + struct.pack(">I", zlib.crc32(t + body))
png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 2, 2, 8, 2, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(b"\0\xff\0\0\0\xff\0\0\0\xff\0\0\xff")) + chunk(b"IEND", b""))
items = (text(b"\xa9nam", "Clicks") + text(b"\xa9ART", "Test Artist") + text(b"\xa9alb", "Test Album")
         + box(b"covr", box(b"data", struct.pack(">II", 14, 0) + png)))
def find(start, end, path):
    p = start
    while p < end:
        size, t = struct.unpack(">I4s", d[p:p + 8])
        if t == path[0]:
            if len(path) == 1: return [p]
            body = p + 8 + (4 if t == b"meta" else 0)
            return [p] + find(body, p + size, path[1:])
        p += size
    raise SystemExit("no " + path[0].decode())
chain = find(0, len(d), [b"moov", b"udta", b"meta", b"ilst"])
ilst = chain[-1]
end = ilst + struct.unpack(">I", d[ilst:ilst + 4])[0]
free = chain[0] + struct.unpack(">I", d[chain[0]:chain[0] + 4])[0]
assert d[free + 4:free + 8] == b"free"
fsize = struct.unpack(">I", d[free:free + 4])[0] - len(items)
assert fsize >= 8
d[free:free + 4] = struct.pack(">I", fsize)
for p in chain:
    d[p:p + 4] = struct.pack(">I", struct.unpack(">I", d[p:p + 4])[0] + len(items))
d[end:end] = items
del d[free + len(items) + fsize:free + len(items) + fsize + len(items)]
open(sys.argv[2], "wb").write(d)
EOF
done
ls -l "$dir"
