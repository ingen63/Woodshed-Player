// Tests des Metronoms (#3, #23) im Offline-Rendering. AKn = n-tes Abnahmekriterium im jeweiligen
// Issue.
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <utility>
#include <vector>

#include "metronome.hpp"

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

using wp::Metronome;
using Ticks = std::vector<Metronome::Tick>;

// Rendert `frames` Frames in Blöcken und gibt die Ausgabe (Stereo) zurück.
std::vector<float> render(Metronome &m, long long frames, int block = 512) {
  std::vector<float> out(static_cast<size_t>(frames) * 2, 0.0f);
  for (long long done = 0; done < frames;) {
    const int n = static_cast<int>(std::min<long long>(block, frames - done));
    m.renderAdd(out.data() + done * 2, n, 2);
    done += n;
  }
  return out;
}

Ticks run(Metronome &m, long long frames, int block = 512) {
  Ticks log;
  m.tickLog = &log;
  render(m, frames, block);
  m.tickLog = nullptr;
  return log;
}

// Takte (ab 1) bis zum ersten Klick mit Tempo `bpm`.
int firstBarWithBpm(const Ticks &t, int bpm, int fromBar = 1) {
  for (auto &k : t)
    if (k.bar >= fromBar && k.sub == 0 && k.beat == 0 && k.bpm == bpm)
      return k.bar;
  return -1;
}

int bpmOfBar(const Ticks &t, int bar) {
  for (auto &k : t)
    if (k.bar == bar && k.beat == 0 && k.sub == 0)
      return k.bpm;
  return -1;
}

// ---------------------------------------------------------------------------

void defaults() { // #3/AK1
  Metronome m(44100);
  CHECK(m.bpm() == 120);
  CHECK(m.meter() == 4);
  CHECK(m.subdivision() == 1);
  CHECK(std::fabs(m.volume() - 0.7f) < 1e-6f);
  CHECK(!m.running());
  CHECK(run(m, 44100).empty()); // gestoppt: keine Klicks
}

void bpmRangeIsClamped() { // #3/AK2
  Metronome m;
  m.setBpm(10);
  CHECK(m.bpm() == 20);
  m.setBpm(400);
  CHECK(m.bpm() == 300);
  m.setBpm(73);
  CHECK(m.bpm() == 73);
}

void startBeginsWithBarOneBeatOne() { // #3/AK11
  Metronome m(44100);
  m.start();
  auto t = run(m, 44100 * 3, 333);
  CHECK(!t.empty() && t[0].frame == 0 && t[0].bar == 1 && t[0].beat == 0 &&
        t[0].kind == Metronome::Accent);
  // Erneuter Start mitten im Takt beginnt wieder mit Takt 1, Schlag 1.
  m.start();
  t = run(m, 1000);
  CHECK(!t.empty() && t[0].frame == 0 && t[0].bar == 1 && t[0].beat == 0);
}

void beatsAreSampleExactWithoutDrift() { // #3/AK9
  for (int sub : {1, 3, 4}) {
    Metronome m(44100);
    m.setSubdivision(sub);
    m.start();
    const long long frames = 44100LL * 300; // 5 Minuten
    auto t = run(m, frames, 512);
    long long beats = 0;
    bool ok = true;
    for (auto &k : t) {
      if (k.sub != 0)
        continue;
      ok = ok && k.frame == beats * 22050; // 0,5 s bei 120 BPM
      ++beats;
    }
    std::printf("  subdivision %d: %lld beats, %zu clicks\n", sub, beats, t.size());
    CHECK(ok);
    CHECK(beats == 600);
    CHECK(static_cast<long long>(t.size()) == 600 * sub);
  }
}

void accentsPerMeter() { // #3/AK6, AK7
  struct Case {
    int meter;
    std::vector<int> kinds;
  };
  const std::vector<Case> cases = {
      {4, {0, 2, 2, 2}},
      {3, {0, 2, 2}},
      {2, {0, 2}},
      {6, {0, 2, 2, 1, 2, 2}},
  };
  for (auto &c : cases) {
    Metronome m(44100);
    m.setMeter(c.meter);
    m.start();
    auto t = run(m, 44100LL * 60 / 120 * c.meter * 2); // zwei Takte
    bool ok = t.size() >= c.kinds.size() * 2;
    for (size_t i = 0; ok && i < c.kinds.size() * 2; ++i)
      ok = t[i].kind == c.kinds[i % c.kinds.size()];
    CHECK(ok);
  }
  Metronome m;
  m.setMeter(5); // ungültig: bleibt 4/4
  CHECK(m.meter() == 4);
}

void subdivisionsAndQuieterSubClicks() { // #3/AK8
  for (int sub = 1; sub <= 4; ++sub) {
    Metronome m(44100);
    m.setSubdivision(sub);
    m.start();
    auto t = run(m, 22050); // ein Schlag
    CHECK(static_cast<int>(t.size()) == sub);
    for (size_t i = 1; i < t.size(); ++i)
      CHECK(t[i].kind == Metronome::Sub);
  }
  // Pegel: Spitze des Zwischenklicks kleiner als die des Schlags (Schlag 2, nicht betont).
  Metronome m(44100);
  m.setSubdivision(2);
  m.start();
  auto out = render(m, 44100);
  auto peak = [&](long long from) {
    float p = 0;
    for (long long i = from; i < from + 2205; ++i)
      p = std::max(p, std::fabs(out[i * 2]));
    return p;
  };
  const float beat = peak(22050), sub = peak(22050 + 11025);
  std::printf("  peak beat %.3f, subdivision %.3f\n", beat, sub);
  CHECK(sub < beat * 0.8f);
  CHECK(beat > 0.1f);
}

void meterChangeWhilePlaying() { // #3/AK10
  Metronome m(44100);
  m.start();
  auto t = run(m, 22050 * 3 + 100); // Schläge 1–3 gespielt, nächster wäre Schlag 4
  CHECK(t.size() == 4 && t.back().beat == 3);
  m.setMeter(3); // Schlag 4 liegt ausserhalb von 3/4 -> weiter mit Schlag 1
  t = run(m, 22050 * 2);
  CHECK(!t.empty() && t[0].beat == 0 && t[0].kind == Metronome::Accent);
  // Unterteilung wirkt sofort.
  m.setSubdivision(4);
  t = run(m, 22050);
  CHECK(t.size() == 4);
}

// #3/AK10, found by #9: a subdivision change re-plans the next click within the beat of the last
// click. Before the fix it counted from the beat after it and skipped a beat (the accent of the
// next bar came as a plain beat).
void subdivisionChangeKeepsBeat() {
  // Between beats: beats 1 and 2 at 0 and 22 050 played, the next tick (beat 3) is due at 44 100.
  // Eighths from there on: beat 3 at 44 100, its eighth at 55 125, beat 4 at 66 150, then the
  // accent of bar 2 at 88 200.
  {
    Metronome m(44100);
    m.start();
    auto t = run(m, 44100);
    CHECK(t.size() == 2);
    m.setSubdivision(2);
    t = run(m, 44100 + 1);
    CHECK(t.size() == 5);
    if (t.size() == 5) {
      CHECK(t[0].frame == 44100 && t[0].beat == 2 && t[0].sub == 0);
      CHECK(t[1].frame == 55125 && t[1].beat == 2 && t[1].sub == 1);
      CHECK(t[2].frame == 66150 && t[2].beat == 3 && t[2].sub == 0);
      CHECK(t[4].frame == 88200 && t[4].beat == 0 && t[4].kind == Metronome::Accent);
    }
  }
  // Within a beat: 100 frames after beat 2 (22 050). Its eighth follows at 22 050 + 11 025 =
  // 33 075 and still belongs to beat 2; beat 3 at 44 100.
  {
    Metronome m(44100);
    m.start();
    auto t = run(m, 22050 + 100);
    m.setSubdivision(2);
    t = run(m, 22050);
    CHECK(t.size() == 2);
    if (t.size() == 2) {
      CHECK(t[0].frame == 33075 && t[0].beat == 1 && t[0].sub == 1 && t[0].kind == Metronome::Sub);
      CHECK(t[1].frame == 44100 && t[1].beat == 2 && t[1].sub == 0);
    }
  }
}

// #70/AK3: meter and subdivision change together within beat 4 of 4/4, to 3/4 triplets. Beat 4
// lies outside 3/4: its triplets still belong to beat 4 of bar 1, the next beat (88 200) is the
// accent of bar 2. Before the fix the triplets counted as beat 1 and bar 2 had no accent.
void meterAndSubdivisionChangeMidBeat() {
  Metronome m(44100);
  m.setSubdivision(2);
  m.start();
  auto t = run(m, 66150 + 2000);
  CHECK(!t.empty() && t.back().frame == 66150 && t.back().beat == 3);
  m.setMeter(3);
  m.setSubdivision(3);
  t = run(m, 88200 + 22050 - 68150 + 1);
  CHECK(t.size() == 6);
  if (t.size() == 6) {
    CHECK(t[0].frame == 73500 && t[0].bar == 1 && t[0].beat == 3 && t[0].kind == Metronome::Sub);
    CHECK(t[1].frame == 80850 && t[1].bar == 1 && t[1].beat == 3 && t[1].kind == Metronome::Sub);
    CHECK(t[2].frame == 88200 && t[2].bar == 2 && t[2].beat == 0 && t[2].kind == Metronome::Accent);
    CHECK(t[5].frame == 110250 && t[5].bar == 2 && t[5].beat == 1 && t[5].kind == Metronome::Beat);
  }
}

void volumeChangeWithoutCrackle() { // #3/AK12
  Metronome m(44100);
  m.start();
  std::vector<float> out(44100 * 2, 0.0f);
  m.renderAdd(out.data(), 100, 2); // mitten im ersten Klick
  m.setVolume(0.0f);
  m.renderAdd(out.data() + 200, 44100 - 100, 2);
  float maxStep = 0;
  for (int i = 1; i < 2000; ++i)
    maxStep = std::max(maxStep, std::fabs(out[i * 2] - out[(i - 1) * 2]));
  std::printf("  largest step between samples: %.4f\n", maxStep);
  CHECK(maxStep < 0.25f); // Klick bei 1600 Hz hat Steigung ~0,16 pro Sample
  float tail = 0;
  for (int i = 4410; i < 44100; ++i)
    tail = std::max(tail, std::fabs(out[i * 2]));
  CHECK(tail == 0.0f); // danach Stille, Metronom läuft aber weiter
  CHECK(m.running());
  m.setVolume(2.0f);
  CHECK(m.volume() == 1.0f);
  m.setVolume(std::nanf("")); // #10/AK4, found by fuzz_capi: NaN is silence, not NaN samples
  CHECK(m.volume() == 0.0f);
}

void rampExampleFromIssue() { // #3/AK16
  Metronome m(44100);
  m.setRamp(true, 145, 150, 5, 4);
  CHECK(m.bpm() == 145); // AK14: Einschalten im Stand setzt Start-BPM
  m.start();
  auto t = run(m, 44100LL * 60);
  CHECK(bpmOfBar(t, 1) == 145);
  CHECK(bpmOfBar(t, 4) == 145);
  CHECK(bpmOfBar(t, 5) == 150);
  CHECK(bpmOfBar(t, 8) == 150);
  CHECK(bpmOfBar(t, 9) == 145);
  CHECK(bpmOfBar(t, 13) == 150);
}

void rampDoesNotOvershootAndLoops() { // #3/AK15, AK16
  Metronome m(44100);
  m.setRamp(true, 100, 150, 20, 1);
  m.start();
  auto t = run(m, 44100LL * 20);
  const int expected[] = {100, 120, 140, 150, 100, 120};
  for (int bar = 1; bar <= 6; ++bar)
    CHECK(bpmOfBar(t, bar) == expected[bar - 1]);
}

void rampDescendingAndHold() { // #3/AK17
  Metronome m(44100);
  m.setRamp(true, 150, 140, 5, 2);
  m.start();
  auto t = run(m, 44100LL * 30);
  const int expected[] = {150, 150, 145, 145, 140, 140, 150};
  for (int bar = 1; bar <= 7; ++bar)
    CHECK(bpmOfBar(t, bar) == expected[bar - 1]);

  Metronome hold(44100);
  hold.setRamp(true, 90, 90, 5, 1);
  hold.start();
  t = run(hold, 44100LL * 20);
  bool ok = true;
  for (auto &k : t)
    ok = ok && k.bpm == 90;
  CHECK(ok);
}

void rampStartResetsAndOffKeepsTempo() { // #3/AK14, AK18
  Metronome m(44100);
  m.setRamp(true, 100, 200, 10, 1);
  m.start();
  run(m, 44100LL * 10); // einige Takte gesteigert
  const int reached = m.bpm();
  CHECK(reached > 100);
  m.setRamp(false, 100, 200, 10, 1); // ausschalten während des Spielens
  run(m, 44100LL * 10);
  CHECK(m.bpm() == reached);
  m.setRamp(true, 100, 200, 10, 1);
  m.stop();
  m.start(); // jeder Start setzt auf Start-BPM
  auto t = run(m, 1000);
  CHECK(!t.empty() && t[0].bpm == 100);
}

void rampWithSixEightAndSubdivision() { // #3/AK19
  Metronome m(44100);
  m.setMeter(6);
  m.setSubdivision(3);
  m.setRamp(true, 120, 130, 10, 1);
  m.start();
  auto t = run(m, 44100LL * 10);
  CHECK(bpmOfBar(t, 1) == 120);
  CHECK(bpmOfBar(t, 2) == 130);
  CHECK(bpmOfBar(t, 3) == 120);
  // Tempowechsel nur an Taktgrenzen: innerhalb eines Takts gleiches Tempo.
  bool ok = true;
  for (auto &k : t)
    ok = ok && k.bpm == bpmOfBar(t, k.bar);
  CHECK(ok);
  CHECK(firstBarWithBpm(t, 130) == 2);
}

// ---- #23 Steigerung nach Zeit ----

struct BarStart {
  double seconds;
  int bpm;
};

std::vector<BarStart> barStarts(const Ticks &t, int rate) {
  std::vector<BarStart> out;
  for (auto &k : t)
    if (k.beat == 0 && k.sub == 0)
      out.push_back({static_cast<double>(k.frame) / rate, k.bpm});
  return out;
}

// Jede Stufe k (Tempo start ± k) beginnt am ersten Taktanfang ab ihrem Idealzeitpunkt round0 + k ·
// Dauer/n, also höchstens einen Takt danach.
bool stepsWithinOneBar(const std::vector<BarStart> &bars, int start, int target, double seconds,
                       double round0) {
  const int n = std::abs(target - start);
  const int dir = target >= start ? 1 : -1;
  for (int k = 1; k <= n; ++k) {
    const double ideal = round0 + k * seconds / n;
    size_t i = 0;
    while (i < bars.size() && bars[i].bpm != start + dir * k)
      ++i;
    if (i == 0 || i == bars.size())
      return false;
    const double barLen = bars[i].seconds - bars[i - 1].seconds;
    if (bars[i].seconds < ideal - 1e-6 || bars[i].seconds - ideal > barLen + 1e-6) {
      std::printf("  step %d: %.3f s instead of %.3f s\n", k, bars[i].seconds, ideal);
      return false;
    }
  }
  return true;
}

void timedRampExampleFromIssue() { // #23/AK5, AK6
  const int rate = 44100;
  Metronome m(rate);
  m.setTimedRamp(true, 100, 110, 60);
  CHECK(m.rampTimed());
  CHECK(m.bpm() == 100); // Einschalten im Stand: Start-BPM wie bei Takten
  m.start();
  auto t = run(m, rate * 64LL);
  auto bars = barStarts(t, rate);
  // Nur 1-BPM-Schritte aufwärts, 10 Wechsel bis 110.
  int changes = 0;
  bool ok = true;
  for (size_t i = 1; i < bars.size(); ++i) {
    if (bars[i].bpm == bars[i - 1].bpm)
      continue;
    ++changes;
    ok = ok && bars[i].bpm == bars[i - 1].bpm + 1;
  }
  CHECK(ok);
  CHECK(changes == 10);
  // Etwa alle 6 s, je höchstens einen Takt nach dem Idealzeitpunkt; 110 nach etwa 60 s.
  CHECK(stepsWithinOneBar(bars, 100, 110, 60, 0));
  // AK6: Tempo wechselt nur am Taktanfang.
  bool sameInBar = true;
  for (auto &k : t)
    sameInBar = sameInBar && k.bpm == bpmOfBar(t, k.bar);
  CHECK(sameInBar);
}

void timedRampLoops() { // #23/AK7
  const int rate = 44100;
  Metronome m(rate);
  m.setTimedRamp(true, 100, 110, 60);
  m.start();
  auto bars = barStarts(run(m, rate * 140LL), rate);
  // Nach dem Ziel (eine Stufe lang, 6 s) zurück auf 100, dann läuft die Steigerung erneut.
  size_t reset = 0;
  for (size_t i = 1; i < bars.size(); ++i)
    if (bars[i - 1].bpm == 110 && bars[i].bpm == 100) {
      reset = i;
      break;
    }
  CHECK(reset > 0);
  if (reset > 0) {
    CHECK(bars[reset].seconds >= 66.0 - 1e-6);
    CHECK(bars[reset].seconds - 66.0 < bars[reset].seconds - bars[reset - 1].seconds + 1e-6);
    std::vector<BarStart> second(bars.begin() + static_cast<long>(reset), bars.end());
    CHECK(stepsWithinOneBar(second, 100, 110, 60, 66.0));
  }
}

void timedRampDescending() { // #23/AK8
  const int rate = 44100;
  Metronome m(rate);
  m.setTimedRamp(true, 120, 100, 60);
  m.start();
  auto bars = barStarts(run(m, rate * 70LL), rate);
  // Bis zum Rücksprung nur 1-BPM-Schritte abwärts bis 100, dann wieder 120.
  size_t i = 1;
  bool ok = true;
  for (; i < bars.size() && bars[i].bpm <= bars[i - 1].bpm; ++i)
    if (bars[i].bpm != bars[i - 1].bpm)
      ok = ok && bars[i].bpm == bars[i - 1].bpm - 1;
  CHECK(ok);
  CHECK(i < bars.size() && bars[i - 1].bpm == 100 && bars[i].bpm == 120);
  CHECK(stepsWithinOneBar(bars, 120, 100, 60, 0));
}

void timedRampStartEqualsTarget() { // #23/AK9
  Metronome m(44100);
  m.setTimedRamp(true, 90, 90, 60);
  m.start();
  auto t = run(m, 44100LL * 130);
  bool ok = !t.empty();
  for (auto &k : t)
    ok = ok && k.bpm == 90;
  CHECK(ok);
}

void timedRampFastStepsStayWithinOneBar() { // #23/AK6 bei kurzen Stufen (mehr als eine pro Takt)
  const int rate = 48000;
  Metronome m(rate);
  m.setTimedRamp(true, 60, 300, 60); // Stufe alle 0,25 s, Takt 0,8–4 s
  m.start();
  auto t = run(m, rate * 60LL, 480); // eine Runde dauert 60,25 s (240 Stufen + Ziel halten)
  auto bars = barStarts(t, rate);
  // An jedem Taktanfang gilt die zuletzt fällige Stufe (übersprungene inklusive).
  bool ok = bars.size() > 30;
  for (auto &b : bars)
    ok = ok && b.bpm == 60 + static_cast<int>(std::floor(b.seconds / 0.25 + 1e-9));
  CHECK(ok);
}

void switchingModes() { // #23/AK1, AK2: Takte bleibt wie bisher, Wechsel der Art während des
                        // Spielens
  Metronome m(44100);
  m.setTimedRamp(true, 100, 150, 600);
  m.setRamp(true, 100, 150, 20, 1); // zurück auf Takte
  CHECK(!m.rampTimed());
  m.start();
  auto t = run(m, 44100LL * 20);
  const int expected[] = {100, 120, 140, 150, 100, 120};
  for (int bar = 1; bar <= 6; ++bar)
    CHECK(bpmOfBar(t, bar) == expected[bar - 1]);

  // Während des Spielens auf Zeit: weiter vom laufenden Tempo aus, nächste Stufe nach Dauer/n.
  Metronome z(44100);
  z.setRamp(true, 100, 200, 10, 1);
  z.start();
  run(z, 44100LL * 5);
  const int cur = z.bpm();
  CHECK(cur > 100 && cur < 200);
  z.setTimedRamp(true, 100, 200, 100); // 1 BPM pro Sekunde
  auto bars = barStarts(run(z, 44100LL * 10), 44100);
  bool ok = bars.size() >= 3;
  for (auto &b : bars)
    ok = ok && b.bpm == cur + static_cast<int>(std::floor(b.seconds - 5.0));
  CHECK(ok);
}

// ---------------------------------------------------------------------------
// #11: cases found by mutation testing (make mutants).

// One click by the rules of metronome.cpp: sine of its sound (accent 1600 Hz, level 1.0), rising
// linearly over 1 ms (44.1 frames: factor (n + 1) / 44.1 up to 1), decaying with a time constant
// of 12 ms (exp(-n / 529.2)), over after 50 ms (2205 frames), times the volume (0.7). renderAdd
// adds it to what is in the buffer (here 0.25 in both channels).
double expectedClick(int n) {
  constexpr double kPi = 3.14159265358979323846;
  if (n >= 2205)
    return 0.0;
  const double env = std::min(1.0, (n + 1) / 44.1) * std::exp(-n / 529.2);
  return 0.7 * 1.0 * env * std::sin(2 * kPi * 1600.0 * n / 44100.0);
}

void clickShapeFollowsTheRules() {
  Metronome m(44100);
  m.start();
  std::vector<float> out(4410 * 2, 0.25f);
  m.renderAdd(out.data(), 4410, 2);
  double worst = 0;
  for (int n = 0; n < 4410; ++n)
    for (int c = 0; c < 2; ++c)
      worst = std::max(worst, std::fabs(double(out[2 * n + c]) - 0.25 - expectedClick(n)));
  std::printf("  largest difference to the rule: %.2g\n", worst);
  CHECK(worst < 1e-5);
  // checks of the rule itself: rising for 1 ms, then falling, silent from frame 2205 on
  CHECK(std::fabs(expectedClick(11)) < std::fabs(expectedClick(11 + 28))); // 1600 Hz: period 27.56
  CHECK(out[2 * 2204] != 0.25f && out[2 * 2205] == 0.25f);
}

// A restart while clicks still ring lets them ring out under the new click (stop lets running
// clicks ring out, #3): five starts 5 ms (220 frames) apart give the sum of the clicks started so
// far. Four voices sound at most, the fifth start takes the oldest one: from then on the first
// click is gone.
void restartsLetRingingClicksRingOut() {
  Metronome m(44100);
  constexpr int r = 220;
  std::vector<float> out(4410 * 2, 0.0f);
  for (int k = 0; k < 5; ++k) {
    m.start();
    m.renderAdd(out.data() + static_cast<size_t>(k) * r * 2, k < 4 ? r : 4410 - 4 * r, 2);
  }
  double worst = 0;
  for (int n = 0; n < 4410; ++n) {
    double expected = 0;
    for (int k = 0; k < 5; ++k)
      if (n >= k * r && !(k == 0 && n >= 4 * r)) // the first click ends at the fifth start
        expected += expectedClick(n - k * r);
    worst = std::max(worst, std::fabs(double(out[2 * n]) - expected));
  }
  std::printf("  largest difference to the sum of the clicks: %.2g\n", worst);
  CHECK(worst < 1e-5);
}

// Stop ends the clicks (running clicks ring out) and reports «not running»: started, 0.6 s played
// (beats at 0 and 0.5 s), stopped: no click in the next 2 s, and after 50 ms silence.
void stopEndsTheClicks() {
  Metronome m(44100);
  m.start();
  CHECK(m.running());
  CHECK(run(m, 26460).size() == 2);
  m.stop();
  CHECK(!m.running());
  std::vector<Metronome::Tick> log;
  m.tickLog = &log;
  auto out = render(m, 88200);
  m.tickLog = nullptr;
  CHECK(log.empty());
  float tail = 0;
  for (size_t i = 2 * 2205; i < out.size(); ++i)
    tail = std::max(tail, std::fabs(out[i]));
  CHECK(tail == 0.0f);
}

// The bpm of the first bar that starts at or after `seconds`, or -1.
int bpmOfFirstBarFrom(const std::vector<BarStart> &bars, double seconds) {
  for (auto &b : bars)
    if (b.seconds >= seconds - 1e-9)
      return b.bpm;
  return -1;
}

// Timed ramp 100 → 200 over 100 s: one BPM per second, at every bar the tempo is 100 + whole
// seconds since the round began (#23/AK5). Setting the same values again while it runs changes
// nothing; a new duration (50 s: a step every 0.5 s) starts the round anew from the running tempo
// (#23/AK2): bpm = running tempo + whole half seconds since the change.
void timedRampSameValuesAgainAndNewDuration() {
  const int rate = 44100;
  Metronome m(rate);
  m.setTimedRamp(true, 100, 200, 100);
  m.start();
  run(m, rate * 5LL + rate / 2); // 5.5 s
  m.setTimedRamp(true, 100, 200, 100);
  auto bars = barStarts(run(m, rate * 10LL), rate);
  bool ok = bars.size() >= 3;
  for (auto &b : bars)
    ok = ok && b.bpm == 100 + static_cast<int>(std::floor(b.seconds + 1e-9));
  CHECK(ok);

  Metronome n(rate);
  n.setTimedRamp(true, 100, 200, 100);
  n.start();
  run(n, rate * 5LL + rate / 2);
  const int cur = n.bpm();
  CHECK(cur == 104); // the bar at 4.8 s (bars of 2.4 s at 100 .. 102 BPM) took 104
  n.setTimedRamp(true, 100, 200, 50);
  bars = barStarts(run(n, rate * 10LL), rate);
  ok = bars.size() >= 3;
  for (auto &b : bars)
    ok = ok && b.bpm == cur + static_cast<int>(std::floor((b.seconds - 5.5) / 0.5 + 1e-9));
  CHECK(ok);
}

// Switching from bars to time while playing starts the round anew from the running tempo, also if
// start, target and duration stay as they were (#23/AK2): bars 100 → 200 in steps of 10 per bar,
// then time 100 → 200 over 240 s (the stored duration): 2.4 s per step from the running tempo.
void switchToTimedWithStoredValuesStartsAnew() {
  const int rate = 44100;
  Metronome m(rate);
  m.setTimedRamp(true, 100, 200, 240);
  m.setRamp(true, 100, 200, 10, 1);
  m.start();
  run(m, rate * 5LL);
  const int cur = m.bpm();
  CHECK(cur > 110 && cur < 200);
  m.setTimedRamp(true, 100, 200, 240);
  auto bars = barStarts(run(m, rate * 10LL), rate);
  bool ok = bars.size() >= 3;
  for (auto &b : bars)
    ok = ok && b.bpm == cur + static_cast<int>(std::floor((b.seconds - 5.0) / 2.4 + 1e-9));
  CHECK(ok);
}

// A round that starts anew in the middle still ends with the return to the start: timed ramp 100 →
// 110 over 20 s (2 s per step, the target held for one step), started anew at 2 s with the running
// tempo 105 (from a bars ramp in steps of 5): 105 counts as reached, 110 is reached 10 s later,
// held 2 s, then 100 again, 12 s after the change at the latest one bar later. The rounds after
// that last 22 s each (11 steps of 2 s): two more returns to 100.
void restartedRoundReturnsToStart() {
  const int rate = 44100;
  Metronome m(rate);
  m.setRamp(true, 100, 110, 5, 1);
  m.start();
  run(m, rate * 2LL); // bar 1 at 100, bar 2 at 2.4 s would take 105: still 100 here
  CHECK(m.bpm() == 100);
  run(m, rate / 2); // 2.5 s: bar 2 at 2.4 s took 105
  CHECK(m.bpm() == 105);
  m.setTimedRamp(true, 100, 110, 20);
  auto bars = barStarts(run(m, rate * 70LL), rate);
  std::vector<double> returns;
  for (size_t i = 1; i < bars.size(); ++i)
    if (bars[i].bpm < bars[i - 1].bpm) // 110 → 100, or 101 if the bar skipped the step of 100
      returns.push_back(bars[i].seconds);
  CHECK(returns.size() >= 3);
  if (returns.size() >= 3) {
    // ideal times 2.5 + 12 = 14.5 s, then every 22 s: 36.5 s, 58.5 s; a bar at 110 BPM is 2.18 s
    const double ideal[3] = {14.5, 36.5, 58.5};
    for (int i = 0; i < 3; ++i) {
      std::printf("  return %d at %.2f s (ideal %.2f s)\n", i + 1, returns[i], ideal[i]);
      CHECK(returns[i] >= ideal[i] - 1e-6 && returns[i] < ideal[i] + 2.2);
    }
  }
}

// Starting the round anew counts the running tempo as reached only if it lies between start and
// target (both included); outside it starts from the start. Timed ramp 100 → 110 over 30 s (3 s per
// step); the tempo set by hand to 90 or 150 → the next bar plays 100; at the target 110 → the next
// bar still plays 110 (the held step).
void restartWithTempoOutsideTheRange() {
  const int rate = 44100;
  for (const auto &[bpm, expected] : {std::pair{90, 100}, {150, 100}, {110, 110}, {105, 105}}) {
    Metronome m(rate);
    m.setTimedRamp(true, 100, 110, 60);
    m.start();
    run(m, rate);
    m.setBpm(bpm);
    m.setTimedRamp(true, 100, 110, 30); // new duration: the round starts anew
    auto bars = barStarts(run(m, rate * 6LL), rate);
    const int next = bpmOfFirstBarFrom(bars, 1.0);
    std::printf("  tempo %d: next bar %d (expected %d)\n", bpm, next, expected);
    CHECK(next == expected);
  }
}

// Bars ramp with start = target and the tempo set by hand above it: it moves to the target in steps
// (120 → 115 → 110 …), like any ramp, and then holds it.
void rampWithStartEqualTargetMovesInSteps() {
  Metronome m(44100);
  m.setRamp(true, 100, 100, 5, 1);
  m.start(); // with a ramp the start plays the start BPM; then set by hand
  auto t = run(m, 100);
  m.setBpm(120);
  t = run(m, 44100LL * 14);
  CHECK(bpmOfBar(t, 2) == 115);
  CHECK(bpmOfBar(t, 3) == 110);
  CHECK(bpmOfBar(t, 4) == 105);
  CHECK(bpmOfBar(t, 5) == 100);
  CHECK(bpmOfBar(t, 6) == 100);
}

// Subdivision changes within a beat: from 1 to 4 clicks, 12'000 frames after beat 2 (22'050):
// sixteenths of 5512.5 frames, the next is the fourth sixteenth of beat 2 (k = floor(12'000 /
// 5512.5) + 1 = 3) at 22'050 + 3 · 5512.5 = 38'587.5 (frame 38'588), then beat 3 at 44'100.
// From 4 to 2 clicks between the third and the fourth sixteenth (14'000 frames after beat 2; the
// third came at 11'025, the fourth would come at 16'537.5): the next eighth would be the third of
// two (k = floor(14'000 / 11'025) + 1 = 2), so the next click is beat 3 at 44'100.
void subdivisionChangeLateInTheBeat() {
  {
    Metronome m(44100);
    m.start();
    run(m, 22050 + 12000);
    m.setSubdivision(4);
    auto t = run(m, 22050);
    CHECK(t.size() >= 2);
    if (t.size() >= 2) {
      CHECK(t[0].frame == 38588 && t[0].beat == 1 && t[0].sub == 3 && t[0].kind == Metronome::Sub);
      CHECK(t[1].frame == 44100 && t[1].beat == 2 && t[1].sub == 0);
    }
  }
  {
    Metronome m(44100);
    m.setSubdivision(4);
    m.start();
    run(m, 22050 + 14000);
    m.setSubdivision(2);
    auto t = run(m, 22050);
    CHECK(!t.empty());
    if (!t.empty())
      CHECK(t[0].frame == 44100 && t[0].beat == 2 && t[0].sub == 0 && t[0].kind == Metronome::Beat);
  }
}

// A shorter meter with the next beat outside it goes on with beat 1: beats 1–3 of 4/4 played, the
// next would be beat 4; switched to 3/4 the next click is the accent of the next bar.
void meterChangeWithNextBeatOutside() {
  Metronome m(44100);
  m.start();
  auto t = run(m, 22050 * 2 + 100);
  CHECK(t.size() == 3);
  m.setMeter(3);
  t = run(m, 22050);
  CHECK(!t.empty() && t[0].beat == 0 && t[0].kind == Metronome::Accent && t[0].bar == 2);
}

} // namespace

int main() {
  const std::vector<std::pair<std::string, std::function<void()>>> tests = {
      {"defaults", defaults},
      {"bpmRangeIsClamped", bpmRangeIsClamped},
      {"startBeginsWithBarOneBeatOne", startBeginsWithBarOneBeatOne},
      {"beatsAreSampleExactWithoutDrift", beatsAreSampleExactWithoutDrift},
      {"accentsPerMeter", accentsPerMeter},
      {"subdivisionsAndQuieterSubClicks", subdivisionsAndQuieterSubClicks},
      {"subdivisionChangeKeepsBeat", subdivisionChangeKeepsBeat},
      {"meterAndSubdivisionChangeMidBeat", meterAndSubdivisionChangeMidBeat},
      {"meterChangeWhilePlaying", meterChangeWhilePlaying},
      {"volumeChangeWithoutCrackle", volumeChangeWithoutCrackle},
      {"rampExampleFromIssue", rampExampleFromIssue},
      {"rampDoesNotOvershootAndLoops", rampDoesNotOvershootAndLoops},
      {"rampDescendingAndHold", rampDescendingAndHold},
      {"rampStartResetsAndOffKeepsTempo", rampStartResetsAndOffKeepsTempo},
      {"rampWithSixEightAndSubdivision", rampWithSixEightAndSubdivision},
      {"timedRampExampleFromIssue", timedRampExampleFromIssue},
      {"timedRampLoops", timedRampLoops},
      {"timedRampDescending", timedRampDescending},
      {"timedRampStartEqualsTarget", timedRampStartEqualsTarget},
      {"timedRampFastStepsStayWithinOneBar", timedRampFastStepsStayWithinOneBar},
      {"switchingModes", switchingModes},
      {"clickShapeFollowsTheRules", clickShapeFollowsTheRules},
      {"restartsLetRingingClicksRingOut", restartsLetRingingClicksRingOut},
      {"timedRampSameValuesAgainAndNewDuration", timedRampSameValuesAgainAndNewDuration},
      {"switchToTimedWithStoredValuesStartsAnew", switchToTimedWithStoredValuesStartsAnew},
      {"restartedRoundReturnsToStart", restartedRoundReturnsToStart},
      {"restartWithTempoOutsideTheRange", restartWithTempoOutsideTheRange},
      {"rampWithStartEqualTargetMovesInSteps", rampWithStartEqualTargetMovesInSteps},
      {"subdivisionChangeLateInTheBeat", subdivisionChangeLateInTheBeat},
      {"meterChangeWithNextBeatOutside", meterChangeWithNextBeatOutside},
      {"stopEndsTheClicks", stopEndsTheClicks},
  };
  for (auto &[name, fn] : tests) {
    const int before = failures;
    fn();
    std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name.c_str());
  }
  std::printf("%d checks, %d failures\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
