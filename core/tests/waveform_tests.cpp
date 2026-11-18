// Tests der Wellenform-Daten (#28) ohne Audiogerät: erzeugter Sinus, Stille, Fehlerfälle, Laufzeit.
#include <chrono>
#include <cmath>
#include <cstdio>
#include <functional>
#include <string>
#include <vector>

#include "waveform.hpp"

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

wp::Peaks peaksOf(const std::vector<float>& v) {
    return wp::Peaks(v.data(), static_cast<long long>(v.size() / kCh), kCh, kSr);
}

// Jeder Abschnitt: Minimum ≈ lo, Maximum ≈ hi.
void checkAll(const wp::Peaks& p, double a, double b, int n, float lo, float hi, float tol) {
    std::vector<float> mins(n, 99.0f), maxs(n, 99.0f);
    CHECK(p.query(a, b, n, mins.data(), maxs.data()));
    int bad = 0;
    for (int i = 0; i < n; ++i)
        if (std::fabs(mins[i] - lo) > tol || std::fabs(maxs[i] - hi) > tol) ++bad;
    CHECK(bad == 0);
}

void sineHasHalfAmplitude() {  // #28/AK1, #28/AK2
    const auto p = peaksOf(sine(3.0, 0.5));
    checkAll(p, 0.0, p.duration(), 300, -0.5f, 0.5f, 0.01f);  // Übersicht
    checkAll(p, 1.0, 2.5, 150, -0.5f, 0.5f, 0.01f);           // Ausschnitt um einen Loop
    checkAll(p, 0.123, 0.987, 7, -0.5f, 0.5f, 0.01f);         // krumme Grenzen
}

void silenceIsZero() {  // #28/AK3
    const std::vector<float> v(static_cast<size_t>(2 * kSr) * kCh, 0.0f);
    const auto p = peaksOf(v);
    checkAll(p, 0.0, p.duration(), 1000, 0.0f, 0.0f, 0.0f);
    checkAll(p, 0.5, 0.501, 50, 0.0f, 0.0f, 0.0f);  // Abschnitte kürzer als ein Block
}

void exactlyCountValues() {  // #28/AK1
    const auto p = peaksOf(sine(1.0, 0.5));
    std::vector<float> mins(1001, 7.0f), maxs(1001, 7.0f);
    CHECK(p.query(0.0, 1.0, 1000, mins.data(), maxs.data()));
    CHECK(mins[1000] == 7.0f && maxs[1000] == 7.0f);  // nichts über count hinaus geschrieben
    for (int i = 0; i < 1000; ++i) CHECK(mins[i] >= -1.0f && maxs[i] <= 1.0f && mins[i] <= maxs[i]);
}

void clipsToRange() {  // #28/AK1 Bereich −1…1
    const auto p = peaksOf(sine(1.0, 1.5));
    checkAll(p, 0.0, 1.0, 10, -1.0f, 1.0f, 0.0f);
}

void invalidRangesFail() {  // #28/AK4
    const auto p = peaksOf(sine(2.0, 0.5));
    float mins[4] = {7, 7, 7, 7}, maxs[4] = {7, 7, 7, 7};
    CHECK(!p.query(1.0, 1.0, 4, mins, maxs));   // Start = Ende
    CHECK(!p.query(1.5, 1.0, 4, mins, maxs));   // Start > Ende
    CHECK(!p.query(-0.1, 1.0, 4, mins, maxs));  // vor dem Anfang
    CHECK(!p.query(1.0, 2.5, 4, mins, maxs));   // über das Ende
    CHECK(!p.query(3.0, 4.0, 4, mins, maxs));   // ganz ausserhalb
    CHECK(!p.query(0.0, 1.0, 0, mins, maxs));   // keine Abschnitte
    CHECK(!p.query(0.0, 1.0, -3, mins, maxs));
    CHECK(!p.query(0.0, NAN, 4, mins, maxs));
    CHECK(!p.query(0.0, 1.0, 4, nullptr, maxs));
    CHECK(mins[0] == 7 && maxs[3] == 7);        // nichts geschrieben
    const wp::Peaks empty;                       // kein Titel
    CHECK(!empty.query(0.0, 1.0, 4, mins, maxs));
    CHECK(p.query(0.0, 2.0, 4, mins, maxs));     // genau die Dauer ist erlaubt
}

void overviewIsFast() {  // #28/AK5: 5 Minuten, 1000 Werte, auf dem Mac unter 200 ms
    const auto v = sine(300.0, 0.5);
    const auto t0 = std::chrono::steady_clock::now();
    const auto p = peaksOf(v);  // beim Laden, im Lade-Thread
    std::vector<float> mins(1000), maxs(1000);
    CHECK(p.query(0.0, p.duration(), 1000, mins.data(), maxs.data()));
    const auto t1 = std::chrono::steady_clock::now();
    CHECK(p.query(0.0, p.duration(), 1000, mins.data(), maxs.data()));
    const auto t2 = std::chrono::steady_clock::now();
    const double build = std::chrono::duration<double, std::milli>(t1 - t0).count();
    const double query = std::chrono::duration<double, std::milli>(t2 - t1).count();
    std::printf("  5 min: Berechnung beim Laden %.1f ms, Übersicht 1000 Werte %.2f ms\n", build, query);
    CHECK(build < 200.0);
    CHECK(query < 20.0);
}

}  // namespace

int main() {
    const std::vector<std::pair<std::string, std::function<void()>>> tests = {
        {"sineHasHalfAmplitude", sineHasHalfAmplitude},
        {"silenceIsZero", silenceIsZero},
        {"exactlyCountValues", exactlyCountValues},
        {"clipsToRange", clipsToRange},
        {"invalidRangesFail", invalidRangesFail},
        {"overviewIsFast", overviewIsFast},
    };
    for (auto& [name, fn] : tests) {
        const int before = failures;
        fn();
        std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name.c_str());
    }
    std::printf("%d Prüfungen, %d Fehler\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
