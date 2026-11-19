// Tests des Metronoms (#3, #23) im Offline-Rendering. AKn = n-tes Abnahmekriterium im jeweiligen Issue.
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

#include "metronome.hpp"

namespace {

int failures = 0;
int checks = 0;

#define CHECK(cond)                                                         \
    do {                                                                    \
        ++checks;                                                           \
        if (!(cond)) {                                                      \
            ++failures;                                                     \
            std::printf("  FAILED %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        }                                                                   \
    } while (0)

using wp::Metronome;
using Ticks = std::vector<Metronome::Tick>;

// Rendert `frames` Frames in Blöcken und gibt die Ausgabe (Stereo) zurück.
std::vector<float> render(Metronome& m, long long frames, int block = 512) {
    std::vector<float> out(static_cast<size_t>(frames) * 2, 0.0f);
    for (long long done = 0; done < frames;) {
        const int n = static_cast<int>(std::min<long long>(block, frames - done));
        m.renderAdd(out.data() + done * 2, n, 2);
        done += n;
    }
    return out;
}

Ticks run(Metronome& m, long long frames, int block = 512) {
    Ticks log;
    m.tickLog = &log;
    render(m, frames, block);
    m.tickLog = nullptr;
    return log;
}

// Takte (ab 1) bis zum ersten Klick mit Tempo `bpm`.
int firstBarWithBpm(const Ticks& t, int bpm, int fromBar = 1) {
    for (auto& k : t)
        if (k.bar >= fromBar && k.sub == 0 && k.beat == 0 && k.bpm == bpm) return k.bar;
    return -1;
}

int bpmOfBar(const Ticks& t, int bar) {
    for (auto& k : t)
        if (k.bar == bar && k.beat == 0 && k.sub == 0) return k.bpm;
    return -1;
}

// ---------------------------------------------------------------------------

void defaults() {  // #3/AK1
    Metronome m(44100);
    CHECK(m.bpm() == 120);
    CHECK(m.meter() == 4);
    CHECK(m.subdivision() == 1);
    CHECK(std::fabs(m.volume() - 0.7f) < 1e-6f);
    CHECK(!m.running());
    CHECK(run(m, 44100).empty());  // gestoppt: keine Klicks
}

void bpmRangeIsClamped() {  // #3/AK2
    Metronome m;
    m.setBpm(10);
    CHECK(m.bpm() == 20);
    m.setBpm(400);
    CHECK(m.bpm() == 300);
    m.setBpm(73);
    CHECK(m.bpm() == 73);
}

void startBeginsWithBarOneBeatOne() {  // #3/AK11
    Metronome m(44100);
    m.start();
    auto t = run(m, 44100 * 3, 333);
    CHECK(!t.empty() && t[0].frame == 0 && t[0].bar == 1 && t[0].beat == 0 && t[0].kind == Metronome::Accent);
    // Erneuter Start mitten im Takt beginnt wieder mit Takt 1, Schlag 1.
    m.start();
    t = run(m, 1000);
    CHECK(!t.empty() && t[0].frame == 0 && t[0].bar == 1 && t[0].beat == 0);
}

void beatsAreSampleExactWithoutDrift() {  // #3/AK9
    for (int sub : {1, 3, 4}) {
        Metronome m(44100);
        m.setSubdivision(sub);
        m.start();
        const long long frames = 44100LL * 300;  // 5 Minuten
        auto t = run(m, frames, 512);
        long long beats = 0;
        bool ok = true;
        for (auto& k : t) {
            if (k.sub != 0) continue;
            ok = ok && k.frame == beats * 22050;  // 0,5 s bei 120 BPM
            ++beats;
        }
        std::printf("  subdivision %d: %lld beats, %zu clicks\n", sub, beats, t.size());
        CHECK(ok);
        CHECK(beats == 600);
        CHECK(static_cast<long long>(t.size()) == 600 * sub);
    }
}

void accentsPerMeter() {  // #3/AK6, AK7
    struct Case {
        int meter;
        std::vector<int> kinds;
    };
    const std::vector<Case> cases = {
        {4, {0, 2, 2, 2}}, {3, {0, 2, 2}}, {2, {0, 2}}, {6, {0, 2, 2, 1, 2, 2}},
    };
    for (auto& c : cases) {
        Metronome m(44100);
        m.setMeter(c.meter);
        m.start();
        auto t = run(m, 44100LL * 60 / 120 * c.meter * 2);  // zwei Takte
        bool ok = t.size() >= c.kinds.size() * 2;
        for (size_t i = 0; ok && i < c.kinds.size() * 2; ++i) ok = t[i].kind == c.kinds[i % c.kinds.size()];
        CHECK(ok);
    }
    Metronome m;
    m.setMeter(5);  // ungültig: bleibt 4/4
    CHECK(m.meter() == 4);
}

void subdivisionsAndQuieterSubClicks() {  // #3/AK8
    for (int sub = 1; sub <= 4; ++sub) {
        Metronome m(44100);
        m.setSubdivision(sub);
        m.start();
        auto t = run(m, 22050);  // ein Schlag
        CHECK(static_cast<int>(t.size()) == sub);
        for (size_t i = 1; i < t.size(); ++i) CHECK(t[i].kind == Metronome::Sub);
    }
    // Pegel: Spitze des Zwischenklicks kleiner als die des Schlags (Schlag 2, nicht betont).
    Metronome m(44100);
    m.setSubdivision(2);
    m.start();
    auto out = render(m, 44100);
    auto peak = [&](long long from) {
        float p = 0;
        for (long long i = from; i < from + 2205; ++i) p = std::max(p, std::fabs(out[i * 2]));
        return p;
    };
    const float beat = peak(22050), sub = peak(22050 + 11025);
    std::printf("  peak beat %.3f, subdivision %.3f\n", beat, sub);
    CHECK(sub < beat * 0.8f);
    CHECK(beat > 0.1f);
}

void meterChangeWhilePlaying() {  // #3/AK10
    Metronome m(44100);
    m.start();
    auto t = run(m, 22050 * 3 + 100);  // Schläge 1–3 gespielt, nächster wäre Schlag 4
    CHECK(t.size() == 4 && t.back().beat == 3);
    m.setMeter(3);  // Schlag 4 liegt ausserhalb von 3/4 -> weiter mit Schlag 1
    t = run(m, 22050 * 2);
    CHECK(!t.empty() && t[0].beat == 0 && t[0].kind == Metronome::Accent);
    // Unterteilung wirkt sofort.
    m.setSubdivision(4);
    t = run(m, 22050);
    CHECK(t.size() == 4);
}

void volumeChangeWithoutCrackle() {  // #3/AK12
    Metronome m(44100);
    m.start();
    std::vector<float> out(44100 * 2, 0.0f);
    m.renderAdd(out.data(), 100, 2);  // mitten im ersten Klick
    m.setVolume(0.0f);
    m.renderAdd(out.data() + 200, 44100 - 100, 2);
    float maxStep = 0;
    for (int i = 1; i < 2000; ++i) maxStep = std::max(maxStep, std::fabs(out[i * 2] - out[(i - 1) * 2]));
    std::printf("  largest step between samples: %.4f\n", maxStep);
    CHECK(maxStep < 0.25f);  // Klick bei 1600 Hz hat Steigung ~0,16 pro Sample
    float tail = 0;
    for (int i = 4410; i < 44100; ++i) tail = std::max(tail, std::fabs(out[i * 2]));
    CHECK(tail == 0.0f);  // danach Stille, Metronom läuft aber weiter
    CHECK(m.running());
    m.setVolume(2.0f);
    CHECK(m.volume() == 1.0f);
}

void rampExampleFromIssue() {  // #3/AK16
    Metronome m(44100);
    m.setRamp(true, 145, 150, 5, 4);
    CHECK(m.bpm() == 145);  // AK14: Einschalten im Stand setzt Start-BPM
    m.start();
    auto t = run(m, 44100LL * 60);
    CHECK(bpmOfBar(t, 1) == 145);
    CHECK(bpmOfBar(t, 4) == 145);
    CHECK(bpmOfBar(t, 5) == 150);
    CHECK(bpmOfBar(t, 8) == 150);
    CHECK(bpmOfBar(t, 9) == 145);
    CHECK(bpmOfBar(t, 13) == 150);
}

void rampDoesNotOvershootAndLoops() {  // #3/AK15, AK16
    Metronome m(44100);
    m.setRamp(true, 100, 150, 20, 1);
    m.start();
    auto t = run(m, 44100LL * 20);
    const int expected[] = {100, 120, 140, 150, 100, 120};
    for (int bar = 1; bar <= 6; ++bar) CHECK(bpmOfBar(t, bar) == expected[bar - 1]);
}

void rampDescendingAndHold() {  // #3/AK17
    Metronome m(44100);
    m.setRamp(true, 150, 140, 5, 2);
    m.start();
    auto t = run(m, 44100LL * 30);
    const int expected[] = {150, 150, 145, 145, 140, 140, 150};
    for (int bar = 1; bar <= 7; ++bar) CHECK(bpmOfBar(t, bar) == expected[bar - 1]);

    Metronome hold(44100);
    hold.setRamp(true, 90, 90, 5, 1);
    hold.start();
    t = run(hold, 44100LL * 20);
    bool ok = true;
    for (auto& k : t) ok = ok && k.bpm == 90;
    CHECK(ok);
}

void rampStartResetsAndOffKeepsTempo() {  // #3/AK14, AK18
    Metronome m(44100);
    m.setRamp(true, 100, 200, 10, 1);
    m.start();
    run(m, 44100LL * 10);  // einige Takte gesteigert
    const int reached = m.bpm();
    CHECK(reached > 100);
    m.setRamp(false, 100, 200, 10, 1);  // ausschalten während des Spielens
    run(m, 44100LL * 10);
    CHECK(m.bpm() == reached);
    m.setRamp(true, 100, 200, 10, 1);
    m.stop();
    m.start();  // jeder Start setzt auf Start-BPM
    auto t = run(m, 1000);
    CHECK(!t.empty() && t[0].bpm == 100);
}

void rampWithSixEightAndSubdivision() {  // #3/AK19
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
    for (auto& k : t) ok = ok && k.bpm == bpmOfBar(t, k.bar);
    CHECK(ok);
    CHECK(firstBarWithBpm(t, 130) == 2);
}


// ---- #23 Steigerung nach Zeit ----

struct BarStart {
    double seconds;
    int bpm;
};

std::vector<BarStart> barStarts(const Ticks& t, int rate) {
    std::vector<BarStart> out;
    for (auto& k : t)
        if (k.beat == 0 && k.sub == 0) out.push_back({static_cast<double>(k.frame) / rate, k.bpm});
    return out;
}

// Jede Stufe k (Tempo start ± k) beginnt am ersten Taktanfang ab ihrem Idealzeitpunkt round0 + k · Dauer/n,
// also höchstens einen Takt danach.
bool stepsWithinOneBar(const std::vector<BarStart>& bars, int start, int target, double seconds,
                       double round0) {
    const int n = std::abs(target - start);
    const int dir = target >= start ? 1 : -1;
    for (int k = 1; k <= n; ++k) {
        const double ideal = round0 + k * seconds / n;
        size_t i = 0;
        while (i < bars.size() && bars[i].bpm != start + dir * k) ++i;
        if (i == 0 || i == bars.size()) return false;
        const double barLen = bars[i].seconds - bars[i - 1].seconds;
        if (bars[i].seconds < ideal - 1e-6 || bars[i].seconds - ideal > barLen + 1e-6) {
            std::printf("  step %d: %.3f s instead of %.3f s\n", k, bars[i].seconds, ideal);
            return false;
        }
    }
    return true;
}

void timedRampExampleFromIssue() {  // #23/AK5, AK6
    const int rate = 44100;
    Metronome m(rate);
    m.setTimedRamp(true, 100, 110, 60);
    CHECK(m.rampTimed());
    CHECK(m.bpm() == 100);  // Einschalten im Stand: Start-BPM wie bei Takten
    m.start();
    auto t = run(m, rate * 64LL);
    auto bars = barStarts(t, rate);
    // Nur 1-BPM-Schritte aufwärts, 10 Wechsel bis 110.
    int changes = 0;
    bool ok = true;
    for (size_t i = 1; i < bars.size(); ++i) {
        if (bars[i].bpm == bars[i - 1].bpm) continue;
        ++changes;
        ok = ok && bars[i].bpm == bars[i - 1].bpm + 1;
    }
    CHECK(ok);
    CHECK(changes == 10);
    // Etwa alle 6 s, je höchstens einen Takt nach dem Idealzeitpunkt; 110 nach etwa 60 s.
    CHECK(stepsWithinOneBar(bars, 100, 110, 60, 0));
    // AK6: Tempo wechselt nur am Taktanfang.
    bool sameInBar = true;
    for (auto& k : t) sameInBar = sameInBar && k.bpm == bpmOfBar(t, k.bar);
    CHECK(sameInBar);
}

void timedRampLoops() {  // #23/AK7
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

void timedRampDescending() {  // #23/AK8
    const int rate = 44100;
    Metronome m(rate);
    m.setTimedRamp(true, 120, 100, 60);
    m.start();
    auto bars = barStarts(run(m, rate * 70LL), rate);
    // Bis zum Rücksprung nur 1-BPM-Schritte abwärts bis 100, dann wieder 120.
    size_t i = 1;
    bool ok = true;
    for (; i < bars.size() && bars[i].bpm <= bars[i - 1].bpm; ++i)
        if (bars[i].bpm != bars[i - 1].bpm) ok = ok && bars[i].bpm == bars[i - 1].bpm - 1;
    CHECK(ok);
    CHECK(i < bars.size() && bars[i - 1].bpm == 100 && bars[i].bpm == 120);
    CHECK(stepsWithinOneBar(bars, 120, 100, 60, 0));
}

void timedRampStartEqualsTarget() {  // #23/AK9
    Metronome m(44100);
    m.setTimedRamp(true, 90, 90, 60);
    m.start();
    auto t = run(m, 44100LL * 130);
    bool ok = !t.empty();
    for (auto& k : t) ok = ok && k.bpm == 90;
    CHECK(ok);
}

void timedRampFastStepsStayWithinOneBar() {  // #23/AK6 bei kurzen Stufen (mehr als eine pro Takt)
    const int rate = 48000;
    Metronome m(rate);
    m.setTimedRamp(true, 60, 300, 60);  // Stufe alle 0,25 s, Takt 0,8–4 s
    m.start();
    auto t = run(m, rate * 60LL, 480);  // eine Runde dauert 60,25 s (240 Stufen + Ziel halten)
    auto bars = barStarts(t, rate);
    // An jedem Taktanfang gilt die zuletzt fällige Stufe (übersprungene inklusive).
    bool ok = bars.size() > 30;
    for (auto& b : bars) ok = ok && b.bpm == 60 + static_cast<int>(std::floor(b.seconds / 0.25 + 1e-9));
    CHECK(ok);
}

void switchingModes() {  // #23/AK1, AK2: Takte bleibt wie bisher, Wechsel der Art während des Spielens
    Metronome m(44100);
    m.setTimedRamp(true, 100, 150, 600);
    m.setRamp(true, 100, 150, 20, 1);  // zurück auf Takte
    CHECK(!m.rampTimed());
    m.start();
    auto t = run(m, 44100LL * 20);
    const int expected[] = {100, 120, 140, 150, 100, 120};
    for (int bar = 1; bar <= 6; ++bar) CHECK(bpmOfBar(t, bar) == expected[bar - 1]);

    // Während des Spielens auf Zeit: weiter vom laufenden Tempo aus, nächste Stufe nach Dauer/n.
    Metronome z(44100);
    z.setRamp(true, 100, 200, 10, 1);
    z.start();
    run(z, 44100LL * 5);
    const int cur = z.bpm();
    CHECK(cur > 100 && cur < 200);
    z.setTimedRamp(true, 100, 200, 100);  // 1 BPM pro Sekunde
    auto bars = barStarts(run(z, 44100LL * 10), 44100);
    bool ok = bars.size() >= 3;
    for (auto& b : bars) ok = ok && b.bpm == cur + static_cast<int>(std::floor(b.seconds - 5.0));
    CHECK(ok);
}

}  // namespace

int main() {
    const std::vector<std::pair<std::string, std::function<void()>>> tests = {
        {"defaults", defaults},
        {"bpmRangeIsClamped", bpmRangeIsClamped},
        {"startBeginsWithBarOneBeatOne", startBeginsWithBarOneBeatOne},
        {"beatsAreSampleExactWithoutDrift", beatsAreSampleExactWithoutDrift},
        {"accentsPerMeter", accentsPerMeter},
        {"subdivisionsAndQuieterSubClicks", subdivisionsAndQuieterSubClicks},
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
    };
    for (auto& [name, fn] : tests) {
        const int before = failures;
        fn();
        std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name.c_str());
    }
    std::printf("%d checks, %d failures\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
