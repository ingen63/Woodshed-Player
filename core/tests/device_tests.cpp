// #61: the device shell of the C API (src/player.cpp) seen from inside. This program compiles
// player.cpp into its own translation unit (instead of linking the shared library wp_core), so it
// can reach the miniaudio device of a player and the notification callback: stop and restart the
// device, send the notifications miniaudio sends (rerouted, interruption, stopped, started) and
// read the state of the player core behind the C API. It runs on the core's null device
// (WP_AUDIO_BACKEND=null), which every machine has. Volumes are 0, so nothing is audible.
// The C-API tests through the shared library stay in capi_tests.cpp.
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <functional>
#include <string>
#include <thread>
#include <utility>
#include <vector>

// NOLINTNEXTLINE(bugprone-suspicious-include): on purpose, see above
#include "../src/player.cpp"
#include "test_required.hpp" // #60: setenv and unsetenv on Windows

namespace fs = std::filesystem;

namespace {

int failures = 0;
int checks = 0;

#define CHECK(cond)                                                                                \
  do {                                                                                             \
    ++checks;                                                                                      \
    if (!(cond)) {                                                                                 \
      ++failures;                                                                                  \
      std::printf("  FAILED %s:%d: %s\n", __FILE__, __LINE__, #cond);                              \
    }                                                                                              \
  } while (0)

const fs::path kAudio = WP_TEST_AUDIO_DIR;
const std::string kSine = (kAudio / "sine440.flac").string();

// Waits until cond() holds (commands reach the engine in the audio callback), at most 2 s.
bool eventually(const std::function<bool()> &cond) {
  for (int i = 0; i < 200; ++i) {
    if (cond())
      return true;
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  return cond();
}

// NOLINTBEGIN(concurrency-mt-unsafe): environment changed on the main thread before any player
void nullBackendOnlyForNull() { // #61: WP_AUDIO_BACKEND=null (#13) selects the null device, nothing
                                // else
  unsetenv("WP_AUDIO_BACKEND");
  CHECK(!nullBackendRequested());
  setenv("WP_AUDIO_BACKEND", "coreaudio", 1);
  CHECK(!nullBackendRequested());
  setenv("WP_AUDIO_BACKEND", "null", 1);
  CHECK(nullBackendRequested());
}
// NOLINTEND(concurrency-mt-unsafe)

// A player with a loaded title, playing, and the metronome running.
wp_player *playingPlayer() {
  wp_player *p = wp_create();
  CHECK(p != nullptr);
  if (!p)
    return nullptr;
  wp_set_volume(p, 0.0f);
  wp_metro_set_volume(p, 0.0f);
  CHECK(wp_load(p, kSine.c_str()) == WP_OK);
  wp_play(p);
  wp_metro_start(p);
  CHECK(eventually([p] { return wp_is_playing(p) == 1 && wp_metro_is_running(p) == 1; }));
  return p;
}

void notify(wp_player *p, ma_device_notification_type type) {
  ma_device_notification n{};
  n.pDevice = &p->device;
  n.type = type;
  notificationCallback(&n);
}

// #14/AK4: a new output (rerouted), an interruption and a stopped device pause playback and the
// metronome.
void deviceEventsPause() {
  for (const auto type :
       {ma_device_notification_type_rerouted, ma_device_notification_type_interruption_began,
        ma_device_notification_type_stopped}) {
    wp_player *p = playingPlayer();
    if (!p)
      return;
    notify(p, type);
    CHECK(eventually([p] { return wp_is_playing(p) == 0; }));
    CHECK(wp_metro_is_running(p) == 0);
    wp_destroy(p);
  }
}

// #61: a started device is available again (e.g. after an interruption on iPhone/iPad).
void startedDeviceIsAvailable() {
  wp_player *p = wp_create();
  CHECK(p != nullptr);
  if (!p)
    return;
  CHECK(p->core->deviceAvailable()); // wp_create started the null device
  p->core->setDeviceAvailable(false);
  notify(p, ma_device_notification_type_started);
  CHECK(p->core->deviceAvailable());
  wp_destroy(p);
}

// #61: play and load start a device that was stopped, and mark it available.
void playAndLoadRestartTheDevice() {
  for (const bool viaLoad : {false, true}) {
    wp_player *p = wp_create();
    CHECK(p != nullptr);
    if (!p)
      return;
    wp_set_volume(p, 0.0f);
    CHECK(ma_device_stop(&p->device) == MA_SUCCESS);
    CHECK(!ma_device_is_started(&p->device));
    p->core->setDeviceAvailable(false);
    if (viaLoad) {
      CHECK(wp_load(p, kSine.c_str()) == WP_OK);
    } else {
      wp_play(p);
    }
    CHECK(ma_device_is_started(&p->device));
    CHECK(p->core->deviceAvailable());
    wp_destroy(p);
  }
}

// #61: a running device marks the player available on play (the state may have been lost).
void playMarksRunningDeviceAvailable() {
  wp_player *p = wp_create();
  CHECK(p != nullptr);
  if (!p)
    return;
  CHECK(ma_device_is_started(&p->device));
  p->core->setDeviceAvailable(false);
  wp_play(p);
  CHECK(p->core->deviceAvailable());
  wp_destroy(p);
}

// #61: meter, subdivision and volume of the metronome reach the core through the C API.
void metronomeSettersReachTheCore() {
  wp_player *p = wp_create();
  CHECK(p != nullptr);
  if (!p)
    return;
  wp_metro_set_meter(p, 3);
  wp_metro_set_subdivision(p, 4);
  wp_metro_set_volume(p, 0.25f);
  CHECK(p->core->metronome().meter() == 3);
  CHECK(p->core->metronome().subdivision() == 4);
  CHECK(p->core->metronome().volume() == 0.25f);
  wp_destroy(p);
}

} // namespace

// #99: the null device is the core's own (custom backend) and consumes audio in 10 ms periods at
// real-time pace. miniaudio's null device moved in one-second bursts on the iOS simulator.
void nullDevicePacesInSmallSteps() {
  wp_player *p = wp_create();
  CHECK(p != nullptr);
  if (!p)
    return;
  CHECK(p->context.backend == ma_backend_custom);
  CHECK(p->device.playback.internalPeriodSizeInFrames == p->device.sampleRate / 100);
  wp_set_volume(p, 0.0f);
  CHECK(wp_load(p, kSine.c_str()) == WP_OK); // 1 s
  wp_play(p);
  CHECK(eventually([p] { return wp_position(p) > 0.0; }));
  const auto start = std::chrono::steady_clock::now();
  const double from = wp_position(p);
  double last = from;
  double largestStep = 0;
  while (std::chrono::steady_clock::now() - start < std::chrono::milliseconds(400)) {
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    const double now = wp_position(p);
    largestStep = std::max(largestStep, now - last);
    last = now;
  }
  const double elapsed =
      std::chrono::duration<double>(std::chrono::steady_clock::now() - start).count();
  CHECK(largestStep < 0.2);           // no bursts (a loaded machine may delay a single sleep)
  CHECK(last - from > 0.5 * elapsed); // real-time pace, not stuck
  CHECK(last - from < elapsed + 0.1); // and not faster
  wp_destroy(p);
}

// #97/AK6: wp_create runs the core at the device's rate, never above WP_MAX_SAMPLE_RATE, so the
// player is supported and loads.
void createdPlayerRateIsSupported() {
  wp_player *p = wp_create();
  CHECK(p != nullptr);
  if (!p)
    return;
  const int rate = p->core->sampleRate();
  CHECK(rate >= WP_MIN_SAMPLE_RATE && rate <= WP_MAX_SAMPLE_RATE);
  CHECK(rate == static_cast<int>(p->device.sampleRate));
  CHECK(p->core->sampleRateSupported());
  wp_destroy(p);
}

// #108/AK1: wp_create keeps the own rate of a device up to the limit (the null device: 48 kHz) and
// runs a faster device (352.8 kHz, an interface rate) at exactly the limit (#97/AK6).
void createdPlayerKeepsOrCapsTheDeviceRate() {
  wp_player *p = wp_create();
  CHECK(p != nullptr);
  if (p) {
    CHECK(p->core->sampleRate() == static_cast<int>(kNullRate));
    CHECK(p->device.sampleRate == kNullRate);
    wp_destroy(p);
  }
  for (const ma_uint32 own : {static_cast<ma_uint32>(WP_MAX_SAMPLE_RATE), ma_uint32{352800}}) {
    nullRate = own;
    p = wp_create();
    nullRate = kNullRate;
    CHECK(p != nullptr);
    if (!p)
      continue;
    CHECK(p->core->sampleRate() == WP_MAX_SAMPLE_RATE);
    CHECK(p->device.sampleRate == static_cast<ma_uint32>(WP_MAX_SAMPLE_RATE));
    CHECK(p->core->deviceAvailable());
    wp_destroy(p);
  }
}

// #108/AK1: the null device describes itself as a playback device (f32, stereo, its own rate) and
// has no capture device.
void nullDeviceInfoOnlyForPlayback() {
  wp_player *p = wp_create();
  CHECK(p != nullptr);
  if (!p)
    return;
  ma_device_info info{};
  CHECK(ma_context_get_device_info(&p->context, ma_device_type_playback, nullptr, &info) ==
        MA_SUCCESS);
  CHECK(std::strcmp(info.name, kNullName) == 0);
  CHECK(info.nativeDataFormatCount == 1);
  CHECK(info.nativeDataFormats[0].format == ma_format_f32);
  CHECK(info.nativeDataFormats[0].channels == static_cast<ma_uint32>(wp::Player::kChannels));
  CHECK(info.nativeDataFormats[0].sampleRate == kNullRate);
  ma_device_info capture{};
  CHECK(ma_context_get_device_info(&p->context, ma_device_type_capture, nullptr, &capture) !=
        MA_SUCCESS);
  wp_destroy(p);
}

// #108/AK1: a device opened on the null backend without a channel count gets the core's stereo;
// one that asks for a count keeps it.
void nullDeviceFillsInTheChannelCount() {
  wp_player *p = wp_create();
  CHECK(p != nullptr);
  if (!p)
    return;
  for (const ma_uint32 asked : {ma_uint32{0}, ma_uint32{1}}) {
    ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
    cfg.playback.format = ma_format_f32;
    cfg.playback.channels = asked;
    cfg.dataCallback = [](ma_device *, void *, const void *, ma_uint32) {};
    // NOLINTNEXTLINE(bugprone-invalid-enum-default-initialization): zeroed miniaudio struct
    ma_device dev{};
    CHECK(ma_device_init(&p->context, &cfg, &dev) == MA_SUCCESS);
    const ma_uint32 expected = asked == 0 ? static_cast<ma_uint32>(wp::Player::kChannels) : asked;
    CHECK(dev.playback.internalChannels == expected);
    CHECK(dev.playback.channels == expected);
    ma_device_uninit(&dev); // never started: the null device's start needs a wp_player
  }
  wp_destroy(p);
}

int main() {
  nullBackendOnlyForNull(); // ends with WP_AUDIO_BACKEND=null for the tests below
  std::printf("WP_AUDIO_BACKEND=null\n");
  const std::vector<std::pair<std::string, std::function<void()>>> tests = {
      {"deviceEventsPause", deviceEventsPause},
      {"startedDeviceIsAvailable", startedDeviceIsAvailable},
      {"playAndLoadRestartTheDevice", playAndLoadRestartTheDevice},
      {"playMarksRunningDeviceAvailable", playMarksRunningDeviceAvailable},
      {"metronomeSettersReachTheCore", metronomeSettersReachTheCore},
      {"nullDevicePacesInSmallSteps", nullDevicePacesInSmallSteps},
      {"createdPlayerRateIsSupported", createdPlayerRateIsSupported},
      {"createdPlayerKeepsOrCapsTheDeviceRate", createdPlayerKeepsOrCapsTheDeviceRate},
      {"nullDeviceInfoOnlyForPlayback", nullDeviceInfoOnlyForPlayback},
      {"nullDeviceFillsInTheChannelCount", nullDeviceFillsInTheChannelCount},
  };
  for (auto &[name, fn] : tests) {
    const int before = failures;
    fn();
    std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name.c_str());
  }
  std::printf("%d checks, %d failures\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
