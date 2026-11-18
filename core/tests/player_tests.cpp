// Tests des Player-Kerns (#14) ohne Audiogerät: Laden von WAV/FLAC/MP3, Fehlerfälle, Laden im Hintergrund,
// Gerätewechsel, Dateiende, Seek und Loop-Grenzen mit geladenen Dateien.
// WAV-Dateien werden hier erzeugt; FLAC/MP3 stammen aus core/tools/make_test_audio.sh (Sinus 440 Hz, 1 s).
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <functional>
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
                  WP_ERR_OUT_OF_MEMORY == wp::kErrOutOfMemory && WP_ERR_FILE_UNREADABLE == wp::kErrFileUnreadable &&
                  WP_ERR_CANCELLED == wp::kErrCancelled && WP_ERR_BUSY == wp::kErrBusy,
              "Fehlercodes in wp_core.h und player_core.hpp müssen gleich sein");
static_assert(WP_LOAD_IDLE == wp::kLoadIdle && WP_LOAD_RUNNING == wp::kLoadRunning &&
                  WP_LOAD_READY == wp::kLoadReady,
              "Ladezustände in wp_core.h und player_core.hpp müssen gleich sein");

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

void put16(std::ofstream& f, unsigned v) { f.put(char(v & 0xff)).put(char((v >> 8) & 0xff)); }
void put32(std::ofstream& f, unsigned v) { put16(f, v & 0xffff); put16(f, v >> 16); }

// 16-Bit-Stereo-WAV mit Frame-Index als Inhalt: links die unteren, rechts die oberen 15 Bit.
// s16 -> f32 teilt durch 32768 und ist damit exakt umkehrbar.
fs::path writeIndexWav(const std::string& name, long long frames, int sr = kSr) {
    const fs::path p = tempDir() / name;
    std::ofstream f(p, std::ios::binary);
    const unsigned bytes = static_cast<unsigned>(frames * 4);
    f.write("RIFF", 4); put32(f, 36 + bytes); f.write("WAVE", 4);
    f.write("fmt ", 4); put32(f, 16); put16(f, 1); put16(f, 2); put32(f, sr); put32(f, sr * 4); put16(f, 4); put16(f, 16);
    f.write("data", 4); put32(f, bytes);
    for (long long i = 0; i < frames; ++i) {
        put16(f, static_cast<unsigned>(i & 0x7fff));
        put16(f, static_cast<unsigned>((i >> 15) & 0x7fff));
    }
    return p;
}

long long frameIndex(const float* frame) {
    return std::llround(frame[0] * 32768.0) + (std::llround(frame[1] * 32768.0) << 15);
}

fs::path writeBytes(const std::string& name, const std::string& bytes) {
    const fs::path p = tempDir() / name;
    std::ofstream(p, std::ios::binary) << bytes;
    return p;
}

std::vector<float> renderFrames(wp::Player& p, long long frames, int block = 480) {
    std::vector<float> out(static_cast<size_t>(frames) * 2);
    for (long long done = 0; done < frames;) {
        const int n = static_cast<int>(std::min<long long>(block, frames - done));
        p.render(out.data() + done * 2, n);
        done += n;
    }
    return out;
}

double rms(const std::vector<float>& v, long long from, long long count) {
    double s = 0;
    for (long long i = from; i < from + count; ++i) s += double(v[i * 2]) * v[i * 2];
    return std::sqrt(s / count);
}

double zeroCrossingFreq(const std::vector<float>& v, long long from, long long count) {
    int crossings = 0;
    for (long long i = from + 1; i < from + count; ++i)
        if (v[(i - 1) * 2] < 0 && v[i * 2] >= 0) ++crossings;
    return crossings * double(kSr) / count;
}

// ---------------------------------------------------------------------------

void loadsWavSampleExact() {  // #14/AK5 (WAV), Seek
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

void loadCompressed(const char* file, double durationTol) {
    wp::Player p(kSr);
    const int r = p.load((kAudio / file).string());
    CHECK(r == wp::kOk);
    if (r != wp::kOk) return;
    CHECK_NEAR(p.engine().duration(), 1.0, durationTol);  // 44,1 kHz mono -> 48 kHz stereo
    p.engine().play();
    auto out = renderFrames(p, kSr / 2);
    CHECK_NEAR(zeroCrossingFreq(out, kSr / 10, kSr / 4), 440.0, 8.0);
    CHECK_NEAR(rms(out, kSr / 10, kSr / 4), 0.5 / std::sqrt(2.0), 0.05);
    bool stereo = true;  // mono wird auf beide Kanäle verteilt
    for (long long i = kSr / 10; i < kSr / 4; ++i) stereo = stereo && out[i * 2] == out[i * 2 + 1];
    CHECK(stereo);
}

void loadsFlac() { loadCompressed("sine440.flac", 2e-3); }  // #14/AK5 (FLAC)
void loadsMp3() { loadCompressed("sine440.mp3", 0.06); }    // #14/AK5 (MP3, Encoder-Verzögerung)

void endOfFileStopsWithLoadedFile() {  // #14/AK5 Dateiende
    wp::Player p(kSr);
    CHECK(p.load(writeIndexWav("index1s.wav", kSr).string()) == wp::kOk);
    p.engine().seek(0.99);
    p.engine().play();
    auto out = renderFrames(p, kSr / 50);
    CHECK(frameIndex(&out[(kSr / 100 - 1) * 2]) == kSr - 1);
    CHECK(out[(kSr / 100) * 2] == 0.0f && out[(kSr / 100) * 2 + 1] == 0.0f);
    CHECK(!p.engine().playing());
    CHECK_NEAR(p.engine().position(), 1.0, 1e-9);
    p.engine().play();  // am Ende: wieder von vorn
    float frame[2];
    p.render(frame, 1);
    CHECK(frameIndex(frame) == 0);
}

void loopBoundsWithLoadedFile() {  // #14/AK5 Loop-Grenzen
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
        if (++expected >= static_cast<long long>(1.75 * kSr)) expected = kSr / 2;
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
void checkStillPlayable(wp::Player& p, double duration) {
    CHECK_NEAR(p.engine().duration(), duration, 1e-9);
    p.engine().seek(0.5);
    p.engine().play();
    float frame[2];
    p.render(frame, 1);
    CHECK(frameIndex(frame) == kSr / 2);
    CHECK(p.engine().playing());
}

void loadErrorsHaveCodeAndText() {  // #14/AK2, #14/AK5 Fehlerfälle
    wp::Player p(kSr);
    CHECK(p.load(writeIndexWav("good.wav", 2 * kSr).string()) == wp::kOk);

    const int missing = p.load((tempDir() / "fehlt.mp3").string());
    CHECK(missing == wp::kErrFileNotFound);
    CHECK(std::strcmp(wp::errorMessage(missing), "Datei nicht gefunden") == 0);
    CHECK(p.loadState() == wp::kErrFileNotFound);
    checkStillPlayable(p, 2.0);

    const int garbage = p.load(writeBytes("kein-audio.mp3", std::string(4096, 'x')).string());
    CHECK(garbage == wp::kErrUnsupportedFormat);
    CHECK(std::strcmp(wp::errorMessage(garbage), "Format unbekannt oder Datei beschädigt") == 0);
    checkStillPlayable(p, 2.0);

    CHECK(p.load(writeBytes("leer.wav", "").string()) == wp::kErrUnsupportedFormat);
    checkStillPlayable(p, 2.0);

    CHECK(p.load("") == wp::kErrInvalidArgument);
    checkStillPlayable(p, 2.0);

    p.setDeviceAvailable(false);
    const int device = p.load(writeIndexWav("good2.wav", kSr).string());
    CHECK(device == wp::kErrDeviceUnavailable);
    CHECK(std::strcmp(wp::errorMessage(device), "Audiogerät nicht verfügbar") == 0);
    checkStillPlayable(p, 2.0);
    p.setDeviceAvailable(true);

    // Jeder Code hat einen eigenen Text.
    for (int c = wp::kErrInvalidArgument; c >= wp::kErrBusy; --c)
        CHECK(std::strcmp(wp::errorMessage(c), wp::errorMessage(-100)) != 0);
}

void errorDuringPlaybackKeepsPlaying() {  // #14/AK2
    wp::Player p(kSr);
    CHECK(p.load(writeIndexWav("play.wav", 3 * kSr).string()) == wp::kOk);
    p.engine().play();
    renderFrames(p, kSr / 2);
    CHECK(p.load((tempDir() / "fehlt.flac").string()) == wp::kErrFileNotFound);
    float frame[2];
    p.render(frame, 1);
    CHECK(frameIndex(frame) == kSr / 2);
    CHECK(p.engine().playing());
}

void loadRunsInBackground() {  // #14/AK3
    const fs::path big = writeIndexWav("big60s.wav", 60LL * kSr);
    wp::Player p(kSr);
    CHECK(p.load(writeIndexWav("small.wav", 2 * kSr).string()) == wp::kOk);
    p.engine().play();

    const auto t0 = std::chrono::steady_clock::now();
    CHECK(p.loadAsync(big.string()) == wp::kOk);
    const double startMs = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - t0).count();
    CHECK(startMs < 50.0);  // kehrt sofort zurück, dekodiert wird im Hintergrund

    // Während des Ladens läuft die Wiedergabe weiter, Fortschritt steigt.
    double lastProgress = 0;
    bool monotonic = true, sawRunning = false;
    std::vector<float> out(480 * 2);
    int state = p.loadState();
    while ((state = p.loadState()) == wp::kLoadRunning) {
        sawRunning = true;
        p.render(out.data(), 480);
        const double prog = p.loadProgress();
        monotonic = monotonic && prog >= lastProgress && prog <= 1.0;
        lastProgress = prog;
        std::this_thread::sleep_for(std::chrono::microseconds(200));
    }
    CHECK(sawRunning || state == wp::kLoadReady);
    CHECK(monotonic);
    CHECK(state == wp::kLoadReady);
    CHECK(p.waitForLoad() == wp::kOk);
    CHECK(p.loadProgress() == 1.0);
    CHECK_NEAR(p.engine().duration(), 60.0, 1e-9);
    p.render(out.data(), 1);  // neuer Titel steht am Anfang, pausiert
    CHECK(!p.engine().playing());
    CHECK(p.engine().position() == 0.0);
}

void newerLoadReplacesRunningLoad() {  // #14/AK3
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

void fileDurationWithoutLoading() {  // #16/AK4 (Dauer beim Import)
    CHECK_NEAR(wp::fileDuration(writeIndexWav("dur.wav", 3 * kSr / 2).string()), 1.5, 1e-9);
    CHECK_NEAR(wp::fileDuration((kAudio / "sine440.flac").string()), 1.0, 1e-6);
    CHECK_NEAR(wp::fileDuration((kAudio / "sine440.mp3").string()), 1.0, 0.06);
    CHECK(wp::fileDuration((tempDir() / "fehlt.mp3").string()) == wp::kErrFileNotFound);
    CHECK(wp::fileDuration(writeBytes("nix.mp3", std::string(512, 'x')).string()) == wp::kErrUnsupportedFormat);
    CHECK(wp::fileDuration("") == wp::kErrInvalidArgument);
}

// 16-Bit-Stereo-WAV mit Sinus (440 Hz) der Amplitude amp.
fs::path writeSineWav(const std::string& name, double seconds, double amp) {
    const fs::path p = tempDir() / name;
    const long long frames = std::llround(seconds * kSr);
    std::ofstream f(p, std::ios::binary);
    const unsigned bytes = static_cast<unsigned>(frames * 4);
    f.write("RIFF", 4); put32(f, 36 + bytes); f.write("WAVE", 4);
    f.write("fmt ", 4); put32(f, 16); put16(f, 1); put16(f, 2); put32(f, kSr); put32(f, kSr * 4); put16(f, 4); put16(f, 16);
    f.write("data", 4); put32(f, bytes);
    for (long long i = 0; i < frames; ++i) {
        const auto s = static_cast<unsigned>(static_cast<int>(std::lround(amp * 32767 * std::sin(2 * M_PI * 440 * i / kSr))) & 0xffff);
        put16(f, s);
        put16(f, s);
    }
    return p;
}

void waveformOfLoadedFile() {  // #28/AK1–AK4 über den Player
    wp::Player p(kSr);
    float mins[100], maxs[100];
    CHECK(p.waveform(0.0, 1.0, 100, mins, maxs) == wp::kErrInvalidArgument);  // noch kein Titel
    CHECK(p.load(writeSineWav("sine_half.wav", 2.0, 0.5).string()) == wp::kOk);
    CHECK(p.waveform(0.0, p.engine().duration(), 100, mins, maxs) == wp::kOk);
    int bad = 0;
    for (int i = 0; i < 100; ++i)
        if (std::fabs(mins[i] + 0.5f) > 0.01f || std::fabs(maxs[i] - 0.5f) > 0.01f) ++bad;
    CHECK(bad == 0);
    CHECK(p.waveform(1.0, 0.5, 10, mins, maxs) == wp::kErrInvalidArgument);
    CHECK(p.waveform(1.0, 3.0, 10, mins, maxs) == wp::kErrInvalidArgument);
    // Ein fehlgeschlagenes Laden behält die Wellenform des bisherigen Titels.
    CHECK(p.load((tempDir() / "fehlt.wav").string()) == wp::kErrFileNotFound);
    CHECK(p.waveform(0.0, 2.0, 10, mins, maxs) == wp::kOk);
    // Ein neuer Titel ersetzt sie.
    CHECK(p.load(writeSineWav("silence.wav", 1.0, 0.0).string()) == wp::kOk);
    CHECK(p.waveform(0.0, 2.0, 10, mins, maxs) == wp::kErrInvalidArgument);
    CHECK(p.waveform(0.0, 1.0, 10, mins, maxs) == wp::kOk);
    CHECK(mins[0] == 0.0f && maxs[9] == 0.0f);
}

void devicePolicy() {  // #14/AK4
    CHECK(wp::pausesPlayback(wp::DeviceEvent::Rerouted));
    CHECK(wp::pausesPlayback(wp::DeviceEvent::InterruptionBegan));
    CHECK(wp::pausesPlayback(wp::DeviceEvent::Stopped));
    CHECK(!wp::pausesPlayback(wp::DeviceEvent::Started));
    CHECK(!wp::pausesPlayback(wp::DeviceEvent::InterruptionEnded));
}

void deviceChangePausesAndKeepsPosition() {  // #14/AK4
    for (auto ev : {wp::DeviceEvent::Rerouted, wp::DeviceEvent::InterruptionBegan, wp::DeviceEvent::Stopped}) {
        wp::Player p(kSr);
        const int lr = p.load(writeIndexWav("device.wav", 3 * kSr).string());
        if (lr != wp::kOk) std::printf("  Ladefehler %d bei Ereignis %d\n", lr, int(ev));
        CHECK(lr == wp::kOk);
        p.engine().setRate(0.75);  // auch im gedehnten Pfad
        p.engine().play();
        p.metronome().start();
        renderFrames(p, kSr);
        const double pos = p.engine().position();

        p.onDeviceEvent(ev);  // z. B. Kopfhörer ab
        auto out = renderFrames(p, kSr / 5);
        bool silent = true;
        for (float x : out) silent = silent && x == 0.0f;
        CHECK(silent);
        CHECK(!p.engine().playing());
        CHECK(!p.metronome().running());
        CHECK(p.engine().position() == pos);

        p.onDeviceEvent(wp::DeviceEvent::InterruptionEnded);  // kein automatisches Weiterspielen
        p.onDeviceEvent(wp::DeviceEvent::Started);
        renderFrames(p, 480);
        CHECK(!p.engine().playing());
        CHECK(p.engine().position() == pos);

        p.engine().setRate(1.0);
        p.engine().play();  // weiter an derselben Stelle
        float frame[2];
        p.render(frame, 1);
        CHECK(std::llabs(frameIndex(frame) - std::llround(pos * kSr)) <= 1);
    }
}

}  // namespace

int main() {
    const std::vector<std::pair<std::string, std::function<void()>>> tests = {
        {"loadsWavSampleExact", loadsWavSampleExact},
        {"loadsFlac", loadsFlac},
        {"loadsMp3", loadsMp3},
        {"endOfFileStopsWithLoadedFile", endOfFileStopsWithLoadedFile},
        {"loopBoundsWithLoadedFile", loopBoundsWithLoadedFile},
        {"loadErrorsHaveCodeAndText", loadErrorsHaveCodeAndText},
        {"errorDuringPlaybackKeepsPlaying", errorDuringPlaybackKeepsPlaying},
        {"loadRunsInBackground", loadRunsInBackground},
        {"newerLoadReplacesRunningLoad", newerLoadReplacesRunningLoad},
        {"fileDurationWithoutLoading", fileDurationWithoutLoading},
        {"waveformOfLoadedFile", waveformOfLoadedFile},
        {"devicePolicy", devicePolicy},
        {"deviceChangePausesAndKeepsPosition", deviceChangePausesAndKeepsPosition},
    };
    for (auto& [name, fn] : tests) {
        const int before = failures;
        fn();
        std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name.c_str());
    }
    fs::remove_all(tempDir());
    std::printf("%d Prüfungen, %d Fehler\n", checks, failures);
    return failures == 0 ? 0 : 1;
}
