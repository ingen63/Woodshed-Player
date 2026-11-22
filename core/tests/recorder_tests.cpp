// Tests of the platform-independent part of the recording (#68) without an audio device: level
// meter, ring buffer, WAV file (header and samples) and the copy of the tap layouts into the ring.
// #113: FLAC file (libFLAC), the 10 s recording the core loads again, and the microphone input on
// miniaudio's null backend. The Core Audio part (recorder_mac.mm) needs real system audio (#51).
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <functional>
#include <string>
#include <thread>
#include <vector>

#if defined(__unix__) || defined(__APPLE__)
#include <sys/resource.h>
#define WP_HAVE_RLIMIT 1
#endif

#include "flac_writer.hpp"
#include "player_core.hpp"
#include "recorder_core.hpp"
#include "wp_core.h"

namespace {

int failures = 0;
int checks = 0;

#define CHECK(cond)                                                                                \
  do {                                                                                             \
    ++checks;                                                                                      \
    if (!(cond)) {                                                                                 \
      ++failures;                                                                                  \
      std::printf("  FAILED %s:%d: %s\n", __FILE__, __LINE__, #cond);                              \
    }                                                                                              \
  } while (0)

using wp::FlacWriter;
using wp::rec::Capture;
using wp::rec::FileFormat;
using wp::rec::FrameRing;
using wp::rec::LevelMeter;
using wp::rec::MicInput;
using wp::rec::TapBuffer;
using wp::rec::TapFormat;
using wp::rec::WavFile;

namespace fs = std::filesystem;

// A fresh path in the temp folder; the file is removed when the object goes away.
struct TempWav {
  fs::path path;
  explicit TempWav(const char *extension = ".wav") {
    static int counter = 0;
    const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    path = fs::temp_directory_path() / ("wp_recorder_test_" + std::to_string(stamp) + "_" +
                                        std::to_string(++counter) + extension);
  }
  TempWav(const TempWav &) = delete;
  TempWav &operator=(const TempWav &) = delete;
  ~TempWav() {
    std::error_code ec;
    fs::remove(path, ec);
  }
  [[nodiscard]] std::string str() const { return path.string(); }
};

// Decoded WAV: interleaved stereo float, empty if the file cannot be read.
struct Decoded {
  bool ok = false;
  uint32_t sampleRate = 0;
  uint32_t channels = 0;
  std::vector<float> samples;
  [[nodiscard]] size_t frames() const { return samples.size() / 2; }
};

Decoded decode(const std::string &path) {
  Decoded d;
  ma_decoder dec;
  const ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, 0, 0);
  if (ma_decoder_init_file(path.c_str(), &cfg, &dec) != MA_SUCCESS)
    return d;
  d.ok = true;
  d.sampleRate = dec.outputSampleRate;
  d.channels = dec.outputChannels;
  std::vector<float> block(4096 * static_cast<size_t>(dec.outputChannels));
  for (;;) {
    ma_uint64 read = 0;
    ma_decoder_read_pcm_frames(&dec, block.data(), 4096, &read);
    if (read == 0)
      break;
    d.samples.insert(d.samples.end(), block.begin(),
                     block.begin() + static_cast<long>(read * dec.outputChannels));
  }
  ma_decoder_uninit(&dec);
  return d;
}

std::vector<uint8_t> readBytes(const std::string &path) {
  std::ifstream f(path, std::ios::binary);
  return {std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>()};
}

uint32_t le32(const std::vector<uint8_t> &b, size_t at) {
  return static_cast<uint32_t>(b[at]) | static_cast<uint32_t>(b[at + 1]) << 8 |
         static_cast<uint32_t>(b[at + 2]) << 16 | static_cast<uint32_t>(b[at + 3]) << 24;
}
uint16_t le16(const std::vector<uint8_t> &b, size_t at) {
  return static_cast<uint16_t>(b[at] | b[at + 1] << 8);
}

// The header of a finished WAV file states its sizes: RIFF size and data chunk of `frames` stereo
// float32 frames. While the file is open they are still placeholders.
bool finishedWav(const std::string &path, uint32_t frames) {
  const auto b = readBytes(path);
  if (b.size() < 12 || le32(b, 4) != b.size() - 8)
    return false;
  for (size_t at = 12; at + 8 <= b.size();) {
    const uint32_t size = le32(b, at + 4);
    if (std::memcmp(b.data() + at, "data", 4) == 0)
      return size == frames * 8 && at + 8 + size <= b.size();
    at += 8 + static_cast<size_t>(size) + (size & 1);
  }
  return false;
}

// Interleaved stereo test signal: left i/1000, right -i/2000 (distinct per frame and channel).
std::vector<float> ramp(uint32_t frames, uint32_t offset = 0) {
  std::vector<float> v(static_cast<size_t>(frames) * 2);
  for (uint32_t i = 0; i < frames; ++i) {
    v[2 * i] = static_cast<float>(offset + i) / 1000.0f;
    v[2 * i + 1] = -static_cast<float>(offset + i) / 2000.0f;
  }
  return v;
}

TapBuffer buffer(const std::vector<float> &data, uint32_t channels) {
  return {channels, static_cast<uint32_t>(data.size() * sizeof(float)), data.data()};
}

// Records one push into a file at 48 kHz and returns the decoded file.
Decoded recordOnce(const std::vector<TapBuffer> &buffers, TapFormat format, Capture &c) {
  TempWav wav;
  CHECK(c.open(wav.str().c_str(), 48000) == 0);
  c.push(buffers.data(), static_cast<uint32_t>(buffers.size()), format);
  c.close();
  return decode(wav.str());
}

// ---- Level meter ----

void meterStartsSilent() { // #68/AK2
  LevelMeter m;
  CHECK(m.frames() == 0);
  CHECK(m.onlySilence());
  CHECK(m.takeLevel() == 0.0f);
}

void meterKeepsHighestPeakUntilTaken() { // #68/AK2
  LevelMeter m;
  m.add(0.5f, 100);
  m.add(0.25f, 50);
  CHECK(m.frames() == 150);
  CHECK(m.takeLevel() == 0.5f);
  CHECK(m.takeLevel() == 0.0f); // taking resets the level
  m.add(0.25f, 10);
  m.add(0.75f, 10);
  CHECK(m.takeLevel() == 0.75f);
  CHECK(m.frames() == 170);
}

void meterSilenceThreshold() { // #68/AK2: wp_rec_only_silence
  LevelMeter m;
  m.add(wp::rec::kSilenceThreshold, 10);
  CHECK(m.onlySilence()); // at the threshold still silence
  m.add(std::nextafter(wp::rec::kSilenceThreshold, 1.0f), 10);
  CHECK(!m.onlySilence());
  m.add(0.0f, 10);
  CHECK(!m.onlySilence()); // stays false for the rest of the recording
}

void meterResetForNextRecording() { // #68/AK2
  LevelMeter m;
  m.add(0.9f, 1000);
  m.reset();
  CHECK(m.frames() == 0);
  CHECK(m.onlySilence());
  CHECK(m.takeLevel() == 0.0f);
}

// ---- Ring buffer ----

void ringRoundTrip() { // #68/AK2
  FrameRing r;
  CHECK(!r.ready());
  CHECK(r.capacity() == 0);
  CHECK(r.init(8));
  CHECK(r.ready());
  CHECK(r.capacity() == 8);
  const auto in = ramp(5);
  CHECK(r.write(in.data(), 5) == 5);
  CHECK(r.availableRead() == 5);
  uint32_t n = 10;
  const float *p = r.acquireRead(n);
  CHECK(p != nullptr);
  CHECK(n == 5);
  CHECK(p != nullptr && std::equal(in.begin(), in.end(), p));
  r.commitRead(n);
  CHECK(r.availableRead() == 0);
  n = 10;
  CHECK(r.acquireRead(n) == nullptr);
  CHECK(n == 0);
  CHECK(r.write(in.data(), 0) == 0);
  r.uninit();
  CHECK(!r.ready());
  CHECK(r.capacity() == 0);
}

void ringDropsWhatDoesNotFit() { // #68/AK2: no blocking on overflow
  FrameRing r;
  CHECK(r.init(4));
  const auto in = ramp(6);
  CHECK(r.write(in.data(), 6) == 4);
  CHECK(r.availableRead() == 4);
  CHECK(r.write(in.data(), 1) == 0); // full
  uint32_t n = 4;
  const float *p = r.acquireRead(n);
  CHECK(n == 4);
  CHECK(p != nullptr && std::equal(in.begin(), in.begin() + 8, p)); // the first 4 frames
}

void ringWrapsAround() { // #68/AK2: a write across the end of the buffer lands in two pieces
  FrameRing r;
  CHECK(r.init(4));
  const auto first = ramp(3);
  CHECK(r.write(first.data(), 3) == 3);
  uint32_t n = 3;
  CHECK(r.acquireRead(n) != nullptr);
  r.commitRead(n);
  const auto second = ramp(3, 100);
  CHECK(r.write(second.data(), 3) == 3);
  CHECK(r.availableRead() == 3);
  std::vector<float> out;
  while (r.availableRead() > 0) {
    uint32_t m = 4;
    const float *p = r.acquireRead(m);
    if (!p)
      break;
    out.insert(out.end(), p, p + static_cast<size_t>(m) * 2);
    r.commitRead(m);
  }
  CHECK(out == second);
}

// Each released ring gives its memory back. Leaked, 40 rings of 32 MiB (written, so the pages are
// real) exceed the memory guard of the mutation build (1024 MiB, #11/AK4).
void ringReleasesMemory() {              // #68/AK2
  constexpr uint32_t kFrames = 1u << 22; // 32 MiB of stereo float
  const std::vector<float> block(static_cast<size_t>(kFrames) * 2, 0.25f);
  bool ok = true;
  for (int i = 0; i < 40; ++i) {
    FrameRing reused;
    ok = ok && reused.init(kFrames) && reused.write(block.data(), kFrames) == kFrames;
    reused.uninit();
  }
  for (int i = 0; i < 40; ++i) {
    FrameRing scoped;
    ok = ok && scoped.init(kFrames) && scoped.write(block.data(), kFrames) == kFrames;
  } // the destructor frees it
  CHECK(ok);
}

void ringFailsWithoutFrames() { // #68/AK2
  FrameRing r;
  CHECK(!r.init(0));
  CHECK(!r.ready());
}

// ---- WAV file ----

void wavHeaderIsStereoFloat() { // #68/AK1, #68/AK2: WAV header
  TempWav wav;
  WavFile w;
  CHECK(w.open(wav.str().c_str(), 44100));
  CHECK(w.isOpen());
  const auto in = ramp(300);
  w.write(in.data(), 300);
  w.close();
  CHECK(!w.isOpen());

  const auto b = readBytes(wav.str());
  CHECK(b.size() >= 44);
  if (b.size() < 44)
    return;
  CHECK(std::memcmp(b.data(), "RIFF", 4) == 0);
  CHECK(le32(b, 4) == b.size() - 8);
  CHECK(std::memcmp(b.data() + 8, "WAVE", 4) == 0);
  // walk the chunks: fmt and data
  bool fmt = false;
  bool data = false;
  for (size_t at = 12; at + 8 <= b.size();) {
    const uint32_t size = le32(b, at + 4);
    if (std::memcmp(b.data() + at, "fmt ", 4) == 0 && at + 24 <= b.size()) {
      fmt = true;
      const uint16_t tag = le16(b, at + 8);
      CHECK(tag == 3 || tag == 0xFFFE); // IEEE float (or extensible)
      CHECK(le16(b, at + 10) == 2);     // channels
      CHECK(le32(b, at + 12) == 44100); // sample rate
      CHECK(le32(b, at + 16) == 44100 * 8);
      CHECK(le16(b, at + 20) == 8);  // block align
      CHECK(le16(b, at + 22) == 32); // bits per sample
    } else if (std::memcmp(b.data() + at, "data", 4) == 0) {
      data = true;
      CHECK(size == 300 * 8);
      CHECK(at + 8 + size <= b.size());
      std::vector<float> samples(size / sizeof(float));
      if (at + 8 + size <= b.size())
        std::memcpy(samples.data(), b.data() + at + 8, size);
      CHECK(samples == in); // little-endian float32, as written
    }
    at += 8 + size + (size & 1);
  }
  CHECK(fmt);
  CHECK(data);
}

void wavSamplesRoundTrip() { // #68/AK2
  TempWav wav;
  WavFile w;
  CHECK(w.open(wav.str().c_str(), 48000));
  const auto in = ramp(1000);
  w.write(in.data(), 600);
  w.write(in.data() + 1200, 400);
  w.close();
  const auto d = decode(wav.str());
  CHECK(d.ok);
  CHECK(d.sampleRate == 48000);
  CHECK(d.channels == 2);
  CHECK(d.samples == in);
}

void wavOpenClosesThePreviousFile() { // #68/AK2
  TempWav a;
  TempWav b;
  WavFile w;
  CHECK(w.open(a.str().c_str(), 48000));
  const auto in = ramp(50);
  w.write(in.data(), 50);
  CHECK(w.open(b.str().c_str(), 48000)); // finishes a
  w.close();
  const auto d = decode(a.str());
  CHECK(d.ok);
  CHECK(d.frames() == 50);
  CHECK(finishedWav(a.str(), 50));
}

void wavDestructorFinishesFile() { // #68/AK2
  TempWav wav;
  const auto in = ramp(70);
  {
    WavFile w;
    CHECK(w.open(wav.str().c_str(), 48000));
    w.write(in.data(), 70);
  }
  CHECK(finishedWav(wav.str(), 70));
}

// Each WAV file releases its file handle: opening again and the destructor close the previous one.
// With a limit of 64 open files, 200 leaked handles make open() fail.
void wavReleasesFileHandles() { // #68/AK2
#if WP_HAVE_RLIMIT
  rlimit old{};
  CHECK(getrlimit(RLIMIT_NOFILE, &old) == 0);
  rlimit low = old;
  low.rlim_cur = std::min<rlim_t>(old.rlim_cur, 64);
  CHECK(setrlimit(RLIMIT_NOFILE, &low) == 0);
  TempWav wav;
  bool ok = true;
  {
    WavFile reused;
    for (int i = 0; i < 200; ++i)
      ok = ok && reused.open(wav.str().c_str(), 48000);
  }
  for (int i = 0; i < 200; ++i) {
    WavFile scoped;
    ok = ok && scoped.open(wav.str().c_str(), 48000);
  }
  setrlimit(RLIMIT_NOFILE, &old);
  CHECK(ok);
#endif
}

void wavFailsInMissingFolder() { // #68/AK2: WP_REC_ERR_FILE
  WavFile w;
  const auto path = fs::temp_directory_path() / "wp_recorder_missing_dir" / "x" / "out.wav";
  CHECK(!w.open(path.string().c_str(), 48000));
  CHECK(!w.isOpen());
  w.close(); // nothing to close
}

// ---- Capture: open, writer thread, tap layouts ----

void captureErrorCodes() { // #68/AK2: codes of wp_rec_start
  Capture c;
  TempWav wav;
  CHECK(c.open(wav.str().c_str(), 0.0) == WP_REC_ERR_OUT_OF_MEMORY);
  c.close();
  const auto missing = fs::temp_directory_path() / "wp_recorder_missing_dir" / "x" / "out.wav";
  CHECK(c.open(missing.string().c_str(), 48000) == WP_REC_ERR_FILE);
  CHECK(c.ring().ready()); // close() frees it
  c.close();
  CHECK(!c.ring().ready());
}

void captureRingHoldsTwoSeconds() { // #68/AK2
  Capture c;
  TempWav wav;
  CHECK(c.open(wav.str().c_str(), 44100) == 0);
  CHECK(c.ring().capacity() == 88200);
  CHECK(c.open(wav.str().c_str(), 100) == 0); // a second open closes the first recording
  CHECK(c.ring().capacity() == 200);
  c.close();
  CHECK(c.ring().capacity() == 0);
}

void captureStereoInterleaved() { // #68/AK2
  Capture c;
  const auto in = ramp(2500); // more than one block (1024 frames)
  const auto d = recordOnce({buffer(in, 2)}, {2, false}, c);
  CHECK(d.ok);
  CHECK(d.sampleRate == 48000);
  CHECK(d.samples == in);
  CHECK(c.meter().frames() == 2500); // kept after close for wp_rec_seconds
  CHECK(c.meter().takeLevel() == in[2 * 2499]);
  CHECK(!c.meter().onlySilence());
}

void captureMonoInterleavedToBoth() { // #68/AK2
  Capture c;
  std::vector<float> mono(10);
  for (size_t i = 0; i < mono.size(); ++i)
    mono[i] = -0.1f * static_cast<float>(i);
  const auto d = recordOnce({buffer(mono, 1)}, {1, false}, c);
  CHECK(d.frames() == 10);
  bool same = d.frames() == 10;
  for (size_t i = 0; same && i < 10; ++i)
    same = d.samples[2 * i] == mono[i] && d.samples[2 * i + 1] == mono[i];
  CHECK(same);
  CHECK(c.meter().takeLevel() == -mono[9]); // absolute value of the most negative sample
}

void captureMoreChannelsKeepsFirstTwo() { // #68/AK2
  Capture c;
  std::vector<float> three(3 * 5);
  for (size_t i = 0; i < 5; ++i) {
    three[3 * i] = 0.01f * static_cast<float>(i);
    three[3 * i + 1] = -0.01f * static_cast<float>(i);
    three[3 * i + 2] = 0.99f; // ignored
  }
  const auto d = recordOnce({buffer(three, 3)}, {3, false}, c);
  CHECK(d.frames() == 5);
  bool same = d.frames() == 5;
  for (size_t i = 0; same && i < 5; ++i)
    same = d.samples[2 * i] == three[3 * i] && d.samples[2 * i + 1] == three[3 * i + 1];
  CHECK(same);
  CHECK(c.meter().takeLevel() == three[12]); // the third channel does not count
}

void captureNonInterleavedTakesLastBuffers() { // #68/AK2: device inputs come first
  Capture c;
  const std::vector<float> deviceIn(1200, 0.7f); // inputs of an audio interface, not recorded
  std::vector<float> left(1200);
  std::vector<float> right(1200);
  for (size_t i = 0; i < left.size(); ++i) {
    left[i] = static_cast<float>(i) / 2000.0f;
    right[i] = -static_cast<float>(i) / 4000.0f;
  }
  const auto d = recordOnce(
      {buffer(deviceIn, 1), buffer(deviceIn, 1), buffer(left, 1), buffer(right, 1)}, {2, true}, c);
  CHECK(d.frames() == 1200);
  bool same = d.frames() == 1200;
  for (size_t i = 0; same && i < 1200; ++i)
    same = d.samples[2 * i] == left[i] && d.samples[2 * i + 1] == right[i];
  CHECK(same);
  CHECK(c.meter().frames() == 1200);
  CHECK(c.meter().takeLevel() == left[1199]);
}

void captureNonInterleavedMono() { // #68/AK2
  Capture c;
  const std::vector<float> deviceIn(4, 0.7f);
  const std::vector<float> mono = {0.1f, 0.2f, 0.3f, 0.4f};
  const auto d = recordOnce({buffer(deviceIn, 1), buffer(mono, 1)}, {1, true}, c);
  CHECK(d.frames() == 4);
  CHECK(d.samples == std::vector<float>({0.1f, 0.1f, 0.2f, 0.2f, 0.3f, 0.3f, 0.4f, 0.4f}));
}

void captureMoreTapChannelsThanBuffers() { // #68/AK2: only the buffers there are
  Capture c;
  const std::vector<float> left = {0.1f, 0.2f};
  const std::vector<float> right = {-0.1f, -0.2f};
  const auto d = recordOnce({buffer(left, 1), buffer(right, 1)}, {4, true}, c);
  CHECK(d.samples == std::vector<float>({0.1f, -0.1f, 0.2f, -0.2f}));
}

void captureIgnoresEmptyInput() { // #68/AK2
  Capture c;
  TempWav wav;
  CHECK(c.open(wav.str().c_str(), 48000) == 0);
  c.push(nullptr, 2, {});
  const std::vector<float> empty;
  const TapBuffer none = buffer(empty, 2);
  c.push(&none, 0, {});
  c.push(&none, 1, {});
  c.close();
  CHECK(c.meter().frames() == 0);
  CHECK(c.meter().onlySilence());
  const auto d = decode(wav.str());
  CHECK(d.ok);
  CHECK(d.frames() == 0);
}

void captureDestructorFinishesRecording() { // #68/AK2
  TempWav wav;
  const auto in = ramp(500);
  {
    Capture c;
    CHECK(c.open(wav.str().c_str(), 48000) == 0);
    const TapBuffer b = buffer(in, 2);
    c.push(&b, 1, {2, false});
  } // stops the writer thread and finishes the file
  CHECK(finishedWav(wav.str(), 500));
  CHECK(decode(wav.str()).samples == in);
}

void captureWritesEverythingOnClose() { // #68/AK2: the writer drains the ring before it stops
  Capture c;
  TempWav wav;
  CHECK(c.open(wav.str().c_str(), 48000) == 0);
  std::vector<float> all;
  for (uint32_t k = 0; k < 10; ++k) {
    const auto part = ramp(3000, k * 3000);
    c.push(std::vector<TapBuffer>{buffer(part, 2)}.data(), 1, {2, false});
    all.insert(all.end(), part.begin(), part.end());
  }
  c.close();
  CHECK(c.meter().frames() == 30000);
  const auto d = decode(wav.str());
  CHECK(d.frames() == 30000);
  CHECK(d.samples == all);
}

void silentCaptureStaysSilent() { // #68/AK2: no permission -> digital silence
  Capture c;
  const std::vector<float> silence(2 * 480, 0.0f);
  const auto d = recordOnce({buffer(silence, 2)}, {2, false}, c);
  CHECK(d.frames() == 480);
  CHECK(c.meter().onlySilence());
  CHECK(c.meter().takeLevel() == 0.0f);
}

// ---- FLAC (#113) ----

// Largest difference between two equally long sample vectors (infinity if the lengths differ).
float maxDiff(const std::vector<float> &a, const std::vector<float> &b) {
  if (a.size() != b.size())
    return INFINITY;
  float m = 0;
  for (size_t i = 0; i < a.size(); ++i)
    m = std::max(m, std::fabs(a[i] - b[i]));
  return m;
}

constexpr double kPi = 3.14159265358979323846;

// Interleaved stereo sine: left at `hz`, right at half the amplitude, starting at frame `offset`.
std::vector<float> sine(uint32_t frames, double hz, uint32_t rate, uint32_t offset = 0) {
  std::vector<float> v(static_cast<size_t>(frames) * 2);
  for (uint32_t i = 0; i < frames; ++i) {
    const double t = static_cast<double>(offset + i) / rate;
    const auto x = static_cast<float>(0.5 * std::sin(2.0 * kPi * hz * t));
    v[2 * i] = x;
    v[2 * i + 1] = 0.5f * x;
  }
  return v;
}

void flacToIntScalesClipsAndRounds() { // #113/AK3
  CHECK(FlacWriter::toInt(0.0f, 24) == 0);
  CHECK(FlacWriter::toInt(1.0f, 24) == 8388607);
  CHECK(FlacWriter::toInt(-1.0f, 24) == -8388607);
  CHECK(FlacWriter::toInt(1.5f, 24) == 8388607);   // clipped
  CHECK(FlacWriter::toInt(-7.0f, 24) == -8388607); // clipped
  CHECK(FlacWriter::toInt(1.0f, 16) == 32767);
  CHECK(FlacWriter::toInt(2.0f, 16) == 32767);
  CHECK(FlacWriter::toInt(-2.0f, 16) == -32767);
  CHECK(FlacWriter::toInt(0.5f, 16) == 16384);   // 16383.5 rounds away from zero
  CHECK(FlacWriter::toInt(-0.5f, 16) == -16384); // symmetric
  CHECK(FlacWriter::toInt(0.25f, 16) == 8192);   // 8191.75 rounds up
  CHECK(FlacWriter::toInt(0.2f / 32767.0f, 16) == 0);
}

void flacRejectsWhatFlacCannotStore() { // #113/AK3
  TempWav f(".flac");
  FlacWriter w;
  CHECK(!w.open(nullptr, 48000, 2));
  CHECK(!w.open(f.str().c_str(), 48000, 0));
  CHECK(!w.open(f.str().c_str(), 48000, 9));
  CHECK(!w.open(f.str().c_str(), 0, 2));
  CHECK(!w.open(f.str().c_str(), 655351, 2));
  CHECK(!w.open(f.str().c_str(), 48000, 2, 8));
  CHECK(!w.open(f.str().c_str(), 48000, 2, 20));
  CHECK(!w.open(f.str().c_str(), 48000, 2, 32));
  CHECK(!w.isOpen());
  CHECK(!fs::exists(f.path));
  const auto missing = fs::temp_directory_path() / "wp_recorder_missing_dir" / "x" / "out.flac";
  CHECK(!w.open(missing.string().c_str(), 48000, 2));
  CHECK(!w.isOpen());
  const float frame[2] = {0.1f, 0.2f};
  CHECK(!w.write(frame, 1)); // nothing open
  CHECK(w.close());          // closing nothing is fine
  // The limits themselves are valid.
  CHECK(w.open(f.str().c_str(), 655350, 8, 16));
  CHECK(w.close());
  CHECK(w.open(f.str().c_str(), 1, 1, 24));
  CHECK(w.close());
}

void flacRoundTrip24And16Bit() { // #113/AK3: lossless within the integer step
  for (const uint32_t bits : {24u, 16u}) {
    TempWav f(".flac");
    FlacWriter w;
    CHECK(w.open(f.str().c_str(), 44100, 2, bits));
    CHECK(w.isOpen());
    const auto in = sine(5000, 440, 44100);
    CHECK(w.write(in.data(), 2000));
    CHECK(w.write(in.data() + 4000, 3000));
    CHECK(w.close());
    CHECK(!w.isOpen());
    const auto d = decode(f.str());
    CHECK(d.ok);
    CHECK(d.sampleRate == 44100);
    CHECK(d.channels == 2);
    CHECK(d.frames() == 5000);
    const float step = 1.0f / static_cast<float>((1u << (bits - 1)) - 1);
    CHECK(maxDiff(d.samples, in) <= step);
  }
}

void flacMonoFile() { // #113/AK3: the writer is not tied to stereo (reused for trimming, #116)
  TempWav f(".flac");
  FlacWriter w;
  CHECK(w.open(f.str().c_str(), 22050, 1, 16));
  const std::vector<float> in = {0.0f, 0.5f, -0.5f, 1.0f, -1.0f};
  CHECK(w.write(in.data(), 5));
  CHECK(w.close());
  ma_decoder dec;
  const ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, 0, 0);
  CHECK(ma_decoder_init_file(f.str().c_str(), &cfg, &dec) == MA_SUCCESS);
  CHECK(dec.outputChannels == 1);
  ma_decoder_uninit(&dec);
}

void flacOpenFinishesThePreviousFile() { // #113/AK3
  TempWav a(".flac"), b(".flac");
  FlacWriter w;
  const auto in = sine(1000, 220, 48000);
  CHECK(w.open(a.str().c_str(), 48000, 2));
  CHECK(w.write(in.data(), 1000));
  CHECK(w.open(b.str().c_str(), 48000, 2));
  CHECK(decode(a.str()).frames() == 1000);
  CHECK(w.close());
  CHECK(decode(b.str()).frames() == 0);
}

void flacDestructorFinishesFile() { // #113/AK3
  TempWav f(".flac");
  const auto in = sine(700, 330, 48000);
  {
    FlacWriter w;
    CHECK(w.open(f.str().c_str(), 48000, 2));
    CHECK(w.write(in.data(), 700));
  }
  const auto d = decode(f.str());
  CHECK(d.frames() == 700);
  CHECK(maxDiff(d.samples, in) <= 1.0f / 8388607.0f);
}

void captureFlacTenSecondsLoadsInTheCore() { // #113/AK5
  constexpr uint32_t kRate = 48000;
  constexpr uint32_t kFrames = 10 * kRate;
  TempWav f(".flac");
  Capture c;
  CHECK(c.open(f.str().c_str(), kRate, FileFormat::Flac) == 0);
  const auto in = sine(kFrames, 440, kRate);
  // In blocks like the audio thread; wait while the ring is nearly full so nothing is dropped.
  for (uint32_t done = 0; done < kFrames;) {
    const uint32_t n = std::min<uint32_t>(512, kFrames - done);
    while (c.ring().capacity() - c.ring().availableRead() < n)
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    const TapBuffer b{2, n * 2 * static_cast<uint32_t>(sizeof(float)), in.data() + 2 * done};
    c.push(&b, 1, {2, false});
    done += n;
  }
  c.close();
  CHECK(c.meter().frames() == kFrames);
  // A valid FLAC file: magic, then the decoded samples.
  const auto bytes = readBytes(f.str());
  CHECK(bytes.size() > 4 && std::memcmp(bytes.data(), "fLaC", 4) == 0);
  CHECK(bytes.size() < in.size() * sizeof(float)); // compressed, smaller than the float data
  const auto d = decode(f.str());
  CHECK(d.sampleRate == kRate);
  CHECK(maxDiff(d.samples, in) <= 1.0f / 8388607.0f);
  // The core reads its length for the library and loads it for playback: 10 s ± 0.1 s.
  CHECK(std::fabs(wp::fileDuration(f.str()) - 10.0) <= 0.1);
  wp::Player p(kRate);
  CHECK(p.load(f.str()) == wp::kOk);
  CHECK(std::fabs(p.engine().duration() - 10.0) <= 0.1);
}

void captureFlacFailsInMissingFolder() { // #113/AK4: no file, no empty title
  Capture c;
  const auto missing = fs::temp_directory_path() / "wp_recorder_missing_dir" / "x" / "out.flac";
  CHECK(c.open(missing.string().c_str(), 48000, FileFormat::Flac) == WP_REC_ERR_FILE);
  c.close();
  CHECK(!fs::exists(missing));
}

void captureWavStaysDefault() { // #113: the system audio keeps its WAV file
  Capture c;
  TempWav f;
  CHECK(c.open(f.str().c_str(), 48000) == 0);
  c.close();
  CHECK(finishedWav(f.str(), 0));
}

void micDeliversStereoFramesToTheCapture() { // #113/AK2, AK3: every device frame lands in the file
  TempWav f(".flac");
  Capture c;
  CHECK(c.open(f.str().c_str(), 48000, FileFormat::Flac) == 0);
  const auto in = sine(1000, 440, 48000);
  MicInput::deliver(c, in.data(), 600);
  MicInput::deliver(c, in.data() + 1200, 400);
  CHECK(c.meter().frames() == 1000);
  CHECK(!c.meter().onlySilence());
  c.close();
  const auto d = decode(f.str());
  CHECK(d.frames() == 1000);
  CHECK(maxDiff(d.samples, in) <= 1.0f / 8388607.0f);
}

// Waits until the capture counted at least `frames` (at most 5 s); false if it did not.
bool waitForFrames(Capture &c, long long frames) {
  const auto until = std::chrono::steady_clock::now() + std::chrono::seconds(5);
  while (c.meter().frames() < frames) {
    if (std::chrono::steady_clock::now() > until)
      return false;
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
  }
  return true;
}

// miniaudio context on the null backend: a capture device without hardware or permission.
struct NullContext {
  ma_context ctx{};
  bool ok = false;
  NullContext() {
    const ma_backend backends[] = {ma_backend_null};
    ok = ma_context_init(backends, 1, nullptr, &ctx) == MA_SUCCESS;
  }
  NullContext(const NullContext &) = delete;
  NullContext &operator=(const NullContext &) = delete;
  ~NullContext() {
    if (ok)
      ma_context_uninit(&ctx);
  }
};

void micRecordsTheDefaultInputIntoFlac() { // #113/AK1, AK2: default input, duration and level
  NullContext null;
  CHECK(null.ok);
  MicInput mic;
  CHECK(mic.sampleRate() == 0.0);
  Capture c;
  CHECK(!mic.start(c)); // not open
  CHECK(mic.open(&null.ctx));
  CHECK(mic.sampleRate() > 0.0);
  TempWav f(".flac");
  CHECK(c.open(f.str().c_str(), mic.sampleRate(), FileFormat::Flac) == 0);
  c.meter().reset();
  CHECK(mic.start(c));
  const auto until = std::chrono::steady_clock::now() + std::chrono::seconds(5);
  while (c.meter().frames() < static_cast<long long>(mic.sampleRate() / 10) &&
         std::chrono::steady_clock::now() < until)
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
  const double rate = mic.sampleRate();
  mic.close();
  CHECK(mic.sampleRate() == 0.0);
  const long long frames = c.meter().frames();
  CHECK(frames >= static_cast<long long>(rate / 10));
  std::this_thread::sleep_for(std::chrono::milliseconds(30));
  CHECK(c.meter().frames() == frames); // closed: nothing arrives any more
  c.close();
  CHECK(c.meter().onlySilence()); // the null device delivers silence, like a denied permission
  const auto d = decode(f.str());
  CHECK(d.ok);
  CHECK(static_cast<long long>(d.frames()) == frames);
}

void micStopsOnReopenAndDestruction() { // #113/AK2: stop means nothing arrives any more
  NullContext null;
  CHECK(null.ok);
  TempWav f(".flac");
  Capture c;
  {
    MicInput mic;
    CHECK(mic.open(&null.ctx));
    CHECK(c.open(f.str().c_str(), mic.sampleRate(), FileFormat::Flac) == 0);
    CHECK(mic.start(c));
    CHECK(waitForFrames(c, 1));
    CHECK(mic.open(&null.ctx)); // a second open closes the running device first
    const long long afterReopen = c.meter().frames();
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    CHECK(c.meter().frames() == afterReopen);
    CHECK(mic.start(c));
    CHECK(waitForFrames(c, afterReopen + 1));
  } // the destructor stops the device
  const long long afterDestruction = c.meter().frames();
  std::this_thread::sleep_for(std::chrono::milliseconds(50));
  CHECK(c.meter().frames() == afterDestruction);
  c.close();
}

} // namespace

int main() {
  const std::vector<std::pair<std::string, std::function<void()>>> tests = {
      {"meterStartsSilent", meterStartsSilent},
      {"meterKeepsHighestPeakUntilTaken", meterKeepsHighestPeakUntilTaken},
      {"meterSilenceThreshold", meterSilenceThreshold},
      {"meterResetForNextRecording", meterResetForNextRecording},
      {"ringRoundTrip", ringRoundTrip},
      {"ringDropsWhatDoesNotFit", ringDropsWhatDoesNotFit},
      {"ringWrapsAround", ringWrapsAround},
      {"ringReleasesMemory", ringReleasesMemory},
      {"ringFailsWithoutFrames", ringFailsWithoutFrames},
      {"wavHeaderIsStereoFloat", wavHeaderIsStereoFloat},
      {"wavSamplesRoundTrip", wavSamplesRoundTrip},
      {"wavOpenClosesThePreviousFile", wavOpenClosesThePreviousFile},
      {"wavDestructorFinishesFile", wavDestructorFinishesFile},
      {"wavReleasesFileHandles", wavReleasesFileHandles},
      {"wavFailsInMissingFolder", wavFailsInMissingFolder},
      {"captureErrorCodes", captureErrorCodes},
      {"captureRingHoldsTwoSeconds", captureRingHoldsTwoSeconds},
      {"captureStereoInterleaved", captureStereoInterleaved},
      {"captureMonoInterleavedToBoth", captureMonoInterleavedToBoth},
      {"captureMoreChannelsKeepsFirstTwo", captureMoreChannelsKeepsFirstTwo},
      {"captureNonInterleavedTakesLastBuffers", captureNonInterleavedTakesLastBuffers},
      {"captureNonInterleavedMono", captureNonInterleavedMono},
      {"captureMoreTapChannelsThanBuffers", captureMoreTapChannelsThanBuffers},
      {"captureIgnoresEmptyInput", captureIgnoresEmptyInput},
      {"captureDestructorFinishesRecording", captureDestructorFinishesRecording},
      {"captureWritesEverythingOnClose", captureWritesEverythingOnClose},
      {"silentCaptureStaysSilent", silentCaptureStaysSilent},
      {"flacToIntScalesClipsAndRounds", flacToIntScalesClipsAndRounds},
      {"flacRejectsWhatFlacCannotStore", flacRejectsWhatFlacCannotStore},
      {"flacRoundTrip24And16Bit", flacRoundTrip24And16Bit},
      {"flacMonoFile", flacMonoFile},
      {"flacOpenFinishesThePreviousFile", flacOpenFinishesThePreviousFile},
      {"flacDestructorFinishesFile", flacDestructorFinishesFile},
      {"captureFlacTenSecondsLoadsInTheCore", captureFlacTenSecondsLoadsInTheCore},
      {"captureFlacFailsInMissingFolder", captureFlacFailsInMissingFolder},
      {"captureWavStaysDefault", captureWavStaysDefault},
      {"micRecordsTheDefaultInputIntoFlac", micRecordsTheDefaultInputIntoFlac},
      {"micDeliversStereoFramesToTheCapture", micDeliversStereoFramesToTheCapture},
      {"micStopsOnReopenAndDestruction", micStopsOnReopenAndDestruction},
  };
  for (auto &[name, fn] : tests) {
    const int before = failures;
    fn();
    std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name.c_str());
  }
  std::printf("%d checks, %d failures\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
