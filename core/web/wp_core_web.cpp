// C-API des Kerns im Browser (#33): Player-Kern ohne Audiogerät und ohne Lade-Thread, gerendert vom
// AudioWorklet. Siehe wp_core_web.h. Die Steuerfunktionen entsprechen player.cpp.
#include "wp_core_web.h"

#include <cstdlib>
#include <memory>
#include <new>
#include <vector>

#include "player_core.hpp"

struct wp_player {
    std::unique_ptr<wp::Player> core;
    std::vector<float> out;
};

extern "C" {

wp_player* wp_web_create(int sampleRate) {
    if (sampleRate < 1) return nullptr;
    try {
        auto* p = new wp_player();
        p->core = std::make_unique<wp::Player>(sampleRate);
        p->out.assign(static_cast<size_t>(WP_WEB_MAX_BLOCK) * wp::Player::kChannels, 0.0f);
        return p;
    } catch (const std::bad_alloc&) {
        return nullptr;
    }
}

wp_player* wp_create(void) { return wp_web_create(48000); }
void wp_destroy(wp_player* p) { delete p; }
int wp_web_sample_rate(wp_player* p) { return p ? p->core->sampleRate() : 0; }

void* wp_web_alloc(size_t bytes) { return std::malloc(bytes ? bytes : 1); }
void wp_web_free(void* ptr) { std::free(ptr); }

const char* wp_error_message(int code) { return wp::errorMessage(code); }

int wp_web_load_encoded(wp_player* p, const void* data, size_t size) {
    if (!p || !data) return WP_ERR_INVALID_ARGUMENT;
    try {
        auto source = std::make_unique<wp::Source>();
        const int r = wp::decodeMemory(data, size, p->core->sampleRate(), *source);
        if (r != WP_OK) return r;
        p->core->engine().collectGarbage();
        return p->core->setSource(std::move(source));
    } catch (const std::bad_alloc&) {
        return WP_ERR_OUT_OF_MEMORY;
    }
}

int wp_web_load_pcm(wp_player* p, const float* interleaved, int channels, int frames, int sampleRate) {
    if (!p) return WP_ERR_INVALID_ARGUMENT;
    try {
        auto source = std::make_unique<wp::Source>();
        const int r = wp::convertPcm(interleaved, channels, frames, sampleRate, p->core->sampleRate(), *source);
        if (r != WP_OK) return r;
        p->core->engine().collectGarbage();
        return p->core->setSource(std::move(source));
    } catch (const std::bad_alloc&) {
        return WP_ERR_OUT_OF_MEMORY;
    }
}

float* wp_web_render(wp_player* p, int frames) {
    if (!p) return nullptr;
    if (frames < 1) frames = 1;
    if (frames > WP_WEB_MAX_BLOCK) frames = WP_WEB_MAX_BLOCK;
    p->core->render(p->out.data(), frames);
    return p->out.data();
}

void wp_play(wp_player* p) { if (p) p->core->engine().play(); }
void wp_pause(wp_player* p) { if (p) p->core->engine().pause(); }
int wp_is_playing(wp_player* p) { return p && p->core->engine().playing() ? 1 : 0; }
void wp_seek(wp_player* p, double s) { if (p) p->core->engine().seek(s); }
void wp_set_rate(wp_player* p, double r) { if (p) p->core->engine().setRate(r); }
void wp_set_loop(wp_player* p, double a, double b) { if (p) p->core->engine().setLoop(a, b); }
void wp_set_volume(wp_player* p, float v) { if (p) p->core->engine().setVolume(v); }
double wp_position(wp_player* p) { return p ? p->core->engine().position() : 0.0; }
double wp_duration(wp_player* p) { return p ? p->core->engine().duration() : 0.0; }
long long wp_loop_passes(wp_player* p) { return p ? p->core->engine().loopPasses() : 0; }
int wp_waveform(wp_player* p, double start, double end, int count, float* mins, float* maxs) {
    return p ? p->core->waveform(start, end, count, mins, maxs) : WP_ERR_INVALID_ARGUMENT;
}

void wp_metro_start(wp_player* p) { if (p) p->core->metronome().start(); }
void wp_metro_stop(wp_player* p) { if (p) p->core->metronome().stop(); }
int wp_metro_is_running(wp_player* p) { return p && p->core->metronome().running() ? 1 : 0; }
void wp_metro_set_bpm(wp_player* p, int bpm) { if (p) p->core->metronome().setBpm(bpm); }
int wp_metro_bpm(wp_player* p) { return p ? p->core->metronome().bpm() : 0; }
void wp_metro_set_meter(wp_player* p, int beats) { if (p) p->core->metronome().setMeter(beats); }
void wp_metro_set_subdivision(wp_player* p, int clicks) { if (p) p->core->metronome().setSubdivision(clicks); }
void wp_metro_set_volume(wp_player* p, float v) { if (p) p->core->metronome().setVolume(v); }
void wp_metro_set_ramp(wp_player* p, int enabled, int start, int target, int step, int every) {
    if (p) p->core->metronome().setRamp(enabled != 0, start, target, step, every);
}
void wp_metro_set_ramp_timed(wp_player* p, int enabled, int start, int target, int seconds) {
    if (p) p->core->metronome().setTimedRamp(enabled != 0, start, target, seconds);
}

// Aufnahme gibt es im Browser nicht.
int wp_rec_available(void) { return 0; }

}  // extern "C"
