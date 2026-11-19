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
  std::unique_ptr<wp::Source> pending; // title being taken over piece by piece (#42)
  long long pendingFrames = 0;
};

struct wp_web_track {
  wp::Source source;
  wp::Peaks peaks;
  int sampleRate = 0;
};

namespace {

wp_web_track *finishTrack(std::unique_ptr<wp_web_track> t, int r, int *err) {
  if (r == WP_OK) {
    try {
      t->peaks =
          wp::Peaks(t->source.data.data(), t->source.frames, wp::Player::kChannels, t->sampleRate);
    } catch (const std::bad_alloc &) {
      r = WP_ERR_OUT_OF_MEMORY;
    }
  }
  if (err)
    *err = r;
  return r == WP_OK ? t.release() : nullptr;
}

} // namespace

extern "C" {

wp_player *wp_web_create(int sampleRate) {
  if (sampleRate < 1)
    return nullptr;
  try {
    auto *p = new wp_player();
    p->core = std::make_unique<wp::Player>(sampleRate);
    p->out.assign(static_cast<size_t>(WP_WEB_MAX_BLOCK) * wp::Player::kChannels, 0.0f);
    return p;
  } catch (const std::bad_alloc &) {
    return nullptr;
  }
}

wp_player *wp_create(void) { return wp_web_create(48000); }
void wp_destroy(wp_player *p) { delete p; }
int wp_web_sample_rate(wp_player *p) { return p ? p->core->sampleRate() : 0; }

void *wp_web_alloc(size_t bytes) { return std::malloc(bytes ? bytes : 1); }
void wp_web_free(void *ptr) { std::free(ptr); }

const char *wp_error_message(int code) { return wp::errorMessage(code); }

int wp_web_load_encoded(wp_player *p, const void *data, size_t size) {
  if (!p || !data)
    return WP_ERR_INVALID_ARGUMENT;
  try {
    auto source = std::make_unique<wp::Source>();
    const int r = wp::decodeMemory(data, size, p->core->sampleRate(), *source);
    if (r != WP_OK)
      return r;
    p->core->engine().collectGarbage();
    return p->core->setSource(std::move(source));
  } catch (const std::bad_alloc &) {
    return WP_ERR_OUT_OF_MEMORY;
  }
}

int wp_web_load_pcm(wp_player *p, const float *interleaved, int channels, int frames,
                    int sampleRate) {
  if (!p)
    return WP_ERR_INVALID_ARGUMENT;
  try {
    auto source = std::make_unique<wp::Source>();
    const int r =
        wp::convertPcm(interleaved, channels, frames, sampleRate, p->core->sampleRate(), *source);
    if (r != WP_OK)
      return r;
    p->core->engine().collectGarbage();
    return p->core->setSource(std::move(source));
  } catch (const std::bad_alloc &) {
    return WP_ERR_OUT_OF_MEMORY;
  }
}

wp_web_track *wp_web_track_decode(const void *data, size_t size, int sampleRate, int *err) {
  try {
    auto t = std::make_unique<wp_web_track>();
    t->sampleRate = sampleRate;
    const int r = wp::decodeMemory(data, size, sampleRate, t->source);
    return finishTrack(std::move(t), r, err);
  } catch (const std::bad_alloc &) {
    if (err)
      *err = WP_ERR_OUT_OF_MEMORY;
    return nullptr;
  }
}

wp_web_track *wp_web_track_convert(const float *interleaved, int channels, int frames, int srcRate,
                                   int dstRate, int *err) {
  try {
    auto t = std::make_unique<wp_web_track>();
    t->sampleRate = dstRate;
    const int r = wp::convertPcm(interleaved, channels, frames, srcRate, dstRate, t->source);
    return finishTrack(std::move(t), r, err);
  } catch (const std::bad_alloc &) {
    if (err)
      *err = WP_ERR_OUT_OF_MEMORY;
    return nullptr;
  }
}

const float *wp_web_track_data(wp_web_track *t) { return t ? t->source.data.data() : nullptr; }
int wp_web_track_frames(wp_web_track *t) { return t ? static_cast<int>(t->source.frames) : 0; }
double wp_web_track_duration(wp_web_track *t) {
  return t && t->sampleRate > 0 ? static_cast<double>(t->source.frames) / t->sampleRate : 0.0;
}
int wp_web_track_waveform(wp_web_track *t, double start, double end, int count, float *mins,
                          float *maxs) {
  return t && t->peaks.query(start, end, count, mins, maxs) ? WP_OK : WP_ERR_INVALID_ARGUMENT;
}
void wp_web_track_free(wp_web_track *t) { delete t; }

int wp_web_pcm_begin(wp_player *p, int frames) {
  if (!p)
    return WP_ERR_INVALID_ARGUMENT;
  p->pending.reset();
  p->pendingFrames = 0;
  if (frames < 1)
    return WP_ERR_INVALID_ARGUMENT;
  try {
    p->core->engine().collectGarbage(); // frees replaced titles before the new one needs the memory
    auto s = std::make_unique<wp::Source>();
    s->data.reserve(static_cast<size_t>(frames) * wp::Player::kChannels); // no zero fill
    p->pending = std::move(s);
    p->pendingFrames = frames;
    return WP_OK;
  } catch (const std::bad_alloc &) {
    return WP_ERR_OUT_OF_MEMORY;
  }
}

int wp_web_pcm_append(wp_player *p, const float *stereo, int frames) {
  if (!p || !p->pending || !stereo || frames < 1)
    return WP_ERR_INVALID_ARGUMENT;
  auto &data = p->pending->data;
  const size_t n = static_cast<size_t>(frames) * wp::Player::kChannels;
  if (data.size() + n > static_cast<size_t>(p->pendingFrames) * wp::Player::kChannels)
    return WP_ERR_INVALID_ARGUMENT;
  data.insert(data.end(), stereo, stereo + n); // within the reserved capacity, no reallocation
  return WP_OK;
}

int wp_web_pcm_commit(wp_player *p) {
  if (!p || !p->pending)
    return WP_ERR_INVALID_ARGUMENT;
  auto source = std::move(p->pending);
  const long long expected = p->pendingFrames;
  p->pendingFrames = 0;
  source->frames = static_cast<long long>(source->data.size() / wp::Player::kChannels);
  if (source->frames != expected)
    return WP_ERR_INVALID_ARGUMENT;
  return p->core->setSource(std::move(source), false);
}

float *wp_web_render(wp_player *p, int frames) {
  if (!p)
    return nullptr;
  if (frames < 1)
    frames = 1;
  if (frames > WP_WEB_MAX_BLOCK)
    frames = WP_WEB_MAX_BLOCK;
  p->core->render(p->out.data(), frames);
  return p->out.data();
}

void wp_play(wp_player *p) {
  if (p)
    p->core->engine().play();
}
void wp_pause(wp_player *p) {
  if (p)
    p->core->engine().pause();
}
int wp_is_playing(wp_player *p) { return p && p->core->engine().playing() ? 1 : 0; }
void wp_seek(wp_player *p, double s) {
  if (p)
    p->core->engine().seek(s);
}
void wp_set_rate(wp_player *p, double r) {
  if (p)
    p->core->engine().setRate(r);
}
void wp_set_loop(wp_player *p, double a, double b) {
  if (p)
    p->core->engine().setLoop(a, b);
}
void wp_set_volume(wp_player *p, float v) {
  if (p)
    p->core->engine().setVolume(v);
}
double wp_position(wp_player *p) { return p ? p->core->engine().position() : 0.0; }
double wp_duration(wp_player *p) { return p ? p->core->engine().duration() : 0.0; }
long long wp_loop_passes(wp_player *p) { return p ? p->core->engine().loopPasses() : 0; }
int wp_waveform(wp_player *p, double start, double end, int count, float *mins, float *maxs) {
  return p ? p->core->waveform(start, end, count, mins, maxs) : WP_ERR_INVALID_ARGUMENT;
}

void wp_metro_start(wp_player *p) {
  if (p)
    p->core->metronome().start();
}
void wp_metro_stop(wp_player *p) {
  if (p)
    p->core->metronome().stop();
}
int wp_metro_is_running(wp_player *p) { return p && p->core->metronome().running() ? 1 : 0; }
void wp_metro_set_bpm(wp_player *p, int bpm) {
  if (p)
    p->core->metronome().setBpm(bpm);
}
int wp_metro_bpm(wp_player *p) { return p ? p->core->metronome().bpm() : 0; }
void wp_metro_set_meter(wp_player *p, int beats) {
  if (p)
    p->core->metronome().setMeter(beats);
}
void wp_metro_set_subdivision(wp_player *p, int clicks) {
  if (p)
    p->core->metronome().setSubdivision(clicks);
}
void wp_metro_set_volume(wp_player *p, float v) {
  if (p)
    p->core->metronome().setVolume(v);
}
void wp_metro_set_ramp(wp_player *p, int enabled, int start, int target, int step, int every) {
  if (p)
    p->core->metronome().setRamp(enabled != 0, start, target, step, every);
}
void wp_metro_set_ramp_timed(wp_player *p, int enabled, int start, int target, int seconds) {
  if (p)
    p->core->metronome().setTimedRamp(enabled != 0, start, target, seconds);
}

// Loading by path (#9/AK7): only where there is a file system and threads, i.e. natively and in the
// Node.js tests (WP_WEB_FILES); the AudioWorklet build loads through wp_web_load_encoded and
// wp_web_pcm_*. The device check of src/player.cpp does not apply: rendering is driven offline.
// Recording: src/recorder_stub.cpp (not available in the browser and offline).
#ifdef WP_WEB_FILES
int wp_load(wp_player *p, const char *path) {
  const int r = wp_load_async(p, path);
  return r != WP_OK ? r : wp_load_wait(p);
}
int wp_load_async(wp_player *p, const char *path) {
  return p && path ? p->core->loadAsync(path) : WP_ERR_INVALID_ARGUMENT;
}
int wp_load_wait(wp_player *p) { return p ? p->core->waitForLoad() : WP_ERR_INVALID_ARGUMENT; }
int wp_load_state(wp_player *p) { return p ? p->core->loadState() : WP_ERR_INVALID_ARGUMENT; }
double wp_load_progress(wp_player *p) { return p ? p->core->loadProgress() : 0.0; }
double wp_file_duration(const char *path) {
  return path ? wp::fileDuration(path) : WP_ERR_INVALID_ARGUMENT;
}
#endif

} // extern "C"
