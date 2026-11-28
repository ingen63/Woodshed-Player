// #162: recording on Windows and Linux: only the microphone (the default input device through
// miniaudio: WASAPI, PulseAudio or ALSA), as FLAC with 24 bit like on the Mac, also armed (#140,
// #147). No system audio there. Ring buffer, writer thread, file, sound gate and the input
// (MicSource) are platform-independent (recorder_core.cpp); this file only holds the C API and its
// state. Portable C++, so the tests run it on every desktop (recorder_desktop_tests.cpp).
#include <atomic>
#include <mutex>
#include <string>

#include "recorder_core.hpp"
#include "wp_core.h"

namespace {

struct Recorder {
  std::mutex mutex;
  std::string error;
  std::atomic<bool> recording{false};
  std::atomic<double> sampleRate{0}; // of the input; 0 before the first start
  wp::rec::Capture capture;          // ring buffer, writer thread, file, level
  wp::rec::MicSource mic;            // device or artificial input (#162)
};

Recorder &rec() {
  static Recorder r;
  return r;
}

// Stores the English log text of a failed start and returns the error code.
int fail(Recorder &r, int code, const char *what) {
  r.error = what;
  return code;
}

void teardown(Recorder &r) {
  r.mic.close();
  r.capture.close();
  r.recording.store(false);
}

int startMic(Recorder &r, const char *path, const wp::rec::GateConfig *gate) {
  const int opened = r.mic.open();
  if (opened == WP_REC_ERR_ACCESS_DENIED)
    return fail(r, opened, "The system refuses access to the microphone");
  if (opened != 0)
    return fail(r, WP_REC_ERR_NO_INPUT, "No input device could be opened");
  r.sampleRate.store(r.mic.sampleRate());
  const int created = r.capture.open(path, r.sampleRate.load(), wp::rec::FileFormat::Flac, gate);
  if (created == WP_REC_ERR_OUT_OF_MEMORY)
    return fail(r, created, "No memory for the ring buffer");
  if (created != 0)
    return fail(r, WP_REC_ERR_FILE, "FLAC file could not be created");
  const int started = r.mic.start(r.capture);
  if (started == WP_REC_ERR_ACCESS_DENIED)
    return fail(r, started, "The system refuses access to the microphone");
  if (started != 0)
    return fail(r, WP_REC_ERR_START, "Microphone could not be started");
  return 0;
}

// Starts a recording of `source`; with `gate` armed (#140).
int start(const char *path, int source, const wp::rec::GateConfig *gate) {
  auto &r = rec();
  std::lock_guard<std::mutex> lock(r.mutex);
  if (r.recording.load())
    return 0;
  r.error.clear();
  if (!path)
    return fail(r, WP_REC_ERR_INVALID_PATH, "No file path");
  if (source != WP_REC_SOURCE_MIC)
    return fail(r, WP_REC_ERR_UNSUPPORTED,
                source == WP_REC_SOURCE_SYSTEM ? "System audio is recorded on the Mac only"
                                               : "Unknown recording source");
  if (gate && !gate->valid())
    return fail(r, WP_REC_ERR_INVALID_ARGUMENT, "Threshold or pause out of range");
  r.capture.meter().reset();
  const int res = startMic(r, path, gate);
  if (res != 0) {
    teardown(r);
    return res;
  }
  r.recording.store(true);
  return 0;
}

} // namespace

extern "C" {

int wp_rec_source_available(int source) {
  return source == WP_REC_SOURCE_MIC && rec().mic.available() ? 1 : 0;
}

int wp_rec_available(void) { return wp_rec_source_available(WP_REC_SOURCE_MIC); }

int wp_rec_start_source(const char *path, int source) { return start(path, source, nullptr); }

int wp_rec_start(const char *path) { return wp_rec_start_source(path, WP_REC_SOURCE_SYSTEM); }

int wp_rec_start_armed(const char *path, int source, double threshold_db, double silence_seconds) {
  const wp::rec::GateConfig gate{threshold_db, silence_seconds};
  return start(path, source, &gate);
}

int wp_rec_start_armed_tail(const char *path, int source, double threshold_db,
                            double silence_seconds, double tail_seconds) {
  const wp::rec::GateConfig gate{threshold_db, silence_seconds, tail_seconds};
  return start(path, source, &gate);
}

int wp_rec_gate_state(void) {
  const auto &capture = rec().capture;
  return capture.gated() ? static_cast<int>(capture.gate().state()) : WP_REC_GATE_OFF;
}

double wp_rec_kept_seconds(void) {
  auto &r = rec();
  return r.capture.gated()
             ? static_cast<double>(r.capture.gate().keptFrames()) / r.sampleRate.load()
             : wp_rec_seconds();
}

void wp_rec_stop(void) {
  auto &r = rec();
  std::lock_guard<std::mutex> lock(r.mutex);
  teardown(r);
}

int wp_rec_is_recording(void) { return rec().recording.load() ? 1 : 0; }

double wp_rec_seconds(void) {
  auto &r = rec();
  const double rate = r.sampleRate.load();
  return rate > 0 ? static_cast<double>(r.capture.meter().frames()) / rate : 0.0;
}

float wp_rec_level(void) { return rec().capture.meter().takeLevel(); }

int wp_rec_only_silence(void) { return rec().capture.meter().onlySilence() ? 1 : 0; }

// No OSStatus outside the Mac.
int wp_rec_os_status(void) { return 0; }

const char *wp_rec_error(void) { return rec().error.c_str(); }

int wp_rec_set_input(int input) {
  return rec().mic.setInput(input) ? 0 : WP_REC_ERR_INVALID_ARGUMENT;
}

} // extern "C"
