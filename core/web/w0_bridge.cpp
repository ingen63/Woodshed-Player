// Machbarkeitstest W0 (#32): Engine und Metronom als WebAssembly für ein AudioWorklet.
// Alle Aufrufe kommen aus demselben Thread (dem AudioWorklet). Neue Titel und Konfiguration werden
// zwischen zwei render()-Aufrufen gesetzt; render() selbst reserviert keinen Speicher.
// Kein Ersatz für die spätere C-API im Web (W1), nur so viel, wie der Test braucht.
#include <cmath>
#include <memory>
#include <vector>

#include "engine.hpp"
#include "metronome.hpp"

#define W0_EXPORT extern "C" __attribute__((used, visibility("default")))

namespace {

constexpr int kChannels = 2;
constexpr int kMaxBlock = 4096;
constexpr size_t kTickLogCapacity = 4096;

struct State {
    wp::Engine engine;
    wp::Metronome metronome;
    std::vector<float> pending;  // Titel, der gerade aus JS befüllt wird
    std::vector<float> out = std::vector<float>(static_cast<size_t>(kMaxBlock) * kChannels);
    std::vector<wp::Metronome::Tick> ticks;
    long long tickCount = 0;
    double maxTickDeviationFrames = 0;
    int sampleRate = 48000;
};

State* g = nullptr;

}  // namespace

W0_EXPORT void w0_init(int sampleRate) {
    delete g;
    g = new State;
    g->sampleRate = sampleRate;
    g->engine.configure(kChannels, sampleRate);
    g->metronome.setSampleRate(sampleRate);
    g->ticks.reserve(kTickLogCapacity);
    g->metronome.tickLog = &g->ticks;
}

// Puffer für einen neuen Titel (interleaved, Stereo); JS schreibt hinein und ruft dann w0_commit_source().
W0_EXPORT float* w0_alloc_source(int frames) {
    g->pending.assign(static_cast<size_t>(frames) * kChannels, 0.0f);
    return g->pending.data();
}

W0_EXPORT void w0_commit_source() {
    g->engine.setSource(std::move(g->pending), kChannels, g->sampleRate);
    g->pending = {};
}

W0_EXPORT void w0_play() { g->engine.play(); }
W0_EXPORT void w0_pause() { g->engine.pause(); }
W0_EXPORT void w0_seek(double seconds) { g->engine.seek(seconds); }
W0_EXPORT void w0_set_rate(double rate) { g->engine.setRate(rate); }
W0_EXPORT void w0_set_loop(double a, double b) { g->engine.setLoop(a, b); }
W0_EXPORT void w0_set_volume(float v) { g->engine.setVolume(v); }
W0_EXPORT int w0_playing() { return g->engine.playing() ? 1 : 0; }
W0_EXPORT double w0_position() { return g->engine.position(); }
W0_EXPORT double w0_duration() { return g->engine.duration(); }
W0_EXPORT double w0_loop_passes() { return static_cast<double>(g->engine.loopPasses()); }

W0_EXPORT void w0_metronome(int on, int bpm, float volume) {
    g->metronome.setBpm(bpm);
    g->metronome.setVolume(volume);
    if (on && !g->metronome.running()) {
        g->tickCount = 0;
        g->maxTickDeviationFrames = 0;
        g->metronome.start();
    } else if (!on && g->metronome.running()) {
        g->metronome.stop();
    }
}

// Grösste Abweichung eines Klicks vom idealen Raster seit dem Start, in Millisekunden.
W0_EXPORT double w0_tick_deviation_ms() { return g->maxTickDeviationFrames * 1000.0 / g->sampleRate; }
W0_EXPORT double w0_tick_count() { return static_cast<double>(g->tickCount); }

// Rendert `frames` Frames interleaved (Stereo) und gibt den Puffer zurück.
W0_EXPORT float* w0_render(int frames) {
    if (frames > kMaxBlock) frames = kMaxBlock;
    float* out = g->out.data();
    g->engine.render(out, frames);
    g->metronome.renderAdd(out, frames, kChannels);
    // Klicks gegen das ideale Raster prüfen (konstantes Tempo, keine Unterteilung).
    for (const auto& t : g->ticks) {
        const double ideal = std::round(static_cast<double>(g->tickCount) * 60.0 * g->sampleRate / t.bpm);
        const double dev = std::fabs(static_cast<double>(t.frame) - ideal);
        if (dev > g->maxTickDeviationFrames) g->maxTickDeviationFrames = dev;
        ++g->tickCount;
    }
    g->ticks.clear();  // Kapazität bleibt, keine Reservierung im Audio-Pfad
    return out;
}
