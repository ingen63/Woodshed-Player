// Audio reference cases (#9) in offline rendering, without an audio device.
//
// The cases call the C API of wp_core.h through the offline core web/wp_core_web.cpp: the same
// functions as the browser core (wp_play, wp_seek, wp_metro_*, ...), rendered block by block with
// wp_web_render; file loading (wp_load*) where a file system and threads exist. The native core
// (src/player.cpp) is the same thin wrapper over wp::Player plus the audio device; capi_tests.cpp
// checks that part.
//
// The same program runs natively (ctest in core/build, build-debug, build-asan, build-tsan) and as
// WebAssembly under Node.js (core/build-wasm). Natively it writes every recorded output to a dump
// (--dump); the WASM run compares its own output against that dump with a tolerance of 1e-6
// (--compare, #9/AK7), stretched tempo cases with 5e-2 (kStretchTolerance, #94).
// reference_api_coverage.cmake checks that every WP_API function of wp_core.h is called here.
//
// Test audio is generated here (#9/AK1): a 440 Hz sine, a ramp whose sample values encode their
// frame index, and silence. No audio file is read. Every case derives its expected value in the
// comment. Case names carry the criterion: #9/AKn, metronome cases also #3/AKn.
//
// Golden file: tests/golden/metronome_positions.txt (#9/AK5). Rewrite it with GOLDEN_UPDATE=1
// (native run only) after an intended change, and review the diff.
#include <algorithm>
#include <climits>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <map>
#include <set>
#include <sstream>
#include <string>
#include <utility>
#include <vector>

#include "flac_writer.hpp"
#include "wp_core.h"
#include "wp_core_web.h"

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

constexpr int kRate = 44100;
constexpr double kPi = 3.14159265358979323846;
// The ramp stores frame n as (n + 1) * 2^-24 (left) and its negative (right). Floats hold every
// integer up to 2^24 exactly, so any frame below 16.7 M frames (6 min) maps back to its index.
constexpr double kRampScale = 16777216.0; // 2^24

// ---- Contract native <-> WASM (#9/AK7) ----

enum class Mode { Plain, Dump, Compare };
Mode mode = Mode::Plain;
std::string contractPath;
std::vector<std::pair<std::string, std::vector<float>>> dumped;
std::map<std::string, std::vector<float>> reference;
std::set<std::string> compared;
constexpr double kContractTolerance = 1e-6;
// Stretched tempo cases (rate != 1) on Linux (#94/AK2): the stretch turns 1-ulp differences of
// sincosf into sample differences, and glibc rounds sincosf differently from Apple's libm and musl
// (WASM). Measured in workflow run 44809822849: up to 2.12e-2 at rate 0.1, 1.83e-5 at 0.5, 2.17e-3
// at 2.0 (amplitude 0.5). macOS and WASM stay bit-identical. A wrong stretch (other random numbers,
// other phase) differs by about 1, so 5e-2 still catches it.
constexpr double kStretchTolerance = 5e-2;

// Keeps an output for the contract: written natively, compared under WASM within tolerance.
void record(const std::string &name, const std::vector<float> &samples,
            double tolerance = kContractTolerance) {
  if (mode == Mode::Dump) {
    dumped.emplace_back(name, samples);
  } else if (mode == Mode::Compare) {
    const auto it = reference.find(name);
    CHECK(it != reference.end());
    if (it == reference.end()) {
      std::printf("  contract: %s missing in the native dump\n", name.c_str());
      return;
    }
    compared.insert(name);
    // Same length native and WASM, e.g. 22 080 frames for tempo_2.0 (#94/AK3).
    CHECK(it->second.size() == samples.size());
    double maxDiff = 0;
    const size_t n = std::min(it->second.size(), samples.size());
    for (size_t i = 0; i < n; ++i)
      maxDiff = std::max(maxDiff, std::fabs(static_cast<double>(it->second[i]) - samples[i]));
    std::printf("  contract %-28s %8zu samples, max diff %.2e\n", name.c_str(), n, maxDiff);
    CHECK(maxDiff <= tolerance);
  }
}

// Dump format: "WPREF1" then per record: uint32 name length, name, uint64 count, float32 samples
// (little endian, as on every supported platform).
bool writeDump(const std::string &path) {
  std::ofstream f(path, std::ios::binary);
  if (!f)
    return false;
  f.write("WPREF1", 6);
  for (auto &[name, s] : dumped) {
    const auto len = static_cast<uint32_t>(name.size());
    const auto count = static_cast<uint64_t>(s.size());
    f.write(reinterpret_cast<const char *>(&len), sizeof len);
    f.write(name.data(), len);
    f.write(reinterpret_cast<const char *>(&count), sizeof count);
    f.write(reinterpret_cast<const char *>(s.data()), static_cast<std::streamsize>(count * 4));
  }
  return static_cast<bool>(f);
}

bool readDump(const std::string &path) {
  std::ifstream f(path, std::ios::binary);
  char magic[6] = {};
  if (!f.read(magic, 6) || std::memcmp(magic, "WPREF1", 6) != 0)
    return false;
  uint32_t len = 0;
  while (f.read(reinterpret_cast<char *>(&len), sizeof len)) {
    std::string name(len, '\0');
    uint64_t count = 0;
    f.read(name.data(), len);
    f.read(reinterpret_cast<char *>(&count), sizeof count);
    std::vector<float> s(count);
    f.read(reinterpret_cast<char *>(s.data()), static_cast<std::streamsize>(count * 4));
    if (!f)
      return false;
    reference[name] = std::move(s);
  }
  return true;
}

// ---- Generated test audio (#9/AK1) ----

std::vector<float> sine(double freq, double seconds, float amp) {
  const auto frames = static_cast<long long>(std::llround(seconds * kRate));
  std::vector<float> s(static_cast<size_t>(frames) * 2);
  for (long long i = 0; i < frames; ++i) {
    const auto v = static_cast<float>(amp * std::sin(2 * kPi * freq * i / kRate));
    s[i * 2] = s[i * 2 + 1] = v;
  }
  return s;
}

float rampValue(long long frame) { return static_cast<float>((frame + 1) / kRampScale); }

std::vector<float> ramp(long long frames) {
  std::vector<float> s(static_cast<size_t>(frames) * 2);
  for (long long i = 0; i < frames; ++i) {
    s[i * 2] = rampValue(i);
    s[i * 2 + 1] = -rampValue(i);
  }
  return s;
}

// Frame index of a ramp sample, -1 for silence.
long long rampIndex(float v) { return std::llround(v * kRampScale) - 1; }

// ---- Offline player ----

struct Offline {
  wp_player *p = wp_web_create(kRate);
  Offline() = default;
  Offline(const Offline &) = delete;
  Offline &operator=(const Offline &) = delete;
  ~Offline() { wp_destroy(p); }
};

// Hands stereo PCM at kRate to the player as the browser worklet does (#42), in pieces of 4096
// frames: an exact copy, no conversion.
bool loadStereo(wp_player *p, const std::vector<float> &s) {
  const int frames = static_cast<int>(s.size() / 2);
  if (wp_web_pcm_begin(p, frames) != WP_OK)
    return false;
  for (int done = 0; done < frames;) {
    const int n = std::min(4096, frames - done);
    if (wp_web_pcm_append(p, s.data() + static_cast<size_t>(done) * 2, n) != WP_OK)
      return false;
    done += n;
  }
  return wp_web_pcm_commit(p) == WP_OK;
}

// Renders `frames` frames in blocks of `block` frames and appends them (stereo) to `out`.
void render(wp_player *p, long long frames, std::vector<float> &out, int block = 512) {
  for (long long done = 0; done < frames;) {
    const int n = static_cast<int>(std::min<long long>(block, frames - done));
    const float *b = wp_web_render(p, n);
    out.insert(out.end(), b, b + static_cast<size_t>(n) * 2);
    done += n;
  }
}

std::vector<float> render(wp_player *p, long long frames, int block = 512) {
  std::vector<float> out;
  render(p, frames, out, block);
  return out;
}

// Checks that the left channel of `out` from frame `from` on is the ramp sequence `expected(k)`;
// reports the first mismatch only. The right channel must be its negative.
template <typename F>
bool rampMatches(const std::vector<float> &out, size_t from, F expected, const char *what) {
  for (size_t k = from; k < out.size() / 2; ++k) {
    const long long want = expected(k);
    const long long got = rampIndex(out[k * 2]);
    if (got != want || out[k * 2 + 1] != -out[k * 2]) {
      std::printf("  %s: output frame %zu is ramp frame %lld, expected %lld\n", what, k, got, want);
      return false;
    }
  }
  return true;
}

// Fundamental frequency of the left channel in [from, to) frames from the upward zero crossings,
// interpolated linearly between samples.
double frequency(const std::vector<float> &out, size_t from, size_t to) {
  double first = -1, last = -1;
  int crossings = 0;
  for (size_t i = from; i + 1 < to; ++i) {
    const double a = out[i * 2], b = out[(i + 1) * 2];
    if (a <= 0 && b > 0) {
      const double t = static_cast<double>(i) + (-a / (b - a));
      if (first < 0)
        first = t;
      last = t;
      ++crossings;
    }
  }
  return crossings < 2 ? 0 : (crossings - 1) * kRate / (last - first);
}

// ---- Click detection for the metronome (#3, #9/AK5) ----

// A click (metronome.cpp) is a sine at the frequency of its kind under a ~50 ms envelope (2205
// frames at 44.1 kHz). Its first sample is sin(0) = 0, so the click scheduled at frame f is the
// first non-zero sample after silence minus one. Between clicks the output is exactly 0. The kind
// follows from the frequency (Accent 1600 Hz, secondary accent 1250 Hz, beat 1000 Hz, subdivision
// 700 Hz), counted over the first 1500 samples of the click.
struct Click {
  long long frame;
  char kind; // A accent, S secondary accent (6/8), B beat, U subdivision
  float peak;
};

class ClickDetector {
public:
  void feed(const float *stereo, int frames) {
    for (int i = 0; i < frames; ++i, ++frame_) {
      const float x = stereo[i * 2];
      if (window_ > 0) {
        peak_ = std::max(peak_, std::fabs(x));
        if ((prev_ <= 0 && x > 0) || (prev_ >= 0 && x < 0))
          ++crossings_;
        if (x != 0)
          prev_ = x;
        if (--window_ == 0)
          finish();
      } else if (x != 0 && zeros_ >= kMinSilence) {
        start_ = frame_ - 1;
        window_ = kWindow - 1;
        crossings_ = 0;
        peak_ = std::fabs(x);
        prev_ = x;
      }
      zeros_ = x == 0 ? zeros_ + 1 : 0;
    }
  }
  std::vector<Click> clicks;

private:
  static constexpr int kWindow = 1500;
  static constexpr int kMinSilence = 64;
  void finish() {
    const double freq = crossings_ / 2.0 * kRate / kWindow;
    const double kinds[4] = {1600, 1250, 1000, 700};
    const char names[4] = {'A', 'S', 'B', 'U'};
    int best = 0;
    for (int k = 1; k < 4; ++k)
      if (std::fabs(freq - kinds[k]) < std::fabs(freq - kinds[best]))
        best = k;
    clicks.push_back({start_, names[best], peak_});
  }
  long long frame_ = 0, start_ = 0, zeros_ = kMinSilence;
  int window_ = 0, crossings_ = 0;
  float peak_ = 0, prev_ = 0;
};

// Renders with click detection; frames are counted from the first rendered frame.
void renderClicks(wp_player *p, long long frames, ClickDetector &d,
                  std::vector<float> *keep = nullptr) {
  for (long long done = 0; done < frames;) {
    const int n = static_cast<int>(std::min<long long>(512, frames - done));
    const float *b = wp_web_render(p, n);
    d.feed(b, n);
    if (keep)
      keep->insert(keep->end(), b, b + static_cast<size_t>(n) * 2);
    done += n;
  }
}

// ---- #9/AK1 generated test audio ----

void generatedTestAudio() {
  // #9/AK1: sine, ramp and silence come from the test itself. Ramp: consecutive frames map to
  // consecutive indices, left and right mirrored. Sine: sin(2π · 440 · 25 / 44100) · 0.5 at frame
  // 25 (a quarter period is 44100 / 440 / 4 = 25.06 frames, so close to the peak 0.5).
  const auto r = ramp(1000);
  CHECK(rampIndex(r[0]) == 0 && rampIndex(r[999 * 2]) == 999 && r[1] == -r[0]);
  const auto s = sine(440, 1.0, 0.5f);
  CHECK(s.size() == static_cast<size_t>(kRate) * 2);
  CHECK_NEAR(s[25 * 2], 0.5 * std::sin(2 * kPi * 440 * 25 / kRate), 1e-7);
  CHECK(s[0] == 0.0f);

  // Silence through the stretch (#9/AK1, #9/AK4): 1 s of zeros at rate 0.5 gives zeros, no noise
  // and no click from the stretcher.
  Offline o;
  CHECK(loadStereo(o.p, std::vector<float>(static_cast<size_t>(kRate) * 2, 0.0f)));
  wp_set_rate(o.p, 0.5);
  wp_play(o.p);
  const auto out = render(o.p, kRate);
  float peak = 0;
  for (float v : out)
    peak = std::max(peak, std::fabs(v));
  CHECK(peak == 0.0f);
  record("silence_rate_0.5", out);
}

// ---- #9/AK2 loop seam ----

void loopSeamOver100Passes() {
  // #9/AK2: ramp of 3 s (132 300 frames), loop A = 0.5 s, B = 1.6 s. In frames:
  // a = round(0.5 · 44100) = 22 050, b = round(1.6 · 44100) = 70 560, length L = 48 510.
  // After a seek to A, output frame k is ramp frame a + (k mod L): the last frame before B
  // (70 559) is followed directly by A (22 050), no gap, no doubled frame. 100 passes are
  // 100 · L = 4 851 000 frames; the loop counter rises by exactly 100. Blocks of varying size put
  // the seam at every position within a block.
  constexpr long long a = 22050, b = 70560, L = b - a;
  Offline o;
  CHECK(loadStereo(o.p, ramp(3 * kRate)));
  wp_set_loop(o.p, 0.5, 1.6);
  wp_seek(o.p, 0.5);
  wp_play(o.p);
  const long long passesBefore = wp_loop_passes(o.p);
  const int blocks[] = {1, 127, 512, 1000, 4096, 333, 2048, 77};
  std::vector<float> out;
  out.reserve(static_cast<size_t>(100 * L + 1) * 2);
  for (long long done = 0, i = 0; done < 100 * L; ++i) {
    const int n = static_cast<int>(std::min<long long>(blocks[i % 8], 100 * L - done));
    render(o.p, n, out, n);
    done += n;
  }
  CHECK(wp_loop_passes(o.p) - passesBefore == 100);
  render(o.p, 1, out, 1); // the frame after the 100th pass is A again
  CHECK(rampMatches(
      out, 0, [&](size_t k) { return a + static_cast<long long>(k) % L; }, "loop from A"));
  CHECK(out.size() == static_cast<size_t>(100 * L + 1) * 2);
  record("loop_from_a", std::vector<float>(out.begin(), out.begin() + 2 * L * 2));

  // Playing from 0 into the loop: frames 0 … b − 1, then a … b − 1 again and again. In b + 3 · L
  // frames the playback reaches B four times (after the frames b − 1, b + L − 1, b + 2L − 1 and
  // b + 3L − 1 of the output), so the counter shows 4.
  Offline o2;
  CHECK(loadStereo(o2.p, ramp(3 * kRate)));
  wp_set_loop(o2.p, 0.5, 1.6);
  wp_play(o2.p);
  const auto out2 = render(o2.p, b + 3 * L, 1000);
  CHECK(rampMatches(
      out2, 0,
      [&](size_t k) {
        const auto f = static_cast<long long>(k);
        return f < b ? f : a + (f - b) % L;
      },
      "loop from 0"));
  CHECK(wp_loop_passes(o2.p) == 4);
}

// ---- #9/AK3 seek and pause ----

void seekStartsAtRoundedFrame() {
  // #9/AK3: after a seek to t the output starts at frame round(t · 44100). t is chosen just below
  // and above half a frame: (54 444 + 0.4) / 44100 → 54 444, (54 444 + 0.6) / 44100 → 54 445; and
  // 0 → 0, 2.5 s → 110 250. Each seek is followed by 300 consecutive ramp frames.
  struct Case {
    double t;
    long long frame;
  };
  const Case cases[] = {
      {(54444 + 0.4) / kRate, 54444}, {(54444 + 0.6) / kRate, 54445}, {0.0, 0}, {2.5, 110250}};
  Offline o;
  CHECK(loadStereo(o.p, ramp(3 * kRate)));
  std::vector<float> all;
  for (const auto &c : cases) {
    // Paused: seek, then play.
    wp_pause(o.p);
    wp_seek(o.p, c.t);
    render(o.p, 64);
    CHECK_NEAR(wp_position(o.p), static_cast<double>(c.frame) / kRate, 1e-12);
    wp_play(o.p);
    const auto out = render(o.p, 300, 100);
    CHECK(rampMatches(
        out, 0, [&](size_t k) { return c.frame + static_cast<long long>(k); },
        "seek while paused"));
    all.insert(all.end(), out.begin(), out.end());
    // While playing: the seek applies with the next block.
    wp_seek(o.p, c.t);
    const auto out2 = render(o.p, 300, 100);
    CHECK(rampMatches(
        out2, 0, [&](size_t k) { return c.frame + static_cast<long long>(k); },
        "seek while playing"));
    all.insert(all.end(), out2.begin(), out2.end());
  }
  record("seek", all);
}

void pauseAndResumeLoseNoFrame() {
  // #9/AK3: play 10 blocks of 300 frames (0 … 2999), pause for 5 blocks (exactly silent, position
  // stays at 3000 / 44100 s), play 10 more blocks: frames 3000 … 5999 follow without a lost or
  // repeated frame. Volume 0.5 halves every sample exactly (a power of two), wp_set_volume.
  Offline o;
  CHECK(loadStereo(o.p, ramp(3 * kRate)));
  wp_set_volume(o.p, 0.5f);
  wp_play(o.p);
  auto out = render(o.p, 3000, 300);
  CHECK(wp_is_playing(o.p) == 1);
  wp_pause(o.p);
  const auto silent = render(o.p, 1500, 300);
  CHECK(wp_is_playing(o.p) == 0);
  CHECK(std::all_of(silent.begin(), silent.end(), [](float v) { return v == 0.0f; }));
  CHECK_NEAR(wp_position(o.p), 3000.0 / kRate, 1e-12);
  wp_play(o.p);
  render(o.p, 3000, out, 300);
  for (auto &v : out)
    v *= 2.0f; // undo the volume, exact
  CHECK(rampMatches(out, 0, [](size_t k) { return static_cast<long long>(k); }, "pause/resume"));
  CHECK(out.size() == 6000u * 2);
  record("pause_resume", out);
}

// ---- #9/AK4 tempo ----

void tempoLengthAndPitch() {
  // #9/AK4: 1 s of a 440 Hz sine (44 100 frames). At rate r playback ends after 44 100 / r output
  // frames: 441 000 at 0.1, 88 200 at 0.5, 44 100 at 1.0, 22 050 at 2.0, each ± 1 %. Rendering in
  // blocks of 64 frames until playback stops measures the length to within 64 frames (0.3 % of the
  // shortest). The pitch stays: the fundamental in the middle half of the output is 440 Hz ± 1 %
  // (± 4.4 Hz). At 1.0 the output is the input itself, so exactly 440 Hz.
  const auto input = sine(440, 1.0, 0.5f);
  for (double r : {0.1, 0.5, 1.0, 2.0}) {
    Offline o;
    // Stereo PCM at the player's rate: wp_web_load_pcm converts nothing and computes the waveform.
    CHECK(wp_web_load_pcm(o.p, input.data(), 2, kRate, kRate) == WP_OK);
    CHECK_NEAR(wp_duration(o.p), 1.0, 1e-12);
    wp_set_rate(o.p, r);
    wp_play(o.p);
    const double expected = kRate / r;
    std::vector<float> out;
    do {
      render(o.p, 64, out, 64);
    } while (wp_is_playing(o.p) && out.size() / 2 < static_cast<size_t>(2 * expected));
    const size_t frames = out.size() / 2;
    const auto len = static_cast<double>(frames);
    const double f = frequency(out, out.size() / 8, out.size() * 3 / 8);
    std::printf("  rate %.1f: %.0f frames (expected %.0f), %.2f Hz\n", r, len, expected, f);
    CHECK(std::fabs(len - expected) <= 0.01 * expected);
    CHECK(std::fabs(f - 440.0) <= 4.4);
    char name[32];
    std::snprintf(name, sizeof name, "tempo_%.1f", r);
    // At 1.0 the stretch is bypassed: exact contract. Otherwise libm may differ (#94/AK2).
    record(name, out, r == 1.0 ? kContractTolerance : kStretchTolerance);
  }
}

// ---- #9/AK5 metronome ----

void metronomeWithoutDriftOverFiveMinutes() {
  // #3/AK9, #9/AK5: at 120 BPM and 44.1 kHz a beat lasts 60 / 120 · 44 100 = 22 050 frames. In 5
  // minutes (300 s) there are 300 · 2 = 600 clicks at exactly k · 22 050 frames after the start,
  // the last at 599 · 22 050 = 13 207 950, without drift. 4/4: the accent on every 4th click
  // (#3/AK7). The metronome runs without a title (#3/AK20). Volume 1 is set and settles during
  // one silent second before the start, so the start is frame 44 100 of the output.
  Offline o;
  wp_metro_set_volume(o.p, 1.0f);
  wp_metro_set_bpm(o.p, 120);
  ClickDetector d;
  renderClicks(o.p, kRate, d);
  wp_metro_start(o.p);
  CHECK(wp_metro_is_running(o.p) == 1);
  renderClicks(o.p, 300LL * kRate, d);
  CHECK(d.clicks.size() == 600u);
  bool exact = true;
  for (size_t k = 0; k < d.clicks.size(); ++k) {
    const auto &c = d.clicks[k];
    const long long want = kRate + static_cast<long long>(k) * 22050;
    const char kind = k % 4 == 0 ? 'A' : 'B';
    if (c.frame != want || c.kind != kind) {
      std::printf("  click %zu at %lld (%c), expected %lld (%c)\n", k, c.frame, c.kind, want, kind);
      exact = false;
      break;
    }
  }
  CHECK(exact);
  if (!d.clicks.empty())
    CHECK(d.clicks.back().frame - kRate == 13207950);
}

void metronomeAccentsAndSubdivisions() {
  // #3/AK7, #9/AK5: 6/8 at 120 BPM, two bars (12 beats at 22 050 frames): accent on beat 1,
  // secondary accent on beat 4, beats elsewhere: A B B S B B A B B S B B.
  {
    Offline o;
    wp_metro_set_volume(o.p, 1.0f);
    wp_metro_set_meter(o.p, 6);
    ClickDetector d;
    renderClicks(o.p, kRate, d);
    wp_metro_start(o.p);
    std::vector<float> keep;
    renderClicks(o.p, 12 * 22050, d, &keep);
    const std::string want = "ABBSBBABBSBB";
    std::string kinds;
    bool positions = d.clicks.size() == 12;
    for (size_t k = 0; k < d.clicks.size(); ++k) {
      kinds += d.clicks[k].kind;
      positions = positions && d.clicks[k].frame == kRate + static_cast<long long>(k) * 22050;
    }
    CHECK(kinds == want);
    CHECK(positions);
    record("metronome_6_8", keep);
  }
  // #3/AK8, #9/AK5: subdivisions at 120 BPM, 4/4. With s clicks per beat click k lies at
  // round(k · 22 050 / s) frames after the start (the metronome sums the interval as a double:
  // s = 2 → 11 025, s = 3 → 7 350, s = 4 → 5 512.5, rounded half away from zero, so 5 513, 11 025,
  // 16 538 …). Every s-th click is a beat (the first of a bar the accent), the others are
  // subdivision clicks and quieter than the beat (levels 0.4 < 0.7 < 1.0).
  for (int s : {2, 3, 4}) {
    Offline o;
    wp_metro_set_volume(o.p, 1.0f);
    wp_metro_set_subdivision(o.p, s);
    ClickDetector d;
    renderClicks(o.p, kRate, d);
    wp_metro_start(o.p);
    renderClicks(o.p, 8 * 22050, d); // 2 bars
    CHECK(d.clicks.size() == static_cast<size_t>(8 * s));
    bool ok = true;
    float beatPeak = 0, subPeak = 1, accentPeak = 0;
    for (size_t k = 0; k < d.clicks.size(); ++k) {
      const auto &c = d.clicks[k];
      const long long want = kRate + std::llround(static_cast<double>(k) * 22050.0 / s);
      const char kind = k % (4 * s) == 0 ? 'A' : (k % s == 0 ? 'B' : 'U');
      ok = ok && c.frame == want && c.kind == kind;
      if (kind == 'B')
        beatPeak = std::max(beatPeak, c.peak);
      if (kind == 'U')
        subPeak = std::min(subPeak, c.peak);
      if (kind == 'A')
        accentPeak = std::max(accentPeak, c.peak);
    }
    if (!ok)
      std::printf("  subdivision %d: positions or kinds differ\n", s);
    CHECK(ok);
    CHECK(subPeak < beatPeak && beatPeak < accentPeak);
  }
}

void metronomeGoldenSequence() {
  // #9/AK5, #3/AK10, #3/AK11, #3/AK15, #3/AK18: a fixed sequence of settings; the click positions
  // (frames after the start) and kinds are kept in tests/golden/metronome_positions.txt. The
  // first lines follow from the rules: 120 BPM 4/4, clicks at 0, 22 050, 44 100, 66 150 (A B B B)
  // and 88 200 (A). Then 6/8 with triplets from 4 s (176 400 frames) on: the change applies at the
  // next click (#3/AK10), triplet clicks every 7 350 frames. Then 3/4, eighths, 90 BPM (14 700
  // frames per click), then the ramp by +5 every bar, switched on while running (#3/AK15: the
  // tempo changes only at bar lines, from the current 90 BPM on), then the timed ramp 60 → 62 over
  // 4 s (#23), then stop (#3/AK11).
  Offline o;
  wp_metro_set_volume(o.p, 1.0f);
  wp_metro_set_bpm(o.p, 120);
  ClickDetector d;
  renderClicks(o.p, kRate, d);
  wp_metro_start(o.p);
  std::vector<float> keep;
  renderClicks(o.p, 4LL * kRate, d, &keep);
  wp_metro_set_meter(o.p, 6);
  wp_metro_set_subdivision(o.p, 3);
  renderClicks(o.p, 6LL * kRate, d, &keep);
  wp_metro_set_meter(o.p, 3);
  wp_metro_set_subdivision(o.p, 2);
  wp_metro_set_bpm(o.p, 90);
  renderClicks(o.p, 6LL * kRate, d);
  // Ramp by bars while running: the tempo stays until the next bar line.
  wp_metro_set_ramp(o.p, 1, 145, 150, 5, 1);
  CHECK(wp_metro_bpm(o.p) == 90);
  renderClicks(o.p, 8LL * kRate, d);
  CHECK(wp_metro_bpm(o.p) > 90); // stepped by +5 at bar lines
  wp_metro_set_ramp_timed(o.p, 1, 60, 62, 4);
  renderClicks(o.p, 10LL * kRate, d);
  wp_metro_set_ramp(o.p, 0, 145, 150, 5, 1); // off: the tempo stays (#3/AK18)
  const int bpmAfterRamp = wp_metro_bpm(o.p);
  CHECK(bpmAfterRamp >= 60 && bpmAfterRamp <= 62);
  renderClicks(o.p, 2LL * kRate, d);
  CHECK(wp_metro_bpm(o.p) == bpmAfterRamp);
  wp_metro_stop(o.p);
  CHECK(wp_metro_is_running(o.p) == 0);
  const size_t clicksAtStop = d.clicks.size();
  renderClicks(o.p, kRate, d);
  CHECK(d.clicks.size() == clicksAtStop); // no click after the stop
  record("metronome_sequence_10s", keep);

  // The derived start of the sequence: 4/4 for 4 s (A B B B A B B B), then from 176 400 6/8 with
  // triplets. 176 400 is the downbeat of bar 3 and stays the accent; triplet clicks follow every
  // 7 350 frames (183 750, 191 100), beat 2 at 198 450, the secondary accent on beat 4 at
  // 176 400 + 3 · 22 050 = 242 550, the next accent at 176 400 + 6 · 22 050 = 308 700. (Before
  // the fix of #9 the subdivision change skipped a beat here, see docs/TESTS.md.)
  const std::pair<long long, char> derived[] = {
      {0, 'A'},      {22050, 'B'},  {44100, 'B'},  {66150, 'B'},  {88200, 'A'},
      {110250, 'B'}, {132300, 'B'}, {154350, 'B'}, {176400, 'A'}, {183750, 'U'},
      {191100, 'U'}, {198450, 'B'}, {242550, 'S'}, {308700, 'A'}};
  for (const auto &entry : derived) {
    const long long frame = entry.first;
    const char kind = entry.second;
    const auto it = std::find_if(d.clicks.begin(), d.clicks.end(),
                                 [&](const Click &c) { return c.frame - kRate == frame; });
    const bool ok = it != d.clicks.end() && it->kind == kind;
    if (!ok)
      std::printf("  no click %c at %lld\n", kind, frame);
    CHECK(ok);
  }

  std::ostringstream text;
  text << "# Metronome click positions of the fixed sequence in reference_tests.cpp\n"
          "# (metronomeGoldenSequence, #9/AK5), 44.1 kHz. Frame after the start, kind:\n"
          "# A accent, S secondary accent (6/8), B beat, U subdivision.\n"
          "# Rewrite with GOLDEN_UPDATE=1 (native run) after an intended change.\n";
  for (const auto &c : d.clicks)
    text << c.frame - kRate << ' ' << c.kind << '\n';
  const std::string path = std::string(WP_GOLDEN_DIR) + "/metronome_positions.txt";
  const char *update = std::getenv("GOLDEN_UPDATE");
  if (update && std::string(update) == "1") {
    std::ofstream f(path);
    f << text.str();
    CHECK(static_cast<bool>(f));
    std::printf("  golden file written: %s (%zu clicks)\n", path.c_str(), d.clicks.size());
    return;
  }
  std::ifstream f(path);
  std::stringstream golden;
  golden << f.rdbuf();
  CHECK(static_cast<bool>(f));
  const bool same = golden.str() == text.str();
  if (!same) {
    auto lines = [](const std::string &s) {
      std::vector<std::string> v;
      std::istringstream in(s);
      for (std::string l; std::getline(in, l);)
        v.push_back(l);
      return v;
    };
    const auto want = lines(golden.str()), got = lines(text.str());
    for (size_t i = 0; i < std::max(want.size(), got.size()); ++i) {
      const std::string w = i < want.size() ? want[i] : "<end>",
                        g = i < got.size() ? got[i] : "<end>";
      if (w != g) {
        std::printf("  golden line %zu: expected \"%s\", got \"%s\"\n", i + 1, w.c_str(),
                    g.c_str());
        break;
      }
    }
  }
  CHECK(same);
}

void metronomeMeterAndSubdivisionChangeMidBeat() {
  // #70/AK2, #70/AK3, #3/AK10: meter and subdivision change together in the middle of a beat. If
  // the running beat lies outside the new meter, it plays to its end (its remaining clicks in the
  // new subdivision) and the next beat is the accent of a new bar. A beat inside the new meter
  // counts on. 120 BPM, a beat is 22 050 frames; changes at frames after the start:
  //  - 4/4 eighths (11 025): A U B U B U B (beat 4 at 66 150). At 68 150 to 3/4 triplets (7 350):
  //    beat 4 lies outside 3/4, its triplets at 73 500 and 80 850, then the accent at 88 200, the
  //    bar 88 200 / 110 250 / 132 300 with triplets.
  //  - At 135 300 (beat 3 of 3/4) to 6/8 quarters: beat 3 lies inside 6/8, the next beat is beat 4
  //    at 154 350, the secondary accent; the accent at 220 500, the secondary accent at 286 650.
  //  - At 335 750 (beat 6 of 6/8, its click at 330 750) to 4/4 eighths: beat 6 lies outside 4/4,
  //    its eighth at 341 775, then the accent at 352 800 and the next at 352 800 + 88 200 = 441
  //    000.
  // (Before the fix the remaining clicks of the beat counted as beat 1 and the accent was missing:
  // 88 200 came as a plain beat.)
  Offline o;
  wp_metro_set_volume(o.p, 1.0f);
  wp_metro_set_bpm(o.p, 120);
  wp_metro_set_subdivision(o.p, 2);
  ClickDetector d;
  renderClicks(o.p, kRate, d);
  wp_metro_start(o.p);
  std::vector<float> keep;
  renderClicks(o.p, 68150, d, &keep);
  wp_metro_set_meter(o.p, 3);
  wp_metro_set_subdivision(o.p, 3);
  renderClicks(o.p, 135300 - 68150, d, &keep);
  wp_metro_set_meter(o.p, 6);
  wp_metro_set_subdivision(o.p, 1);
  renderClicks(o.p, 335750 - 135300, d, &keep);
  wp_metro_set_meter(o.p, 4);
  wp_metro_set_subdivision(o.p, 2);
  renderClicks(o.p, 443000 - 335750, d, &keep);
  record("metronome_meter_subdivision_change", keep);

  const std::pair<long long, char> want[] = {
      {0, 'A'},      {11025, 'U'},  {22050, 'B'},  {33075, 'U'},  {44100, 'B'},  {55125, 'U'},
      {66150, 'B'},  {73500, 'U'},  {80850, 'U'},  {88200, 'A'},  {95550, 'U'},  {102900, 'U'},
      {110250, 'B'}, {117600, 'U'}, {124950, 'U'}, {132300, 'B'}, {154350, 'S'}, {176400, 'B'},
      {198450, 'B'}, {220500, 'A'}, {242550, 'B'}, {264600, 'B'}, {286650, 'S'}, {308700, 'B'},
      {330750, 'B'}, {341775, 'U'}, {352800, 'A'}, {363825, 'U'}, {374850, 'B'}, {385875, 'U'},
      {396900, 'B'}, {407925, 'U'}, {418950, 'B'}, {429975, 'U'}, {441000, 'A'}};
  const size_t n = sizeof want / sizeof want[0];
  CHECK(d.clicks.size() == n);
  for (size_t k = 0; k < std::min(n, d.clicks.size()); ++k) {
    const auto &c = d.clicks[k];
    if (c.frame - kRate != want[k].first || c.kind != want[k].second) {
      std::printf("  click %zu at %lld (%c), expected %lld (%c)\n", k, c.frame - kRate, c.kind,
                  want[k].first, want[k].second);
      CHECK(false);
      break;
    }
  }
}

void metronomeWithTitle() {
  // #3/AK20, #9/AK5: title (silence) and metronome play together; the title adds exactly 0, so the
  // clicks lie at the same positions as without a title (k · 22 050 after the start).
  Offline o;
  CHECK(loadStereo(o.p, std::vector<float>(static_cast<size_t>(3 * kRate) * 2, 0.0f)));
  wp_metro_set_volume(o.p, 1.0f);
  ClickDetector d;
  renderClicks(o.p, kRate, d);
  wp_play(o.p);
  wp_metro_start(o.p);
  renderClicks(o.p, kRate, d);
  CHECK(wp_is_playing(o.p) == 1);
  CHECK(d.clicks.size() == 2u);
  if (d.clicks.size() == 2u)
    CHECK(d.clicks[0].frame == kRate && d.clicks[1].frame == kRate + 22050);
}

// ---- #9/AK7 the rest of the C API ----

void writeWavFloat(const std::string &path, const std::vector<float> &mono, int rate) {
  std::ofstream f(path, std::ios::binary);
  auto u32 = [&](uint32_t v) { f.write(reinterpret_cast<const char *>(&v), 4); };
  auto u16 = [&](uint16_t v) { f.write(reinterpret_cast<const char *>(&v), 2); };
  const auto bytes = static_cast<uint32_t>(mono.size() * 4);
  f.write("RIFF", 4);
  u32(36 + bytes);
  f.write("WAVEfmt ", 8);
  u32(16);
  u16(3); // IEEE float
  u16(1);
  u32(static_cast<uint32_t>(rate));
  u32(static_cast<uint32_t>(rate) * 4);
  u16(4);
  u16(32);
  f.write("data", 4);
  u32(bytes);
  f.write(reinterpret_cast<const char *>(mono.data()), bytes);
}

void loadFromFile() {
  // #9/AK7: loading by path. A generated 2 s WAV (440 Hz sine, amplitude 0.5, mono, 22 050 Hz) is
  // converted to the player's rate (wp_create: 48 kHz) and stereo, so it lasts 2 s = 96 000
  // frames. Each of 8 waveform sections (0.25 s, 110 periods) reaches ± 0.5 (± 1 % for the
  // resampler). A missing file reports WP_ERR_FILE_NOT_FOUND and keeps the title.
  const std::string path = std::string(WP_TEST_TMP_DIR) + "/reference_sine.wav";
  std::vector<float> mono(44100);
  for (size_t i = 0; i < mono.size(); ++i)
    mono[i] = static_cast<float>(0.5 * std::sin(2 * kPi * 440 * static_cast<double>(i) / 22050));
  writeWavFloat(path, mono, 22050);
  CHECK_NEAR(wp_file_duration(path.c_str()), 2.0, 1e-9);

  wp_player *p = wp_create();
  CHECK(p != nullptr);
  if (!p)
    return;
  CHECK(wp_web_sample_rate(p) == 48000);
  CHECK(wp_load_state(p) == WP_LOAD_IDLE);
  CHECK(wp_load_async(p, path.c_str()) == WP_OK);
  CHECK(wp_load_wait(p) == WP_OK);
  CHECK(wp_load_state(p) == WP_LOAD_READY);
  CHECK(wp_load_progress(p) == 1.0);
  CHECK_NEAR(wp_duration(p), 2.0, 1.0 / 48000);
  float mins[8], maxs[8];
  CHECK(wp_waveform(p, 0.0, 2.0, 8, mins, maxs) == WP_OK);
  bool peaks = true;
  for (int i = 0; i < 8; ++i)
    peaks = peaks && std::fabs(maxs[i] - 0.5f) < 0.005f && std::fabs(mins[i] + 0.5f) < 0.005f;
  CHECK(peaks);
  record("load_waveform", [&] {
    std::vector<float> w(mins, mins + 8);
    w.insert(w.end(), maxs, maxs + 8);
    return w;
  }());

  const std::string missing = std::string(WP_TEST_TMP_DIR) + "/missing.wav";
  CHECK(wp_load(p, missing.c_str()) == WP_ERR_FILE_NOT_FOUND);
  CHECK(wp_load_state(p) == WP_ERR_FILE_NOT_FOUND);
  CHECK(std::string(wp_error_message(WP_ERR_FILE_NOT_FOUND)) !=
        wp_error_message(WP_ERR_UNSUPPORTED_FORMAT));
  CHECK_NEAR(wp_duration(p), 2.0, 1.0 / 48000); // the previous title stays

  // Render 0.25 s from 1 s on: a resampled sine, identical natively and under WASM.
  wp_seek(p, 1.0);
  wp_play(p);
  std::vector<float> out;
  for (int i = 0; i < 12000 / 480; ++i) {
    const float *b = wp_web_render(p, 480);
    out.insert(out.end(), b, b + 960);
  }
  CHECK_NEAR(wp_position(p), 1.25, 1e-9);
  CHECK(std::fabs(frequency(out, 0, out.size() / 2) * 48000.0 / kRate - 440.0) <= 4.4);
  record("load_render", out);
  wp_destroy(p);
}

void mp3ExportUnavailableOffline() {
  // #141, #9/AK7: the offline and browser cores have no MP3 export (mp3_api_stub.cpp): the encoder
  // is never available, the export reports WP_ERR_ENCODER_UNAVAILABLE and touches nothing.
  CHECK(wp_mp3_available("libmp3lame.dylib") == 0);
  CHECK(wp_mp3_available(nullptr) == 0);
  int cancel = 0;
  double progress = -1;
  CHECK(wp_mp3_export("libmp3lame.dylib", "in.wav", "out.mp3", 192, &cancel, &progress) ==
        WP_ERR_ENCODER_UNAVAILABLE);
  CHECK(progress == -1);
  CHECK(wp_mp3_export(nullptr, nullptr, nullptr, 0, nullptr, nullptr) ==
        WP_ERR_ENCODER_UNAVAILABLE);
}

void recordingUnavailableOffline() {
  // #9/AK7: the offline and browser cores have no recording (recorder_stub.cpp): not available,
  // start reports WP_REC_ERR_UNSUPPORTED, idle values, an English error text.
  CHECK(wp_rec_available() == 0);
  CHECK(wp_rec_start("unused.wav") == WP_REC_ERR_UNSUPPORTED);
  // #113: neither source, so no microphone in the browser either.
  CHECK(wp_rec_source_available(WP_REC_SOURCE_SYSTEM) == 0);
  CHECK(wp_rec_source_available(WP_REC_SOURCE_MIC) == 0);
  CHECK(wp_rec_start_source("unused.flac", WP_REC_SOURCE_MIC) == WP_REC_ERR_UNSUPPORTED);
  CHECK(wp_rec_start_source("unused.wav", WP_REC_SOURCE_SYSTEM) == WP_REC_ERR_UNSUPPORTED);
  // #140: no armed recording either.
  CHECK(wp_rec_start_armed("unused.flac", WP_REC_SOURCE_MIC, -50.0, 5.0) == WP_REC_ERR_UNSUPPORTED);
  CHECK(wp_rec_start_armed_tail("unused.flac", WP_REC_SOURCE_MIC, -30.0, 5.0, 1.0) ==
        WP_REC_ERR_UNSUPPORTED); // #147
  CHECK(wp_rec_gate_state() == WP_REC_GATE_OFF);
  CHECK(wp_rec_kept_seconds() == 0.0);
  wp_rec_stop();
  CHECK(wp_rec_is_recording() == 0);
  CHECK(wp_rec_seconds() == 0.0);
  CHECK(wp_rec_level() == 0.0f);
  CHECK(wp_rec_only_silence() == 1);
  CHECK(wp_rec_os_status() == 0);
  CHECK(std::strlen(wp_rec_error()) > 0);
  // #162: no microphone to point at an artificial input either.
  CHECK(wp_rec_set_input(WP_REC_INPUT_TONE) == WP_REC_ERR_UNSUPPORTED);
}

// A 16-bit mono WAV in memory: `frames` samples of a 440 Hz sine with amplitude 0.5.
std::vector<unsigned char> wavInMemory(int rate, int frames) {
  std::vector<unsigned char> b;
  auto u16 = [&](unsigned v) {
    b.push_back(static_cast<unsigned char>(v & 0xff));
    b.push_back(static_cast<unsigned char>((v >> 8) & 0xff));
  };
  auto u32 = [&](unsigned v) {
    u16(v & 0xffff);
    u16(v >> 16);
  };
  auto tag = [&](const char *t) { b.insert(b.end(), t, t + 4); };
  const unsigned bytes = static_cast<unsigned>(frames) * 2;
  tag("RIFF");
  u32(36 + bytes);
  tag("WAVE");
  tag("fmt ");
  u32(16);
  u16(1);
  u16(1);
  u32(static_cast<unsigned>(rate));
  u32(static_cast<unsigned>(rate) * 2);
  u16(2);
  u16(16);
  tag("data");
  u32(bytes);
  for (int i = 0; i < frames; ++i)
    u16(static_cast<unsigned>(
            std::lround(0.5 * 32767 * std::sin(2 * kPi * 440 * static_cast<double>(i) / rate))) &
        0xffff);
  return b;
}

// #120: a minimal M4A (one AAC track at 44.1 kHz, no priming) with `frames` placeholder frames of
// 1024 samples, frame i made of 10 + i % 7 bytes of the value i, in chunks of 10 frames.
std::vector<uint8_t> m4aInMemory(uint32_t frames) {
  std::vector<uint8_t> f;
  auto u32 = [](std::vector<uint8_t> &b, uint32_t v) {
    for (int i = 0; i < 4; ++i)
      b.push_back(static_cast<uint8_t>(v >> (24 - 8 * i)));
  };
  auto box = [&](const char *type, const std::vector<uint8_t> &body) {
    std::vector<uint8_t> b;
    u32(b, static_cast<uint32_t>(body.size() + 8));
    b.insert(b.end(), type, type + 4);
    b.insert(b.end(), body.begin(), body.end());
    return b;
  };
  auto cat = [](std::initializer_list<std::vector<uint8_t>> parts) {
    std::vector<uint8_t> b;
    for (const auto &p : parts)
      b.insert(b.end(), p.begin(), p.end());
    return b;
  };
  auto words = [&](std::initializer_list<uint32_t> v) {
    std::vector<uint8_t> b;
    for (const uint32_t x : v)
      u32(b, x);
    return b;
  };
  std::vector<uint8_t> data, sizes = words({0, 0, frames});
  for (uint32_t i = 0; i < frames; ++i) {
    data.insert(data.end(), 10 + i % 7, static_cast<uint8_t>(i));
    u32(sizes, 10 + i % 7);
  }
  const uint32_t duration = frames * 1024;
  std::vector<uint8_t> entry = words({0, 1, 0, 0, 0x00020010, 0, uint32_t{kRate} << 16});
  entry.resize(28); // reserved, data reference index, version, channels, bits, rate
  const auto stsd = box("stsd", cat({words({0, 1}), box("mp4a", entry)}));
  auto stbl = [&](uint32_t base) {
    std::vector<uint8_t> offsets = words({0, (frames + 9) / 10});
    for (uint32_t c = 0, at = base; c < (frames + 9) / 10; ++c) {
      u32(offsets, at);
      for (uint32_t i = 10 * c; i < std::min(frames, 10 * c + 10); ++i)
        at += 10 + i % 7;
    }
    return box("stbl", cat({stsd, box("stts", words({0, 1, frames, 1024})),
                            box("stsc", words({0, 1, 1, 10, 1})), box("stsz", sizes),
                            box("stco", offsets)}));
  };
  auto moov = [&](uint32_t base) {
    const auto mdia = box(
        "mdia", cat({box("mdhd", words({0, 0, 0, kRate, duration, 0})),
                     box("hdlr", words({0, 0, 0x736f756e, 0, 0, 0})), box("minf", stbl(base))}));
    std::vector<uint8_t> mvhd = words({0, 0, 0, kRate, duration, 0x00010000});
    mvhd.resize(100);
    std::vector<uint8_t> tkhd = words({0, 0, 0, 1, 0, duration});
    tkhd.resize(84);
    return box("moov", cat({box("mvhd", mvhd), box("trak", cat({box("tkhd", tkhd), mdia}))}));
  };
  const auto ftyp = box("ftyp", cat({{'M', '4', 'A', ' '}, words({0})}));
  const size_t base = ftyp.size() + moov(0).size() + 8;
  f = cat({ftyp, moov(static_cast<uint32_t>(base)), box("mdat", data)});
  return f;
}

// #116: trimming through the C API. A 2 s WAV (16 bit, 44.1 kHz) cut to [0.5, 1.75] keeps
// round(0.5 × 44100) = 22050 to round(1.75 × 44100) = 77175, that is 55125 frames of 2 bytes after
// the 44-byte header; the same sine as FLAC (encoded by libFLAC) stays FLAC and lossless. The new
// files are recorded byte by byte, so native and WASM must cut and encode to the same bytes.
void trimInMemory() {
  const auto wav = wavInMemory(kRate, 2 * kRate);
  wp_trim_result *r = nullptr;
  CHECK(wp_trim(wav.data(), wav.size(), 0.5, 1.75, &r) == WP_OK);
  if (!r)
    return;
  CHECK(wp_trim_size(r) == 44 + 55125 * 2);
  CHECK(wp_trim_start(r) == 22050.0 / kRate && wp_trim_end(r) == 77175.0 / kRate);
  const auto *bytes = static_cast<const unsigned char *>(wp_trim_data(r));
  // the samples are those of the old file from frame 22050 on
  CHECK(std::equal(bytes + 44, bytes + wp_trim_size(r), wav.begin() + 44 + 22050 * 2));
  record("trim_wav", std::vector<float>(bytes, bytes + wp_trim_size(r)));
  wp_trim_free(r);

  std::vector<uint8_t> flac;
  wp::FlacWriter w;
  CHECK(w.openMemory(&flac, kRate, 1, 16));
  std::vector<int32_t> pcm;
  for (size_t i = 44; i + 1 < wav.size(); i += 2)
    pcm.push_back(static_cast<int16_t>(wav[i] | (wav[i + 1] << 8)));
  CHECK(w.writeInt(pcm.data(), static_cast<uint32_t>(pcm.size())));
  CHECK(w.close());
  CHECK(wp_trim(flac.data(), flac.size(), 0.5, 1.75, &r) == WP_OK);
  if (!r)
    return;
  CHECK(std::memcmp(wp_trim_data(r), "fLaC", 4) == 0);
  wp_player *p = wp_web_create(kRate);
  CHECK(wp_web_load_encoded(p, wp_trim_data(r), wp_trim_size(r)) == WP_OK);
  CHECK(std::lround(wp_duration(p) * kRate) == 55125);
  const auto *b = static_cast<const unsigned char *>(wp_trim_data(r));
  record("trim_flac", std::vector<float>(b, b + wp_trim_size(r)));
  wp_trim_free(r);
  wp_destroy(p);
  // #120/AK4: an M4A is cut alike natively and in the browser: the same bytes. Trimming does not
  // decode, so the AAC frames are placeholders: 100 frames of 1024 samples, frame i of 10 + i % 7
  // bytes holding i; [0.7, 2.2] s keeps frames 29 (pre-roll) to 94, the edit list skips 1024.
  const std::vector<uint8_t> m4a = m4aInMemory(100);
  CHECK(wp_trim(m4a.data(), m4a.size(), 0.7, 2.2, &r) == WP_OK);
  if (!r)
    return;
  const auto *m = static_cast<const unsigned char *>(wp_trim_data(r));
  CHECK(std::memcmp(m + 4, "ftyp", 4) == 0);
  CHECK(wp_trim_start(r) == 30 * 1024.0 / kRate && wp_trim_end(r) == 95 * 1024.0 / kRate);
  const std::vector<uint8_t> out(m, m + wp_trim_size(r));
  const uint8_t first[] = {29, 29, 29, 29, 29, 29, 29, 29, 29, 29, 29};
  CHECK(std::search(out.begin(), out.end(), first, first + 11) != out.end());
  record("trim_m4a", std::vector<float>(m, m + wp_trim_size(r)));
  wp_trim_free(r);
  // too short or no audio: an error and no result
  CHECK(wp_trim(wav.data(), wav.size(), 0.5, 1.25, &r) == WP_ERR_INVALID_ARGUMENT && !r);
  const std::string junk(512, 'x');
  CHECK(wp_trim(junk.data(), junk.size(), 0.0, 1.0, &r) == WP_ERR_UNSUPPORTED_FORMAT && !r);
}

void webEntryPointsAtTheirLimits() {
  // #11 (found by mutation testing): the browser entry points of wp_core_web.h at their limits.
  // A title decoded into a track (0.5 s at 8000 Hz = 4000 frames) has its length, duration and
  // waveform; bytes that are no audio give WP_ERR_UNSUPPORTED_FORMAT and no track.
  const auto wav = wavInMemory(8000, 4000);
  int err = -999;
  wp_web_track *t = wp_web_track_decode(wav.data(), wav.size(), 8000, &err);
  CHECK(t != nullptr && err == WP_OK);
  if (t) {
    CHECK(wp_web_track_frames(t) == 4000);
    CHECK(wp_web_track_duration(t) == 0.5);
    float mins[4], maxs[4];
    CHECK(wp_web_track_waveform(t, 0.0, 0.5, 4, mins, maxs) == WP_OK);
    CHECK(std::fabs(maxs[0] - 0.5f) < 0.01f && std::fabs(mins[3] + 0.5f) < 0.01f);
    wp_web_track_free(t);
  }
  const std::string junk(512, 'x');
  CHECK(wp_web_track_decode(junk.data(), junk.size(), 8000, &err) == nullptr);
  CHECK(err == WP_ERR_UNSUPPORTED_FORMAT);
  CHECK(wp_web_track_duration(nullptr) == 0.0);

  wp_player *p = wp_web_create(8000);
  CHECK(p != nullptr);
  if (!p)
    return;
  CHECK(wp_web_load_encoded(p, junk.data(), junk.size()) == WP_ERR_UNSUPPORTED_FORMAT);
  CHECK(wp_web_load_encoded(p, wav.data(), wav.size()) == WP_OK);
  CHECK(wp_duration(p) == 0.5);

  // PCM in parts: one frame is the smallest title and the smallest part; a new begin discards an
  // unfinished title, also when the new one is rejected (0 frames).
  CHECK(wp_web_pcm_begin(p, 10) == WP_OK);
  CHECK(wp_web_pcm_begin(p, 0) == WP_ERR_INVALID_ARGUMENT);
  const float frame[2] = {0.25f, -0.25f};
  CHECK(wp_web_pcm_append(p, frame, 1) == WP_ERR_INVALID_ARGUMENT); // nothing begun any more
  CHECK(wp_web_pcm_begin(p, 1) == WP_OK);
  CHECK(wp_web_pcm_append(p, frame, 1) == WP_OK);
  CHECK(wp_web_pcm_commit(p) == WP_OK);
  CHECK(wp_duration(p) == 1.0 / 8000);

  // The metronome volume reaches the output: 0 is silence, 1 the click (no title playing).
  wp_metro_set_volume(p, 0.0f);
  wp_metro_start(p);
  wp_web_render(p, 800); // the gain smooths over 5 ms = 40 frames
  const float *b = wp_web_render(p, 800);
  float quiet = 0;
  for (int i = 0; i < 1600; ++i)
    quiet = std::max(quiet, std::fabs(b[i]));
  CHECK(quiet == 0.0f);
  wp_metro_stop(p);
  wp_metro_set_volume(p, 1.0f);
  wp_metro_start(p);
  b = wp_web_render(p, 400);
  float loud = 0;
  for (int i = 0; i < 800; ++i)
    loud = std::max(loud, std::fabs(b[i]));
  CHECK(loud > 0.3f);
  wp_destroy(p);
}

// #157/AK5: the recording of the browser through wp_web_rec_* on generated audio, fed in render
// quanta of 128 frames as the AudioWorklet delivers them and stored piece by piece as the worker
// does. Armed with threshold -30 dBFS, pause 2 s and tail 1 s (as «Armed»): 1.5 s silence, 0.5 s
// sine, 0.8 s pause (kept), 0.5 s sine, 2.5 s silence (ends it), 0.5 s sine (not kept). The file
// holds 1 s lead-in + 0.5 + 0.8 + 0.5
// + 1 s tail = 3.8 s. The gate state per block and the decoded file are compared native against
// WASM.
std::vector<uint8_t> webRecording(wp_web_rec *r, const std::vector<float> &mono, int channels,
                                  std::vector<float> &gates) {
  std::vector<uint8_t> file;
  const auto total = static_cast<int>(mono.size());
  for (int done = 0; done < total; done += 128) {
    const int n = std::min(128, total - done);
    float *in = wp_web_rec_input(r);
    CHECK(in != nullptr);
    if (!in)
      break;
    for (int i = 0; i < n; ++i)
      for (int c = 0; c < channels; ++c)
        in[i * channels + c] = mono[static_cast<size_t>(done) + static_cast<size_t>(i)];
    CHECK(wp_web_rec_feed(r, n) == WP_OK);
    gates.push_back(static_cast<float>(wp_web_rec_gate(r)));
    const auto *out = static_cast<const uint8_t *>(wp_web_rec_out(r));
    CHECK(wp_web_rec_out_offset(r) == static_cast<double>(file.size()));
    file.insert(file.end(), out, out + wp_web_rec_out_size(r));
    wp_web_rec_take(r);
  }
  CHECK(wp_web_rec_finish(r) == WP_OK);
  const auto *out = static_cast<const uint8_t *>(wp_web_rec_out(r));
  file.insert(file.end(), out, out + wp_web_rec_out_size(r));
  wp_web_rec_take(r);
  const auto *head = static_cast<const uint8_t *>(wp_web_rec_header(r));
  std::copy(head, head + wp_web_rec_header_size(r), file.begin());
  return file;
}

void webRecordingArmed() {
  constexpr int rate = 48000;
  std::vector<float> mono;
  auto silence = [&](double s) { mono.insert(mono.end(), static_cast<size_t>(s * rate), 0.0f); };
  auto tone = [&](double s) {
    for (int i = 0; i < static_cast<int>(s * rate); ++i)
      mono.push_back(static_cast<float>(0.5 * std::cos(2.0 * kPi * 440.0 * i / rate)));
  };
  silence(1.5);
  tone(0.5);
  silence(0.8);
  tone(0.5);
  silence(2.5);
  tone(0.5);
  int err = 1;
  wp_web_rec *r = wp_web_rec_create(rate, 2, 1, -30.0, 2.0, 1.0, &err);
  CHECK(r != nullptr && err == WP_OK);
  if (!r)
    return;
  CHECK(wp_web_rec_gate(r) == WP_REC_GATE_ARMED);
  std::vector<float> gates;
  const std::vector<uint8_t> file = webRecording(r, mono, 2, gates);
  CHECK(wp_web_rec_gate(r) == WP_REC_GATE_DONE);
  CHECK(std::fabs(wp_web_rec_seconds(r) - static_cast<double>(mono.size()) / rate) < 1e-9);
  CHECK(std::fabs(wp_web_rec_kept_seconds(r) - 3.8) < 0.01);
  CHECK(std::fabs(wp_web_rec_level(r) - 0.5f) < 1e-6f); // peak since the start, then reset
  CHECK(wp_web_rec_level(r) == 0.0f);
  wp_web_rec_free(r);
  // Gate: armed for the first 1.5 s, then recording, done 2 s into the long silence.
  CHECK(gates.front() == WP_REC_GATE_ARMED && gates.back() == WP_REC_GATE_DONE);
  const auto firstRecording = std::find(gates.begin(), gates.end(), WP_REC_GATE_RECORDING);
  CHECK(std::abs((firstRecording - gates.begin()) - (rate * 3 / 2) / 128) <= 1);
  wp_web_track *t = wp_web_track_decode(file.data(), file.size(), rate, &err);
  CHECK(t != nullptr && err == WP_OK);
  if (!t)
    return;
  const int frames = wp_web_track_frames(t);
  CHECK(std::abs(frames - static_cast<int>(3.8 * rate)) <= rate / 100);
  const float *pcm = wp_web_track_data(t);
  int first = -1;
  for (int i = 0; i < frames && first < 0; ++i)
    if (std::fabs(pcm[2 * i]) > 0.0316f)
      first = i;
  CHECK(std::abs(first - rate) <= rate / 100); // 1 s lead-in
  record("web_rec_armed_gate", gates);
  record("web_rec_armed_file", std::vector<float>(pcm, pcm + 2 * frames));
  wp_web_track_free(t);

  // Without arming (the record button), mono: every frame, and the error cases.
  r = wp_web_rec_create(rate, 1, 0, 0.0, 0.0, 0.0, &err);
  CHECK(r != nullptr && err == WP_OK && wp_web_rec_gate(r) == WP_REC_GATE_OFF);
  if (!r)
    return;
  std::vector<float> none;
  const std::vector<float> part(mono.begin() + rate, mono.begin() + 2 * rate);
  const std::vector<uint8_t> plain = webRecording(r, part, 1, none);
  CHECK(wp_web_rec_only_silence(r) == 0);
  CHECK(wp_web_rec_feed(r, 0) == WP_REC_ERR_INVALID_ARGUMENT);
  CHECK(wp_web_rec_feed(r, WP_WEB_MAX_BLOCK + 1) == WP_REC_ERR_INVALID_ARGUMENT);
  wp_web_rec_free(r);
  t = wp_web_track_decode(plain.data(), plain.size(), rate, &err);
  CHECK(t != nullptr && wp_web_track_frames(t) == rate);
  if (t)
    record("web_rec_plain_file",
           std::vector<float>(wp_web_track_data(t), wp_web_track_data(t) + 2 * rate));
  wp_web_track_free(t);
  // Limits: 8000 and 192000 Hz, 1 and 8 channels; a block of 1 and of WP_WEB_MAX_BLOCK frames, its
  // last sample in the last channel reaching the core.
  for (const auto [rRate, ch] :
       {std::pair{WP_MIN_SAMPLE_RATE, 1}, std::pair{WP_MAX_SAMPLE_RATE, 8}}) {
    r = wp_web_rec_create(rRate, ch, 0, 0, 0, 0, &err);
    CHECK(r != nullptr && err == WP_OK);
    if (!r)
      continue;
    float *in = wp_web_rec_input(r);
    CHECK(in != nullptr);
    if (!in) {
      wp_web_rec_free(r);
      continue;
    }
    const size_t n = static_cast<size_t>(WP_WEB_MAX_BLOCK) * static_cast<size_t>(ch);
    std::fill(in, in + n, 0.0f);
    in[n - 1] = 0.75f;
    CHECK(wp_web_rec_feed(r, WP_WEB_MAX_BLOCK) == WP_OK);
    CHECK(std::fabs(wp_web_rec_level(r) - 0.75f) < 1e-6f);
    CHECK(wp_web_rec_feed(r, 1) == WP_OK);
    CHECK(std::fabs(wp_web_rec_seconds(r) - (WP_WEB_MAX_BLOCK + 1.0) / rRate) < 1e-12);
    wp_web_rec_free(r);
  }
  CHECK(wp_web_rec_create(WP_MIN_SAMPLE_RATE - 1, 2, 0, 0, 0, 0, &err) == nullptr);
  CHECK(wp_web_rec_create(WP_MAX_SAMPLE_RATE + 1, 2, 0, 0, 0, 0, &err) == nullptr);
  CHECK(wp_web_rec_create(rate, 2, 1, -30.0, 0.0, 1.0, &err) == nullptr);
  CHECK(err == WP_REC_ERR_INVALID_ARGUMENT);
  CHECK(wp_web_rec_create(4000, 2, 0, 0, 0, 0, &err) == nullptr);
  CHECK(wp_web_rec_create(rate, 0, 0, 0, 0, 0, &err) == nullptr);
  CHECK(wp_web_rec_create(rate, 9, 0, 0, 0, 0, nullptr) == nullptr);
  CHECK(wp_web_rec_feed(nullptr, 1) == WP_REC_ERR_INVALID_ARGUMENT);
  CHECK(wp_web_rec_finish(nullptr) == WP_REC_ERR_INVALID_ARGUMENT);
  CHECK(wp_web_rec_input(nullptr) == nullptr && wp_web_rec_out(nullptr) == nullptr);
  CHECK(wp_web_rec_out_size(nullptr) == 0 && wp_web_rec_out_offset(nullptr) == 0.0);
  CHECK(wp_web_rec_header(nullptr) == nullptr && wp_web_rec_header_size(nullptr) == 0);
  CHECK(wp_web_rec_gate(nullptr) == WP_REC_GATE_OFF && wp_web_rec_cut(nullptr) == 0.0);
  CHECK(wp_web_rec_seconds(nullptr) == 0.0 && wp_web_rec_kept_seconds(nullptr) == 0.0);
  CHECK(wp_web_rec_level(nullptr) == 0.0f && wp_web_rec_only_silence(nullptr) == 0);
  wp_web_rec_take(nullptr);
  wp_web_rec_free(nullptr);
}

void sampleRateLowerLimit() {
  // #76/AK1 #76/AK2: WP_MIN_SAMPLE_RATE (8000 Hz) is the lowest rate the core accepts. At the limit
  // a player loads and plays; just below it (7999 Hz) and at nonsense rates (1 Hz, where the time
  // stretch divided by zero, docs/TESTS.md «Gefundene Fehler» Nr. 21; 0 and negative) the player
  // exists but stays silent, and every way of loading reports WP_ERR_UNSUPPORTED_SAMPLE_RATE
  // instead of crashing. Decoding and converting into a track check the rate the same way.
  CHECK(WP_MIN_SAMPLE_RATE == 8000);
  CHECK(std::string(wp_error_message(WP_ERR_UNSUPPORTED_SAMPLE_RATE)) != wp_error_message(-100));
  const auto wav = wavInMemory(8000, 800);
  const float pcm[4] = {0.25f, -0.25f, 0.25f, -0.25f};
  int err = -999;

  wp_web_track *t = wp_web_track_decode(wav.data(), wav.size(), WP_MIN_SAMPLE_RATE, &err);
  CHECK(t != nullptr && err == WP_OK);
  wp_web_track_free(t);
  t = wp_web_track_convert(pcm, 2, 2, WP_MIN_SAMPLE_RATE, WP_MIN_SAMPLE_RATE, &err);
  CHECK(t != nullptr && err == WP_OK);
  wp_web_track_free(t);

  wp_player *p = wp_web_create(WP_MIN_SAMPLE_RATE);
  CHECK(p != nullptr);
  if (p) {
    CHECK(wp_web_load_encoded(p, wav.data(), wav.size()) == WP_OK);
    CHECK(wp_web_load_pcm(p, pcm, 2, 2, WP_MIN_SAMPLE_RATE) == WP_OK);
    wp_play(p);
    const float *b = wp_web_render(p, 2);
    CHECK(b != nullptr && b[0] == 0.25f);
    wp_destroy(p);
  }

  for (const int rate : {WP_MIN_SAMPLE_RATE - 1, 1, 0, -1}) {
    err = -999;
    CHECK(wp_web_track_decode(wav.data(), wav.size(), rate, &err) == nullptr);
    CHECK(err == WP_ERR_UNSUPPORTED_SAMPLE_RATE);
    err = -999;
    CHECK(wp_web_track_convert(pcm, 2, 2, rate, WP_MIN_SAMPLE_RATE, &err) == nullptr);
    CHECK(err == WP_ERR_UNSUPPORTED_SAMPLE_RATE);
    err = -999;
    CHECK(wp_web_track_convert(pcm, 2, 2, WP_MIN_SAMPLE_RATE, rate, &err) == nullptr);
    CHECK(err == WP_ERR_UNSUPPORTED_SAMPLE_RATE);

    p = wp_web_create(rate);
    CHECK(p != nullptr);
    if (!p)
      continue;
    CHECK(wp_web_sample_rate(p) == rate);
    CHECK(wp_web_load_encoded(p, wav.data(), wav.size()) == WP_ERR_UNSUPPORTED_SAMPLE_RATE);
    CHECK(wp_web_load_pcm(p, pcm, 2, 2, WP_MIN_SAMPLE_RATE) == WP_ERR_UNSUPPORTED_SAMPLE_RATE);
    CHECK(wp_web_pcm_begin(p, 2) == WP_OK);
    CHECK(wp_web_pcm_append(p, pcm, 2) == WP_OK);
    CHECK(wp_web_pcm_commit(p) == WP_ERR_UNSUPPORTED_SAMPLE_RATE);
    CHECK(wp_load(p, "any.wav") == WP_ERR_UNSUPPORTED_SAMPLE_RATE);
    CHECK(wp_load_state(p) == WP_ERR_UNSUPPORTED_SAMPLE_RATE);
    CHECK(wp_duration(p) == 0.0);
    // Silent output, also with the metronome running.
    wp_metro_set_volume(p, 1.0f);
    wp_metro_start(p);
    wp_play(p);
    const float *b = wp_web_render(p, 400);
    float peak = 0;
    for (int i = 0; b && i < 800; ++i)
      peak = std::max(peak, std::fabs(b[i]));
    CHECK(b != nullptr && peak == 0.0f);
    wp_destroy(p);
  }
}

void sampleRateUpperLimit() {
  // #97/AK1 #97/AK2 #97/AK3: WP_MAX_SAMPLE_RATE (192 000 Hz) is the highest rate the core accepts.
  // At the limit a player loads and plays, decoding and converting work; above it (192 001 Hz and
  // INT_MAX, where decoding a short file reserved gigabytes, docs/TESTS.md «Gefundene Fehler»)
  // the player stays silent and every way of loading, decoding and converting (target and source
  // rate) reports WP_ERR_UNSUPPORTED_SAMPLE_RATE.
  CHECK(WP_MAX_SAMPLE_RATE == 192000);
  const auto wav = wavInMemory(8000, 800);
  const float pcm[4] = {0.25f, -0.25f, 0.25f, -0.25f};
  int err = -999;

  wp_web_track *t = wp_web_track_decode(wav.data(), wav.size(), WP_MAX_SAMPLE_RATE, &err);
  CHECK(t != nullptr && err == WP_OK);
  if (t)
    CHECK(wp_web_track_frames(t) == 19200); // 0.1 s at 192 kHz
  wp_web_track_free(t);
  t = wp_web_track_convert(pcm, 2, 2, WP_MAX_SAMPLE_RATE, WP_MAX_SAMPLE_RATE, &err);
  CHECK(t != nullptr && err == WP_OK);
  wp_web_track_free(t);

  wp_player *p = wp_web_create(WP_MAX_SAMPLE_RATE);
  CHECK(p != nullptr);
  if (p) {
    CHECK(wp_web_load_encoded(p, wav.data(), wav.size()) == WP_OK);
    CHECK(wp_web_load_pcm(p, pcm, 2, 2, WP_MAX_SAMPLE_RATE) == WP_OK);
    wp_play(p);
    const float *b = wp_web_render(p, 2);
    CHECK(b != nullptr && b[0] == 0.25f);
    wp_destroy(p);
  }

  for (const int rate : {WP_MAX_SAMPLE_RATE + 1, INT_MAX}) {
    err = -999;
    CHECK(wp_web_track_decode(wav.data(), wav.size(), rate, &err) == nullptr);
    CHECK(err == WP_ERR_UNSUPPORTED_SAMPLE_RATE);
    err = -999;
    CHECK(wp_web_track_convert(pcm, 2, 2, rate, WP_MAX_SAMPLE_RATE, &err) == nullptr);
    CHECK(err == WP_ERR_UNSUPPORTED_SAMPLE_RATE);
    err = -999;
    CHECK(wp_web_track_convert(pcm, 2, 2, WP_MAX_SAMPLE_RATE, rate, &err) == nullptr);
    CHECK(err == WP_ERR_UNSUPPORTED_SAMPLE_RATE);

    p = wp_web_create(rate);
    CHECK(p != nullptr);
    if (!p)
      continue;
    CHECK(wp_web_sample_rate(p) == rate);
    CHECK(wp_web_load_encoded(p, wav.data(), wav.size()) == WP_ERR_UNSUPPORTED_SAMPLE_RATE);
    CHECK(wp_web_load_pcm(p, pcm, 2, 2, WP_MAX_SAMPLE_RATE) == WP_ERR_UNSUPPORTED_SAMPLE_RATE);
    CHECK(wp_web_pcm_begin(p, 2) == WP_OK);
    CHECK(wp_web_pcm_append(p, pcm, 2) == WP_OK);
    CHECK(wp_web_pcm_commit(p) == WP_ERR_UNSUPPORTED_SAMPLE_RATE);
    CHECK(wp_load(p, "any.wav") == WP_ERR_UNSUPPORTED_SAMPLE_RATE);
    CHECK(wp_load_state(p) == WP_ERR_UNSUPPORTED_SAMPLE_RATE);
    CHECK(wp_duration(p) == 0.0);
    // Silent output, also with the metronome running.
    wp_metro_set_volume(p, 1.0f);
    wp_metro_start(p);
    wp_play(p);
    const float *b = wp_web_render(p, 400);
    float peak = 0;
    for (int i = 0; b && i < 800; ++i)
      peak = std::max(peak, std::fabs(b[i]));
    CHECK(b != nullptr && peak == 0.0f);
    wp_destroy(p);
  }
}

void run(const char *name, void (*test)()) {
  const int before = failures;
  test();
  std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name);
}

} // namespace

int main(int argc, char **argv) {
  if (argc == 3 && std::string(argv[1]) == "--dump") {
    mode = Mode::Dump;
    contractPath = argv[2];
  } else if (argc == 3 && std::string(argv[1]) == "--compare") {
    mode = Mode::Compare;
    contractPath = argv[2];
    if (!readDump(contractPath)) {
      std::printf("FAIL native dump %s missing or unreadable; run the native reference_tests "
                  "first (make test-wasm does)\n",
                  contractPath.c_str());
      return 1;
    }
  }
  run("#9/AK1 generated test audio, silence through the stretch", generatedTestAudio);
  run("#9/AK2 loop seam over 100 passes (ramp)", loopSeamOver100Passes);
  run("#9/AK3 seek starts at round(t x rate)", seekStartsAtRoundedFrame);
  run("#9/AK3 pause and resume lose no frame", pauseAndResumeLoseNoFrame);
  run("#9/AK4 #94/AK2 #94/AK3 tempo: length input / r, pitch 440 Hz", tempoLengthAndPitch);
  run("#3/AK9 #9/AK5 120 BPM without drift over 5 min", metronomeWithoutDriftOverFiveMinutes);
  run("#3/AK7 #3/AK8 #9/AK5 accents and subdivisions", metronomeAccentsAndSubdivisions);
  run("#3/AK10 #3/AK11 #3/AK15 #3/AK18 #9/AK5 golden click positions of a fixed sequence",
      metronomeGoldenSequence);
  run("#70/AK2 #70/AK3 #3/AK10 meter and subdivision change mid-beat",
      metronomeMeterAndSubdivisionChangeMidBeat);
  run("#3/AK20 #9/AK5 metronome with title", metronomeWithTitle);
  run("#9/AK7 load from file, waveform, errors", loadFromFile);
  run("#9/AK7 recording unavailable offline", recordingUnavailableOffline);
  run("#141 MP3 export unavailable offline", mp3ExportUnavailableOffline);
  run("#11 browser entry points at their limits", webEntryPointsAtTheirLimits);
  run("#116/AK4 #116/AK7 #120/AK4 trimming WAV, FLAC and M4A in memory", trimInMemory);
  run("#157/AK5 recording in the browser, armed and plain", webRecordingArmed);
  run("#76/AK1 #76/AK2 sample rate lower limit", sampleRateLowerLimit);
  run("#97/AK1 #97/AK2 #97/AK3 sample rate upper limit", sampleRateUpperLimit);

  if (mode == Mode::Dump) {
    const bool ok = writeDump(contractPath);
    CHECK(ok);
    std::printf("contract: %zu outputs written to %s\n", dumped.size(), contractPath.c_str());
  } else if (mode == Mode::Compare) {
    CHECK(compared.size() == reference.size()); // every native output was produced here too
    std::printf("contract: %zu of %zu native outputs compared\n", compared.size(),
                reference.size());
  }
  std::printf("%d checks, %d failed\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
