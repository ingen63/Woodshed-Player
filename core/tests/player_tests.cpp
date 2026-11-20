// Tests des Player-Kerns (#14) ohne Audiogerät: Laden von WAV/FLAC/MP3, Fehlerfälle, Laden im
// Hintergrund, Gerätewechsel, Dateiende, Seek und Loop-Grenzen mit geladenen Dateien. WAV-Dateien
// werden hier erzeugt; FLAC/MP3 stammen aus core/tools/make_test_audio.sh (Sinus 440 Hz, 1 s).
#include <algorithm>
#include <atomic>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iterator>
#include <memory>
#include <new>
#include <random>
#include <string>
#include <thread>
#include <vector>

#include "player_core.hpp"
#include "wp_core.h"

namespace fs = std::filesystem;

static_assert(WP_OK == wp::kOk && WP_ERR_INVALID_ARGUMENT == wp::kErrInvalidArgument &&
                  WP_ERR_FILE_NOT_FOUND == wp::kErrFileNotFound &&
                  WP_ERR_UNSUPPORTED_FORMAT == wp::kErrUnsupportedFormat &&
                  WP_ERR_DEVICE_UNAVAILABLE == wp::kErrDeviceUnavailable &&
                  WP_ERR_OUT_OF_MEMORY == wp::kErrOutOfMemory &&
                  WP_ERR_FILE_UNREADABLE == wp::kErrFileUnreadable &&
                  WP_ERR_CANCELLED == wp::kErrCancelled && WP_ERR_BUSY == wp::kErrBusy &&
                  WP_ERR_UNSUPPORTED_SAMPLE_RATE == wp::kErrUnsupportedSampleRate &&
                  WP_MIN_SAMPLE_RATE == wp::kMinSampleRate,
              "error codes in wp_core.h and player_core.hpp must match");
static_assert(WP_LOAD_IDLE == wp::kLoadIdle && WP_LOAD_RUNNING == wp::kLoadRunning &&
                  WP_LOAD_READY == wp::kLoadReady,
              "load states in wp_core.h and player_core.hpp must match");

// #61: every operator new of this program goes through here. A thread can make its allocations fail
// (tFailAlloc) and the largest single allocation is recorded (gLargestAlloc), to check how much the
// loading reserves at once.
namespace {
thread_local bool tFailAlloc = false;
std::atomic<std::size_t> gLargestAlloc{0};

void *testNew(std::size_t n) {
  if (tFailAlloc)
    throw std::bad_alloc();
  std::size_t largest = gLargestAlloc.load(std::memory_order_relaxed);
  while (n > largest &&
         !gLargestAlloc.compare_exchange_weak(largest, n, std::memory_order_relaxed)) {
  }
  if (void *p = std::malloc(n ? n : 1))
    return p;
  throw std::bad_alloc();
}
void *testNew(std::size_t n, std::align_val_t al) {
  if (tFailAlloc)
    throw std::bad_alloc();
  void *p = nullptr;
  const std::size_t a = std::max(static_cast<std::size_t>(al), sizeof(void *));
  if (posix_memalign(&p, a, n ? n : 1) == 0)
    return p;
  throw std::bad_alloc();
}
} // namespace

void *operator new(std::size_t n) { return testNew(n); }
void *operator new[](std::size_t n) { return testNew(n); }
void *operator new(std::size_t n, const std::nothrow_t &) noexcept {
  try {
    return testNew(n);
  } catch (...) {
    return nullptr;
  }
}
void *operator new[](std::size_t n, const std::nothrow_t &) noexcept {
  try {
    return testNew(n);
  } catch (...) {
    return nullptr;
  }
}
void *operator new(std::size_t n, std::align_val_t a) { return testNew(n, a); }
void *operator new[](std::size_t n, std::align_val_t a) { return testNew(n, a); }
void operator delete(void *p) noexcept { std::free(p); }
void operator delete[](void *p) noexcept { std::free(p); }
void operator delete(void *p, std::size_t) noexcept { std::free(p); }
void operator delete[](void *p, std::size_t) noexcept { std::free(p); }
void operator delete(void *p, std::align_val_t) noexcept { std::free(p); }
void operator delete[](void *p, std::align_val_t) noexcept { std::free(p); }
void operator delete(void *p, std::size_t, std::align_val_t) noexcept { std::free(p); }
void operator delete[](void *p, std::size_t, std::align_val_t) noexcept { std::free(p); }

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

#define CHECK_NEAR(a, b, tol) CHECK(std::fabs((a) - (b)) <= (tol))

constexpr int kSr = 48000;
const fs::path kAudio = WP_TEST_AUDIO_DIR;

fs::path tempDir() {
  static const fs::path dir = [] {
    // Eigener Ordner je Lauf, damit parallele Läufe sich nicht gegenseitig die Dateien löschen.
    fs::path d = fs::temp_directory_path() /
                 ("wp_player_tests_" + std::to_string(std::random_device{}()) + "_" +
                  std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    fs::remove_all(d);
    fs::create_directories(d);
    return d;
  }();
  return dir;
}

void put16(std::ofstream &f, unsigned v) { f.put(char(v & 0xff)).put(char((v >> 8) & 0xff)); }
void put32(std::ofstream &f, unsigned v) {
  put16(f, v & 0xffff);
  put16(f, v >> 16);
}

// 16-Bit-Stereo-WAV mit Frame-Index als Inhalt: links die unteren, rechts die oberen 15 Bit.
// s16 -> f32 teilt durch 32768 und ist damit exakt umkehrbar.
fs::path writeIndexWav(const std::string &name, long long frames, int sr = kSr) {
  const fs::path p = tempDir() / name;
  std::ofstream f(p, std::ios::binary);
  const unsigned bytes = static_cast<unsigned>(frames * 4);
  f.write("RIFF", 4);
  put32(f, 36 + bytes);
  f.write("WAVE", 4);
  f.write("fmt ", 4);
  put32(f, 16);
  put16(f, 1);
  put16(f, 2);
  put32(f, sr);
  put32(f, sr * 4);
  put16(f, 4);
  put16(f, 16);
  f.write("data", 4);
  put32(f, bytes);
  for (long long i = 0; i < frames; ++i) {
    put16(f, static_cast<unsigned>(i & 0x7fff));
    put16(f, static_cast<unsigned>((i >> 15) & 0x7fff));
  }
  return p;
}

long long frameIndex(const float *frame) {
  return std::llround(frame[0] * 32768.0) + (std::llround(frame[1] * 32768.0) << 15);
}

fs::path writeBytes(const std::string &name, const std::string &bytes) {
  const fs::path p = tempDir() / name;
  std::ofstream(p, std::ios::binary) << bytes;
  return p;
}

std::vector<float> renderFrames(wp::Player &p, long long frames, int block = 480) {
  std::vector<float> out(static_cast<size_t>(frames) * 2);
  for (long long done = 0; done < frames;) {
    const int n = static_cast<int>(std::min<long long>(block, frames - done));
    p.render(out.data() + done * 2, n);
    done += n;
  }
  return out;
}

double rms(const std::vector<float> &v, long long from, long long count) {
  double s = 0;
  for (long long i = from; i < from + count; ++i)
    s += double(v[i * 2]) * v[i * 2];
  return std::sqrt(s / count);
}

double zeroCrossingFreq(const std::vector<float> &v, long long from, long long count) {
  int crossings = 0;
  for (long long i = from + 1; i < from + count; ++i)
    if (v[(i - 1) * 2] < 0 && v[i * 2] >= 0)
      ++crossings;
  return crossings * double(kSr) / count;
}

// ---------------------------------------------------------------------------

void loadsWavSampleExact() { // #14/AK5 (WAV), Seek
  wp::Player p(kSr);
  CHECK(p.loadState() == wp::kLoadIdle);
  CHECK(p.load(writeIndexWav("index2s.wav", 2 * kSr).string()) == wp::kOk);
  CHECK(p.loadState() == wp::kLoadReady);
  CHECK(p.loadProgress() == 1.0);
  CHECK_NEAR(p.engine().duration(), 2.0, 1e-9);
  p.engine().seek(1.25);
  p.engine().play();
  float frame[2];
  p.render(frame, 1);
  CHECK(frameIndex(frame) == 60000);
  p.render(frame, 1);
  CHECK(frameIndex(frame) == 60001);
}

void loadCompressed(const char *file, double durationTol) {
  wp::Player p(kSr);
  const int r = p.load((kAudio / file).string());
  CHECK(r == wp::kOk);
  if (r != wp::kOk)
    return;
  CHECK_NEAR(p.engine().duration(), 1.0, durationTol); // 44,1 kHz mono -> 48 kHz stereo
  p.engine().play();
  auto out = renderFrames(p, kSr / 2);
  CHECK_NEAR(zeroCrossingFreq(out, kSr / 10, kSr / 4), 440.0, 8.0);
  CHECK_NEAR(rms(out, kSr / 10, kSr / 4), 0.5 / std::sqrt(2.0), 0.05);
  bool stereo = true; // mono wird auf beide Kanäle verteilt
  for (long long i = kSr / 10; i < kSr / 4; ++i)
    stereo = stereo && out[i * 2] == out[i * 2 + 1];
  CHECK(stereo);
}

void loadsFlac() { loadCompressed("sine440.flac", 2e-3); } // #14/AK5 (FLAC)
void loadsMp3() { loadCompressed("sine440.mp3", 0.06); }   // #14/AK5 (MP3, Encoder-Verzögerung)

void endOfFileStopsWithLoadedFile() { // #14/AK5 Dateiende
  wp::Player p(kSr);
  CHECK(p.load(writeIndexWav("index1s.wav", kSr).string()) == wp::kOk);
  p.engine().seek(0.99);
  p.engine().play();
  auto out = renderFrames(p, kSr / 50);
  CHECK(frameIndex(&out[(kSr / 100 - 1) * 2]) == kSr - 1);
  CHECK(out[(kSr / 100) * 2] == 0.0f && out[(kSr / 100) * 2 + 1] == 0.0f);
  CHECK(!p.engine().playing());
  CHECK_NEAR(p.engine().position(), 1.0, 1e-9);
  p.engine().play(); // am Ende: wieder von vorn
  float frame[2];
  p.render(frame, 1);
  CHECK(frameIndex(frame) == 0);
}

void loopBoundsWithLoadedFile() { // #14/AK5 Loop-Grenzen
  wp::Player p(kSr);
  CHECK(p.load(writeIndexWav("index3s.wav", 3 * kSr).string()) == wp::kOk);
  p.engine().setLoop(0.5, 1.75);
  p.engine().seek(1.7);
  p.engine().play();
  auto out = renderFrames(p, 4 * kSr, 333);
  long long expected = static_cast<long long>(1.7 * kSr);
  bool ok = true;
  for (long long i = 0; i < 4 * kSr && ok; ++i) {
    ok = frameIndex(&out[i * 2]) == expected;
    if (++expected >= static_cast<long long>(1.75 * kSr))
      expected = kSr / 2;
  }
  CHECK(ok);
  CHECK(p.engine().playing());
  // Loop über das Dateiende hinaus wird am Ende begrenzt.
  p.engine().setLoop(2.0, 5.0);
  p.engine().seek(2.99);
  auto end = renderFrames(p, kSr / 50);
  CHECK(frameIndex(&end[(kSr / 100 - 1) * 2]) == 3 * kSr - 1);
  CHECK(frameIndex(&end[(kSr / 100) * 2]) == 2 * kSr);
}

// Bisheriger Titel spielt nach einem Fehler weiter, Dauer bleibt.
void checkStillPlayable(wp::Player &p, double duration) {
  CHECK_NEAR(p.engine().duration(), duration, 1e-9);
  p.engine().seek(0.5);
  p.engine().play();
  float frame[2];
  p.render(frame, 1);
  CHECK(frameIndex(frame) == kSr / 2);
  CHECK(p.engine().playing());
}

void loadErrorsHaveCodeAndText() { // #14/AK2, #14/AK5 Fehlerfälle
  wp::Player p(kSr);
  CHECK(p.load(writeIndexWav("good.wav", 2 * kSr).string()) == wp::kOk);

  const int missing = p.load((tempDir() / "missing.mp3").string());
  CHECK(missing == wp::kErrFileNotFound);
  CHECK(std::strcmp(wp::errorMessage(missing), "File not found") == 0);
  CHECK(p.loadState() == wp::kErrFileNotFound);
  checkStillPlayable(p, 2.0);

  const int garbage = p.load(writeBytes("no-audio.mp3", std::string(4096, 'x')).string());
  CHECK(garbage == wp::kErrUnsupportedFormat);
  CHECK(std::strcmp(wp::errorMessage(garbage), "Unsupported format or corrupt file") == 0);
  checkStillPlayable(p, 2.0);

  CHECK(p.load(writeBytes("empty.wav", "").string()) == wp::kErrUnsupportedFormat);
  checkStillPlayable(p, 2.0);

  CHECK(p.load("") == wp::kErrInvalidArgument);
  checkStillPlayable(p, 2.0);

  p.setDeviceAvailable(false);
  const int device = p.load(writeIndexWav("good2.wav", kSr).string());
  CHECK(device == wp::kErrDeviceUnavailable);
  CHECK(std::strcmp(wp::errorMessage(device), "Audio device unavailable") == 0);
  checkStillPlayable(p, 2.0);
  p.setDeviceAvailable(true);

  // Jeder Code hat einen eigenen Text.
  for (int c = wp::kErrInvalidArgument; c >= wp::kErrUnsupportedSampleRate; --c)
    CHECK(std::strcmp(wp::errorMessage(c), wp::errorMessage(-100)) != 0);
}

// #10/AK3: truncated or wrong audio files never crash; the load ends with kOk (the readable part)
// or kErrUnsupportedFormat, whose text the app shows in the user's language (loadUnsupported in
// the ARB files). After a failed load the previous title stays playable. The cut points cover the
// empty file, a part of the header, the header alone and parts of the audio data.
void truncatedAndWrongAudioFiles() {
  wp::Player p(kSr);
  CHECK(p.load(writeIndexWav("previous.wav", 2 * kSr).string()) == wp::kOk);
  const auto readAll = [](const fs::path &f) {
    std::ifstream in(f, std::ios::binary);
    return std::string((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
  };
  const std::string wav = readAll(writeIndexWav("whole.wav", kSr / 2));
  const struct {
    const char *ext;
    std::string bytes;
  } files[] = {{"wav", wav},
               {"flac", readAll(kAudio / "sine440.flac")},
               {"mp3", readAll(kAudio / "sine440.mp3")}};
  int ok = 0, unsupported = 0;
  for (const auto &f : files) {
    const size_t n = f.bytes.size();
    for (const size_t cut : {size_t{0}, size_t{1}, size_t{4}, size_t{12}, size_t{44}, size_t{100},
                             n / 4, n / 2, 3 * n / 4, n - 1}) {
      const std::string name = std::string("cut_") + std::to_string(cut) + "." + f.ext;
      const fs::path path = writeBytes(name, f.bytes.substr(0, cut));
      const int r = p.load(path.string());
      CHECK(r == wp::kOk || r == wp::kErrUnsupportedFormat);
      const double d = wp::fileDuration(path.string());
      CHECK(d > 0 || d == wp::kErrUnsupportedFormat);
      if (r == wp::kOk) {
        ++ok;
        CHECK(p.engine().duration() > 0 && p.engine().duration() <= 1.1); // at most the whole file
        CHECK(p.load(writeIndexWav("previous.wav", 2 * kSr).string()) == wp::kOk);
      } else {
        ++unsupported;
        checkStillPlayable(p, 2.0);
      }
    }
  }
  CHECK(ok > 0 && unsupported > 0); // both outcomes occur
  // Wrong contents behind a known extension, and a known format behind a wrong extension.
  CHECK(p.load(writeBytes("text.flac", "fLaC but not really a FLAC stream").string()) ==
        wp::kErrUnsupportedFormat);
  CHECK(p.load(writeBytes("riff.wav", std::string("RIFF\x10\0\0\0WAVEfmt ", 16)).string()) ==
        wp::kErrUnsupportedFormat);
  checkStillPlayable(p, 2.0);
  CHECK(p.load(writeBytes("flac_named.mp3", files[1].bytes).string()) == wp::kOk);
  CHECK_NEAR(p.engine().duration(), 1.0, 2e-3);
}

void errorDuringPlaybackKeepsPlaying() { // #14/AK2
  wp::Player p(kSr);
  CHECK(p.load(writeIndexWav("play.wav", 3 * kSr).string()) == wp::kOk);
  p.engine().play();
  renderFrames(p, kSr / 2);
  CHECK(p.load((tempDir() / "missing.flac").string()) == wp::kErrFileNotFound);
  float frame[2];
  p.render(frame, 1);
  CHECK(frameIndex(frame) == kSr / 2);
  CHECK(p.engine().playing());
}

void loadRunsInBackground() { // #14/AK3
  const fs::path big = writeIndexWav("big60s.wav", 60LL * kSr);
  wp::Player p(kSr);
  CHECK(p.load(writeIndexWav("small.wav", 2 * kSr).string()) == wp::kOk);
  p.engine().play();

  const auto t0 = std::chrono::steady_clock::now();
  CHECK(p.loadAsync(big.string()) == wp::kOk);
  const double startMs =
      std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
  CHECK(startMs < 50.0); // kehrt sofort zurück, dekodiert wird im Hintergrund

  // Während des Ladens läuft die Wiedergabe weiter, Fortschritt steigt.
  double lastProgress = 0;
  bool monotonic = true, sawRunning = false, sawPartial = false;
  std::vector<float> out(480 * 2);
  int state = 0;
  while ((state = p.loadState()) == wp::kLoadRunning) {
    sawRunning = true;
    p.render(out.data(), 480);
    const double prog = p.loadProgress();
    monotonic = monotonic && prog >= lastProgress && prog <= 1.0;
    sawPartial = sawPartial || (prog > 0.0 && prog < 1.0); // #11: progress in steps
    lastProgress = prog;
    std::this_thread::sleep_for(std::chrono::microseconds(200));
  }
  CHECK(sawRunning || state == wp::kLoadReady);
  CHECK(monotonic);
  // #11: 60 s are decoded in 352 blocks of 8192 frames; polled every 0.2 ms the state is seen as
  // running (the previous title left it «ready») and the progress between 0 and 1
  CHECK(sawRunning);
  CHECK(sawPartial);
  CHECK(state == wp::kLoadReady);
  CHECK(p.waitForLoad() == wp::kOk);
  CHECK(p.loadProgress() == 1.0);
  CHECK_NEAR(p.engine().duration(), 60.0, 1e-9);
  p.render(out.data(), 1); // neuer Titel steht am Anfang, pausiert
  CHECK(!p.engine().playing());
  CHECK(p.engine().position() == 0.0);
}

void newerLoadReplacesRunningLoad() { // #14/AK3
  const fs::path big = writeIndexWav("big30s.wav", 30LL * kSr);
  const fs::path small = writeIndexWav("small1s.wav", kSr);
  wp::Player p(kSr);
  CHECK(p.loadAsync(big.string()) == wp::kOk);
  CHECK(p.loadAsync(small.string()) == wp::kOk);
  CHECK(p.waitForLoad() == wp::kOk);
  float frame[2];
  p.render(frame, 1);
  CHECK_NEAR(p.engine().duration(), 1.0, 1e-9);
}

void fileDurationWithoutLoading() { // #16/AK4 (Dauer beim Import)
  CHECK_NEAR(wp::fileDuration(writeIndexWav("dur.wav", 3 * kSr / 2).string()), 1.5, 1e-9);
  CHECK_NEAR(wp::fileDuration((kAudio / "sine440.flac").string()), 1.0, 1e-6);
  CHECK_NEAR(wp::fileDuration((kAudio / "sine440.mp3").string()), 1.0, 0.06);
  CHECK(wp::fileDuration((tempDir() / "missing.mp3").string()) == wp::kErrFileNotFound);
  CHECK(wp::fileDuration(writeBytes("nix.mp3", std::string(512, 'x')).string()) ==
        wp::kErrUnsupportedFormat);
  CHECK(wp::fileDuration("") == wp::kErrInvalidArgument);
}

// 16-Bit-Stereo-WAV mit Sinus (440 Hz) der Amplitude amp.
fs::path writeSineWav(const std::string &name, double seconds, double amp) {
  const fs::path p = tempDir() / name;
  const long long frames = std::llround(seconds * kSr);
  std::ofstream f(p, std::ios::binary);
  const unsigned bytes = static_cast<unsigned>(frames * 4);
  f.write("RIFF", 4);
  put32(f, 36 + bytes);
  f.write("WAVE", 4);
  f.write("fmt ", 4);
  put32(f, 16);
  put16(f, 1);
  put16(f, 2);
  put32(f, kSr);
  put32(f, kSr * 4);
  put16(f, 4);
  put16(f, 16);
  f.write("data", 4);
  put32(f, bytes);
  for (long long i = 0; i < frames; ++i) {
    const auto s = static_cast<unsigned>(
        static_cast<int>(std::lround(amp * 32767 * std::sin(2 * M_PI * 440 * i / kSr))) & 0xffff);
    put16(f, s);
    put16(f, s);
  }
  return p;
}

void waveformOfLoadedFile() { // #28/AK1–AK4 über den Player
  wp::Player p(kSr);
  float mins[100], maxs[100];
  CHECK(p.waveform(0.0, 1.0, 100, mins, maxs) == wp::kErrInvalidArgument); // noch kein Titel
  CHECK(p.load(writeSineWav("sine_half.wav", 2.0, 0.5).string()) == wp::kOk);
  CHECK(p.waveform(0.0, p.engine().duration(), 100, mins, maxs) == wp::kOk);
  int bad = 0;
  for (int i = 0; i < 100; ++i)
    if (std::fabs(mins[i] + 0.5f) > 0.01f || std::fabs(maxs[i] - 0.5f) > 0.01f)
      ++bad;
  CHECK(bad == 0);
  CHECK(p.waveform(1.0, 0.5, 10, mins, maxs) == wp::kErrInvalidArgument);
  CHECK(p.waveform(1.0, 3.0, 10, mins, maxs) == wp::kErrInvalidArgument);
  // Ein fehlgeschlagenes Laden behält die Wellenform des bisherigen Titels.
  CHECK(p.load((tempDir() / "missing.wav").string()) == wp::kErrFileNotFound);
  CHECK(p.waveform(0.0, 2.0, 10, mins, maxs) == wp::kOk);
  // Ein neuer Titel ersetzt sie.
  CHECK(p.load(writeSineWav("silence.wav", 1.0, 0.0).string()) == wp::kOk);
  CHECK(p.waveform(0.0, 2.0, 10, mins, maxs) == wp::kErrInvalidArgument);
  CHECK(p.waveform(0.0, 1.0, 10, mins, maxs) == wp::kOk);
  CHECK(mins[0] == 0.0f && maxs[9] == 0.0f);
}

void devicePolicy() { // #14/AK4
  CHECK(wp::pausesPlayback(wp::DeviceEvent::Rerouted));
  CHECK(wp::pausesPlayback(wp::DeviceEvent::InterruptionBegan));
  CHECK(wp::pausesPlayback(wp::DeviceEvent::Stopped));
  CHECK(!wp::pausesPlayback(wp::DeviceEvent::Started));
  CHECK(!wp::pausesPlayback(wp::DeviceEvent::InterruptionEnded));
}

void deviceChangePausesAndKeepsPosition() { // #14/AK4
  for (auto ev :
       {wp::DeviceEvent::Rerouted, wp::DeviceEvent::InterruptionBegan, wp::DeviceEvent::Stopped}) {
    wp::Player p(kSr);
    const int lr = p.load(writeIndexWav("device.wav", 3 * kSr).string());
    if (lr != wp::kOk)
      std::printf("  load error %d at event %d\n", lr, int(ev));
    CHECK(lr == wp::kOk);
    p.engine().setRate(0.75); // auch im gedehnten Pfad
    p.engine().play();
    p.metronome().start();
    renderFrames(p, kSr);
    const double pos = p.engine().position();

    p.onDeviceEvent(ev); // z. B. Kopfhörer ab
    auto out = renderFrames(p, kSr / 5);
    bool silent = true;
    for (float x : out)
      silent = silent && x == 0.0f;
    CHECK(silent);
    CHECK(!p.engine().playing());
    CHECK(!p.metronome().running());
    CHECK(p.engine().position() == pos);

    p.onDeviceEvent(wp::DeviceEvent::InterruptionEnded); // kein automatisches Weiterspielen
    p.onDeviceEvent(wp::DeviceEvent::Started);
    renderFrames(p, 480);
    CHECK(!p.engine().playing());
    CHECK(p.engine().position() == pos);

    p.engine().setRate(1.0);
    p.engine().play(); // weiter an derselben Stelle
    float frame[2];
    p.render(frame, 1);
    CHECK(std::llabs(frameIndex(frame) - std::llround(pos * kSr)) <= 1);
  }
}

std::string readBytes(const fs::path &p) {
  std::ifstream f(p, std::ios::binary);
  return std::string(std::istreambuf_iterator<char>(f), {});
}

// Dekodieren aus dem Speicher (Web) liefert dasselbe wie aus der Datei (#33/AK3).
// #8: a file without read permission is reported as unreadable (wp_core.h: WP_ERR_FILE_UNREADABLE),
// not as missing or as unsupported; the current title stays playable.
void unreadableFileIsReported() {
  wp::Player p(kSr);
  CHECK(p.load(writeIndexWav("good3.wav", 2 * kSr).string()) == wp::kOk);
  const fs::path locked = writeIndexWav("locked.wav", kSr);
  fs::permissions(locked, fs::perms::none);
  std::ifstream probe(locked);
  if (probe.is_open()) { // running as root: permissions do not apply
    std::printf("  note: file permissions not enforced, check skipped\n");
  } else {
    CHECK(p.load(locked.string()) == wp::kErrFileUnreadable);
    CHECK(std::strcmp(wp::errorMessage(wp::kErrFileUnreadable), "File cannot be read") == 0);
    CHECK(wp::fileDuration(locked.string()) == wp::kErrFileUnreadable);
    checkStillPlayable(p, 2.0);
  }
  fs::permissions(locked, fs::perms::owner_read | fs::perms::owner_write);
}

// #8: a valid WAV header without a single frame is no audio.
void emptyAudioIsUnsupported() {
  wp::Player p(kSr);
  const fs::path empty = writeIndexWav("zero-frames.wav", 0);
  CHECK(p.load(empty.string()) == wp::kErrUnsupportedFormat);
  CHECK(wp::fileDuration(empty.string()) == wp::kErrUnsupportedFormat);
  const std::string bytes = readBytes(empty);
  wp::Source out;
  CHECK(wp::decodeMemory(bytes.data(), bytes.size(), kSr, out) == wp::kErrUnsupportedFormat);
  CHECK(out.frames == 0 && out.data.empty());
}

void decodeMemoryMatchesFile() {
  for (const fs::path &file :
       {writeIndexWav("mem.wav", kSr / 2), kAudio / "sine440.flac", kAudio / "sine440.mp3"}) {
    wp::Player fromFile(kSr);
    CHECK(fromFile.load(file.string()) == wp::kOk);
    const std::string bytes = readBytes(file);
    auto src = std::make_unique<wp::Source>();
    CHECK(wp::decodeMemory(bytes.data(), bytes.size(), kSr, *src) == wp::kOk);
    CHECK(src->frames == fromFile.engine().frames());
    wp::Player fromMemory(kSr);
    CHECK(fromMemory.setSource(std::move(src)) == wp::kOk);
    CHECK(fromMemory.engine().duration() == fromFile.engine().duration());
    fromFile.engine().play();
    fromMemory.engine().play();
    const long long n = fromFile.engine().frames();
    CHECK(renderFrames(fromFile, n) == renderFrames(fromMemory, n));
  }
  wp::Source out;
  CHECK(wp::decodeMemory("no audio!!", 10, kSr, out) == wp::kErrUnsupportedFormat);
  CHECK(wp::decodeMemory("", 0, kSr, out) == wp::kErrUnsupportedFormat);
  CHECK(wp::decodeMemory(nullptr, 10, kSr, out) == wp::kErrInvalidArgument);
}

// #61: FLAC of silence (mono, 16 bit, fixed blocks of 4096 frames, one CONSTANT subframe each), a
// few bytes per block, so far more audio than kMinBytesPerSecond allows for its size. STREAMINFO
// claims `claimed` frames (default: the true length); a PADDING block of `padding` bytes makes the
// file larger without audio.
std::string silentFlac(long long frames, int sr, long long claimed = -1, size_t padding = 0) {
  if (claimed < 0)
    claimed = frames;
  constexpr int kBlockFrames = 4096;
  auto crc8 = [](const std::string &d) {
    unsigned c = 0;
    for (const unsigned char b : d) {
      c ^= b;
      for (int i = 0; i < 8; ++i)
        c = (c & 0x80) ? ((c << 1) ^ 0x07) & 0xff : (c << 1) & 0xff;
    }
    return static_cast<char>(c);
  };
  auto crc16 = [](const std::string &d) {
    unsigned c = 0;
    for (const unsigned char b : d) {
      c ^= static_cast<unsigned>(b) << 8;
      for (int i = 0; i < 8; ++i)
        c = (c & 0x8000) ? ((c << 1) ^ 0x8005) & 0xffff : (c << 1) & 0xffff;
    }
    return c;
  };
  std::string f = "fLaC";
  f += padding > 0 ? '\x00' : '\x80'; // STREAMINFO, last metadata block without padding
  f += std::string("\x00\x00\x22", 3);
  f += std::string("\x10\x00\x10\x00", 4); // block size 4096 .. 4096
  f += std::string(6, '\0');               // frame sizes unknown
  // 20 bits sample rate, 3 bits channels - 1 (0), 5 bits bits per sample - 1 (15), 36 bits frames
  const unsigned long long packed = (static_cast<unsigned long long>(sr) << 44) | (15ULL << 36) |
                                    static_cast<unsigned long long>(claimed);
  for (int b = 7; b >= 0; --b)
    f += static_cast<char>((packed >> (8 * b)) & 0xff);
  f += std::string(16, '\0'); // MD5 unknown
  if (padding > 0) {
    f += '\x81'; // last metadata block, PADDING
    for (int b = 2; b >= 0; --b)
      f += static_cast<char>((padding >> (8 * b)) & 0xff);
    f += std::string(padding, '\0');
  }
  CHECK(sr == 8000 && frames % kBlockFrames == 0);
  for (long long n = 0; n < frames / kBlockFrames; ++n) {
    std::string h = "\xff\xf8"; // sync, fixed block size
    h += '\xc4';                // 4096 frames, 8 kHz
    h += '\x08';                // mono, 16 bit
    if (n < 0x80) {             // frame number, UTF-8 coded
      h += static_cast<char>(n);
    } else {
      h += static_cast<char>(0xc0 | (n >> 6));
      h += static_cast<char>(0x80 | (n & 0x3f));
    }
    h += crc8(h);
    h += std::string(3, '\0'); // CONSTANT subframe, value 0
    const unsigned c = crc16(h);
    h += static_cast<char>(c >> 8);
    h += static_cast<char>(c & 0xff);
    f += h;
  }
  return f;
}

// #75: titles longer than 5 minutes, here 6 minutes at the lowest rate (8 kHz, 23 MB decoded).
constexpr int kLongSr = wp::kMinSampleRate;
constexpr long long kLongFrames = 6LL * 60 * kLongSr;

// The frame index pattern of writeIndexWav at a few places, and the length.
void checkIndexSource(const wp::Source &src, long long frames) {
  CHECK(src.frames == frames);
  CHECK(src.data.size() == static_cast<size_t>(frames) * 2);
  if (src.frames != frames)
    return;
  for (const long long i : {0LL, 1LL, frames / 3, frames / 2, frames - 2, frames - 1})
    CHECK(frameIndex(&src.data[static_cast<size_t>(i) * 2]) == i);
}

// The WAV of writeIndexWav with another length in its header (RIFF and data chunk size).
std::string withHeaderFrames(std::string wav, unsigned long long frames) {
  const auto put = [&wav](size_t at, unsigned long long v) {
    const auto u = static_cast<unsigned>(std::min<unsigned long long>(v, 0xffffffffULL));
    for (int b = 0; b < 4; ++b)
      wav[at + static_cast<size_t>(b)] = static_cast<char>((u >> (8 * b)) & 0xff);
  };
  put(4, 36 + frames * 4);
  put(40, frames * 4);
  return wav;
}

// #75/AK1: a long title with a correct header reserves its length once instead of growing
// geometrically: the buffer ends up no larger than the samples plus one decode block.
void longTitleReservesHeaderLength() {
  const fs::path file = writeIndexWav("long6min.wav", kLongFrames, kLongSr);
  const std::string bytes = readBytes(file);
  wp::Source out;
  CHECK(wp::decodeMemory(bytes.data(), bytes.size(), kLongSr, out) == wp::kOk);
  checkIndexSource(out, kLongFrames);
  CHECK(out.data.capacity() <= static_cast<size_t>(kLongFrames + 8192) * 2);
  // the same from the file (size from the file system)
  wp::Player p(kLongSr);
  CHECK(p.load(file.string()) == wp::kOk);
  CHECK(p.engine().frames() == kLongFrames);
}

// #75/AK3: a wrong length in the header still loads correctly. Too long (twice, and far beyond
// what the file can hold) reads up to the end of the data; too short reads what the header
// claims, as before. Implausible lengths are not reserved.
void longTitleWithWrongHeaderLength() {
  const std::string wav = readBytes(writeIndexWav("long6min-wrong.wav", kLongFrames, kLongSr));
  for (const unsigned long long claimed :
       {2ULL * kLongFrames, 0xffffffffULL / 4, static_cast<unsigned long long>(kLongFrames) - 1}) {
    const std::string bytes = withHeaderFrames(wav, claimed);
    wp::Source out;
    CHECK(wp::decodeMemory(bytes.data(), bytes.size(), kLongSr, out) == wp::kOk);
    const long long expected = std::min<long long>(kLongFrames, static_cast<long long>(claimed));
    checkIndexSource(out, expected);
    // twice the length is plausible for the file size and reserves at most that; the claim of
    // 4 GB of samples from 11.5 MB is not, the buffer only grows to what was decoded
    if (claimed == 2ULL * kLongFrames)
      CHECK(out.data.capacity() <= static_cast<size_t>(claimed + 8192) * 2);
    else
      CHECK(out.data.capacity() < static_cast<size_t>(4 * kLongFrames) * 2);
    wp::Player p(kLongSr);
    CHECK(p.load(writeBytes("long6min-claimed.wav", bytes).string()) == wp::kOk);
    CHECK(p.engine().frames() == expected);
  }
}

// #75/AK1, #61: loading from a file uses the file size for the plausibility of the header length,
// so a long title reserves its length once there too: no single allocation is larger than the
// samples plus one decode block (growing step by step would allocate about twice 5 minutes).
void longTitleFromFileReservesOnce() {
  const fs::path file = writeIndexWav("long6min-file.wav", kLongFrames, kLongSr);
  gLargestAlloc.store(0);
  wp::Player p(kLongSr);
  CHECK(p.load(file.string()) == wp::kOk);
  CHECK(p.engine().frames() == kLongFrames);
  CHECK(gLargestAlloc.load() <= static_cast<size_t>(kLongFrames + 8192) * 2 * sizeof(float));
}

// #75, #61: the header length is reserved only once the decoder has really delivered the first
// 5 minutes. A title of 1 minute whose header claims 6 minutes (plausible for the file size, made
// large with padding) keeps the reservation of 5 minutes.
void shortTitleClaimingLongerReservesOnlyFiveMinutes() {
  constexpr long long kOneMinute = 118LL * 4096;
  constexpr long long kClaimed = 704LL * 4096;
  const std::string bytes = silentFlac(kOneMinute, 8000, kClaimed, 200000);
  wp::Source out;
  CHECK(wp::decodeMemory(bytes.data(), bytes.size(), 8000, out) == wp::kOk);
  CHECK(out.frames == kOneMinute);
  CHECK(out.data.capacity() <= static_cast<size_t>(300LL * 8000 + 8192) * 2);
}

// #75, #61: the header length is trusted for the reservation only if the file is large enough for
// that much audio. Six minutes of silence in FLAC take 8 KB: the true length is reserved no more
// than an implausible one, the buffer grows while decoding.
void lengthImplausibleForTheFileSizeIsNotReserved() {
  constexpr long long kFrames = 704LL * 4096; // a bit over 6 minutes at 8 kHz
  const std::string bytes = silentFlac(kFrames, 8000);
  CHECK(bytes.size() < 10000);
  wp::Source out;
  CHECK(wp::decodeMemory(bytes.data(), bytes.size(), 8000, out) == wp::kOk);
  CHECK(out.frames == kFrames);
  CHECK(std::all_of(out.data.begin(), out.data.end(), [](float v) { return v == 0.0f; }));
  CHECK(out.data.capacity() != static_cast<size_t>(kFrames + 8192) * 2);
}

// #14/AK3, #61: after a load the progress is 1, also when the header claimed more frames than the
// file holds (the frames counted then stay below the claimed length).
void progressIsCompleteAfterLoad() {
  const fs::path file = writeBytes("claims-double.flac", silentFlac(4LL * 4096, 8000, 8LL * 4096));
  wp::Player p(8000);
  CHECK(p.load(file.string()) == wp::kOk);
  CHECK(p.engine().frames() == 4LL * 4096);
  CHECK(p.loadProgress() == 1.0);
}

// #14/AK2, #61: if the loading thread cannot be started (no memory), the load reports
// WP_ERR_OUT_OF_MEMORY, and the load state says so too.
void loadThreadWithoutMemory() {
  const std::string file = writeIndexWav("no-thread.wav", 1000).string();
  wp::Player p(kSr);
  tFailAlloc = true;
  const int r = p.loadAsync(file);
  tFailAlloc = false;
  CHECK(r == wp::kErrOutOfMemory);
  CHECK(p.loadState() == wp::kErrOutOfMemory);
  CHECK(p.load(file) == wp::kOk); // afterwards loading works again
}

// #76, #61: the metronome clicks at the rate of the player (unsupported rates: the lowest one).
void metronomeRunsAtThePlayerRate() {
  for (const int rate : {8000, 22050, 96000}) {
    wp::Player p(rate);
    CHECK(p.metronome().sampleRate() == rate);
    CHECK(p.engine().sampleRate() == rate);
  }
  wp::Player low(wp::kMinSampleRate - 1);
  CHECK(low.metronome().sampleRate() == wp::kMinSampleRate);
}

// #76, #61: a player with an unsupported sample rate renders silence into the whole buffer.
void unsupportedRateRendersSilence() {
  wp::Player p(wp::kMinSampleRate - 1);
  std::vector<float> out(256 * 2, 0.5f);
  p.render(out.data(), 256);
  CHECK(std::all_of(out.begin(), out.end(), [](float v) { return v == 0.0f; }));
}

// Fremd dekodiertes PCM (AAC/M4A aus dem Browser) wird auf Stereo und die Rate des Kerns gewandelt
// (#33/AK4).
void convertPcmToPlayerFormat() {
  constexpr int kSrc = 44100;
  std::vector<float> mono(kSrc);
  for (int i = 0; i < kSrc; ++i)
    mono[i] = 0.5f * static_cast<float>(std::sin(2 * 3.14159265358979323846 * 440 * i / kSrc));
  auto src = std::make_unique<wp::Source>();
  CHECK(wp::convertPcm(mono.data(), 1, kSrc, kSrc, kSr, *src) == wp::kOk);
  CHECK(std::llabs(src->frames - kSr) <= 2);
  wp::Player p(kSr);
  CHECK(p.setSource(std::move(src)) == wp::kOk);
  CHECK_NEAR(p.engine().duration(), 1.0, 1e-3);
  float mins[10], maxs[10];
  CHECK(p.waveform(0.0, 0.5, 10, mins, maxs) == wp::kOk);
  CHECK_NEAR(maxs[5], 0.5, 0.01);
  p.engine().play();
  auto out = renderFrames(p, kSr / 2);
  CHECK_NEAR(zeroCrossingFreq(out, kSr / 10, kSr / 4), 440.0, 8.0);
  CHECK_NEAR(rms(out, kSr / 10, kSr / 4), 0.5 / std::sqrt(2.0), 0.02);
  bool stereo = true;
  for (long long i = kSr / 10; i < kSr / 4; ++i)
    stereo = stereo && out[i * 2] == out[i * 2 + 1];
  CHECK(stereo);

  // Gleiche Rate, Stereo: unverändert
  std::vector<float> st = {0.1f, -0.1f, 0.2f, -0.2f, 0.3f, -0.3f};
  wp::Source same;
  CHECK(wp::convertPcm(st.data(), 2, 3, kSr, kSr, same) == wp::kOk);
  CHECK(same.frames == 3 && same.data == st);

  wp::Source bad;
  CHECK(wp::convertPcm(nullptr, 2, 3, kSr, kSr, bad) == wp::kErrInvalidArgument);
  CHECK(wp::convertPcm(st.data(), 0, 3, kSr, kSr, bad) == wp::kErrInvalidArgument);
  CHECK(wp::convertPcm(st.data(), 2, 0, kSr, kSr, bad) == wp::kErrInvalidArgument);
  CHECK(wp::convertPcm(st.data(), 2, 3, 0, kSr, bad) == wp::kErrUnsupportedSampleRate); // #76
  wp::Player q(kSr);
  CHECK(q.setSource(nullptr) == wp::kErrInvalidArgument);
  CHECK(q.setSource(std::make_unique<wp::Source>()) == wp::kErrInvalidArgument);
}

// #42/AK1: in the browser the worklet takes over a title without computing the waveform (the worker
// has it).
void setSourceWithoutPeaks() {
  wp::Player p(kSr);
  auto first = std::make_unique<wp::Source>();
  first->data.assign(static_cast<size_t>(kSr) * 2, 0.5f);
  first->frames = kSr;
  CHECK(p.setSource(std::move(first)) == wp::kOk);
  float mins[10], maxs[10];
  CHECK(p.waveform(0.0, 1.0, 10, mins, maxs) == wp::kOk);
  auto second = std::make_unique<wp::Source>();
  second->data.assign(static_cast<size_t>(kSr) * 4, 0.25f);
  second->frames = 2 * kSr;
  CHECK(p.setSource(std::move(second), false) == wp::kOk);
  CHECK_NEAR(p.engine().duration(), 2.0, 1e-9);
  CHECK(p.waveform(0.0, 1.0, 10, mins, maxs) == wp::kErrInvalidArgument); // no stale waveform
  p.engine().play();
  auto out = renderFrames(p, 64);
  CHECK(out[10] == 0.25f);
}

// #11, found by mutation testing: the load state follows every request. A rejected request (empty
// path, no device) is the state, not the previous «ready»; a failed load leaves the progress at 0,
// only success sets it to 1.
void loadStateFollowsEveryRequest() {
  wp::Player p(kSr);
  CHECK(p.load(writeIndexWav("state.wav", kSr / 10).string()) == wp::kOk);
  CHECK(p.loadState() == wp::kLoadReady);
  CHECK(p.loadAsync("") == wp::kErrInvalidArgument);
  CHECK(p.loadState() == wp::kErrInvalidArgument);
  p.setDeviceAvailable(false);
  CHECK(p.loadAsync(writeIndexWav("state2.wav", kSr / 10).string()) == wp::kErrDeviceUnavailable);
  CHECK(p.loadState() == wp::kErrDeviceUnavailable);
  // the device reports «started»: available again
  p.onDeviceEvent(wp::DeviceEvent::Started);
  CHECK(p.deviceAvailable());

  wp::Player q(kSr);
  CHECK(q.load(writeBytes("noaudio.wav", std::string(4096, 'x')).string()) ==
        wp::kErrUnsupportedFormat);
  CHECK(q.loadState() == wp::kErrUnsupportedFormat);
  CHECK(q.loadProgress() == 0.0);
}

// The shortest title is one frame; conversion keeps one frame (same rate), and samples that are not
// finite become silence, the rest is limited to ±8 (#10) also when converting.
void oneFrameAndBadSamplesWhenConverting() {
  wp::Player p(kSr);
  auto one = std::make_unique<wp::Source>();
  one->data = {0.25f, -0.25f};
  one->frames = 1;
  CHECK(p.setSource(std::move(one)) == wp::kOk);
  CHECK_NEAR(p.engine().duration(), 1.0 / kSr, 1e-15);

  const float in[2] = {0.5f, -0.5f};
  wp::Source single;
  CHECK(wp::convertPcm(in, 2, 1, kSr, kSr, single) == wp::kOk);
  CHECK(single.frames == 1 && single.data[0] == 0.5f && single.data[1] == -0.5f);

  std::vector<float> bad(2 * 20000, 0.25f);
  bad[2 * 19000] = std::nanf("");
  bad[2 * 19001 + 1] = INFINITY;
  bad[2 * 19002] = 100.0f;
  wp::Source clean;
  CHECK(wp::convertPcm(bad.data(), 2, 20000, kSr, kSr, clean) == wp::kOk);
  CHECK(clean.frames == 20000);
  bool finite = true;
  for (float v : clean.data)
    finite = finite && std::isfinite(v) && std::fabs(v) <= 8.0f;
  CHECK(finite);
  CHECK(clean.data[2 * 19000] == 0.0f && clean.data[2 * 19001 + 1] == 0.0f);
  CHECK(clean.data[2 * 19002] == 8.0f);
}

void errorMessagesAreEnglishAscii() { // #46/AK1
  const int codes[] = {WP_OK,
                       WP_ERR_INVALID_ARGUMENT,
                       WP_ERR_FILE_NOT_FOUND,
                       WP_ERR_UNSUPPORTED_FORMAT,
                       WP_ERR_DEVICE_UNAVAILABLE,
                       WP_ERR_OUT_OF_MEMORY,
                       WP_ERR_FILE_UNREADABLE,
                       WP_ERR_CANCELLED,
                       WP_ERR_BUSY,
                       WP_ERR_UNSUPPORTED_SAMPLE_RATE,
                       -100};
  const char *german[] = {"datei",       "fehler",      "nicht",    "kein",
                          "unbekannt",   "laden",       "speicher", "aufruf",
                          "audiog",      "abgebrochen", "bitte",    "erneut",
                          "ausgelastet", "gelesen",     "gefunden", "format unbekannt"};
  for (int c : codes) {
    const char *m =
        wp::errorMessage(c); // wp_error_message forwards here (player.cpp, wp_core_web.cpp)
    CHECK(m != nullptr && *m != '\0');
    std::string lower;
    bool ascii = true;
    for (const char *q = m; *q; ++q) {
      const auto u = static_cast<unsigned char>(*q);
      if (u < 0x20 || u > 0x7e)
        ascii = false;
      lower += static_cast<char>(std::tolower(u));
    }
    CHECK(ascii);
    for (const char *w : german)
      CHECK(lower.find(w) == std::string::npos);
  }
}

// #57/AK2: a render thread plays like the audio device while this thread controls play, pause,
// seek, tempo, loop, metronome and loads a new title. Under ThreadSanitizer (make sanitize-thread)
// every data race fails the run; in every build the output stays finite and the final state
// follows the last commands.
void controlFromSecondThreadWhileRendering() {
  const fs::path wav = writeIndexWav("race4s.wav", 4LL * kSr);
  wp::Player p(kSr);
  CHECK(p.load(wav.string()) == wp::kOk);
  std::atomic<bool> stop{false};
  std::atomic<bool> finite{true};
  std::atomic<long long> blocks{0};
  std::thread audio([&] {
    std::vector<float> out(256 * 2);
    while (!stop.load()) {
      p.render(out.data(), 256);
      for (float x : out)
        if (!std::isfinite(x))
          finite.store(false);
      blocks.fetch_add(1);
    }
  });
  auto waitBlocks = [&](long long n) {
    const long long target = blocks.load() + n;
    while (blocks.load() < target)
      std::this_thread::yield();
  };
  wp::Engine &e = p.engine();
  wp::Metronome &m = p.metronome();
  for (int i = 0; i < 200; ++i) {
    e.play();
    e.seek((i % 35) / 10.0);
    e.setRate(0.5 + (i % 16) / 10.0);
    if (i % 3 == 0)
      e.setLoop(1.0, 3.0);
    if (i % 7 == 0)
      e.setLoop(0, 0);
    if (i % 5 == 0)
      e.pause();
    if (i % 4 == 0) {
      m.start();
      m.setBpm(60 + i);
      m.setSubdivision(1 + i % 4);
    }
    if (i % 9 == 0)
      m.stop();
    (void)e.position();
    (void)e.loopPasses();
    if (i % 50 == 25) {
      CHECK(p.loadAsync(wav.string()) == wp::kOk); // loader thread runs alongside
      e.collectGarbage();
    }
    if (i % 20 == 0)
      waitBlocks(1);
  }
  CHECK(p.waitForLoad() == wp::kOk);
  e.collectGarbage();
  // Loop 1–3 s, tempo 1.5, playing: after 2 s of output the position is inside the loop.
  e.setLoop(1.0, 3.0);
  e.seek(1.5);
  e.setRate(1.5);
  e.play();
  m.stop();
  waitBlocks(2LL * kSr / 256);
  stop = true;
  audio.join();
  CHECK(finite.load());
  CHECK(e.playing());
  CHECK(e.rate() == 1.5);
  CHECK(e.position() >= 1.0 - 1e-6 && e.position() <= 3.0 + 1e-6);
  e.pause();
  float frame[2];
  p.render(frame, 1);
  CHECK(!e.playing());
}

} // namespace

int main() {
  const std::vector<std::pair<std::string, std::function<void()>>> tests = {
      {"loadsWavSampleExact", loadsWavSampleExact},
      {"loadsFlac", loadsFlac},
      {"loadsMp3", loadsMp3},
      {"endOfFileStopsWithLoadedFile", endOfFileStopsWithLoadedFile},
      {"loopBoundsWithLoadedFile", loopBoundsWithLoadedFile},
      {"loadErrorsHaveCodeAndText", loadErrorsHaveCodeAndText},
      {"truncatedAndWrongAudioFiles", truncatedAndWrongAudioFiles},
      {"errorMessagesAreEnglishAscii", errorMessagesAreEnglishAscii},
      {"loadStateFollowsEveryRequest", loadStateFollowsEveryRequest},
      {"oneFrameAndBadSamplesWhenConverting", oneFrameAndBadSamplesWhenConverting},
      {"errorDuringPlaybackKeepsPlaying", errorDuringPlaybackKeepsPlaying},
      {"loadRunsInBackground", loadRunsInBackground},
      {"newerLoadReplacesRunningLoad", newerLoadReplacesRunningLoad},
      {"fileDurationWithoutLoading", fileDurationWithoutLoading},
      {"waveformOfLoadedFile", waveformOfLoadedFile},
      {"devicePolicy", devicePolicy},
      {"deviceChangePausesAndKeepsPosition", deviceChangePausesAndKeepsPosition},
      {"decodeMemoryMatchesFile", decodeMemoryMatchesFile},
      {"longTitleReservesHeaderLength", longTitleReservesHeaderLength},
      {"longTitleWithWrongHeaderLength", longTitleWithWrongHeaderLength},
      {"longTitleFromFileReservesOnce", longTitleFromFileReservesOnce},
      {"shortTitleClaimingLongerReservesOnlyFiveMinutes",
       shortTitleClaimingLongerReservesOnlyFiveMinutes},
      {"lengthImplausibleForTheFileSizeIsNotReserved",
       lengthImplausibleForTheFileSizeIsNotReserved},
      {"progressIsCompleteAfterLoad", progressIsCompleteAfterLoad},
      {"loadThreadWithoutMemory", loadThreadWithoutMemory},
      {"unsupportedRateRendersSilence", unsupportedRateRendersSilence},
      {"metronomeRunsAtThePlayerRate", metronomeRunsAtThePlayerRate},
      {"unreadableFileIsReported", unreadableFileIsReported},
      {"emptyAudioIsUnsupported", emptyAudioIsUnsupported},
      {"convertPcmToPlayerFormat", convertPcmToPlayerFormat},
      {"setSourceWithoutPeaks", setSourceWithoutPeaks},
      {"controlFromSecondThreadWhileRendering", controlFromSecondThreadWhileRendering},
  };
  for (auto &[name, fn] : tests) {
    const int before = failures;
    fn();
    std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name.c_str());
  }
  fs::remove_all(tempDir());
  std::printf("%d checks, %d failures\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
