// Tests der Wiedergabe-Logik im Offline-Rendering (ohne Audiogerät). Testaudio wird erzeugt.
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

#include "engine.hpp"

namespace {

int failures = 0;
int checks = 0;

#define CHECK(cond)                                                              \
    do {                                                                         \
        ++checks;                                                                \
        if (!(cond)) {                                                           \
            ++failures;                                                          \
            std::printf("  FEHLER %s:%d: %s\n", __FILE__, __LINE__, #cond);      \
        }                                                                        \
    } while (0)

#define CHECK_NEAR(a, b, tol) CHECK(std::fabs((a) - (b)) <= (tol))

constexpr double kPi = 3.14159265358979323846;

// Rampe: Wert = Frame-Index (exakt darstellbar bis 2^24), gleich in beiden Kanälen.
std::vector<float> ramp(long long frames) {
    std::vector<float> v(static_cast<size_t>(frames) * 2);
    for (long long i = 0; i < frames; ++i) v[2 * i] = v[2 * i + 1] = static_cast<float>(i);
    return v;
}

std::vector<float> sine(double freq, double seconds, int sr, float amp = 0.5f) {
    const long long n = static_cast<long long>(seconds * sr);
    std::vector<float> v(static_cast<size_t>(n) * 2);
    for (long long i = 0; i < n; ++i) v[2 * i] = v[2 * i + 1] = amp * static_cast<float>(std::sin(2 * kPi * freq * i / sr));
    return v;
}

std::vector<float> renderFrames(wp::Engine& e, long long frames, int block = 512) {
    std::vector<float> out(static_cast<size_t>(frames) * e.channels());
    long long done = 0;
    while (done < frames) {
        const int n = static_cast<int>(std::min<long long>(block, frames - done));
        e.render(out.data() + done * e.channels(), n);
        done += n;
    }
    return out;
}

double rms(const std::vector<float>& v, long long from, long long count, int ch = 2) {
    double s = 0;
    for (long long i = from; i < from + count; ++i) s += double(v[i * ch]) * v[i * ch];
    return std::sqrt(s / count);
}

// Frequenz über Nulldurchgänge (aufsteigend) des linken Kanals.
double zeroCrossingFreq(const std::vector<float>& v, long long from, long long count, int sr, int ch = 2) {
    int crossings = 0;
    for (long long i = from + 1; i < from + count; ++i)
        if (v[(i - 1) * ch] < 0 && v[i * ch] >= 0) ++crossings;
    return crossings * double(sr) / count;
}

// ---------------------------------------------------------------------------

void loopSeamDirectIsSampleExact() {  // #5/AK4
    const int sr = 1000;
    wp::Engine e;
    e.setSource(ramp(5000), 2, sr);
    e.setLoop(1.0, 2.0);  // Frames 1000..1999
    e.seek(1.5);
    e.play();
    // 100 Durchläufe, ungerade Blockgrösse, damit der Sprung mitten in Blöcken liegt.
    const long long n = 100 * 1000 + 500;
    auto out = renderFrames(e, n, 333);
    long long expected = 1500;
    bool ok = true;
    for (long long i = 0; i < n && ok; ++i) {
        ok = out[2 * i] == float(expected) && out[2 * i + 1] == float(expected);
        if (++expected >= 2000) expected = 1000;
    }
    CHECK(ok);
    CHECK(e.playing());
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
    e.seek(3.0);  // hinter dem Loop-Ende
    e.play();
    float frame[2];
    e.render(frame, 1);
    CHECK(frame[0] == 1000.0f);
}

void loopAtFileEndIsClamped() {
    const int sr = 1000;
    wp::Engine e;
    e.setSource(ramp(3000), 2, sr);
    e.setLoop(1.5, 10.0);  // B hinter dem Dateiende -> Dateiende
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
    e.setLoop(1.0, 1.5);  // kürzer als 1 s -> aus
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
    e.play();  // am Ende: wieder von vorn
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

void stretchKeepsPitchAndChangesLength() {  // #5/AK3
    const int sr = 44100;
    for (double rate : {0.25, 0.5, 1.5, 2.0}) {
        wp::Engine e;
        e.setSource(sine(440, 2.0, sr), 2, sr);
        e.setRate(rate);
        e.play();
        long long rendered = 0;
        std::vector<float> all;
        std::vector<float> block(512 * 2);
        while (e.playing() && rendered < sr * 20) {
            e.render(block.data(), 512);
            all.insert(all.end(), block.begin(), block.end());
            rendered += 512;
        }
        const double seconds = double(rendered) / sr;
        std::printf("  Tempo %.2f: %.3f s gespielt (erwartet %.3f)\n", rate, seconds, 2.0 / rate);
        CHECK_NEAR(seconds, 2.0 / rate, 0.05);
        // Tonhöhe in der Mitte (weg von Ein-/Ausschwingen): 440 Hz ± 1 %.
        const long long mid = rendered / 2 - sr / 4;
        const double f = zeroCrossingFreq(all, mid, sr / 2, sr);
        std::printf("  Tempo %.2f: %.1f Hz\n", rate, f);
        CHECK_NEAR(f, 440.0, 4.4);
    }
}

void stretchLoopHasNoGap() {  // #5/AK4 (gedehnter Pfad)
    const int sr = 44100;
    wp::Engine e;
    e.setSource(sine(441, 4.0, sr), 2, sr);  // 441 Hz: 100 Samples pro Periode, Loop ganzzahlig
    e.setLoop(1.0, 2.0);
    e.seek(1.0);
    e.setRate(0.5);
    e.play();
    const long long n = sr * 10;  // fünf Loop-Durchläufe bei 0,5x
    auto out = renderFrames(e, n);
    const double ref = 0.5 / std::sqrt(2.0);
    const long long win = sr / 100;  // 10 ms
    double minRms = 1;
    for (long long i = sr / 2; i + win < n; i += win) minRms = std::min(minRms, rms(out, i, win));
    std::printf("  kleinster 10-ms-Pegel: %.3f (Referenz %.3f)\n", minRms, ref);
    CHECK(minRms > ref * 0.7);  // keine Lücke, kein Einbruch über 3 dB
    CHECK(e.position() >= 1.0 && e.position() < 2.0);
}

void positionFollowsRate() {
    const int sr = 44100;
    wp::Engine e;
    e.setSource(sine(440, 5.0, sr), 2, sr);
    e.setRate(0.5);
    e.play();
    renderFrames(e, sr * 2);  // 2 s Ausgabe = 1 s Quelle
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
    for (int i = 0; i < 100 && ok; ++i) ok = out[2 * i] == 0.5f * float(i) && out[2 * i + 1] == 0.5f * float(i);
    CHECK(ok);
    e.setVolume(0.0f);
    auto silent = renderFrames(e, 50);
    bool allZero = true;
    for (float v : silent) allZero = allZero && v == 0.0f;
    CHECK(allZero);
    CHECK(e.playing());
}

void rateChangeKeepsPositionAndSignal() {
    const int sr = 44100;
    wp::Engine e;
    e.setSource(sine(440, 6.0, sr), 2, sr);
    e.play();
    auto a = renderFrames(e, sr);  // 1 s bei 1,0x -> Position 1,0 s
    CHECK_NEAR(e.position(), 1.0, 0.001);
    e.setRate(0.5);
    auto b = renderFrames(e, sr);  // 1 s Ausgabe bei 0,5x -> 0,5 s Quelle
    CHECK_NEAR(e.position(), 1.5, 0.02);
    e.setRate(1.0);
    auto c = renderFrames(e, sr);  // zurück bei 1,0x -> 1 s Quelle, kein Sprung
    CHECK_NEAR(e.position(), 2.5, 0.02);
    // Kein Aussetzer an den Übergängen: Pegel bleibt nahe dem Sinus-Effektivwert.
    const double ref = 0.5 / std::sqrt(2.0);
    CHECK_NEAR(rms(b, sr / 4, sr / 2), ref, ref * 0.15);
    CHECK_NEAR(rms(c, sr / 4, sr / 2), ref, ref * 0.15);
    // Steilheit: grösster Sprung zwischen Samples nahe der Sinus-Steigung (0,5*2*pi*440/44100 = 0,0313).
    double maxStep = 0;
    for (auto* v : {&b, &c})
        for (long long i = sr / 20; i + 1 < sr; ++i) maxStep = std::max(maxStep, double(std::fabs((*v)[2 * (i + 1)] - (*v)[2 * i])));
    std::printf("  grösster Sprung: %.4f\n", maxStep);
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
    renderFrames(e, sr / 2);  // 0,5 s Ausgabe = 0,25 s Quelle
    CHECK_NEAR(e.position(), 3.25, 0.02);
    e.seek(0.0);
    renderFrames(e, sr / 2);
    CHECK_NEAR(e.position(), 0.25, 0.02);
    CHECK(e.playing());
}

}  // namespace

int main() {
    const std::vector<std::pair<std::string, std::function<void()>>> tests = {
        {"loopSeamDirectIsSampleExact", loopSeamDirectIsSampleExact},
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
    };
    for (auto& [name, fn] : tests) {
        const int before = failures;
        fn();
        std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name.c_str());
    }
    std::printf("%d Prüfungen, %d Fehler\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
