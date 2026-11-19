// C-API: Audiogerät über miniaudio, alles andere im Player-Kern (player_core: Engine, Metronom,
// Laden). Das Gerät läuft ab wp_create mit seiner eigenen Samplerate; Titel werden beim Laden auf
// diese Rate gewandelt. Der Audio-Callback sperrt nicht und reserviert nichts; Befehle erreichen
// ihn über eine Lock-free-Queue (#14).
#include <memory>
#include <mutex>
#include <new>

#include "miniaudio_impl.hpp"
#include "player_core.hpp"
#include "wp_core.h"

struct wp_player {
  std::unique_ptr<wp::Player> core;
  std::mutex deviceMutex; // nur Steuer-Threads
  ma_context context{};
  ma_device
      device{}; // NOLINT(bugprone-invalid-enum-default-initialization): zeroed miniaudio struct
  bool contextReady = false;
  bool deviceReady = false;
};

namespace {

void dataCallback(ma_device *device, void *output, const void *, ma_uint32 frameCount) {
  auto *p = static_cast<wp_player *>(device->pUserData);
  p->core->render(static_cast<float *>(output), static_cast<int>(frameCount));
}

void notificationCallback(const ma_device_notification *n) {
  auto *p = static_cast<wp_player *>(n->pDevice->pUserData);
  if (!p || !p->core)
    return;
  switch (n->type) {
  case ma_device_notification_type_started:
    p->core->onDeviceEvent(wp::DeviceEvent::Started);
    break;
  case ma_device_notification_type_stopped:
    p->core->onDeviceEvent(wp::DeviceEvent::Stopped);
    break;
  case ma_device_notification_type_rerouted:
    p->core->onDeviceEvent(wp::DeviceEvent::Rerouted);
    break;
  case ma_device_notification_type_interruption_began:
    p->core->onDeviceEvent(wp::DeviceEvent::InterruptionBegan);
    break;
  case ma_device_notification_type_interruption_ended:
    p->core->onDeviceEvent(wp::DeviceEvent::InterruptionEnded);
    break;
  default:
    break;
  }
}

// Kontext und Gerät anlegen, falls noch nicht geschehen. sampleRate 0 = Samplerate des Geräts.
bool initDevice(wp_player *p, ma_uint32 sampleRate) {
  if (!p->contextReady) {
    ma_context_config cc = ma_context_config_init();
    // iPhone/iPad: Wiedergabe auch bei eingeschaltetem Stummschalter.
    cc.coreaudio.sessionCategory = ma_ios_session_category_playback;
    if (ma_context_init(nullptr, 0, &cc, &p->context) != MA_SUCCESS)
      return false;
    p->contextReady = true;
  }
  if (!p->deviceReady) {
    ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
    cfg.playback.format = ma_format_f32;
    cfg.playback.channels = wp::Player::kChannels;
    cfg.sampleRate = sampleRate;
    cfg.dataCallback = dataCallback;
    cfg.notificationCallback = notificationCallback;
    cfg.pUserData = p;
    if (ma_device_init(&p->context, &cfg, &p->device) != MA_SUCCESS)
      return false;
    p->deviceReady = true;
  }
  return true;
}

// Vor dem Laden und Abspielen: Gerät anlegen bzw. wieder starten, falls es fehlte oder gestoppt
// wurde. Ein später angelegtes Gerät läuft mit der Samplerate des Kerns (miniaudio wandelt bei
// Bedarf).
void refreshDevice(wp_player *p) {
  std::lock_guard<std::mutex> lock(p->deviceMutex);
  bool ok = initDevice(p, static_cast<ma_uint32>(p->core->sampleRate()));
  if (ok && !ma_device_is_started(&p->device))
    ok = ma_device_start(&p->device) == MA_SUCCESS;
  p->core->setDeviceAvailable(ok);
}

} // namespace

extern "C" {

wp_player *wp_create(void) {
  auto *p = new (std::nothrow) wp_player();
  if (!p)
    return nullptr;
  // Erst das Gerät (für seine Samplerate), dann der Kern; der Callback läuft erst nach
  // ma_device_start.
  std::lock_guard<std::mutex> lock(p->deviceMutex);
  const bool ready = initDevice(p, 0);
  p->core = std::make_unique<wp::Player>(ready ? static_cast<int>(p->device.sampleRate) : 48000);
  // Ohne Gerät gibt es trotzdem einen Player; wp_load meldet dann WP_ERR_DEVICE_UNAVAILABLE.
  p->core->setDeviceAvailable(ready && ma_device_start(&p->device) == MA_SUCCESS);
  return p;
}

void wp_destroy(wp_player *p) {
  if (!p)
    return;
  if (p->deviceReady)
    ma_device_uninit(&p->device); // danach läuft kein Callback mehr
  if (p->contextReady)
    ma_context_uninit(&p->context);
  p->core.reset();
  delete p;
}

const char *wp_error_message(int code) { return wp::errorMessage(code); }

int wp_load(wp_player *p, const char *path) {
  const int r = wp_load_async(p, path);
  return r != WP_OK ? r : wp_load_wait(p);
}

int wp_load_async(wp_player *p, const char *path) {
  if (!p || !path)
    return WP_ERR_INVALID_ARGUMENT;
  refreshDevice(p);
  return p->core->loadAsync(path);
}

double wp_file_duration(const char *path) {
  return path ? wp::fileDuration(path) : WP_ERR_INVALID_ARGUMENT;
}

int wp_load_wait(wp_player *p) { return p ? p->core->waitForLoad() : WP_ERR_INVALID_ARGUMENT; }
int wp_load_state(wp_player *p) { return p ? p->core->loadState() : WP_ERR_INVALID_ARGUMENT; }
double wp_load_progress(wp_player *p) { return p ? p->core->loadProgress() : 0.0; }

void wp_play(wp_player *p) {
  if (!p)
    return;
  refreshDevice(p);
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

} // extern "C"
