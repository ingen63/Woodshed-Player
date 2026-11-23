// Tests of the C API (wp_core.h, src/player.cpp) through the shared library, as the Dart FFI
// binding uses it (#8: the C API had no test of its own). Every call is checked with a null
// handle, and the calls are checked to reach the player core: load, seek, rate, loop, waveform,
// metronome. wp_create opens the real audio device; without a device (e.g. a headless runner) the
// load reports WP_ERR_DEVICE_UNAVAILABLE and the checks that need a loaded title are skipped with
// the reason in the output; WP_AUDIO_DEVICE_REQUIRED=1 makes that a failure (#125).
// With --null-backend (#13, second ctest case) the tests run on the core's null device
// (WP_AUDIO_BACKEND=null), which every machine has: then the load must succeed and nothing is
// skipped. Volumes are 0, so nothing is audible. Test audio: core/tests/audio/sine440.flac (440 Hz,
// 1 s).
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <functional>
#include <string>
#include <system_error>
#include <thread>
#include <utility>
#include <vector>

#include "test_required.hpp"
#include "wp_core.h"

namespace fs = std::filesystem;

namespace {

int failures = 0;
int checks = 0;
bool nullBackend = false; // --null-backend: a device is guaranteed

#define CHECK(cond)                                                                                \
  do {                                                                                             \
    ++checks;                                                                                      \
    if (!(cond)) {                                                                                 \
      ++failures;                                                                                  \
      std::printf("  FAILED %s:%d: %s\n", __FILE__, __LINE__, #cond);                              \
    }                                                                                              \
  } while (0)

#define CHECK_NEAR(a, b, tol) CHECK(std::fabs((a) - (b)) <= (tol))

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

void nullHandleIsSafe() { // every call accepts a null player without crashing
  CHECK(wp_load(nullptr, kSine.c_str()) == WP_ERR_INVALID_ARGUMENT);
  CHECK(wp_load_async(nullptr, kSine.c_str()) == WP_ERR_INVALID_ARGUMENT);
  CHECK(wp_load_wait(nullptr) == WP_ERR_INVALID_ARGUMENT);
  CHECK(wp_load_state(nullptr) == WP_ERR_INVALID_ARGUMENT);
  CHECK(wp_load_progress(nullptr) == 0.0);
  CHECK(wp_is_playing(nullptr) == 0);
  CHECK(wp_position(nullptr) == 0.0);
  CHECK(wp_duration(nullptr) == 0.0);
  CHECK(wp_loop_passes(nullptr) == 0);
  float mins[4], maxs[4];
  CHECK(wp_waveform(nullptr, 0, 1, 4, mins, maxs) == WP_ERR_INVALID_ARGUMENT);
  CHECK(wp_metro_is_running(nullptr) == 0);
  CHECK(wp_metro_bpm(nullptr) == 0);
  CHECK(wp_file_duration(nullptr) == WP_ERR_INVALID_ARGUMENT);
  // Calls without a result only must not crash.
  wp_play(nullptr);
  wp_pause(nullptr);
  wp_seek(nullptr, 1.0);
  wp_set_rate(nullptr, 1.0);
  wp_set_loop(nullptr, 0.0, 2.0);
  wp_set_volume(nullptr, 0.0f);
  wp_metro_start(nullptr);
  wp_metro_stop(nullptr);
  wp_metro_set_bpm(nullptr, 120);
  wp_metro_set_meter(nullptr, 3);
  wp_metro_set_subdivision(nullptr, 2);
  wp_metro_set_volume(nullptr, 0.0f);
  wp_metro_set_ramp(nullptr, 1, 100, 120, 5, 4);
  wp_metro_set_ramp_timed(nullptr, 1, 100, 120, 60);
  wp_destroy(nullptr);
}

void errorMessagesAndFileDuration() {
  // Every error code has its own English text; 0 is no error.
  const std::string notFound = wp_error_message(WP_ERR_FILE_NOT_FOUND);
  const std::string unsupported = wp_error_message(WP_ERR_UNSUPPORTED_FORMAT);
  CHECK(!notFound.empty() && !unsupported.empty() && notFound != unsupported);
  // sine440.flac is exactly 1 s long (make_test_audio.sh).
  CHECK_NEAR(wp_file_duration(kSine.c_str()), 1.0, 1e-6);
  CHECK(wp_file_duration((kAudio / "missing.flac").string().c_str()) == WP_ERR_FILE_NOT_FOUND);
  CHECK(wp_file_duration("") == WP_ERR_INVALID_ARGUMENT);
}

// #105/AK2 (regression for found bug 39, fuzz regression capi/path_ending_in_dot): a path that ends
// in '.' (the folder ".", a file "song.") made miniaudio read past the end of the path
// (stack-buffer-overflow found by fuzz_capi). Such a file decodes like any other, a folder is a
// documented error.
void pathEndingInDot() {
  const fs::path dir = fs::temp_directory_path() / "wp_capi_tests_105";
  std::error_code ec;
  fs::create_directories(dir, ec);
  const fs::path dotted = dir / "sine440.";
  fs::copy_file(kSine, dotted, fs::copy_options::overwrite_existing, ec);
  CHECK(!ec);
  CHECK_NEAR(wp_file_duration(dotted.string().c_str()), 1.0, 1e-6);
  for (const std::string &folder : {std::string("."), (dir / ".").string()}) {
    const double d = wp_file_duration(folder.c_str());
    CHECK(d == WP_ERR_UNSUPPORTED_FORMAT || d == WP_ERR_FILE_UNREADABLE);
  }
  CHECK(wp_file_duration((dir / "missing.").string().c_str()) == WP_ERR_FILE_NOT_FOUND);

  wp_player *p = wp_create();
  CHECK(p != nullptr);
  if (!p)
    return;
  wp_set_volume(p, 0.0f);
  const int r = wp_load(p, dotted.string().c_str());
  CHECK(r == WP_OK || (!nullBackend && r == WP_ERR_DEVICE_UNAVAILABLE));
  if (wptest::needs(wptest::kAudioDeviceRequired, r != WP_ERR_DEVICE_UNAVAILABLE,
                    "no audio device, folder load check skipped", failures) &&
      r == WP_OK) {
    CHECK_NEAR(wp_duration(p), 1.0, 1e-3);
    const int folder = wp_load(p, ".");
    CHECK(folder == WP_ERR_UNSUPPORTED_FORMAT || folder == WP_ERR_FILE_UNREADABLE);
  }
  wp_destroy(p);
  fs::remove_all(dir, ec);
}

void loadAndTransport() {
  wp_player *p = wp_create();
  CHECK(p != nullptr);
  if (!p)
    return;
  wp_set_volume(p, 0.0f);
  CHECK(wp_load(p, nullptr) == WP_ERR_INVALID_ARGUMENT);
  CHECK(wp_load_state(p) == WP_LOAD_IDLE); // a missing path does not start a load
  // No title yet: no waveform.
  float mins[10], maxs[10];
  CHECK(wp_waveform(p, 0.0, 1.0, 10, mins, maxs) == WP_ERR_INVALID_ARGUMENT);

  const int r = wp_load(p, kSine.c_str());
  CHECK(r == WP_OK || (!nullBackend && r == WP_ERR_DEVICE_UNAVAILABLE));
  if (!wptest::needs(wptest::kAudioDeviceRequired, r != WP_ERR_DEVICE_UNAVAILABLE,
                     "no audio device, load checks skipped", failures)) {
    wp_destroy(p);
    return;
  }
  CHECK(wp_load_state(p) == WP_LOAD_READY);
  CHECK(wp_load_progress(p) == 1.0);
  CHECK_NEAR(wp_duration(p), 1.0, 1e-3); // 1 s, resampled to the device rate
  CHECK(wp_is_playing(p) == 0);

  // A missing file is reported by the async load as well.
  CHECK(wp_load(p, (kAudio / "missing.flac").string().c_str()) == WP_ERR_FILE_NOT_FOUND);
  CHECK(wp_load(p, kSine.c_str()) == WP_OK);

  wp_seek(p, 0.5);
  CHECK(eventually([&] { return std::fabs(wp_position(p) - 0.5) < 1e-3; }));
  wp_set_rate(p, 5.0); // clamped to 2.0; position stays
  CHECK_NEAR(wp_position(p), 0.5, 1e-3);

  // 10 sections of a sine with amplitude ~1 (FLAC full scale): every section reaches the peaks.
  CHECK(wp_waveform(p, 0.0, 1.0, 10, mins, maxs) == WP_OK);
  bool peaks = true;
  for (int i = 0; i < 10; ++i)
    peaks = peaks && maxs[i] > 0.4f && mins[i] < -0.4f;
  CHECK(peaks);
  CHECK(wp_waveform(p, 0.5, 0.5, 10, mins, maxs) == WP_ERR_INVALID_ARGUMENT); // start >= end

  wp_set_loop(p, 0.0, 0.5); // shorter than 1 s: ignored, counter stays
  const long long passes = wp_loop_passes(p);
  wp_play(p);
  CHECK(eventually([&] { return wp_is_playing(p) == 1; }));
  // The device consumes audio: the position moves on from 0.5 s (also on the null device).
  CHECK(eventually([&] { return wp_position(p) > 0.55; }));
  wp_pause(p);
  CHECK(eventually([&] { return wp_is_playing(p) == 0; }));
  CHECK(wp_loop_passes(p) == passes);
  wp_destroy(p);
}

void metronomeThroughCApi() {
  wp_player *p = wp_create();
  CHECK(p != nullptr);
  if (!p)
    return;
  wp_metro_set_volume(p, 0.0f);
  wp_metro_set_bpm(p, 500); // range 20–300
  CHECK(wp_metro_bpm(p) == 300);
  wp_metro_set_bpm(p, 5);
  CHECK(wp_metro_bpm(p) == 20);
  wp_metro_set_bpm(p, 120);
  CHECK(wp_metro_bpm(p) == 120);
  wp_metro_set_meter(p, 3);
  wp_metro_set_subdivision(p, 2);
  CHECK(wp_metro_is_running(p) == 0);
  wp_metro_start(p);
  CHECK(wp_metro_is_running(p) == 1);
  wp_metro_stop(p);
  CHECK(wp_metro_is_running(p) == 0);
  // Switching a ramp on while stopped sets its start tempo (bars: 100 BPM, time: 90 BPM).
  wp_metro_set_ramp(p, 1, 100, 140, 5, 4);
  CHECK(wp_metro_bpm(p) == 100);
  wp_metro_set_ramp(p, 0, 100, 140, 5, 4); // off: the tempo stays
  CHECK(wp_metro_bpm(p) == 100);
  wp_metro_set_ramp_timed(p, 1, 90, 140, 60);
  CHECK(wp_metro_bpm(p) == 90);
  wp_destroy(p);
}

// Recording itself needs real system audio and the user's permission (#51); only the states
// before a recording and the argument check are tested. Other platforms have the stub.
void recorderStartsIdle() {
#if defined(__APPLE__)
  CHECK(wp_rec_start(nullptr) == WP_REC_ERR_INVALID_PATH);
  CHECK(std::strcmp(wp_rec_error(), "No file path") == 0);
#else
  CHECK(wp_rec_available() == 0);
  CHECK(wp_rec_start("x.wav") == WP_REC_ERR_UNSUPPORTED);
#endif
  CHECK(wp_rec_is_recording() == 0);
  CHECK(wp_rec_seconds() == 0.0);
  CHECK(wp_rec_level() == 0.0f);
  CHECK(wp_rec_only_silence() == 1);
  CHECK(wp_rec_os_status() == 0);
  wp_rec_stop(); // stopping without a recording is harmless
  CHECK(wp_rec_is_recording() == 0);
}

// #125/AK2, AK3: unset or empty skips with the reason, 1 makes a missing resource a failure, any
// other value fails with the variable's name and the allowed value. Messages go to a temp file.
void requiredVariable() {
  using wptest::Requirement;
  CHECK(wptest::requirement(nullptr) == Requirement::Optional);
  CHECK(wptest::requirement("") == Requirement::Optional);
  CHECK(wptest::requirement("1") == Requirement::Required);
  for (const char *bad : {"0", "yes", "true", " 1", "1 "})
    CHECK(wptest::requirement(bad) == Requirement::Invalid);

  const char *var = "WP_SELFTEST_REQUIRED";
  std::FILE *out = std::tmpfile();
  CHECK(out != nullptr);
  if (!out)
    return;
  const auto written = [out] {
    std::string text(512, '\0');
    CHECK(std::fseek(out, 0, SEEK_SET) == 0);
    text.resize(std::fread(text.data(), 1, text.size(), out));
    CHECK(std::fseek(out, 0, SEEK_SET) == 0);
    return text;
  };
  int f = 0;
  unsetenv(var); // NOLINT(concurrency-mt-unsafe): single-threaded here
  CHECK(wptest::needs(var, true, "selftest resource missing", f, out) && f == 0);
  CHECK(!wptest::needs(var, false, "selftest resource missing", f, out) && f == 0);
  CHECK(written().find("skipped: selftest resource missing") != std::string::npos);

  setenv(var, "1", 1); // NOLINT(concurrency-mt-unsafe): single-threaded here
  CHECK(wptest::needs(var, true, "selftest resource missing", f, out) && f == 0);
  CHECK(!wptest::needs(var, false, "selftest resource missing", f, out) && f == 1);
  CHECK(written().find("FAILED selftest resource missing, but WP_SELFTEST_REQUIRED=1") !=
        std::string::npos);

  setenv(var, "yes", 1); // NOLINT(concurrency-mt-unsafe): single-threaded here
  CHECK(!wptest::needs(var, true, "selftest resource missing", f, out) && f == 2);
  CHECK(written().find("FAILED WP_SELFTEST_REQUIRED=yes is not allowed: use 1") !=
        std::string::npos);
  unsetenv(var); // NOLINT(concurrency-mt-unsafe): single-threaded here
  std::fclose(out);
}

} // namespace

int main(int argc, char **argv) {
  if (argc > 1 && std::strcmp(argv[1], "--null-backend") == 0) {
    nullBackend = true;
    setenv("WP_AUDIO_BACKEND", "null", 1); // NOLINT(concurrency-mt-unsafe): before any thread
    std::printf("WP_AUDIO_BACKEND=null\n");
  }
  const std::vector<std::pair<std::string, std::function<void()>>> tests = {
      {"nullHandleIsSafe", nullHandleIsSafe},
      {"errorMessagesAndFileDuration", errorMessagesAndFileDuration},
      {"pathEndingInDot", pathEndingInDot},
      {"loadAndTransport", loadAndTransport},
      {"metronomeThroughCApi", metronomeThroughCApi},
      {"recorderStartsIdle", recorderStartsIdle},
      {"requiredVariable", requiredVariable},
  };
  for (auto &[name, fn] : tests) {
    const int before = failures;
    fn();
    std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name.c_str());
  }
  std::printf("%d checks, %d failures\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
