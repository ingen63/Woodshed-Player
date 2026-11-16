// C-API: Audiogerät und Dekodieren über miniaudio, Wiedergabe-Logik in Engine, Metronom in Metronome.
// Das Gerät läuft ab wp_create mit seiner eigenen Samplerate; Titel werden beim Laden auf diese Rate gewandelt.
#include <cstring>
#include <mutex>
#include <new>
#include <vector>

#include "engine.hpp"
#include "metronome.hpp"
#include "miniaudio_impl.hpp"
#include "wp_core.h"

struct wp_player {
    wp::Engine engine;
    wp::Metronome metronome;
    std::mutex engineMutex;  // Laden tauscht die Quelle; der Audio-Thread wartet nie darauf (try_lock)
    ma_context context{};
    ma_device device{};
    bool contextReady = false;
    bool deviceReady = false;
    int sampleRate = 48000;
};

namespace {

constexpr int kChannels = 2;

void dataCallback(ma_device* device, void* output, const void*, ma_uint32 frameCount) {
    auto* p = static_cast<wp_player*>(device->pUserData);
    auto* out = static_cast<float*>(output);
    const int frames = static_cast<int>(frameCount);
    if (p->engineMutex.try_lock()) {
        p->engine.render(out, frames);
        p->engineMutex.unlock();
    } else {
        std::memset(out, 0, sizeof(float) * frames * kChannels);  // gerade wird geladen
    }
    p->metronome.renderAdd(out, frames, kChannels);
}

bool startDevice(wp_player* p) {
    ma_context_config cc = ma_context_config_init();
    // iPhone/iPad: Wiedergabe auch bei eingeschaltetem Stummschalter.
    cc.coreaudio.sessionCategory = ma_ios_session_category_playback;
    if (ma_context_init(nullptr, 0, &cc, &p->context) != MA_SUCCESS) return false;
    p->contextReady = true;

    ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
    cfg.playback.format = ma_format_f32;
    cfg.playback.channels = kChannels;
    cfg.sampleRate = 0;  // Samplerate des Geräts
    cfg.dataCallback = dataCallback;
    cfg.pUserData = p;
    if (ma_device_init(&p->context, &cfg, &p->device) != MA_SUCCESS) return false;
    p->deviceReady = true;
    p->sampleRate = static_cast<int>(p->device.sampleRate);
    p->metronome.setSampleRate(p->sampleRate);
    return ma_device_start(&p->device) == MA_SUCCESS;
}

int decodeFile(const char* path, int sampleRate, std::vector<float>& out) {
    ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, kChannels, static_cast<ma_uint32>(sampleRate));
    ma_decoder dec;
    if (ma_decoder_init_file(path, &cfg, &dec) != MA_SUCCESS) return -1;
    out.clear();
    std::vector<float> buf(4096 * kChannels);
    for (;;) {
        ma_uint64 read = 0;
        ma_result r = ma_decoder_read_pcm_frames(&dec, buf.data(), 4096, &read);
        out.insert(out.end(), buf.begin(), buf.begin() + static_cast<long>(read * kChannels));
        if (r != MA_SUCCESS || read == 0) break;
    }
    ma_decoder_uninit(&dec);
    return out.empty() ? -2 : 0;
}

}  // namespace

extern "C" {

wp_player* wp_create(void) {
    auto* p = new (std::nothrow) wp_player();
    if (p && !startDevice(p)) {
        wp_destroy(p);
        return nullptr;
    }
    return p;
}

void wp_destroy(wp_player* p) {
    if (!p) return;
    if (p->deviceReady) ma_device_uninit(&p->device);
    if (p->contextReady) ma_context_uninit(&p->context);
    delete p;
}

int wp_load(wp_player* p, const char* path) {
    if (!p || !path) return -1;
    std::vector<float> pcm;
    if (int err = decodeFile(path, p->sampleRate, pcm); err != 0) return err;
    std::lock_guard<std::mutex> lock(p->engineMutex);
    p->engine.setSource(std::move(pcm), kChannels, p->sampleRate);
    return 0;
}

void wp_play(wp_player* p) { if (p) p->engine.play(); }
void wp_pause(wp_player* p) { if (p) p->engine.pause(); }
int wp_is_playing(wp_player* p) { return p && p->engine.playing() ? 1 : 0; }
void wp_seek(wp_player* p, double s) { if (p) p->engine.seek(s); }
void wp_set_rate(wp_player* p, double r) { if (p) p->engine.setRate(r); }
void wp_set_loop(wp_player* p, double a, double b) { if (p) p->engine.setLoop(a, b); }
void wp_set_volume(wp_player* p, float v) { if (p) p->engine.setVolume(v); }
double wp_position(wp_player* p) { return p ? p->engine.position() : 0.0; }
double wp_duration(wp_player* p) { return p ? p->engine.duration() : 0.0; }

void wp_metro_start(wp_player* p) { if (p) p->metronome.start(); }
void wp_metro_stop(wp_player* p) { if (p) p->metronome.stop(); }
int wp_metro_is_running(wp_player* p) { return p && p->metronome.running() ? 1 : 0; }
void wp_metro_set_bpm(wp_player* p, int bpm) { if (p) p->metronome.setBpm(bpm); }
int wp_metro_bpm(wp_player* p) { return p ? p->metronome.bpm() : 0; }
void wp_metro_set_meter(wp_player* p, int beats) { if (p) p->metronome.setMeter(beats); }
void wp_metro_set_subdivision(wp_player* p, int clicks) { if (p) p->metronome.setSubdivision(clicks); }
void wp_metro_set_volume(wp_player* p, float v) { if (p) p->metronome.setVolume(v); }
void wp_metro_set_ramp(wp_player* p, int enabled, int start, int target, int step, int every) {
    if (p) p->metronome.setRamp(enabled != 0, start, target, step, every);
}

}  // extern "C"
