// Tests der Wellenform-Daten (#28) ohne Audiogerät: erzeugter Sinus, Stille, Fehlerfälle, Laufzeit.
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

#include "test_timing.hpp"
#include "waveform.hpp"

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

constexpr int kSr = 48000;
constexpr int kCh = 2;
constexpr double kPi = 3.14159265358979323846;

std::vector<float> sine(double seconds, double amp, double hz = 440.0) {
  const long long n = std::llround(seconds * kSr);
  std::vector<float> v(static_cast<size_t>(n) * kCh);
  for (long long i = 0; i < n; ++i) {
    const float x = static_cast<float>(amp * std::sin(2 * kPi * hz * i / kSr));
    v[i * kCh] = x;
    v[i * kCh + 1] = x;
  }
  return v;
}

wp::Peaks peaksOf(const std::vector<float> &v) {
  return wp::Peaks(v.data(), static_cast<long long>(v.size() / kCh), kCh, kSr);
}

// Jeder Abschnitt: Minimum ≈ lo, Maximum ≈ hi.
void checkAll(const wp::Peaks &p, double a, double b, int n, float lo, float hi, float tol) {
  std::vector<float> mins(n, 99.0f), maxs(n, 99.0f);
  CHECK(p.query(a, b, n, mins.data(), maxs.data()));
  int bad = 0;
  for (int i = 0; i < n; ++i)
    if (std::fabs(mins[i] - lo) > tol || std::fabs(maxs[i] - hi) > tol)
      ++bad;
  CHECK(bad == 0);
}

void sineHasHalfAmplitude() { // #28/AK1, #28/AK2
  const auto p = peaksOf(sine(3.0, 0.5));
  checkAll(p, 0.0, p.duration(), 300, -0.5f, 0.5f, 0.01f); // Übersicht
  checkAll(p, 1.0, 2.5, 150, -0.5f, 0.5f, 0.01f);          // Ausschnitt um einen Loop
  checkAll(p, 0.123, 0.987, 7, -0.5f, 0.5f, 0.01f);        // krumme Grenzen
}

void silenceIsZero() { // #28/AK3
  const std::vector<float> v(static_cast<size_t>(2 * kSr) * kCh, 0.0f);
  const auto p = peaksOf(v);
  checkAll(p, 0.0, p.duration(), 1000, 0.0f, 0.0f, 0.0f);
  checkAll(p, 0.5, 0.501, 50, 0.0f, 0.0f, 0.0f); // Abschnitte kürzer als ein Block
}

void exactlyCountValues() { // #28/AK1
  const auto p = peaksOf(sine(1.0, 0.5));
  std::vector<float> mins(1001, 7.0f), maxs(1001, 7.0f);
  CHECK(p.query(0.0, 1.0, 1000, mins.data(), maxs.data()));
  CHECK(mins[1000] == 7.0f && maxs[1000] == 7.0f); // nichts über count hinaus geschrieben
  for (int i = 0; i < 1000; ++i)
    CHECK(mins[i] >= -1.0f && maxs[i] <= 1.0f && mins[i] <= maxs[i]);
}

void clipsToRange() { // #28/AK1 Bereich −1…1
  const auto p = peaksOf(sine(1.0, 1.5));
  checkAll(p, 0.0, 1.0, 10, -1.0f, 1.0f, 0.0f);
}

void invalidRangesFail() { // #28/AK4
  const auto p = peaksOf(sine(2.0, 0.5));
  float mins[4] = {7, 7, 7, 7}, maxs[4] = {7, 7, 7, 7};
  CHECK(!p.query(1.0, 1.0, 4, mins, maxs));  // Start = Ende
  CHECK(!p.query(1.5, 1.0, 4, mins, maxs));  // Start > Ende
  CHECK(!p.query(-0.1, 1.0, 4, mins, maxs)); // vor dem Anfang
  CHECK(!p.query(1.0, 2.5, 4, mins, maxs));  // über das Ende
  CHECK(!p.query(3.0, 4.0, 4, mins, maxs));  // ganz ausserhalb
  CHECK(!p.query(0.0, 1.0, 0, mins, maxs));  // keine Abschnitte
  CHECK(!p.query(0.0, 1.0, -3, mins, maxs));
  CHECK(!p.query(0.0, NAN, 4, mins, maxs));
  CHECK(!p.query(0.0, 1.0, 4, nullptr, maxs));
  CHECK(mins[0] == 7 && maxs[3] == 7); // nichts geschrieben
  const wp::Peaks empty;               // kein Titel
  CHECK(!empty.query(0.0, 1.0, 4, mins, maxs));
  CHECK(p.query(0.0, 2.0, 4, mins, maxs)); // genau die Dauer ist erlaubt
}

void overviewIsFast() { // #28/AK5: 5 Minuten, 1000 Werte, auf dem Mac unter 200 ms
  const auto v = sine(300.0, 0.5);
  const auto t0 = std::chrono::steady_clock::now();
  const auto p = peaksOf(v); // beim Laden, im Lade-Thread
  std::vector<float> mins(1000), maxs(1000);
  CHECK(p.query(0.0, p.duration(), 1000, mins.data(), maxs.data()));
  const auto t1 = std::chrono::steady_clock::now();
  CHECK(p.query(0.0, p.duration(), 1000, mins.data(), maxs.data()));
  const auto t2 = std::chrono::steady_clock::now();
  const double build = std::chrono::duration<double, std::milli>(t1 - t0).count();
  const double query = std::chrono::duration<double, std::milli>(t2 - t1).count();
  std::printf("  5 min: computed while loading %.1f ms, overview of 1000 values %.2f ms\n", build,
              query);
  CHECK(!kTimingChecks || build < 200.0);
  CHECK(!kTimingChecks || query < 20.0);
}

} // namespace

// #8: without samples, channels or frames there is no overview and every query fails.
void noAudioHasNoOverview() {
  const std::vector<float> stereo(64, 0.5f); // 32 frames
  float mins[2] = {7, 7}, maxs[2] = {7, 7};
  for (const wp::Peaks &p :
       {wp::Peaks(nullptr, 32, 2, 48000), wp::Peaks(stereo.data(), 0, 2, 48000),
        wp::Peaks(stereo.data(), -5, 2, 48000), wp::Peaks(stereo.data(), 32, 0, 48000)}) {
    CHECK(p.frames() == 0);
    CHECK(p.duration() == 0.0);
    CHECK(!p.query(0.0, 0.0005, 2, mins, maxs));
  }
  CHECK(mins[0] == 7 && maxs[1] == 7); // nothing written
}

// #11, found by mutation testing: every block keeps its own minimum and maximum. Stereo at 1000 Hz,
// 100 frames = blocks of 32, 32, 32 and a last block of 4 frames; in block k the left channel
// rises to (k + 1) / 10 and the right one falls to −(k + 1) / 20 in its last frame, everything else
// is 0. One value per block (4 values over 0 .. 0.1 s) gives exactly these, and so does a value per
// half block (8 values over 0 .. 0.064 s, each half shows its whole block).
void eachBlockKeepsItsPeaks() {
  std::vector<float> s(200, 0.0f);
  for (int k = 0; k < 4; ++k) {
    const int last = std::min(32 * k + 31, 99);
    s[2 * last] = (k + 1) / 10.0f;
    s[2 * last + 1] = -(k + 1) / 20.0f;
  }
  wp::Peaks p(s.data(), 100, 2, 1000);
  CHECK(p.frames() == 100);
  CHECK(p.duration() == 0.1);
  float mins[8], maxs[8];
  CHECK(p.query(0.0, 0.1, 4, mins, maxs));
  for (int k = 0; k < 4; ++k) {
    CHECK(maxs[k] == (k + 1) / 10.0f);
    CHECK(mins[k] == -(k + 1) / 20.0f);
  }
  CHECK(p.query(0.0, 0.064, 4, mins, maxs)); // 16 frames each: block 0, 0, 1, 1
  CHECK(maxs[0] == 0.1f && maxs[1] == 0.1f && maxs[2] == 0.2f && maxs[3] == 0.2f);
  // from 0.032 s (block 1) on: 2 values of 34 frames, blocks 1–2 and 2–3
  CHECK(p.query(0.032, 0.1, 2, mins, maxs));
  CHECK(maxs[0] == 0.3f && mins[0] == -0.15f);
  CHECK(maxs[1] == 0.4f && mins[1] == -0.2f);
  // one value over everything
  CHECK(p.query(0.0, 0.1, 1, mins, maxs));
  CHECK(maxs[0] == 0.4f && mins[0] == -0.2f);
}

// Mono works like stereo: one channel, 64 frames, peak 0.5 in the second block.
void monoHasAnOverview() {
  std::vector<float> s(64, 0.0f);
  s[40] = 0.5f;
  s[10] = -0.25f;
  wp::Peaks p(s.data(), 64, 1, 1000);
  CHECK(p.frames() == 64);
  float mins[2], maxs[2];
  CHECK(p.query(0.0, 0.064, 2, mins, maxs));
  CHECK(mins[0] == -0.25f && maxs[0] == 0.0f);
  CHECK(mins[1] == 0.0f && maxs[1] == 0.5f);
}

// Start and end at the edges: the end may lie up to one frame after the duration (the duration
// itself counts as the end, #28/AK4), not further; a start at the duration has nothing to show.
// Without a sample rate the duration is 0.
void rangeEdges() {
  const std::vector<float> s(2000 * 2, 0.25f);
  wp::Peaks p(s.data(), 2000, 2, 1000); // 2 s
  float mins[4], maxs[4];
  CHECK(p.query(0.0, 2.0 + 1.0 / 1000, 4, mins, maxs));
  CHECK(!p.query(0.0, 2.0 + 2.0 / 1000, 4, mins, maxs));
  CHECK(!p.query(2.0, 2.0 + 0.5 / 1000, 4, mins, maxs));
  CHECK(p.query(1.999, 2.0, 1, mins, maxs));
  CHECK(maxs[0] == 0.25f);
  const wp::Peaks noRate(s.data(), 2000, 2, 0);
  CHECK(noRate.duration() == 0.0);
  CHECK(!noRate.query(0.0, 1.0, 4, mins, maxs)); // duration 0: nothing to show
}

int main() {
  const std::vector<std::pair<std::string, std::function<void()>>> tests = {
      {"eachBlockKeepsItsPeaks", eachBlockKeepsItsPeaks},
      {"monoHasAnOverview", monoHasAnOverview},
      {"rangeEdges", rangeEdges},
      {"sineHasHalfAmplitude", sineHasHalfAmplitude},
      {"silenceIsZero", silenceIsZero},
      {"exactlyCountValues", exactlyCountValues},
      {"clipsToRange", clipsToRange},
      {"invalidRangesFail", invalidRangesFail},
      {"overviewIsFast", overviewIsFast},
      {"noAudioHasNoOverview", noAudioHasNoOverview},
  };
  for (auto &[name, fn] : tests) {
    const int before = failures;
    fn();
    std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name.c_str());
  }
  std::printf("%d checks, %d failures\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
