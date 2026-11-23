// Tests der Wiedergabe-Logik im Offline-Rendering (ohne Audiogerät). Testaudio wird erzeugt.
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <memory>
#include <new>
#include <string>
#include <thread>
#include <vector>

#include "command_queue.hpp"
#include "engine.hpp"
#include "metronome.hpp"
#include "replace_new.hpp"
#include "sample_rate.hpp"
#include "test_timing.hpp"

// Zählt Speicherreservierungen und -freigaben im markierten Thread (#14/AK1).
namespace {
thread_local bool tCountAllocs = false;
std::atomic<long> gAllocs{0};
#if WP_REPLACE_NEW
void *countedAlloc(std::size_t n) {
  if (tCountAllocs)
    ++gAllocs;
  if (void *p = std::malloc(n ? n : 1))
    return p;
  throw std::bad_alloc();
}
void countedFree(void *p) noexcept {
  if (p && tCountAllocs)
    ++gAllocs;
  std::free(p);
}
#endif
} // namespace

// Not under ThreadSanitizer, whose runtime brings its own operators (#101, replace_new.hpp); there
// nothing is counted and the check of #14/AK1 runs in the other builds only.
#if WP_REPLACE_NEW
void *operator new(std::size_t n) { return countedAlloc(n); }
void *operator new[](std::size_t n) { return countedAlloc(n); }
void operator delete(void *p) noexcept { countedFree(p); }
void operator delete[](void *p) noexcept { countedFree(p); }
void operator delete(void *p, std::size_t) noexcept { countedFree(p); }
void operator delete[](void *p, std::size_t) noexcept { countedFree(p); }
#endif

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

constexpr double kPi = 3.14159265358979323846;

// Rampe: Wert = Frame-Index (exakt darstellbar bis 2^24), gleich in beiden Kanälen.
std::vector<float> ramp(long long frames) {
  std::vector<float> v(static_cast<size_t>(frames) * 2);
  for (long long i = 0; i < frames; ++i)
    v[2 * i] = v[2 * i + 1] = static_cast<float>(i);
  return v;
}

std::vector<float> sine(double freq, double seconds, int sr, float amp = 0.5f) {
  const long long n = static_cast<long long>(seconds * sr);
  std::vector<float> v(static_cast<size_t>(n) * 2);
  for (long long i = 0; i < n; ++i)
    v[2 * i] = v[2 * i + 1] = amp * static_cast<float>(std::sin(2 * kPi * freq * i / sr));
  return v;
}

std::vector<float> renderFrames(wp::Engine &e, long long frames, int block = 512) {
  std::vector<float> out(static_cast<size_t>(frames) * e.channels());
  long long done = 0;
  while (done < frames) {
    const int n = static_cast<int>(std::min<long long>(block, frames - done));
    e.render(out.data() + done * e.channels(), n);
    done += n;
  }
  return out;
}

double rms(const std::vector<float> &v, long long from, long long count, int ch = 2) {
  double s = 0;
  for (long long i = from; i < from + count; ++i)
    s += double(v[i * ch]) * v[i * ch];
  return std::sqrt(s / count);
}

// Frequenz über Nulldurchgänge (aufsteigend) des linken Kanals.
double zeroCrossingFreq(const std::vector<float> &v, long long from, long long count, int sr,
                        int ch = 2) {
  int crossings = 0;
  for (long long i = from + 1; i < from + count; ++i)
    if (v[(i - 1) * ch] < 0 && v[i * ch] >= 0)
      ++crossings;
  return crossings * double(sr) / count;
}

// ---------------------------------------------------------------------------

void loopSeamDirectIsSampleExact() { // #5/AK4
  const int sr = 1000;
  wp::Engine e;
  e.setSource(ramp(5000), 2, sr);
  e.setLoop(1.0, 2.0); // Frames 1000..1999
  e.seek(1.5);
  e.play();
  // 100 Durchläufe, ungerade Blockgrösse, damit der Sprung mitten in Blöcken liegt.
  const long long n = 100 * 1000 + 500;
  auto out = renderFrames(e, n, 333);
  long long expected = 1500;
  bool ok = true;
  for (long long i = 0; i < n && ok; ++i) {
    ok = out[2 * i] == float(expected) && out[2 * i + 1] == float(expected);
    if (++expected >= 2000)
      expected = 1000;
  }
  CHECK(ok);
  CHECK(e.playing());
}

void loopPassesCountJumpsFromLoopEnd() { // #29/AK2
  const int sr = 1000;
  wp::Engine e;
  e.setSource(ramp(5000), 2, sr);
  e.setLoop(1.0, 2.0);
  e.seek(1.5);
  e.play();
  renderFrames(e, 400, 333);
  CHECK(e.loopPasses() == 0);
  renderFrames(e, 200, 333); // über das Loop-Ende
  CHECK(e.loopPasses() == 1);
  renderFrames(e, 3000, 4096); // grosse Blöcke: jeder Sprung zählt einzeln
  CHECK(e.loopPasses() == 4);
}

void loopPassesIgnoreSeeks() { // #29/AK2
  const int sr = 1000;
  wp::Engine e;
  e.setSource(ramp(5000), 2, sr);
  e.setLoop(1.0, 2.0);
  e.seek(1.9);
  e.play();
  renderFrames(e, 50);
  e.seek(1.2); // von Hand zurück
  renderFrames(e, 50);
  CHECK(e.loopPasses() == 0);
  e.seek(3.0); // hinter das Loop-Ende: Sprung zum Anfang ist kein Durchgang
  renderFrames(e, 50);
  CHECK(e.loopPasses() == 0);
  CHECK_NEAR(e.position(), 1.05, 1e-9);
}

void loopPassesCountWhileStretching() { // #29/AK2
  const int sr = 44100;
  wp::Engine e;
  e.setSource(sine(440, 6, sr), 2, sr);
  e.setRate(0.5);
  e.setLoop(1.0, 2.0);
  e.seek(1.0);
  e.play();
  renderFrames(e, static_cast<long long>(1.9 * sr)); // 0,95 s Original
  CHECK(e.loopPasses() == 0);
  renderFrames(e, static_cast<long long>(4.2 * sr)); // bis 3,05 s Original: drei Sprünge
  CHECK(e.loopPasses() == 3);
  e.seek(4.0);
  renderFrames(e, 2048);
  CHECK(e.loopPasses() == 3);
}

void seekSetsPositionAndFirstSample() {
  const int sr = 1000;
  wp::Engine e;
  e.setSource(ramp(5000), 2, sr);
  e.seek(2.25);
  e.play();
  float frame[2];
  e.render(frame, 1);
  CHECK(frame[0] == 2250.0f);
  CHECK_NEAR(e.position(), 2.251, 1e-9);
}

void seekOutsideLoopJumpsToLoopStart() {
  const int sr = 1000;
  wp::Engine e;
  e.setSource(ramp(5000), 2, sr);
  e.setLoop(1.0, 2.0);
  e.seek(3.0); // hinter dem Loop-Ende
  e.play();
  float frame[2];
  e.render(frame, 1);
  CHECK(frame[0] == 1000.0f);
}

void loopAtFileEndIsClamped() {
  const int sr = 1000;
  wp::Engine e;
  e.setSource(ramp(3000), 2, sr);
  e.setLoop(1.5, 10.0); // B hinter dem Dateiende -> Dateiende
  e.seek(2.9);
  e.play();
  auto out = renderFrames(e, 200);
  CHECK(out[2 * 99] == 2999.0f);
  CHECK(out[2 * 100] == 1500.0f);
  CHECK(e.playing());
}

void shortLoopIsIgnored() {
  const int sr = 1000;
  wp::Engine e;
  e.setSource(ramp(3000), 2, sr);
  e.setLoop(1.0, 1.5); // kürzer als 1 s -> aus
  e.seek(1.4);
  e.play();
  auto out = renderFrames(e, 200);
  CHECK(out[2 * 150] == 1550.0f);
}

void endOfFileStopsAndRestarts() {
  const int sr = 1000;
  wp::Engine e;
  e.setSource(ramp(1000), 2, sr);
  e.seek(0.9);
  e.play();
  auto out = renderFrames(e, 200);
  CHECK(!e.playing());
  CHECK(out[2 * 99] == 999.0f);
  CHECK(out[2 * 100] == 0.0f);
  CHECK_NEAR(e.position(), 1.0, 1e-9);
  e.play(); // am Ende: wieder von vorn
  float frame[2];
  e.render(frame, 1);
  CHECK(frame[0] == 0.0f);
  CHECK(e.playing());
}

void rateIsClamped() {
  wp::Engine e;
  e.setRate(5.0);
  CHECK(e.rate() == 2.0);
  e.setRate(0.01);
  CHECK(e.rate() == 0.1);
  e.setRate(0.75);
  CHECK(e.rate() == 0.75);
}

void stretchKeepsPitchAndChangesLength() { // #5/AK3
  const int sr = 44100;
  for (double rate : {0.25, 0.5, 1.5, 2.0}) {
    wp::Engine e;
    e.setSource(sine(440, 2.0, sr), 2, sr);
    e.setRate(rate);
    e.play();
    long long rendered = 0;
    std::vector<float> all;
    std::vector<float> block(512 * 2);
    do { // Befehle wirken erst im ersten render()
      e.render(block.data(), 512);
      all.insert(all.end(), block.begin(), block.end());
      rendered += 512;
    } while (e.playing() && rendered < sr * 20);
    const double seconds = double(rendered) / sr;
    std::printf("  tempo %.2f: %.3f s played (expected %.3f)\n", rate, seconds, 2.0 / rate);
    CHECK_NEAR(seconds, 2.0 / rate, 0.05);
    // Tonhöhe in der Mitte (weg von Ein-/Ausschwingen): 440 Hz ± 1 %.
    const long long mid = rendered / 2 - sr / 4;
    const double f = zeroCrossingFreq(all, mid, sr / 2, sr);
    std::printf("  tempo %.2f: %.1f Hz\n", rate, f);
    CHECK_NEAR(f, 440.0, 4.4);
  }
}

void stretchLoopHasNoGap() { // #5/AK4 (gedehnter Pfad)
  const int sr = 44100;
  wp::Engine e;
  e.setSource(sine(441, 4.0, sr), 2, sr); // 441 Hz: 100 Samples pro Periode, Loop ganzzahlig
  e.setLoop(1.0, 2.0);
  e.seek(1.0);
  e.setRate(0.5);
  e.play();
  const long long n = sr * 10; // fünf Loop-Durchläufe bei 0,5x
  auto out = renderFrames(e, n);
  const double ref = 0.5 / std::sqrt(2.0);
  const long long win = sr / 100; // 10 ms
  double minRms = 1;
  for (long long i = sr / 2; i + win < n; i += win)
    minRms = std::min(minRms, rms(out, i, win));
  std::printf("  lowest 10 ms level: %.3f (reference %.3f)\n", minRms, ref);
  CHECK(minRms > ref * 0.7); // keine Lücke, kein Einbruch über 3 dB
  CHECK(e.position() >= 1.0 && e.position() < 2.0);
}

void positionFollowsRate() {
  const int sr = 44100;
  wp::Engine e;
  e.setSource(sine(440, 5.0, sr), 2, sr);
  e.setRate(0.5);
  e.play();
  renderFrames(e, sr * 2); // 2 s Ausgabe = 1 s Quelle
  CHECK_NEAR(e.position(), 1.0, 0.01);
}

void stretchIsDeterministic() {
  const int sr = 44100;
  auto run = [&] {
    wp::Engine e;
    e.setSource(sine(330, 1.0, sr), 2, sr);
    e.setRate(0.7);
    e.play();
    return renderFrames(e, sr);
  };
  CHECK(run() == run());
}

void volumeScalesDirectOutput() {
  const int sr = 1000;
  wp::Engine e;
  e.setSource(ramp(2000), 2, sr);
  e.setVolume(0.5f);
  e.play();
  auto out = renderFrames(e, 100, 64);
  bool ok = true;
  for (int i = 0; i < 100 && ok; ++i)
    ok = out[2 * i] == 0.5f * float(i) && out[2 * i + 1] == 0.5f * float(i);
  CHECK(ok);
  e.setVolume(0.0f);
  auto silent = renderFrames(e, 50);
  bool allZero = true;
  for (float v : silent)
    allZero = allZero && v == 0.0f;
  CHECK(allZero);
  CHECK(e.playing());
}

// #10/AK4, found by fuzz_capi: arguments through the C API may be NaN, infinite or huge. Expected
// from the rules of engine.cpp: NaN seek and NaN rate change nothing, a seek beyond the end lands
// on the end (2000 frames at 1000 Hz = 2 s), a loop end beyond the file ends at the file end, the
// volume is limited to 0–1 (5 plays like 1, NaN is silence). Every sample stays finite.
void nonFiniteArgumentsAreSafe() {
  const int sr = 1000;
  wp::Engine e;
  e.setSource(ramp(2000), 2, sr);
  e.setRate(1.5);
  e.setRate(std::nan(""));
  CHECK(e.rate() == 1.5);
  e.setRate(1.0);
  e.seek(0.5);
  renderFrames(e, 1);
  e.pause();
  e.seek(std::nan(""));
  renderFrames(e, 1);
  CHECK_NEAR(e.position(), 0.5, 1e-9);
  e.seek(INFINITY);
  renderFrames(e, 1);
  CHECK_NEAR(e.position(), 2.0, 1e-9);
  e.seek(1e300);
  renderFrames(e, 1);
  CHECK_NEAR(e.position(), 2.0, 1e-9);
  e.seek(-INFINITY);
  renderFrames(e, 1);
  CHECK(e.position() == 0.0);
  // Loop 0.5 s .. end of file: the playhead wraps from frame 2000 to 500.
  e.setLoop(0.5, 1e300);
  e.seek(1.9);
  e.setVolume(5.0f);
  e.play();
  auto out = renderFrames(e, 200, 64);
  CHECK(out[0] == 1900.0f);      // volume 5 limited to 1
  CHECK(out[2 * 100] == 500.0f); // 1900 + 100 = 2000 wraps to the loop start 500
  e.setLoop(std::nan(""), 1.0);  // invalid: loop off
  e.setVolume(std::nanf(""));
  auto silent = renderFrames(e, 100);
  bool zero = true;
  for (float v : silent)
    zero = zero && v == 0.0f;
  CHECK(zero);
  e.setVolume(INFINITY);
  e.setRate(INFINITY); // limited to 2.0
  CHECK(e.rate() == 2.0);
  auto fast = renderFrames(e, 300);
  bool finite = true;
  for (float v : fast)
    finite = finite && std::isfinite(v);
  CHECK(finite);
}

void rateChangeKeepsPositionAndSignal() {
  const int sr = 44100;
  wp::Engine e;
  e.setSource(sine(440, 6.0, sr), 2, sr);
  e.play();
  auto a = renderFrames(e, sr); // 1 s bei 1,0x -> Position 1,0 s
  CHECK_NEAR(e.position(), 1.0, 0.001);
  e.setRate(0.5);
  auto b = renderFrames(e, sr); // 1 s Ausgabe bei 0,5x -> 0,5 s Quelle
  CHECK_NEAR(e.position(), 1.5, 0.02);
  e.setRate(1.0);
  auto c = renderFrames(e, sr); // zurück bei 1,0x -> 1 s Quelle, kein Sprung
  CHECK_NEAR(e.position(), 2.5, 0.02);
  // Kein Aussetzer an den Übergängen: Pegel bleibt nahe dem Sinus-Effektivwert.
  const double ref = 0.5 / std::sqrt(2.0);
  CHECK_NEAR(rms(b, sr / 4, sr / 2), ref, ref * 0.15);
  CHECK_NEAR(rms(c, sr / 4, sr / 2), ref, ref * 0.15);
  // Steilheit: grösster Sprung zwischen Samples nahe der Sinus-Steigung (0,5*2*pi*440/44100 =
  // 0,0313).
  double maxStep = 0;
  for (auto *v : {&b, &c})
    for (long long i = sr / 20; i + 1 < sr; ++i)
      maxStep = std::max(maxStep, double(std::fabs((*v)[2 * (i + 1)] - (*v)[2 * i])));
  std::printf("  largest step: %.4f\n", maxStep);
  CHECK(maxStep < 0.1);
}

void seekDuringStretchedPlayback() {
  const int sr = 44100;
  wp::Engine e;
  e.setSource(sine(440, 6.0, sr), 2, sr);
  e.setRate(0.5);
  e.play();
  renderFrames(e, sr);
  CHECK_NEAR(e.position(), 0.5, 0.02);
  e.seek(3.0);
  renderFrames(e, sr / 2); // 0,5 s Ausgabe = 0,25 s Quelle
  CHECK_NEAR(e.position(), 3.25, 0.02);
  e.seek(0.0);
  renderFrames(e, sr / 2);
  CHECK_NEAR(e.position(), 0.25, 0.02);
  CHECK(e.playing());
}

void queueKeepsOrderAndRejectsWhenFull() { // #14/AK1
  wp::CommandQueue<int> q(4);
  CHECK(q.capacity() == 4);
  for (int i = 0; i < 4; ++i)
    CHECK(q.push(i));
  CHECK(!q.push(99));
  int v = -1;
  for (int i = 0; i < 4; ++i) {
    CHECK(q.pop(v));
    CHECK(v == i);
  }
  CHECK(!q.pop(v));
  CHECK(q.push(5) && q.pop(v) && v == 5); // nach dem Umlauf weiter benutzbar
}

void queueManyProducersDeliverEachCommandOnce() { // #14/AK1
  wp::CommandQueue<int> q(64);
  constexpr int kThreads = 4, kPerThread = 20000;
  std::vector<std::thread> producers;
  producers.reserve(kThreads);
  for (int t = 0; t < kThreads; ++t) {
    producers.emplace_back([&q, t] {
      for (int i = 0; i < kPerThread; ++i)
        while (!q.push(t * kPerThread + i))
          std::this_thread::yield();
    });
  }
  std::vector<int> seen(kThreads * kPerThread, 0);
  std::vector<int> last(kThreads, -1);
  bool ordered = true;
  int received = 0, v = 0;
  while (received < kThreads * kPerThread) {
    if (!q.pop(v))
      continue;
    ++seen[v];
    ++received;
    const int t = v / kPerThread;
    ordered = ordered && v > last[t]; // je Erzeuger in Reihenfolge
    last[t] = v;
  }
  for (auto &th : producers)
    th.join();
  bool once = true;
  for (int n : seen)
    once = once && n == 1;
  CHECK(once);
  CHECK(ordered);
  CHECK(!q.pop(v));
}

void commandsApplyInOrderAtNextRender() { // #14/AK1
  const int sr = 1000;
  wp::Engine e;
  e.setSource(ramp(5000), 2, sr);
  e.seek(1.0);
  e.seek(2.0);
  e.play();
  CHECK(!e.playing()); // wirkt erst im Audio-Thread
  float frame[2];
  e.render(frame, 1);
  CHECK(frame[0] == 2000.0f);
  CHECK(e.playing());
  e.play();
  e.pause();
  e.render(frame, 1);
  CHECK(!e.playing());
  CHECK(frame[0] == 0.0f);
}

void renderDoesNotAllocate() { // #14/AK1: Audio-Thread reserviert keinen Speicher
  const int sr = 48000;
  wp::Engine e;
  e.setSource(sine(440, 4.0, sr), 2, sr);
  wp::Metronome m(sr);
  m.setSubdivision(4);
  m.start();
  auto next = std::make_unique<wp::Source>();
  next->data = sine(220, 3.0, sr);
  next->frames = static_cast<long long>(next->data.size()) / 2;
  std::vector<float> out(512 * 2);
  auto block = [&](int n) {
    for (int i = 0; i < n; ++i) {
      e.render(out.data(), 512);
      m.renderAdd(out.data(), 512, 2);
    }
  };

  gAllocs = 0;
  tCountAllocs = true;
  e.play();
  e.setVolume(0.8f);
  e.setLoop(0.5, 2.0);
  block(20);
  e.setRate(0.5);
  block(60);
  e.seek(1.0);
  block(10);
  e.setRate(1.7);
  block(40);
  e.setRate(1.0);
  e.setLoop(0, 0);
  block(10);
  tCountAllocs = false;

  CHECK(e.submitSource(std::move(next)));
  tCountAllocs = true;
  block(5); // Titelwechsel: alter Titel wird im Audio-Thread nicht freigegeben
  e.play();
  e.setRate(0.8);
  block(20);
  tCountAllocs = false;
  CHECK(gAllocs.load() == 0);
  if (gAllocs.load() != 0)
    std::printf("  %ld allocations on the audio thread\n", gAllocs.load());
  e.collectGarbage();
  CHECK_NEAR(e.duration(), 3.0, 1e-9);
  CHECK(e.playing());
}

void commandsFromManyThreadsWhileRendering() { // #14/AK1, #57/AK2
  const int sr = 8000;
  wp::Engine e;
  e.setSource(sine(440, 10.0, sr), 2, sr);
  e.setLoop(1.0, 9.0);
  e.play();
  std::atomic<bool> stop{false};
  std::vector<std::thread> controllers;
  controllers.reserve(3);
  for (int t = 0; t < 3; ++t) {
    controllers.emplace_back([&e, &stop, t] {
      int i = 0;
      while (!stop.load()) {
        switch ((i++ + t) % 6) {
        case 0:
          e.seek((i % 90) / 10.0);
          break;
        case 1:
          e.setRate(0.5 + (i % 15) / 10.0);
          break;
        case 2:
          e.setVolume((i % 10) / 10.0f);
          break;
        case 3: // #57/AK2: loop and pause from other threads, too
          e.setLoop(1.0 + (i % 3), 6.0 + (i % 3));
          break;
        case 4:
          e.pause();
          break;
        default:
          e.play();
          break;
        }
        std::this_thread::yield();
      }
    });
  }
  std::vector<float> out(256 * 2);
  bool finite = true;
  for (int i = 0; i < 400; ++i) {
    e.render(out.data(), 256);
    for (float x : out)
      finite = finite && std::isfinite(x);
  }
  stop = true;
  for (auto &th : controllers)
    th.join();
  e.render(out.data(), 256); // restliche Befehle abarbeiten
  CHECK(finite);
  CHECK(e.position() >= 0.0 && e.position() <= 10.0);
  e.pause();
  e.render(out.data(), 256);
  CHECK(!e.playing());
}

void seeksAreCoalescedPerBlock() { // #14/AK1: viele Seeks in einem Block kosten nur einen
  const int sr = 48000;
  wp::Engine e;
  e.setSource(sine(440, 10.0, sr), 2, sr);
  e.setRate(0.5);
  e.play();
  std::vector<float> out(512 * 2);
  e.render(out.data(), 512); // gedehnter Pfad aktiv
  for (int i = 0; i < 1000; ++i)
    e.seek((i % 90) / 10.0);
  e.seek(4.0);
  const auto t0 = std::chrono::steady_clock::now();
  e.render(out.data(), 1);
  const double ms =
      std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
  CHECK_NEAR(e.position(), 4.0, 1e-3);
  CHECK(!kTimingChecks || ms < 50.0);
  if (ms >= 50.0)
    std::printf("  block with 1001 seeks: %.1f ms\n", ms);

  // Seek vor einem Titelwechsel gilt dem alten Titel und verfällt.
  auto next = std::make_unique<wp::Source>();
  next->data = sine(220, 2.0, sr);
  next->frames = static_cast<long long>(next->data.size()) / 2;
  e.seek(5.0);
  CHECK(e.submitSource(std::move(next)));
  e.render(out.data(), 1);
  CHECK(e.position() == 0.0);
  e.collectGarbage();
}

// ---------------------------------------------------------------------------
// #11: cases found by mutation testing (make mutants). Each names the rule it checks; the expected
// values are derived from the rule, the numbers in the comments.

// Left and right channel with different content: left a 441 Hz sine, right silence (or the other
// way round).
std::vector<float> leftOnlySine(double seconds, int sr, bool left = true) {
  const long long n = static_cast<long long>(seconds * sr);
  std::vector<float> v(static_cast<size_t>(n) * 2, 0.0f);
  for (long long i = 0; i < n; ++i)
    v[2 * i + (left ? 0 : 1)] = 0.5f * static_cast<float>(std::sin(2 * kPi * 441.0 * i / sr));
  return v;
}

double peakOfChannel(const std::vector<float> &v, int channel) {
  double peak = 0;
  for (size_t i = static_cast<size_t>(channel); i < v.size(); i += 2)
    peak = std::max(peak, double(std::fabs(v[i])));
  return peak;
}

// The loop may start at 0: a = 0 s is a valid start (0 <= a), loop 0..1 s at 1000 Hz plays frames
// 0..999 and then 0 again.
void loopMayStartAtZero() {
  const int sr = 1000;
  wp::Engine e;
  e.setSource(ramp(3000), 2, sr);
  e.setLoop(0.0, 1.0);
  e.seek(0.9);
  e.play();
  auto out = renderFrames(e, 200);
  CHECK(out[2 * 99] == 999.0f);
  CHECK(out[2 * 100] == 0.0f);
}

// End at least 1 s after the start, in frames after rounding: 1.0 .. 1.9996 s rounds to frames
// 1000 .. 2000 but is shorter than 1 s, so there is no loop; playing on from 1.9 s reaches 2100.
void loopJustShorterThanOneSecondIsIgnored() {
  const int sr = 1000;
  wp::Engine e;
  e.setSource(ramp(3000), 2, sr);
  e.setLoop(1.0, 1.9996);
  e.seek(1.9);
  e.play();
  auto out = renderFrames(e, 200);
  CHECK(out[2 * 150] == 2050.0f);
}

// A loop end beyond the file ends at the file end; if that leaves less than 1 s there is no loop:
// 3 s file, loop 2.5 .. 10 s -> 2.5 .. 3.0 s = 0.5 s -> ignored, the title plays to its end.
void loopShortenedByFileEndIsIgnored() {
  const int sr = 1000;
  wp::Engine e;
  e.setSource(ramp(3000), 2, sr);
  e.setLoop(2.5, 10.0);
  e.seek(2.9);
  e.play();
  auto out = renderFrames(e, 200);
  CHECK(out[2 * 99] == 2999.0f);
  CHECK(out[2 * 100] == 0.0f); // end of file: silence, not the loop start 2500
  CHECK(!e.playing());
}

// A seek exactly to the loop end counts as behind it: the next sample is the loop start, and the
// jump is no pass (#29/AK2), in the direct and in the stretched path.
void seekExactlyToLoopEnd() {
  const int sr = 1000;
  wp::Engine e;
  e.setSource(ramp(5000), 2, sr);
  e.setLoop(1.0, 2.0);
  e.seek(2.0);
  e.play();
  float frame[2];
  e.render(frame, 1);
  CHECK(frame[0] == 1000.0f);
  CHECK(e.loopPasses() == 0);

  wp::Engine s;
  s.setSource(sine(440, 4.0, 44100), 2, 44100);
  s.setRate(0.5);
  s.setLoop(1.0, 2.0);
  s.seek(2.0);
  s.play();
  renderFrames(s, 4410); // 0.1 s output = 0.05 s source after the jump to 1.0 s
  CHECK(s.loopPasses() == 0);
  CHECK_NEAR(s.position(), 1.05, 0.001);
}

// Several loop passes within one block of the stretched path: 1000 Hz, loop 1.0 .. 2.5 s (1500
// frames), rate 2.0, one block of 4096 frames = 8192 source frames from frame 1000: the playhead
// reaches 9192, that is 6692 frames past the loop end = 1 + floor(6692 / 1500) = 5 passes, and
// ends at 1000 + 6692 mod 1500 = 1692 frames = 1.692 s.
void manyLoopPassesInOneStretchedBlock() {
  const int sr = 1000;
  wp::Engine e;
  e.setSource(ramp(5000), 2, sr);
  e.setLoop(1.0, 2.5);
  e.seek(1.0);
  e.setRate(2.0);
  e.play();
  std::vector<float> out(4096 * 2);
  e.render(out.data(), 4096);
  CHECK(e.loopPasses() == 5);
  CHECK_NEAR(e.position(), 1.692, 1e-9);
}

// Starting playback at the end of the title starts from the beginning, also when the seek to the
// end comes in the same block as play: 2000 frames at 1000 Hz, seek to 2.0 s and play -> frame 0.
void playAfterSeekToEndStartsOver() {
  const int sr = 1000;
  wp::Engine e;
  e.setSource(ramp(2000), 2, sr);
  e.seek(2.0);
  e.play();
  float frame[2];
  e.render(frame, 1);
  CHECK(frame[0] == 0.0f);
  CHECK(e.playing());
}

// A new title is visible at once, before the audio thread takes it: position 0, paused, its
// length; setSource (tests, tools) the same without any render.
void newTitleIsVisibleAtOnce() {
  const int sr = 1000;
  wp::Engine e;
  e.setSource(ramp(5000), 2, sr);
  CHECK(e.frames() == 5000);
  CHECK_NEAR(e.duration(), 5.0, 1e-12);
  e.seek(2.0);
  e.play();
  renderFrames(e, 100);
  CHECK(e.playing());
  auto next = std::make_unique<wp::Source>();
  next->data = ramp(3000);
  next->frames = 3000;
  CHECK(e.submitSource(std::move(next)));
  CHECK(e.frames() == 3000);
  CHECK(e.position() == 0.0);
  CHECK(!e.playing());

  e.seek(1.0);
  e.play();
  renderFrames(e, 100);
  CHECK(e.playing());
  e.setSource(ramp(4000), 2, sr);
  CHECK(e.frames() == 4000);
  CHECK(e.position() == 0.0);
  CHECK(!e.playing());
}

// render writes exactly the requested frames, also above the internal block of 4096 frames, and
// writes silence after the end of the title: 10'000 frames of a 6000-frame ramp in one call give
// 0 .. 5999, then zeros; the sentinel behind the buffer stays untouched. The same in the stretched
// path (the samples there are not the ramp, but the sentinel holds).
void renderWritesExactlyTheRequestedFrames() {
  const int sr = 1000;
  constexpr float kSentinel = 7.0f;
  wp::Engine e;
  e.setSource(ramp(6000), 2, sr);
  e.play();
  std::vector<float> out(10000 * 2 + 64, kSentinel);
  e.render(out.data(), 10000);
  bool ramped = true;
  for (int i = 0; i < 6000 && ramped; ++i)
    ramped = out[2 * i] == float(i) && out[2 * i + 1] == float(i);
  CHECK(ramped);
  bool silent = true;
  for (int i = 6000; i < 10000 && silent; ++i)
    silent = out[2 * i] == 0.0f && out[2 * i + 1] == 0.0f;
  CHECK(silent);
  bool sentinel = true;
  for (size_t i = 10000 * 2; i < out.size(); ++i)
    sentinel = sentinel && out[i] == kSentinel;
  CHECK(sentinel);

  wp::Engine s;
  s.setSource(sine(440, 2.0, 44100), 2, 44100);
  s.setRate(0.5);
  s.play();
  std::vector<float> st(10000 * 2 + 64, kSentinel);
  s.render(st.data(), 10000);
  bool kept = true;
  for (size_t i = 10000 * 2; i < st.size(); ++i)
    kept = kept && st[i] == kSentinel;
  CHECK(kept);
  bool written = true;
  for (size_t i = 0; i < 10000 * 2; ++i)
    written = written && st[i] != kSentinel;
  CHECK(written);
}

// Tempo without pitch change keeps the channels apart: with only one channel carrying a signal,
// the other stays silent at the highest rate (2.0, the largest input per block: 4096 output frames
// read 8192 source frames) and right after a seek in the stretched path. Both directions.
void stretchKeepsChannelsApart() {
  const int sr = 44100;
  for (bool left : {true, false}) {
    wp::Engine e;
    e.setSource(leftOnlySine(4.0, sr, left), 2, sr);
    e.setRate(2.0);
    e.play();
    std::vector<float> out(4096 * 2);
    double silentPeak = 0, signalPeak = 0;
    for (int b = 0; b < 4; ++b) {
      e.render(out.data(), 4096);
      silentPeak = std::max(silentPeak, peakOfChannel(out, left ? 1 : 0));
      signalPeak = std::max(signalPeak, peakOfChannel(out, left ? 0 : 1));
    }
    e.setRate(0.5);
    e.seek(1.0);
    for (int b = 0; b < 4; ++b) {
      e.render(out.data(), 4096);
      silentPeak = std::max(silentPeak, peakOfChannel(out, left ? 1 : 0));
    }
    std::printf("  %s only: silent channel peak %.2g, signal %.2f\n", left ? "left" : "right",
                silentPeak, signalPeak);
    CHECK(silentPeak == 0.0);
    CHECK(signalPeak > 0.3);
  }
}

// A seek in the stretched path is heard at once: the stretcher is primed with the new place
// (outputSeek), so the first 10 ms after a seek from a silent part into a 441 Hz sine (0.5
// amplitude, RMS 0.354) already carry it. Measured 20.11.2026: 0.149, rising to full level within
// 30 ms; without priming the first 40 ms are silent (the stretcher's latency). And nothing of the
// sine is heard 10 ms after a seek back into the silent part (without priming 0.11).
void stretchedSeekStartsAtFullLevel() {
  const int sr = 44100;
  // 0 .. 2 s silence, 2 .. 4 s sine
  std::vector<float> src(static_cast<size_t>(4 * sr) * 2, 0.0f);
  for (long long i = 2 * sr; i < 4 * sr; ++i)
    src[2 * i] = src[2 * i + 1] =
        0.5f * static_cast<float>(std::sin(2 * kPi * 441.0 * double(i) / sr));
  wp::Engine e;
  e.setSource(std::move(src), 2, sr);
  e.setRate(0.5);
  e.play();
  renderFrames(e, sr / 2); // in the silent part
  e.seek(3.0);
  auto out = renderFrames(e, sr / 10, 441);
  const double ref = 0.5 / std::sqrt(2.0);
  const double first = rms(out, 0, sr / 100);
  std::printf("  first 10 ms after the seek: %.3f (reference %.3f)\n", first, ref);
  CHECK(first > ref * 0.25);

  // the other way round: from the sine into the silent part, nothing of the sine after 10 ms
  e.seek(0.5);
  auto quiet = renderFrames(e, sr / 10, 441);
  const double after = rms(quiet, sr / 100, sr / 100 * 9);
  std::printf("  10 .. 100 ms after the seek into silence: %.4f\n", after);
  CHECK(after < 0.01);
}

// The stretched path reads the source at the rate: after 50 and after 200 blocks of 512 frames at
// 0.5 the read position is the same distance ahead of the audible position (the stretcher's look
// ahead), it does not drift by a frame per block.
void stretchedReadPositionDoesNotDrift() {
  const int sr = 44100;
  wp::Engine e;
  e.setSource(sine(440, 10.0, sr), 2, sr);
  e.setRate(0.5);
  e.play();
  renderFrames(e, 50 * 512);
  const double lead1 = double(e.readFrame()) - e.position() * sr;
  renderFrames(e, 150 * 512);
  const double lead2 = double(e.readFrame()) - e.position() * sr;
  std::printf("  read ahead: %.1f and %.1f frames\n", lead1, lead2);
  CHECK(std::fabs(lead2 - lead1) <= 1.0);
}

// After the end of the title the stretched path is fed silence: a constant signal (0.5) fades out,
// the 20 ms before the last block are well below its level. Measured 20.11.2026: 0.17; fed with the
// last frame again instead of silence it stays at 0.5.
void stretchedEndOfTitleFadesToSilence() {
  const int sr = 44100;
  wp::Engine e;
  e.setSource(std::vector<float>(static_cast<size_t>(sr) * 2, 0.5f), 2, sr);
  e.setRate(0.5);
  e.play();
  std::vector<float> all;
  std::vector<float> block(441 * 2);
  do { // 2 s output = 1 s source; commands take effect in the first render
    e.render(block.data(), 441);
    all.insert(all.end(), block.begin(), block.end());
  } while (e.playing() && all.size() < static_cast<size_t>(4 * sr) * 2);
  CHECK(!e.playing());
  const long long frames = static_cast<long long>(all.size() / 2);
  const long long win = sr / 50; // 20 ms
  // the last block may already be silent after the stop; look at the 20 ms before the last block
  const double tail = rms(all, frames - 441 - win, win);
  std::printf("  last 20 ms before the end: %.3f\n", tail);
  CHECK(tail < 0.25);
}

// The volume also scales the stretched path: the same title at rate 0.7 with volume 0.5 gives
// exactly half of every sample at volume 1.0 (the stretch is deterministic).
void volumeScalesStretchedOutput() {
  const int sr = 44100;
  auto run = [&](float volume) {
    wp::Engine e;
    e.setSource(sine(330, 1.0, sr), 2, sr);
    e.setRate(0.7);
    e.setVolume(volume);
    e.play();
    return renderFrames(e, sr / 2);
  };
  const auto full = run(1.0f), half = run(0.5f);
  bool ok = full.size() == half.size();
  double peak = 0;
  for (size_t i = 0; ok && i < full.size(); ++i) {
    ok = half[i] == 0.5f * full[i];
    peak = std::max(peak, double(std::fabs(full[i])));
  }
  CHECK(ok);
  CHECK(peak > 0.3);
}

// A new engine is set up for stereo at 44.1 kHz: a title handed over through the queue plays in
// the stretched path without a configure call of its own (Player calls configure, tools may not).
void defaultEngineTakesATitleThroughTheQueue() {
  wp::Engine e;
  CHECK(e.channels() == 2 && e.sampleRate() == 44100);
  auto src = std::make_unique<wp::Source>();
  src->data = sine(440, 1.0, 44100);
  src->frames = 44100;
  CHECK(e.submitSource(std::move(src)));
  e.setRate(0.5);
  e.play();
  auto out = renderFrames(e, 22050);
  const double ref = 0.5 / std::sqrt(2.0);
  CHECK_NEAR(rms(out, 11025, 11025), ref, ref * 0.15);
  CHECK_NEAR(e.position(), 0.25, 0.01);
}

// The command queue of the engine holds kQueueCapacity (1024) commands until the next render:
// the 1025th is rejected (#14/AK1), and after a render there is room again.
void commandQueueHoldsExactlyItsCapacity() {
  wp::Engine e;
  e.setSource(ramp(1000), 2, 1000);
  bool accepted = true;
  for (size_t i = 0; i < wp::Engine::kQueueCapacity; ++i)
    accepted = accepted && e.setVolume(0.5f);
  CHECK(accepted);
  CHECK(!e.setVolume(0.5f));
  renderFrames(e, 1);
  CHECK(e.setVolume(0.5f));
}

// Several threads sending at once never see a full queue while there is room: 4 threads × 200
// commands = 800 < 1024, so every send succeeds, also when another thread takes the same slot at
// the same moment (#14/AK1).
void concurrentSendsSucceedWhileThereIsRoom() {
  for (int round = 0; round < 20; ++round) {
    wp::Engine e;
    std::atomic<int> rejected{0};
    std::atomic<bool> go{false};
    std::vector<std::thread> threads;
    threads.reserve(4);
    for (int t = 0; t < 4; ++t)
      threads.emplace_back([&] {
        while (!go.load())
          std::this_thread::yield();
        for (int i = 0; i < 200; ++i)
          if (!e.setVolume(0.5f))
            ++rejected;
      });
    go.store(true);
    for (auto &t : threads)
      t.join();
    CHECK(rejected.load() == 0);
  }
}

} // namespace

// #8: without a title, play does nothing: the output stays silent and the position at 0.
void playWithoutTitleStaysSilent() {
  wp::Engine e;
  CHECK(!e.submitSource(nullptr)); // no source: rejected, nothing queued
  e.play();
  const auto out = renderFrames(e, 1024);
  bool silent = true;
  for (float v : out)
    silent = silent && v == 0.0f;
  CHECK(silent);
  CHECK(!e.playing());
  CHECK(e.position() == 0.0);
}

// Renders 0.3 s of a 440 Hz tone at tempo 0.5 with the engine configured at `rate`.
std::vector<float> stretchedAtRate(int rate) {
  wp::Engine e;
  e.setSource(sine(440, 1.0, wp::kMinSampleRate), 2, rate);
  e.setRate(0.5);
  e.play();
  return renderFrames(e, wp::kMinSampleRate * 3 / 10);
}

bool allFinite(const std::vector<float> &v) {
  for (const float x : v)
    if (!std::isfinite(x))
      return false;
  return true;
}

void stretchRateHasALowerLimit() { // #81/AK1 #81/AK3 #81/AK4
  CHECK(wp::kMinSampleRate == 8000);
  const auto atLimit = stretchedAtRate(wp::kMinSampleRate); // unchanged
  CHECK(allFinite(atLimit));
  CHECK(rms(atLimit, wp::kMinSampleRate / 10, wp::kMinSampleRate / 10) > 0.1);
  for (const int rate : {wp::kMinSampleRate - 1, 1, 0, -1}) { // protected
    const auto out = stretchedAtRate(rate);
    CHECK(allFinite(out));
    CHECK(out == atLimit); // the stretch runs at the limit, not below it
  }
  wp::Engine e; // positions keep the given rate
  e.configure(2, 1);
  CHECK(e.sampleRate() == 1);
}

int main(int argc, char **argv) {
  const std::string filter = argc > 1 ? argv[1] : ""; // optional: nur Tests, deren Name das enthält
  const std::vector<std::pair<std::string, std::function<void()>>> tests = {
      {"loopSeamDirectIsSampleExact", loopSeamDirectIsSampleExact},
      {"playWithoutTitleStaysSilent", playWithoutTitleStaysSilent},
      {"loopPassesCountJumpsFromLoopEnd", loopPassesCountJumpsFromLoopEnd},
      {"loopPassesIgnoreSeeks", loopPassesIgnoreSeeks},
      {"loopPassesCountWhileStretching", loopPassesCountWhileStretching},
      {"seekSetsPositionAndFirstSample", seekSetsPositionAndFirstSample},
      {"seekOutsideLoopJumpsToLoopStart", seekOutsideLoopJumpsToLoopStart},
      {"loopAtFileEndIsClamped", loopAtFileEndIsClamped},
      {"shortLoopIsIgnored", shortLoopIsIgnored},
      {"endOfFileStopsAndRestarts", endOfFileStopsAndRestarts},
      {"rateIsClamped", rateIsClamped},
      {"stretchKeepsPitchAndChangesLength", stretchKeepsPitchAndChangesLength},
      {"stretchLoopHasNoGap", stretchLoopHasNoGap},
      {"positionFollowsRate", positionFollowsRate},
      {"stretchIsDeterministic", stretchIsDeterministic},
      {"volumeScalesDirectOutput", volumeScalesDirectOutput},
      {"nonFiniteArgumentsAreSafe", nonFiniteArgumentsAreSafe},
      {"rateChangeKeepsPositionAndSignal", rateChangeKeepsPositionAndSignal},
      {"seekDuringStretchedPlayback", seekDuringStretchedPlayback},
      {"queueKeepsOrderAndRejectsWhenFull", queueKeepsOrderAndRejectsWhenFull},
      {"queueManyProducersDeliverEachCommandOnce", queueManyProducersDeliverEachCommandOnce},
      {"commandsApplyInOrderAtNextRender", commandsApplyInOrderAtNextRender},
      {"renderDoesNotAllocate", renderDoesNotAllocate},
      {"seeksAreCoalescedPerBlock", seeksAreCoalescedPerBlock},
      {"commandsFromManyThreadsWhileRendering", commandsFromManyThreadsWhileRendering},
      {"loopMayStartAtZero", loopMayStartAtZero},
      {"loopJustShorterThanOneSecondIsIgnored", loopJustShorterThanOneSecondIsIgnored},
      {"loopShortenedByFileEndIsIgnored", loopShortenedByFileEndIsIgnored},
      {"seekExactlyToLoopEnd", seekExactlyToLoopEnd},
      {"manyLoopPassesInOneStretchedBlock", manyLoopPassesInOneStretchedBlock},
      {"playAfterSeekToEndStartsOver", playAfterSeekToEndStartsOver},
      {"newTitleIsVisibleAtOnce", newTitleIsVisibleAtOnce},
      {"renderWritesExactlyTheRequestedFrames", renderWritesExactlyTheRequestedFrames},
      {"stretchKeepsChannelsApart", stretchKeepsChannelsApart},
      {"stretchedSeekStartsAtFullLevel", stretchedSeekStartsAtFullLevel},
      {"stretchedReadPositionDoesNotDrift", stretchedReadPositionDoesNotDrift},
      {"stretchedEndOfTitleFadesToSilence", stretchedEndOfTitleFadesToSilence},
      {"commandQueueHoldsExactlyItsCapacity", commandQueueHoldsExactlyItsCapacity},
      {"volumeScalesStretchedOutput", volumeScalesStretchedOutput},
      {"defaultEngineTakesATitleThroughTheQueue", defaultEngineTakesATitleThroughTheQueue},
      {"concurrentSendsSucceedWhileThereIsRoom", concurrentSendsSucceedWhileThereIsRoom},
      {"stretchRateHasALowerLimit", stretchRateHasALowerLimit},
  };
  for (auto &[name, fn] : tests) {
    if (name.find(filter) == std::string::npos)
      continue;
    const int before = failures;
    fn();
    std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name.c_str());
  }
  reportTimingChecks(failures);
  std::printf("%d checks, %d failures\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
