// C-API: Dekodieren und Audiogerät über miniaudio, Wiedergabe-Logik in Engine.
#include <cstring>
#include <mutex>
#include <new>
#include <vector>

#include "engine.hpp"
#include "miniaudio_impl.hpp"
#include "wp_core.h"

struct wp_player {
    wp::Engine engine;
    ma_device device{};
    bool deviceReady = false;
    std::mutex mutex;  // schützt load/destroy
};

namespace {

void dataCallback(ma_device* device, void* output, const void*, ma_uint32 frameCount) {
    auto* p = static_cast<wp_player*>(device->pUserData);
    p->engine.render(static_cast<float*>(output), static_cast<int>(frameCount));
}

int decodeFile(const char* path, std::vector<float>& out, int& channels, int& sampleRate) {
    ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, 2, 0);  // immer Stereo
    ma_decoder dec;
    if (ma_decoder_init_file(path, &cfg, &dec) != MA_SUCCESS) return -1;
    channels = static_cast<int>(dec.outputChannels);
    sampleRate = static_cast<int>(dec.outputSampleRate);

    out.clear();
    std::vector<float> buf(4096 * channels);
    for (;;) {
        ma_uint64 read = 0;
        ma_result r = ma_decoder_read_pcm_frames(&dec, buf.data(), 4096, &read);
        out.insert(out.end(), buf.begin(), buf.begin() + static_cast<long>(read * channels));
        if (r != MA_SUCCESS || read == 0) break;
    }
    ma_decoder_uninit(&dec);
    return out.empty() ? -2 : 0;
}

}  // namespace

extern "C" {

wp_player* wp_create(void) { return new (std::nothrow) wp_player(); }

void wp_destroy(wp_player* p) {
    if (!p) return;
    {
        std::lock_guard<std::mutex> lock(p->mutex);
        if (p->deviceReady) ma_device_uninit(&p->device);
    }
    delete p;
}

int wp_load(wp_player* p, const char* path) {
    if (!p || !path) return -1;
    std::vector<float> pcm;
    int channels = 0, rate = 0;
    if (int err = decodeFile(path, pcm, channels, rate); err != 0) return err;

    std::lock_guard<std::mutex> lock(p->mutex);
    if (p->deviceReady) {
        ma_device_uninit(&p->device);
        p->deviceReady = false;
    }
    p->engine.setSource(std::move(pcm), channels, rate);

    ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
    cfg.playback.format = ma_format_f32;
    cfg.playback.channels = static_cast<ma_uint32>(channels);
    cfg.sampleRate = static_cast<ma_uint32>(rate);  // miniaudio wandelt auf die Geräterate
    cfg.dataCallback = dataCallback;
    cfg.pUserData = p;
    if (ma_device_init(nullptr, &cfg, &p->device) != MA_SUCCESS) return -3;
    p->deviceReady = true;
    if (ma_device_start(&p->device) != MA_SUCCESS) return -4;
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

}  // extern "C"
