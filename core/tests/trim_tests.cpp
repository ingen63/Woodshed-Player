// #116: trimming start and end of WAV, FLAC, MP3 and ADTS files (src/trim.cpp; MP4 in
// trim_mp4_tests.cpp). The trimmed files
// are decoded again by the core (wp::decodeMemory, the path of the player and the web core) and
// checked against the positions of the clicks in the test audio: clicks3.* has clicks at 0.5, 1.0,
// 2.0 and 2.5 s (core/tools/make_test_audio.sh), WAV and FLAC files are generated here.
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "flac_writer.hpp"
#include "player_core.hpp"
#include "trim.hpp"
#include "wp_core.h"

namespace {

int failures = 0;

#define CHECK(cond)                                                                                \
  do {                                                                                             \
    if (!(cond)) {                                                                                 \
      ++failures;                                                                                  \
      std::printf("  FAILED %s:%d: %s\n", __FILE__, __LINE__, #cond);                              \
    }                                                                                              \
  } while (0)

#define CHECK_NEAR(a, b, tol) CHECK(std::fabs((a) - (b)) <= (tol))

using Bytes = std::vector<uint8_t>;
using wp::trim::Format;

constexpr int kRate = 44100;
// #116/AK4: the cut may be off by at most 50 ms.
constexpr double kMaxDeviation = 0.050;

Bytes readFile(const std::string &name) {
  std::ifstream f(std::string(WP_TEST_AUDIO_DIR) + "/" + name, std::ios::binary);
  return Bytes(std::istreambuf_iterator<char>(f), {});
}

// Stereo float frames of a file at `rate`, as the player decodes it; empty if it cannot.
std::vector<float> decode(const Bytes &b, int rate = kRate) {
  wp::Source s;
  if (wp::decodeMemory(b.data(), b.size(), rate, s) != wp::kOk)
    return {};
  return s.data;
}

long long frames(const std::vector<float> &stereo) {
  return static_cast<long long>(stereo.size() / 2);
}

// Frame of the first click (left channel above 0.3) at or after frame `from`; -1 if there is none.
long long click(const std::vector<float> &stereo, long long from = 0) {
  for (long long i = std::max(0LL, from); i < frames(stereo); ++i)
    if (std::fabs(stereo[static_cast<size_t>(i) * 2]) > 0.3f)
      return i;
  return -1;
}

// Loudest sample in frames [from, to).
float peak(const std::vector<float> &stereo, long long from, long long to) {
  float m = 0;
  for (long long i = std::max(0LL, from); i < std::min(to, frames(stereo)); ++i)
    m = std::max(m, std::fabs(stereo[static_cast<size_t>(i) * 2]));
  return m;
}

void u16(Bytes &b, unsigned v) {
  b.push_back(static_cast<uint8_t>(v & 0xff));
  b.push_back(static_cast<uint8_t>((v >> 8) & 0xff));
}
void u32(Bytes &b, unsigned v) {
  u16(b, v & 0xffff);
  u16(b, v >> 16);
}
void tag(Bytes &b, const char *t) { b.insert(b.end(), t, t + 4); }

// Stereo WAV, 3 s at 44.1 kHz: frame i holds i (16 bit: i % 30000, float: i / 2^24) on the left and
// its negative on the right, so every frame of the result names its position in the original. A
// LIST chunk before and an «id3 » chunk after the data must stay; float files get a fact chunk.
Bytes wav(bool isFloat, long long n = 3LL * kRate) {
  const unsigned bytesPerSample = isFloat ? 4 : 2;
  const unsigned align = 2 * bytesPerSample;
  const unsigned dataBytes = static_cast<unsigned>(n) * align;
  Bytes b;
  tag(b, "RIFF");
  u32(b, 0); // patched below
  tag(b, "WAVE");
  tag(b, "fmt ");
  u32(b, 16);
  u16(b, isFloat ? 3 : 1);
  u16(b, 2);
  u32(b, kRate);
  u32(b, kRate * align);
  u16(b, align);
  u16(b, bytesPerSample * 8);
  if (isFloat) {
    tag(b, "fact");
    u32(b, 4);
    u32(b, static_cast<unsigned>(n));
  }
  tag(b, "LIST");
  u32(b, 5);
  b.insert(b.end(), {'I', 'N', 'F', 'O', 'x', 0}); // odd length, padded
  tag(b, "data");
  u32(b, dataBytes);
  for (long long i = 0; i < n; ++i) {
    for (int c = 0; c < 2; ++c) {
      if (isFloat) {
        float v = static_cast<float>(static_cast<double>(i + 1) / 16777216.0) * (c ? -1.0f : 1.0f);
        uint32_t bits = 0;
        std::memcpy(&bits, &v, 4);
        u32(b, bits);
      } else {
        const int v = static_cast<int>(i % 30000) * (c ? -1 : 1);
        u16(b, static_cast<unsigned>(v) & 0xffff);
      }
    }
  }
  tag(b, "id3 ");
  u32(b, 4);
  b.insert(b.end(), {'T', 'A', 'G', '!'});
  const unsigned riff = static_cast<unsigned>(b.size() - 8);
  for (int i = 0; i < 4; ++i)
    b[4 + i] = static_cast<uint8_t>(riff >> (8 * i));
  return b;
}

bool contains(const Bytes &b, const char *text) {
  const size_t n = std::strlen(text);
  return std::search(b.begin(), b.end(), text, text + n) != b.end();
}

// ---- WAV ----

void wav16CutsExactlyAndKeepsChunks() { // #116/AK4
  const Bytes in = wav(false);
  const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
  CHECK(r.code == WP_OK);
  CHECK(wp::trim::detect(r.bytes.data(), r.bytes.size()) == Format::Wav);
  CHECK(r.start == 30870.0 / kRate); // round(0.7 × 44100) = 30870
  CHECK(r.end == 97020.0 / kRate);   // round(2.2 × 44100) = 97020
  // Header 12 + fmt 24 + LIST 14 (5 bytes padded) + data header 8, 66150 frames × 4 bytes, id3 12
  CHECK(r.bytes.size() == 12 + 24 + 14 + 8 + 66150 * 4 + 12);
  CHECK(contains(r.bytes, "INFOx") && contains(r.bytes, "TAG!"));
  const std::vector<float> out = decode(r.bytes);
  CHECK(frames(out) == 66150); // (2.2 − 0.7) × 44100
  // Frame 0 is old frame 30870 (value 30870 % 30000 = 870), the last old frame 97019 (7019).
  CHECK(std::lround(out[0] * 32768.0f) == 870 && std::lround(out[1] * 32768.0f) == -870);
  CHECK(std::lround(out.back() * 32768.0f) == -7019);
  // The RIFF size covers the whole new file.
  CHECK(r.bytes[4] + (r.bytes[5] << 8) + (r.bytes[6] << 16) + (r.bytes[7] << 24) ==
        static_cast<int>(r.bytes.size() - 8));
}

void wavFloatUpdatesFact() { // #116/AK4
  const Bytes in = wav(true);
  const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.5, 2.0);
  CHECK(r.code == WP_OK);
  // fact chunk right after fmt: sample count (2.0 − 0.5) × 44100 = 66150
  const uint8_t *fact = r.bytes.data() + 12 + 24 + 8;
  CHECK(std::memcmp(r.bytes.data() + 36, "fact", 4) == 0);
  CHECK((fact[0] | (fact[1] << 8) | (fact[2] << 16)) == 66150);
  const std::vector<float> out = decode(r.bytes);
  CHECK(frames(out) == 66150);
  // frame 0 = old frame 22050, stored as (22050 + 1) / 2^24
  CHECK(std::llround(out[0] * 16777216.0) == 22051);
}

// ---- FLAC ----

void flacStaysLosslessWithTags() { // #116/AK4
  const Bytes in = readFile("clicks3.flac");
  const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
  CHECK(r.code == WP_OK);
  CHECK(wp::trim::detect(r.bytes.data(), r.bytes.size()) == Format::Flac);
  CHECK(r.start == 30870.0 / kRate && r.end == 97020.0 / kRate);
  // The Vorbis comment stays, the seek table (it points into the old audio) goes.
  CHECK(contains(r.bytes, "TITLE=Clicks"));
  bool seekTable = false;
  for (size_t p = 4; p + 4 <= r.bytes.size();) {
    seekTable = seekTable || (r.bytes[p] & 0x7F) == 3;
    const size_t len =
        (size_t{r.bytes[p + 1]} << 16) | (size_t{r.bytes[p + 2]} << 8) | r.bytes[p + 3];
    if (r.bytes[p] & 0x80)
      break;
    p += 4 + len;
  }
  CHECK(!seekTable);
  // Lossless: the samples are those of the original from frame 30870 on.
  const std::vector<float> old = decode(in), out = decode(r.bytes);
  CHECK(frames(out) == 66150);
  CHECK(std::equal(out.begin(), out.end(), old.begin() + 30870 * 2));
  CHECK(click(out) == 13230); // the click at 1.0 s is now at (1.0 − 0.7) × 44100
}

// FLAC files of other depths stay at their depth and lossless (16 and 24 bit, the recording's).
void flacKeepsBitDepth() { // #116/AK4
  for (const uint32_t bits : {16u, 24u}) {
    Bytes in;
    wp::FlacWriter w;
    CHECK(w.openMemory(&in, kRate, 1, bits));
    std::vector<int32_t> s(2 * kRate);
    const int32_t top = (1 << (bits - 1)) - 1;
    for (size_t i = 0; i < s.size(); ++i)
      s[i] = static_cast<int32_t>((static_cast<long long>(i) * 7919) % (2LL * top)) - top;
    CHECK(w.writeInt(s.data(), static_cast<uint32_t>(s.size())));
    CHECK(w.close());
    const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.25, 1.75);
    CHECK(r.code == WP_OK);
    // bits per sample − 1 in the stream info (byte 8 + 12/13)
    CHECK((((r.bytes[8 + 12] & 1) << 4) | (r.bytes[8 + 13] >> 4)) + 1 == static_cast<int>(bits));
    const std::vector<float> old = decode(in), out = decode(r.bytes);
    CHECK(frames(out) == 66150); // 1.5 s
    CHECK(std::equal(out.begin(), out.end(), old.begin() + 11025 * 2));
  }
}

void flacWriterMemoryLimits() { // #116: depths libFLAC stores, nothing open after close
  Bytes out;
  wp::FlacWriter w;
  CHECK(!w.openMemory(nullptr, kRate, 2, 16));
  CHECK(!w.openMemory(&out, kRate, 2, 3));
  CHECK(!w.openMemory(&out, kRate, 2, 33));
  CHECK(!w.openMemory(&out, kRate, 0, 16));
  // a target that holds something already is emptied first
  out.assign(100, 0x55);
  CHECK(w.openMemory(&out, kRate, 2, 4));
  CHECK(w.close());
  CHECK(std::memcmp(out.data(), "fLaC", 4) == 0);
  CHECK(w.openMemory(&out, kRate, 2, 32));
  const int32_t big[2] = {2147483647, -2147483647};
  CHECK(w.writeInt(big, 1));
  CHECK(w.close());
  CHECK(!w.writeInt(big, 1));
  CHECK(out.size() > 42 && std::memcmp(out.data(), "fLaC", 4) == 0);
}

// ---- MP3 ----

// MP3 with the clicks at 1.0 and 2.0 s cut to [0.7, 2.2]: they must sit at 0.3 and 1.3 s.
void checkMp3(const char *file, int rate, bool vbr) {
  const Bytes in = readFile(file);
  CHECK(!in.empty());
  const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
  CHECK(r.code == WP_OK);
  CHECK(wp::trim::detect(r.bytes.data(), r.bytes.size()) == Format::Mp3);
  CHECK(r.bytes.size() < in.size());
  CHECK(contains(r.bytes, vbr ? "Xing" : "Info") && !contains(r.bytes, vbr ? "Info" : "Xing"));
  CHECK_NEAR(r.start, 0.7, 1.0 / rate);
  CHECK_NEAR(r.end, 2.2, 1.0 / rate);
  const std::vector<float> out = decode(r.bytes, rate);
  // #116/AK4: the decoder of the core honours the LAME tag, so the cut is exact to the sample
  CHECK(std::llabs(frames(out) - std::llround(1.5 * rate)) <= 1);
  const std::vector<float> old = decode(in, rate);
  const long long c1 = click(old, std::llround(0.9 * rate));
  const long long c2 = click(old, std::llround(1.9 * rate));
  const long long n1 = click(out), n2 = click(out, std::llround(1.2 * rate));
  const long long shift = std::llround(0.7 * rate);
  CHECK(c1 > 0 && c2 > 0 && n1 >= 0 && n2 > 0);
  CHECK(std::llabs(n1 - (c1 - shift)) <= 1);
  CHECK(std::llabs(n2 - (c2 - shift)) <= 1);
  CHECK(std::fabs((n1 - (c1 - shift)) / static_cast<double>(rate)) <= kMaxDeviation);
  // No click at the new start: the frames before it (bit reservoir, overlap) came along.
  CHECK(peak(out, 0, std::llround(0.2 * rate)) < 0.02f);
  // Trimming the result again (it has the new LAME tag) still lands on the samples.
  const wp::trim::Result again = wp::trim::trim(r.bytes.data(), r.bytes.size(), 0.2, 1.4);
  CHECK(again.code == WP_OK);
  const std::vector<float> twice = decode(again.bytes, rate);
  CHECK(std::llabs(frames(twice) - std::llround(1.2 * rate)) <= 1);
  CHECK(std::llabs(click(twice) - (c1 - std::llround(0.9 * rate))) <= 1);
}

void mp3CbrVbrAndMpeg2() { // #116/AK4
  checkMp3("clicks3.mp3", kRate, false);
  checkMp3("clicks3_vbr.mp3", kRate, true);
  checkMp3("clicks3_22k.mp3", 22050, false);
}

void mp3KeepsId3Tags() { // #116/AK4: ID3v2 before and ID3v1 after the audio stay
  const Bytes mp3 = readFile("clicks3.mp3");
  Bytes in = {'I', 'D', '3', 4, 0, 0, 0, 0, 0, 10};
  in.insert(in.end(), {'T', 'I', 'T', '2', 0, 0, 0, 0, 0, 0});
  in.insert(in.end(), mp3.begin(), mp3.end());
  Bytes v1(128, 0);
  std::memcpy(v1.data(), "TAGTrimmed title", 16);
  in.insert(in.end(), v1.begin(), v1.end());
  const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
  CHECK(r.code == WP_OK);
  CHECK(std::equal(in.begin(), in.begin() + 20, r.bytes.begin()));
  CHECK(std::equal(v1.begin(), v1.end(), r.bytes.end() - 128));
  CHECK(wp::trim::detect(r.bytes.data(), r.bytes.size()) == Format::Mp3);
  CHECK(std::llabs(frames(decode(r.bytes)) - 66150) <= 1);
}

// Without an Info frame the decoder plays every sample of every frame; the cut adds a LAME tag.
void mp3WithoutLameTag() { // #116/AK4
  const Bytes mp3 = readFile("clicks3.mp3");
  // The first frame is the Info frame: 128 kbit/s at 44.1 kHz, 417 or 418 bytes (padding bit).
  const size_t info = (mp3[2] & 2) ? 418 : 417;
  const Bytes in(mp3.begin() + static_cast<long>(info), mp3.end());
  const std::vector<float> old = decode(in);
  const long long c1 = click(old, std::llround(0.9 * kRate));
  CHECK(c1 > std::llround(1.0 * kRate)); // later by the encoder and decoder delay (576 + 529)
  const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
  CHECK(r.code == WP_OK);
  const std::vector<float> out = decode(r.bytes);
  CHECK(std::llabs(frames(out) - 66150) <= 1);
  CHECK(std::llabs(click(out) - (c1 - 30870)) <= 1);
}

// ---- AAC in ADTS ----

void adtsAtFrameBoundaries() { // #116/AK4
  const Bytes in = readFile("clicks3.aac");
  CHECK(wp::trim::detect(in.data(), in.size()) == Format::Adts);
  const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
  CHECK(r.code == WP_OK);
  CHECK(wp::trim::detect(r.bytes.data(), r.bytes.size()) == Format::Adts);
  // Frames of 1024 samples: 0.7 × 44100 / 1024 = 30.1 → frame 30 (0.6966 s); 2.2 s → 94.7 → 95.
  CHECK(r.start == 30 * 1024.0 / kRate);
  CHECK(r.end == 95 * 1024.0 / kRate);
  CHECK(std::fabs(r.start - 0.7) <= kMaxDeviation && std::fabs(r.end - 2.2) <= kMaxDeviation);
  // The result is the original frames 30 to 94, unchanged.
  size_t p = 0, i = 0, from = 0;
  while (p + 7 <= in.size() && i < 30) {
    p += ((size_t{in[p + 3]} & 3) << 11) | (size_t{in[p + 4]} << 3) | (in[p + 5] >> 5);
    ++i;
  }
  from = p;
  size_t to = p;
  for (; i < 95; ++i)
    to += ((size_t{in[to + 3]} & 3) << 11) | (size_t{in[to + 4]} << 3) | (in[to + 5] >> 5);
  CHECK(r.bytes.size() == to - from);
  CHECK(std::equal(r.bytes.begin(), r.bytes.end(), in.begin() + static_cast<long>(from)));
}

// ---- Rules and errors ----

void rangeRules() { // #116/AK7
  const Bytes in = wav(false);
  // at least 1 s remains, the end lies after the start
  CHECK(wp::trim::trim(in.data(), in.size(), 1.0, 1.999).code == WP_ERR_INVALID_ARGUMENT);
  CHECK(wp::trim::trim(in.data(), in.size(), 2.0, 1.0).code == WP_ERR_INVALID_ARGUMENT);
  CHECK(wp::trim::trim(in.data(), in.size(), NAN, 2.0).code == WP_ERR_INVALID_ARGUMENT);
  CHECK(wp::trim::trim(in.data(), in.size(), 0.0, NAN).code == WP_ERR_INVALID_ARGUMENT);
  // exactly 1 s is allowed
  const wp::trim::Result one = wp::trim::trim(in.data(), in.size(), 1.0, 2.0);
  CHECK(one.code == WP_OK && frames(decode(one.bytes)) == kRate);
  // bounds beyond the file are clamped: [−5, 99] keeps all 3 s, [2.5, 99] only 0.5 s (too short)
  const wp::trim::Result all = wp::trim::trim(in.data(), in.size(), -5.0, 99.0);
  CHECK(all.code == WP_OK && all.start == 0.0 && all.end == 3.0);
  CHECK(all.bytes == in);
  CHECK(wp::trim::trim(in.data(), in.size(), 2.5, 99.0).code == WP_ERR_INVALID_ARGUMENT);
  // a file of 0.9 s can never be trimmed
  const Bytes shortWav = wav(false, 39690);
  CHECK(wp::trim::trim(shortWav.data(), shortWav.size(), 0.0, 0.9).code == WP_ERR_INVALID_ARGUMENT);
}

void unsupportedFiles() { // #116: unknown and damaged files are refused (#120: M4A in
                          // trim_mp4_tests)
  const Bytes m4a = readFile("sine440.m4a");
  CHECK(wp::trim::detect(m4a.data(), m4a.size()) == Format::Mp4);
  const Bytes garbage(5000, 0x42);
  CHECK(wp::trim::detect(garbage.data(), garbage.size()) == Format::Unknown);
  CHECK(wp::trim::trim(garbage.data(), garbage.size(), 0.0, 1.0).code == WP_ERR_UNSUPPORTED_FORMAT);
  CHECK(wp::trim::trim(nullptr, 0, 0.0, 1.0).code == WP_ERR_UNSUPPORTED_FORMAT);
  // a WAV cut off inside its header, a FLAC without its blocks
  Bytes wavHead = wav(false);
  wavHead.resize(30);
  CHECK(wp::trim::trim(wavHead.data(), wavHead.size(), 0.0, 1.0).code == WP_ERR_UNSUPPORTED_FORMAT);
  const Bytes flacHead = {'f', 'L', 'a', 'C', 0x80, 0, 0, 34};
  CHECK(wp::trim::trim(flacHead.data(), flacHead.size(), 0.0, 1.0).code ==
        WP_ERR_UNSUPPORTED_FORMAT);
}

void capiResult() { // #116: the C API hands the bytes over and frees them
  const Bytes in = wav(false);
  wp_trim_result *r = nullptr;
  CHECK(wp_trim(in.data(), in.size(), 0.5, 1.5, &r) == WP_OK);
  CHECK(r != nullptr);
  CHECK(wp_trim_size(r) == 12 + 24 + 14 + 8 + 44100 * 4 + 12);
  CHECK(std::memcmp(wp_trim_data(r), "RIFF", 4) == 0);
  CHECK(wp_trim_start(r) == 0.5 && wp_trim_end(r) == 1.5);
  wp_trim_free(r);
  r = reinterpret_cast<wp_trim_result *>(&failures); // must be reset on an error
  CHECK(wp_trim(in.data(), in.size(), 0.5, 1.0, &r) == WP_ERR_INVALID_ARGUMENT);
  CHECK(r == nullptr);
  CHECK(wp_trim(nullptr, 10, 0.0, 1.0, &r) == WP_ERR_INVALID_ARGUMENT);
  CHECK(wp_trim(in.data(), in.size(), 0.0, 1.0, nullptr) == WP_ERR_INVALID_ARGUMENT);
  CHECK(wp_trim_data(nullptr) == nullptr && wp_trim_size(nullptr) == 0);
  CHECK(wp_trim_start(nullptr) == 0.0 && wp_trim_end(nullptr) == 0.0);
  wp_trim_free(nullptr);
}

// ---- More cases (#116, found by mutation testing) ----

// CRC-16 of the LAME tag (polynomial 0x8005 reflected, initial 0), computed here independently.
uint16_t lameCrc(const uint8_t *d, size_t n) {
  uint16_t crc = 0;
  for (size_t i = 0; i < n; ++i) {
    crc ^= d[i];
    for (int b = 0; b < 8; ++b)
      crc =
          (crc & 1) ? static_cast<uint16_t>((crc >> 1) ^ 0xA001) : static_cast<uint16_t>(crc >> 1);
  }
  return crc;
}

uint32_t be32(const uint8_t *p) {
  return (uint32_t{p[0]} << 24) | (uint32_t{p[1]} << 16) | (uint32_t{p[2]} << 8) | p[3];
}

// Length of the MPEG audio frame at p (Layer III, MPEG-1 44.1 kHz or the stream's own rate).
size_t mp3FrameLen(const Bytes &b, size_t p) {
  static const int br1[] = {0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320};
  static const int br2[] = {0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160};
  static const int rates[] = {44100, 48000, 32000};
  const int version = (b[p + 1] >> 3) & 3;
  const int rate = rates[(b[p + 2] >> 2) & 3] >> (version == 3 ? 0 : version == 2 ? 1 : 2);
  const int kbps = (version == 3 ? br1 : br2)[b[p + 2] >> 4];
  const int len = (version == 3 ? 144000 : 72000) * kbps / rate + ((b[p + 2] >> 1) & 1);
  return static_cast<size_t>(len);
}

// The Info/Xing frame of the new file checks out: frame count and byte count equal what follows,
// the seek table rises from the start of the audio, both CRCs of the LAME tag are right, its header
// is that of the audio frames (same channel mode).
void infoFrameIsConsistent() { // #116/AK4
  const Bytes in = readFile("clicks3.mp3");
  const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
  CHECK(r.code == WP_OK);
  const Bytes &b = r.bytes;
  const size_t info = mp3FrameLen(b, 0);
  const size_t x = 4 + 32; // stereo MPEG-1: side information of 32 bytes
  CHECK(std::memcmp(b.data() + x, "Info", 4) == 0);
  CHECK(be32(b.data() + x + 4) == 0x0F);
  size_t frames = 0;
  for (size_t p = info; p + 4 <= b.size(); p += mp3FrameLen(b, p))
    ++frames;
  CHECK(be32(b.data() + x + 8) == frames);
  CHECK(be32(b.data() + x + 12) == b.size());
  // 0.7 s and 2.2 s with the decoder delay 576 + 529 = 1105: first audible frame
  // (30870 + 1105) / 1152 = 27, last ceil((97020 + 1105) / 1152) − 1 = 85; with the empty frame and
  // frame 26 before it: 85 − 26 + 1 + 1 = 61 frames.
  CHECK(frames == 61);
  const uint8_t *toc = b.data() + x + 16;
  CHECK(toc[0] == info * 256 / b.size());
  for (int i = 1; i < 100; ++i)
    CHECK(toc[i] >= toc[i - 1]);
  // percent 50 lies at frame 30 of 61: header, info frame and 30 frames of the audio before it
  size_t at = info;
  for (size_t f = 0; f < 61 * 50 / 100; ++f)
    at += mp3FrameLen(b, at);
  CHECK(toc[50] == at * 256 / b.size());
  CHECK(toc[99] < 255);
  // the quality field after the 100 bytes of the seek table stays 0
  CHECK(be32(b.data() + x + 116) == 0);
  const uint8_t *t = b.data() + x + 120;
  CHECK(lameCrc(b.data(), static_cast<size_t>(t - b.data()) + 34) == ((t[34] << 8) | t[35]));
  CHECK(lameCrc(b.data() + info, b.size() - info) == ((t[32] << 8) | t[33]));
  CHECK(be32(t + 28) == b.size());
  // the header of the info frame has the channel mode and rate of the audio frames
  CHECK(b[3] == b[info + 3]);
  CHECK((b[2] & 0x0C) == (b[info + 2] & 0x0C));
}

// Start at 0 (no frame before the first one), end beyond the file (clamped to its length).
void mp3FromTheStartToTheEnd() { // #116/AK4, AK7
  const Bytes in = readFile("clicks3.mp3");
  const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.0, 99.0);
  CHECK(r.code == WP_OK);
  CHECK(r.start == 0.0);
  CHECK(r.end == 3.0); // 116 frames × 1152 − 576 − 756 = 132300 samples
  const std::vector<float> out = decode(r.bytes);
  CHECK(frames(out) == 132300);
  CHECK(click(out) == click(decode(in)));
  const wp::trim::Result head = wp::trim::trim(in.data(), in.size(), 0.0, 1.5);
  CHECK(head.code == WP_OK && frames(decode(head.bytes)) == 66150);
}

// Frames with a CRC (mono, 64 kbit/s): the side information starts 2 bytes later. LAME writes its
// Info frame there too, which dr_mp3 does not take as one: it plays it as a silent frame and skips
// no encoder delay, so the click at 1.0 s lies 1152 + 576 + 529 samples later. The cut follows the
// decoder: it treats the frame as audio as well.
void mp3WithCrc() { // #116/AK4
  const Bytes in = readFile("clicks3_crc.mp3");
  CHECK((in[1] & 1) == 0 || (in[mp3FrameLen(in, 0) + 1] & 1) == 0); // protected frames
  const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
  CHECK(r.code == WP_OK);
  const std::vector<float> old = decode(in), out = decode(r.bytes);
  CHECK(std::llabs(frames(out) - 66150) <= 1);
  CHECK(click(old, 39690) == 44100 + 1152 + 1105);
  CHECK(std::llabs(click(out) - (click(old, 39690) - 30870)) <= 1);
  CHECK(peak(out, 0, 8820) < 0.02f);
  CHECK(std::memcmp(r.bytes.data() + 4 + 17, "Info", 4) == 0); // mono: side information of 17 bytes
}

// APE, Lyrics3 v2 and ID3v1 tags after the audio stay as they are; a damaged Lyrics3 tag is no tag.
void mp3KeepsTagsAtTheEnd() { // #116/AK4
  const Bytes mp3 = readFile("clicks3.mp3");
  Bytes lyrics;
  const std::string text = "LYRICSBEGININD00002110abcdefg";
  lyrics.insert(lyrics.end(), text.begin(), text.end());
  const std::string size = "000029"; // the 29 bytes above
  lyrics.insert(lyrics.end(), size.begin(), size.end());
  const std::string end = "LYRICS200";
  lyrics.insert(lyrics.end(), end.begin(), end.end());
  Bytes ape(32, 0); // APEv2 with header: header 32 + 5 bytes item + footer 32 = 69
  Bytes apeFooter(32, 0);
  std::memcpy(ape.data(), "APETAGEX", 8);
  std::memcpy(apeFooter.data(), "APETAGEX", 8);
  for (Bytes *h : {&ape, &apeFooter}) {
    (*h)[12] = 5 + 32; // size without the header
    (*h)[23] = 0x80;   // has a header
  }
  Bytes v1(128, 0);
  std::memcpy(v1.data(), "TAGTrimmed", 10);
  Bytes tail;
  for (const Bytes *part : {&ape, &apeFooter, &lyrics, &v1})
    tail.insert(tail.end(), part->begin(), part->end());
  tail.insert(tail.begin() + 32, {'i', 't', 'e', 'm', '!'});
  Bytes in = mp3;
  in.insert(in.end(), tail.begin(), tail.end());
  const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
  CHECK(r.code == WP_OK);
  CHECK(r.bytes.size() > tail.size());
  CHECK(std::equal(tail.begin(), tail.end(), r.bytes.end() - static_cast<long>(tail.size())));
  // the same cut as without the tags, followed by them
  const wp::trim::Result plain = wp::trim::trim(mp3.data(), mp3.size(), 0.7, 2.2);
  Bytes expected = plain.bytes;
  expected.insert(expected.end(), tail.begin(), tail.end());
  CHECK(r.bytes == expected);
  // the APE tag alone, without ID3v1, and with an APE tag that claims more than the file holds
  Bytes onlyApe = mp3;
  onlyApe.insert(onlyApe.end(), apeFooter.begin(), apeFooter.end());
  onlyApe[onlyApe.size() - 32 + 23] = 0;  // no header: 5 + 32 bytes of footer and item...
  onlyApe[onlyApe.size() - 32 + 12] = 32; // ...here only the footer itself
  const wp::trim::Result a = wp::trim::trim(onlyApe.data(), onlyApe.size(), 0.7, 2.2);
  CHECK(a.code == WP_OK);
  CHECK(std::equal(apeFooter.begin(), apeFooter.begin() + 12, a.bytes.end() - 32));
  // Lyrics3 with a size that is not a number: no tag, its bytes are dropped like other junk
  Bytes broken = mp3;
  Bytes bad = lyrics;
  bad[29] = 'x';
  broken.insert(broken.end(), bad.begin(), bad.end());
  broken.insert(broken.end(), v1.begin(), v1.end());
  const wp::trim::Result b = wp::trim::trim(broken.data(), broken.size(), 0.7, 2.2);
  CHECK(b.code == WP_OK);
  CHECK(std::equal(v1.begin(), v1.end(), b.bytes.end() - 128));
  CHECK(!contains(b.bytes, "LYRICSBEGIN"));
}

// ID3v2 with a footer and with a size beyond the file.
void id3v2Variants() { // #116
  const Bytes mp3 = readFile("clicks3.mp3");
  Bytes in = {'I', 'D', '3', 4, 0, 0x10, 0, 0, 0, 2, 'a', 'b'}; // footer flag, body 2
  const Bytes footer = {'3', 'D', 'I', 4, 0, 0x10, 0, 0, 0, 2};
  in.insert(in.end(), footer.begin(), footer.end());
  in.insert(in.end(), mp3.begin(), mp3.end());
  const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
  CHECK(r.code == WP_OK);
  CHECK(std::equal(in.begin(), in.begin() + 22, r.bytes.begin()));
  CHECK(wp::trim::detect(r.bytes.data(), r.bytes.size()) == Format::Mp3);
  const Bytes huge = {'I', 'D', '3', 4, 0, 0, 0x7F, 0x7F, 0x7F, 0x7F, 1, 2, 3};
  CHECK(wp::trim::detect(huge.data(), huge.size()) == Format::Unknown);
  CHECK(wp::trim::trim(huge.data(), huge.size(), 0, 1).code == WP_ERR_UNSUPPORTED_FORMAT);
}

// ADTS with tags around it, a frame with a CRC (9-byte header), junk and a frame of another rate.
void adtsVariants() { // #116/AK4
  const Bytes aac = readFile("clicks3.aac");
  Bytes in = {'I', 'D', '3', 4, 0, 0, 0, 0, 0, 1, 'x'};
  const size_t prefix = in.size();
  in.insert(in.end(), aac.begin(), aac.end());
  in.insert(in.end(), {0x12, 0x34}); // junk after the last frame
  Bytes v1(128, 0);
  std::memcpy(v1.data(), "TAG", 3);
  in.insert(in.end(), v1.begin(), v1.end());
  const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
  CHECK(r.code == WP_OK);
  CHECK(std::equal(in.begin(), in.begin() + static_cast<long>(prefix), r.bytes.begin()));
  CHECK(std::equal(v1.begin(), v1.end(), r.bytes.end() - 128));
  CHECK(r.start == 30 * 1024.0 / kRate && r.end == 95 * 1024.0 / kRate);
  const wp::trim::Result plain = wp::trim::trim(aac.data(), aac.size(), 0.7, 2.2);
  CHECK(r.bytes.size() == plain.bytes.size() + prefix + 128);
  // a frame of another sampling rate in the middle is not part of the stream: one frame less
  Bytes mixed = aac;
  size_t p = 0;
  for (int i = 0; i < 40; ++i)
    p += ((size_t{mixed[p + 3]} & 3) << 11) | (size_t{mixed[p + 4]} << 3) | (mixed[p + 5] >> 5);
  mixed[p + 2] = static_cast<uint8_t>((mixed[p + 2] & ~0x3C) | (3 << 2)); // 48 kHz
  const wp::trim::Result m = wp::trim::trim(mixed.data(), mixed.size(), 0.0, 99.0);
  CHECK(m.code == WP_OK);
  CHECK(m.end == plain.end + (130 - 95) * 1024.0 / kRate - 1024.0 / kRate ||
        m.end < wp::trim::trim(aac.data(), aac.size(), 0.0, 99.0).end);
  // a header with a CRC (protection absent = 0) needs 9 bytes; a sampling rate index of 13 is none
  Bytes crc = {0xFF, 0xF0, 0x50, 0x80, 0x01, 0x20, 0x00, 0, 0};
  CHECK(wp::trim::detect(crc.data(), 9) == Format::Adts);
  crc[2] = static_cast<uint8_t>((crc[2] & ~0x3C) | (13 << 2));
  CHECK(wp::trim::detect(crc.data(), 9) == Format::Unknown);
  const Bytes shortHeader = {0xFF, 0xF1, 0x50, 0x80, 0x01, 0x20};
  CHECK(wp::trim::detect(shortHeader.data(), shortHeader.size()) == Format::Unknown);
}

// WAV: an odd number of data bytes gets its pad byte, a chunk after it stays aligned; extensible
// format; a data size beyond the file (streaming) is clamped; damaged chunk lists and formats are
// refused.
void wavVariants() { // #116/AK4
  // 8-bit mono, 3 s at 8000 Hz; keep 1.0001 s → 8001 bytes of data
  constexpr unsigned kRate8 = 8000;
  auto make = [&](unsigned fmtTag, unsigned dataSize, bool extensible) {
    Bytes b;
    tag(b, "RIFF");
    u32(b, 0);
    tag(b, "WAVE");
    tag(b, "fmt ");
    u32(b, extensible ? 40 : 16);
    u16(b, extensible ? 0xFFFE : fmtTag);
    u16(b, 1);
    u32(b, kRate8);
    u32(b, kRate8);
    u16(b, 1);
    u16(b, 8);
    if (extensible) {
      u16(b, 22);
      u16(b, 8);
      u32(b, 4);
      u16(b, fmtTag); // sub format GUID, first two bytes
      for (int i = 0; i < 14; ++i)
        b.push_back(0);
    }
    tag(b, "data");
    u32(b, dataSize);
    for (unsigned i = 0; i < 3 * kRate8; ++i)
      b.push_back(static_cast<uint8_t>(i % 251));
    tag(b, "LIST");
    u32(b, 4);
    tag(b, "INFO");
    const unsigned riff = static_cast<unsigned>(b.size() - 8);
    for (int i = 0; i < 4; ++i)
      b[4 + i] = static_cast<uint8_t>(riff >> (8 * i));
    return b;
  };
  for (const bool extensible : {false, true}) {
    const Bytes in = make(1, 3 * kRate8, extensible);
    const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.5, 1.500125);
    CHECK(r.code == WP_OK);
    const size_t header = extensible ? 12 + 48 + 8 : 12 + 24 + 8;
    CHECK(r.bytes.size() == header + 8001 + 1 + 12); // pad byte, then the LIST chunk
    CHECK(r.bytes[header + 8001] == 0);
    CHECK(std::memcmp(r.bytes.data() + header + 8002, "LIST", 4) == 0);
    CHECK(r.bytes[header] == 4000 % 251); // first byte = old byte 0.5 × 8000
    const unsigned riff = r.bytes[4] | (r.bytes[5] << 8) | (r.bytes[6] << 16) | (r.bytes[7] << 24);
    CHECK(riff == r.bytes.size() - 8);
    CHECK(frames(decode(r.bytes, kRate8)) == 8001);
  }
  // streaming: data size 0xFFFFFFFF counts up to the end of the file (here 3 s and the LIST chunk)
  const Bytes stream = make(1, 0xFFFFFFFFu, false);
  const wp::trim::Result s = wp::trim::trim(stream.data(), stream.size(), 0.0, 99.0);
  CHECK(s.code == WP_OK && s.end == (3 * kRate8 + 12) / 8000.0);
  // ADPCM (format 2), also inside an extensible format, is not trimmed
  for (const bool extensible : {false, true}) {
    const Bytes adpcm = make(2, 3 * kRate8, extensible);
    CHECK(wp::trim::trim(adpcm.data(), adpcm.size(), 0.5, 2.0).code == WP_ERR_UNSUPPORTED_FORMAT);
  }
  // a chunk before the data that claims more bytes than the file has: no data chunk is found
  Bytes runaway = make(1, 3 * kRate8, false);
  runaway.insert(runaway.begin() + 36, {'j', 'u', 'n', 'k', 0xF0, 0xFF, 0xFF, 0x00});
  CHECK(wp::trim::trim(runaway.data(), runaway.size(), 0.5, 2.0).code == WP_ERR_UNSUPPORTED_FORMAT);
  // a fmt chunk too short, a fact chunk cut off by the end of the file
  Bytes shortFmt = make(1, 3 * kRate8, false);
  shortFmt[16] = 14;
  CHECK(wp::trim::trim(shortFmt.data(), shortFmt.size(), 0.5, 2.0).code != WP_OK);
  Bytes factOnly = {'R', 'I', 'F', 'F', 0,   0, 0, 0, 'W', 'A', 'V',
                    'E', 'f', 'a', 'c', 't', 4, 0, 0, 0,   1};
  CHECK(wp::trim::trim(factOnly.data(), factOnly.size(), 0, 1).code == WP_ERR_UNSUPPORTED_FORMAT);
}

// FLAC: an ID3v2 tag before it stays; a file without Vorbis comment gets the encoder's; the last
// metadata block is marked as such; a file cut short or with a broken block list is refused;
// trimming to the end of the file reads the decoder's last block.
void flacVariants() { // #116/AK4
  Bytes plain;
  wp::FlacWriter w;
  CHECK(w.openMemory(&plain, kRate, 1, 16));
  std::vector<int32_t> pcm(3 * kRate);
  for (size_t i = 0; i < pcm.size(); ++i)
    pcm[i] = static_cast<int32_t>(i % 2000) - 1000;
  CHECK(w.writeInt(pcm.data(), static_cast<uint32_t>(pcm.size())));
  CHECK(w.close());
  // drop every block but the stream info (libFLAC adds a Vorbis comment)
  size_t p = 4;
  std::vector<std::pair<size_t, size_t>> blocks;
  for (;;) {
    const size_t len = (size_t{plain[p + 1]} << 16) | (size_t{plain[p + 2]} << 8) | plain[p + 3];
    blocks.emplace_back(p, 4 + len);
    const bool last = plain[p] & 0x80;
    p += 4 + len;
    if (last)
      break;
  }
  Bytes bare(plain.begin(), plain.begin() + 4 + 38);
  bare[4] |= 0x80;
  bare.insert(bare.end(), plain.begin() + static_cast<long>(p), plain.end());
  // a CUESHEET block (type 5) and an APPLICATION block (type 2) after the stream info
  Bytes withBlocks(plain.begin(), plain.begin() + 4 + 38);
  withBlocks.insert(withBlocks.end(),
                    {5, 0, 0, 2, 'c', 'c', 2, 0, 0, 4, 'a', 'p', 'p', '!', 0x81, 0, 0, 1, 0});
  withBlocks.insert(withBlocks.end(), plain.begin() + static_cast<long>(p), plain.end());
  Bytes id3 = {'I', 'D', '3', 4, 0, 0, 0, 0, 0, 3, 'x', 'y', 'z'};
  Bytes tagged = id3;
  tagged.insert(tagged.end(), bare.begin(), bare.end());
  for (const Bytes *in : {&bare, &withBlocks, &tagged}) {
    const wp::trim::Result r = wp::trim::trim(in->data(), in->size(), 0.5, 99.0);
    CHECK(r.code == WP_OK);
    CHECK(r.end == 3.0);
    const size_t at = in == &tagged ? id3.size() : 0;
    CHECK(std::equal(in->begin(), in->begin() + static_cast<long>(at) + 4, r.bytes.begin()));
    // walk the blocks: exactly the last one is marked, the audio follows at once (sync 0xFFF8)
    size_t q = at + 4;
    int count = 0;
    bool vorbis = false, cue = false, app = false;
    for (;;) {
      const uint8_t type = r.bytes[q] & 0x7F;
      vorbis = vorbis || type == 4;
      cue = cue || type == 5;
      app = app || type == 2;
      const size_t len =
          (size_t{r.bytes[q + 1]} << 16) | (size_t{r.bytes[q + 2]} << 8) | r.bytes[q + 3];
      ++count;
      const bool last = r.bytes[q] & 0x80;
      q += 4 + len;
      if (last)
        break;
    }
    CHECK(vorbis); // the encoder's, as the file had none
    CHECK(!cue);
    CHECK(app == (in == &withBlocks));
    CHECK(r.bytes[q] == 0xFF && (r.bytes[q + 1] & 0xFE) == 0xF8);
    CHECK(count >= 2);
    const std::vector<float> out = decode(r.bytes);
    CHECK(frames(out) == 2 * kRate + kRate / 2);
  }
  // cut short in the audio: the stream info promises more samples than there are
  Bytes cut = bare;
  cut.resize(cut.size() / 2);
  CHECK(wp::trim::trim(cut.data(), cut.size(), 0.5, 2.9).code != WP_OK);
  // a block list running past the end, a block shorter than its header says
  Bytes runaway(plain.begin(), plain.begin() + 4 + 38);
  runaway[4] &= 0x7F;
  runaway.insert(runaway.end(), {4, 0, 1, 0});
  CHECK(wp::trim::trim(runaway.data(), runaway.size(), 0, 1).code == WP_ERR_UNSUPPORTED_FORMAT);
  const Bytes headOnly = {'f', 'L', 'a', 'C', 0x80, 0, 0};
  CHECK(wp::trim::trim(headOnly.data(), headOnly.size(), 0, 1).code == WP_ERR_UNSUPPORTED_FORMAT);
}

// Exactly kMinSeconds minus the tolerance is accepted.
void rangeTolerance() { // #116/AK7
  const Bytes in = wav(false);
  CHECK(wp::trim::trim(in.data(), in.size(), 0.0, 1.0 - 1e-9).code == WP_OK);
  CHECK(wp::trim::trim(in.data(), in.size(), 0.0, 1.0 - 2e-9).code == WP_ERR_INVALID_ARGUMENT);
}

// An odd number of data bytes in the old file (its pad byte stays outside the data), an ID3v2 tag
// before the RIFF header (the RIFF size is that of the RIFF part), junk before an MP3 that looks
// like a frame.
void moreLayouts() { // #116/AK4
  constexpr unsigned kRate8 = 8000;
  Bytes w = {'I', 'D', '3', 4, 0, 0, 0, 0, 0, 2, 'i', 'd'};
  const size_t riff = w.size();
  tag(w, "RIFF");
  u32(w, 0);
  tag(w, "WAVE");
  tag(w, "fmt ");
  u32(w, 16);
  u16(w, 1);
  u16(w, 1);
  u32(w, kRate8);
  u32(w, kRate8);
  u16(w, 1);
  u16(w, 8);
  tag(w, "data");
  u32(w, 3 * kRate8 + 1); // odd: one pad byte follows
  for (unsigned i = 0; i < 3 * kRate8 + 1; ++i)
    w.push_back(static_cast<uint8_t>(i % 199));
  w.push_back(0); // pad byte
  tag(w, "LIST");
  u32(w, 4);
  tag(w, "INFO");
  const unsigned size = static_cast<unsigned>(w.size() - riff - 8);
  for (int i = 0; i < 4; ++i)
    w[riff + 4 + i] = static_cast<uint8_t>(size >> (8 * i));
  const wp::trim::Result r = wp::trim::trim(w.data(), w.size(), 1.0, 2.5);
  CHECK(r.code == WP_OK);
  CHECK(std::equal(w.begin(), w.begin() + 12, r.bytes.begin()));
  // 12 ID3 + 12 RIFF + 24 fmt + 8 data header + 12000 bytes + 12 LIST (even, no pad byte)
  CHECK(r.bytes.size() == 12 + 12 + 24 + 8 + 12000 + 12);
  CHECK(std::memcmp(r.bytes.data() + r.bytes.size() - 12, "LIST", 4) == 0);
  const unsigned riffSize = r.bytes[riff + 4] | (r.bytes[riff + 5] << 8) |
                            (r.bytes[riff + 6] << 16) | (r.bytes[riff + 7] << 24);
  CHECK(riffSize == r.bytes.size() - riff - 8);

  const Bytes mp3 = readFile("clicks3.mp3");
  Bytes junk = {0xFF, 0xFB, 0x90, 0x64}; // a frame header (128 kbit/s) not followed by another one
  for (int i = 0; i < 300; ++i)
    junk.push_back(static_cast<uint8_t>(i * 7));
  Bytes in = junk;
  in.insert(in.end(), mp3.begin(), mp3.end());
  const wp::trim::Result m = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
  const wp::trim::Result plain = wp::trim::trim(mp3.data(), mp3.size(), 0.7, 2.2);
  CHECK(m.code == WP_OK && m.bytes == plain.bytes);
}

// #116 regression (found bug 43, fuzz regression trim/flac_seek_infinity): trimming a FLAC file
// seeked to the start with dr_flac. On a file shorter than its header says, the binary search of
// the seek converted infinity or NaN to an integer (undefined behaviour, UBSan under make
// sanitize). Since then the part before the start is decoded and dropped. The reduced input: a
// valid STREAMINFO that claims 98304 frames (2.2 s) and a single silent frame of 4096 frames. Cut
// from 0.5 s, the file ends long before the start: refused as damaged.
void flacShorterThanItsHeader() {
  const Bytes flac = {
      'f',  'L',  'a',  'C',  0x80, 0x00, 0x00, 0x22, // last metadata block: STREAMINFO, 34 bytes
      0x10, 0x00, 0x10, 0x00,                         // block size 4096 .. 4096
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00,             // frame size unknown
      0x0a, 0xc4, 0x42, 0xf0, 0x00, 0x01, 0x80, 0x00, // 44100 Hz, stereo, 16 bit, 98304 frames
      0,    0,    0,    0,    0,    0,    0,    0,    0, 0, 0, 0, 0, 0, 0, 0, // MD5 unknown
      0xff, 0xf8, 0xc9, 0x18, 0x00, 0xc2, // frame 0: 4096 frames, 44100 Hz, stereo, 16 bit, CRC-8
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, // two CONSTANT subframes of value 0
      0xb8, 0xee,                         // CRC-16
  };
  CHECK(wp::trim::trim(flac.data(), flac.size(), 0.5, 2.0).code == WP_ERR_UNSUPPORTED_FORMAT);
}

void run(const char *name, void (*test)()) {
  const int before = failures;
  test();
  std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name);
}

} // namespace

int main() {
  std::setvbuf(stdout, nullptr, _IONBF, 0);
  run("#116/AK4 WAV 16 bit exact, other chunks kept", wav16CutsExactlyAndKeepsChunks);
  run("#116/AK4 WAV float with fact chunk", wavFloatUpdatesFact);
  run("#116/AK4 FLAC lossless, tags kept, seek table removed", flacStaysLosslessWithTags);
  run("#116/AK4 FLAC keeps 16 and 24 bit", flacKeepsBitDepth);
  run("#116 FLAC writer into memory", flacWriterMemoryLimits);
  run("#116/AK4 MP3 CBR, VBR, MPEG-2 exact with LAME tag, no click", mp3CbrVbrAndMpeg2);
  run("#116/AK4 MP3 keeps ID3 tags", mp3KeepsId3Tags);
  run("#116/AK4 MP3 without LAME tag", mp3WithoutLameTag);
  run("#116/AK4 ADTS at frame boundaries", adtsAtFrameBoundaries);
  run("#116/AK7 at least 1 s, end after start", rangeRules);
  run("#116 unknown and damaged files refused", unsupportedFiles);
  run("#116 C API", capiResult);
  run("#116/AK4 MP3 info frame: counts, seek table, CRCs", infoFrameIsConsistent);
  run("#116/AK4 #116/AK7 MP3 from the start, to the end", mp3FromTheStartToTheEnd);
  run("#116/AK4 MP3 with CRC", mp3WithCrc);
  run("#116/AK4 MP3 keeps APE, Lyrics3 and ID3v1 tags", mp3KeepsTagsAtTheEnd);
  run("#116 ID3v2 with footer or beyond the file", id3v2Variants);
  run("#116/AK4 ADTS with tags, junk, CRC header", adtsVariants);
  run("#116/AK4 WAV pad byte, extensible, streaming, damaged", wavVariants);
  run("#116/AK4 FLAC blocks, ID3v2, damaged", flacVariants);
  run("#116/AK7 tolerance of the shortest range", rangeTolerance);
  run("#116/AK4 odd WAV data, ID3v2 before RIFF, junk before MP3", moreLayouts);
  run("#116 regression (found bug 43): FLAC shorter than its header", flacShorterThanItsHeader);
  std::printf("%s\n", failures == 0 ? "all trim tests passed" : "trim tests FAILED");
  return failures == 0 ? 0 : 1;
}
