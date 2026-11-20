// #61: the device shell of the C API (src/player.cpp) seen from inside. This program compiles
// player.cpp into its own translation unit (instead of linking the shared library wp_core), so it
// can reach the miniaudio device of a player and the notification callback: stop and restart the
// device, send the notifications miniaudio sends (rerouted, interruption, stopped, started) and
// read the state of the player core behind the C API. It runs on miniaudio's null device
// (WP_AUDIO_BACKEND=null), which every machine has. Volumes are 0, so nothing is audible.
// The C-API tests through the shared library stay in capi_tests.cpp.
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

int main() {
  nullBackendOnlyForNull(); // ends with WP_AUDIO_BACKEND=null for the tests below
  std::printf("WP_AUDIO_BACKEND=null\n");
  const std::vector<std::pair<std::string, std::function<void()>>> tests = {
      {"deviceEventsPause", deviceEventsPause},
      {"startedDeviceIsAvailable", startedDeviceIsAvailable},
      {"playAndLoadRestartTheDevice", playAndLoadRestartTheDevice},
      {"playMarksRunningDeviceAvailable", playMarksRunningDeviceAvailable},
      {"metronomeSettersReachTheCore", metronomeSettersReachTheCore},
  };
  for (auto &[name, fn] : tests) {
    const int before = failures;
    fn();
    std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name.c_str());
  }
  std::printf("%d checks, %d failures\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
