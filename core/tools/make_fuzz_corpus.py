#!/usr/bin/env python3
"""Writes the start corpus of the fuzz targets (#10/AK4) to core/tests/fuzz/corpus/.

Only generated data, no foreign audio files: small WAV files (8/16/24-bit, float, mono and stereo,
sine and ramp), damaged WAV headers, the first bytes of the project's own test audio
(core/tests/audio/sine440.*, made by make_test_audio.sh) and command programs for fuzz_capi
(format in core/tests/fuzz/fuzz_capi.cpp). Run again after changing the format of fuzz_capi.
"""
import math
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests", "fuzz", "corpus")
AUDIO = os.path.join(ROOT, "tests", "audio")


def wav(frames, channels=1, rate=8000, bits=16, fmt=1, sample=None, data_size=None):
    """RIFF/WAVE with a PCM (fmt 1) or float (fmt 3) data chunk."""
    sample = sample or (lambda i, c: 0.5 * math.sin(2 * math.pi * 440 * i / rate))
    body = bytearray()
    for i in range(frames):
        for c in range(channels):
            v = sample(i, c)
            if fmt == 3:
                body += struct.pack("<f", v)
            elif bits == 8:
                body += struct.pack("<B", max(0, min(255, round(128 + 127 * v))))
            elif bits == 16:
                body += struct.pack("<h", round(32767 * v))
            elif bits == 24:
                body += struct.pack("<i", round(8388607 * v))[:3]
    block = channels * bits // 8
    fmt_chunk = struct.pack("<HHIIHH", fmt, channels, rate, rate * block, block, bits)
    size = len(body) if data_size is None else data_size
    return (b"RIFF" + struct.pack("<I", 4 + 8 + len(fmt_chunk) + 8 + len(body)) + b"WAVE"
            + b"fmt " + struct.pack("<I", len(fmt_chunk)) + fmt_chunk
            + b"data" + struct.pack("<I", size) + bytes(body))


def head(name, n):
    with open(os.path.join(AUDIO, name), "rb") as f:
        return f.read(n)


def decoder_corpus():
    ramp = lambda i, c: (i % 100) / 100.0 - 0.5 if c == 0 else 0.5 - (i % 100) / 100.0
    full = wav(400, 2, 8000, 16, sample=ramp)
    return {
        "wav16_mono": wav(400),
        "wav16_stereo_ramp": full,
        "wav8_stereo": wav(300, 2, 11025, 8),
        "wav24_mono": wav(300, 1, 22050, 24),
        "wav_float_stereo": wav(300, 2, 8000, 32, fmt=3),
        "wav_header_only": wav(0),
        "wav_truncated": full[: len(full) // 2],
        "wav_huge_data_size": wav(50, data_size=0x7FFFFFF0),
        "wav_zero_channels": full[:22] + b"\x00\x00" + full[24:],
        "wav_zero_rate": full[:24] + b"\x00\x00\x00\x00" + full[28:],
        "flac_head": head("sine440.flac", 1500),
        "mp3_head": head("sine440.mp3", 1500),
        "garbage": bytes(range(256)),
    }


# fuzz_capi: first byte picks the rate (index into 8000, 22050, 44100, 48000, 96000)
(LOAD_ENCODED, LOAD_PCM, LOAD_FILE, PLAY, PAUSE, SEEK, RATE, LOOP, VOLUME, RENDER, RENDER_LONG,
 METRO_START, METRO_STOP, METRO_BPM, METRO_METER, METRO_SUBDIV, METRO_VOLUME, METRO_RAMP,
 METRO_RAMP_SEC, WAVEFORM) = range(20)


def u16(v):
    return struct.pack("<H", v)


def u32(v):
    return struct.pack("<I", v & 0xFFFFFFFF)


def sec(s):
    """Plausible seconds: kind < 200, hundredths."""
    return bytes([0]) + u32(round(s * 100))


def raw(d):
    """Any double (kind >= 230)."""
    return bytes([255]) + struct.pack("<d", d)


def program(rate_index, *ops):
    return bytes([rate_index]) + b"".join(bytes([o[0]]) + b"".join(o[1:]) for o in ops)


def capi_corpus():
    tone = wav(16000, 1, 8000, 16)  # 2 s
    pcm = (LOAD_PCM, bytes([1]), u32(66150), bytes([2]))  # stereo 1.5 s at 44.1 kHz
    return {
        "play_render": program(2, pcm, (PLAY,), (RENDER_LONG, bytes([40]))),
        "loop_seek_rate": program(2, pcm, (LOOP, sec(0.2), sec(1.3)), (PLAY,),
                                  (RATE, bytes([10])), (RENDER_LONG, bytes([63])),
                                  (SEEK, sec(1.4)), (RENDER_LONG, bytes([20])),
                                  (RATE, bytes([38])), (RENDER, u16(4096))),
        "encoded_wav": program(0, (LOAD_ENCODED, u16(len(tone)), tone), (PLAY,),
                               (RENDER_LONG, bytes([63])), (WAVEFORM, sec(0), sec(2), bytes([64]))),
        "file_wav": program(1, (LOAD_FILE, u16(len(tone)), tone), (SEEK, sec(1.0)), (PLAY,),
                            (RENDER_LONG, bytes([10]))),
        "metronome": program(3, (METRO_BPM, u32(180)), (METRO_METER, u32(6)),
                             (METRO_SUBDIV, u32(3)), (METRO_START,), (RENDER_LONG, bytes([63])),
                             (METRO_RAMP, bytes([1]), u32(60), u32(90), u32(5), u32(1)),
                             (RENDER_LONG, bytes([63])),
                             (METRO_RAMP_SEC, bytes([1]), u32(100), u32(120), u32(1)),
                             (RENDER_LONG, bytes([63])), (METRO_STOP,)),
        "extremes": program(4, pcm, (SEEK, raw(1e300)), (LOOP, raw(-1.0), raw(1e18)),
                            (RATE, bytes([200]), struct.pack("<d", 1e-300)),
                            (VOLUME, bytes([200]), struct.pack("<f", 0.5)), (PLAY,),
                            (RENDER_LONG, bytes([8])), (PAUSE,), (RENDER, u16(0))),
    }


def write(kind, files):
    d = os.path.join(OUT, kind)
    os.makedirs(d, exist_ok=True)
    for name, data in files.items():
        with open(os.path.join(d, name), "wb") as f:
            f.write(data)
    print(f"{kind}: {len(files)} files, {sum(len(v) for v in files.values())} bytes")


if __name__ == "__main__":
    write("decoder", decoder_corpus())
    write("capi", capi_corpus())
    sys.exit(0)
