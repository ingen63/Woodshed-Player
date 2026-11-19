// Tests der Wiedergabe-Logik im Offline-Rendering (ohne Audiogerät). Testaudio wird erzeugt.
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <new>
#include <string>
#include <thread>
#include <vector>

#include "command_queue.hpp"
#include "engine.hpp"
#include "metronome.hpp"

// Zählt Speicherreservierungen und -freigaben im markierten Thread (#14/AK1).
namespace {
thread_local bool tCountAllocs = false;
std::atomic<long> gAllocs{0};
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
} // namespace

void *operator new(std::size_t n) { return countedAlloc(n); }
void *operator new[](std::size_t n) { return countedAlloc(n); }
void operator delete(void *p) noexcept { countedFree(p); }
void operator delete[](void *p) noexcept { countedFree(p); }
void operator delete(void *p, std::size_t) noexcept { countedFree(p); }
void operator delete[](void *p, std::size_t) noexcept { countedFree(p); }

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

void commandsFromManyThreadsWhileRendering() { // #14/AK1
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
        switch ((i++ + t) % 4) {
        case 0:
          e.seek((i % 90) / 10.0);
          break;
        case 1:
          e.setRate(0.5 + (i % 15) / 10.0);
          break;
        case 2:
          e.setVolume((i % 10) / 10.0f);
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
  CHECK(ms < 50.0);
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

} // namespace

int main(int argc, char **argv) {
  const std::string filter = argc > 1 ? argv[1] : ""; // optional: nur Tests, deren Name das enthält
  const std::vector<std::pair<std::string, std::function<void()>>> tests = {
      {"loopSeamDirectIsSampleExact", loopSeamDirectIsSampleExact},
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
      {"rateChangeKeepsPositionAndSignal", rateChangeKeepsPositionAndSignal},
      {"seekDuringStretchedPlayback", seekDuringStretchedPlayback},
      {"queueKeepsOrderAndRejectsWhenFull", queueKeepsOrderAndRejectsWhenFull},
      {"queueManyProducersDeliverEachCommandOnce", queueManyProducersDeliverEachCommandOnce},
      {"commandsApplyInOrderAtNextRender", commandsApplyInOrderAtNextRender},
      {"renderDoesNotAllocate", renderDoesNotAllocate},
      {"seeksAreCoalescedPerBlock", seeksAreCoalescedPerBlock},
      {"commandsFromManyThreadsWhileRendering", commandsFromManyThreadsWhileRendering},
  };
  for (auto &[name, fn] : tests) {
    if (name.find(filter) == std::string::npos)
      continue;
    const int before = failures;
    fn();
    std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name.c_str());
  }
  std::printf("%d checks, %d failures\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
