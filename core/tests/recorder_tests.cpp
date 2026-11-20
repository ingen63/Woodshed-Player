// Tests of the platform-independent part of the recording (#68) without an audio device: level
// meter, ring buffer, WAV file (header and samples) and the copy of the tap layouts into the ring.
// The Core Audio part (recorder_mac.mm) needs real system audio (#51).
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
#include <vector>

#if defined(__unix__) || defined(__APPLE__)
#include <sys/resource.h>
#define WP_HAVE_RLIMIT 1
#endif

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

using wp::rec::Capture;
using wp::rec::FrameRing;
using wp::rec::LevelMeter;
using wp::rec::TapBuffer;
using wp::rec::TapFormat;
using wp::rec::WavFile;

namespace fs = std::filesystem;

// A fresh path in the temp folder; the file is removed when the object goes away.
struct TempWav {
  fs::path path;
  TempWav() {
    static int counter = 0;
    const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    path = fs::temp_directory_path() /
           ("wp_recorder_test_" + std::to_string(stamp) + "_" + std::to_string(++counter) + ".wav");
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
  };
  for (auto &[name, fn] : tests) {
    const int before = failures;
    fn();
    std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name.c_str());
  }
  std::printf("%d checks, %d failures\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
