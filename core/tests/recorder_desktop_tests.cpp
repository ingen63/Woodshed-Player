// #162: tests of the recording of Windows and Linux (recorder_desktop.cpp) through its C API, with
// the artificial input (WP_REC_INPUT_SILENCE, WP_REC_INPUT_TONE) instead of a microphone, a device
// that refuses access (WP_REC_INPUT_DENIED) and none at all (WP_REC_INPUT_NONE). Portable: they run
// on every desktop, in CI on Windows (job «windows») and Linux (job «checks»). Files go to a folder
// and a name with umlauts, which on Windows only open as UTF-16 (#60).
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <thread>
#include <vector>

#include "flac_writer.hpp"
#include "miniaudio_impl.hpp"
#include "recorder_core.hpp"
#include "wp_core.h"

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

namespace fs = std::filesystem;
using wp::rec::SimulatedInput;

// UTF-8 form of a path (on Windows string() would give the ANSI code page).
std::string utf8(const fs::path &p) { return p.u8string(); }

// A fresh folder with umlauts in the temp folder, removed with everything in it at the end.
struct TempDir {
  fs::path path;
  TempDir() {
    static int counter = 0;
    const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    path = fs::temp_directory_path() /
           fs::u8path("wp_rec_desktop_" + std::to_string(stamp) + "_" + std::to_string(++counter) +
                      " \xC3\x9C"
                      "bung");
    fs::create_directories(path);
  }
  TempDir(const TempDir &) = delete;
  TempDir &operator=(const TempDir &) = delete;
  ~TempDir() {
    std::error_code ec;
    fs::remove_all(path, ec);
  }
  // UTF-8 path of the file `name` (UTF-8) in this folder.
  [[nodiscard]] std::string file(const std::string &name) const {
    return utf8(path / fs::u8path(name));
  }
};

bool exists(const std::string &utf8Path) { return fs::exists(fs::u8path(utf8Path)); }

std::vector<uint8_t> readBytes(const std::string &utf8Path) {
  std::ifstream f(fs::u8path(utf8Path), std::ios::binary);
  return {std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>()};
}

// Rate, channels and bits per sample from the STREAMINFO of a FLAC file; zeros if it is none.
struct StreamInfo {
  uint32_t rate = 0;
  uint32_t channels = 0;
  uint32_t bits = 0;
};
StreamInfo streamInfo(const std::string &utf8Path) {
  const auto b = readBytes(utf8Path);
  StreamInfo s;
  if (b.size() < 42 || std::memcmp(b.data(), "fLaC", 4) != 0 || (b[4] & 0x7f) != 0)
    return s;
  s.rate = static_cast<uint32_t>(b[18]) << 12 | static_cast<uint32_t>(b[19]) << 4 |
           static_cast<uint32_t>(b[20]) >> 4;
  s.channels = ((b[20] >> 1) & 7u) + 1;
  s.bits = ((b[20] & 1u) << 4 | static_cast<uint32_t>(b[21]) >> 4) + 1;
  return s;
}

// Decoded file: interleaved float, empty if it cannot be read.
struct Decoded {
  bool ok = false;
  uint32_t rate = 0;
  uint32_t channels = 0;
  std::vector<float> samples;
  [[nodiscard]] double seconds() const {
    return channels && rate ? static_cast<double>(samples.size()) / channels / rate : 0.0;
  }
  [[nodiscard]] float peak() const {
    float p = 0;
    for (const float v : samples)
      p = std::max(p, std::fabs(v));
    return p;
  }
};
Decoded decode(const std::string &utf8Path) {
  Decoded d;
  ma_decoder dec;
  const ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, 0, 0);
  if (wp_decoder_init_file(utf8Path.c_str(), &cfg, &dec) != MA_SUCCESS)
    return d;
  d.ok = true;
  d.rate = dec.outputSampleRate;
  d.channels = dec.outputChannels;
  std::vector<float> block(4096 * static_cast<size_t>(dec.outputChannels));
  for (;;) {
    ma_uint64 read = 0;
    ma_decoder_read_pcm_frames(&dec, block.data(), 4096, &read);
    if (read == 0)
      break;
    d.samples.insert(d.samples.end(), block.begin(),
                     block.begin() + static_cast<std::ptrdiff_t>(read * dec.outputChannels));
  }
  ma_decoder_uninit(&dec);
  return d;
}

void sleepSeconds(double s) { std::this_thread::sleep_for(std::chrono::duration<double>(s)); }

// Waits until the gate is in `state`, at most `guard` seconds (protection against a hang).
bool waitForGate(int state, double guard = 10.0) {
  const auto end = std::chrono::steady_clock::now() + std::chrono::duration<double>(guard);
  while (wp_rec_gate_state() != state) {
    if (std::chrono::steady_clock::now() > end)
      return false;
    std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  return true;
}

// ---- Input selection ----

void unknownInputIsRejected() { // #162
  CHECK(wp_rec_set_input(-1) == WP_REC_ERR_INVALID_ARGUMENT);
  CHECK(wp_rec_set_input(WP_REC_INPUT_NONE + 1) == WP_REC_ERR_INVALID_ARGUMENT);
  CHECK(wp_rec_set_input(WP_REC_INPUT_SILENCE) == 0);
  CHECK(wp_rec_source_available(WP_REC_SOURCE_MIC) == 1); // the rejected values changed nothing
}

void withoutInputDeviceNothingIsAvailable() { // #162/AK1: no input device, no record button
  CHECK(wp_rec_set_input(WP_REC_INPUT_NONE) == 0);
  CHECK(wp_rec_source_available(WP_REC_SOURCE_MIC) == 0);
  CHECK(wp_rec_available() == 0);
  for (const int input : {WP_REC_INPUT_SILENCE, WP_REC_INPUT_TONE, WP_REC_INPUT_DENIED}) {
    CHECK(wp_rec_set_input(input) == 0);
    CHECK(wp_rec_source_available(WP_REC_SOURCE_MIC) == 1);
    CHECK(wp_rec_available() == 1);
  }
  // The real device: available exactly when miniaudio lists an input device.
  CHECK(wp_rec_set_input(WP_REC_INPUT_DEVICE) == 0);
  CHECK(wp_rec_source_available(WP_REC_SOURCE_MIC) == (wp::rec::hasInputDevice() ? 1 : 0));
}

void systemAudioIsMacOnly() { // #162: no system audio on Windows and Linux
  CHECK(wp_rec_set_input(WP_REC_INPUT_TONE) == 0);
  CHECK(wp_rec_source_available(WP_REC_SOURCE_SYSTEM) == 0);
  CHECK(wp_rec_source_available(7) == 0);
  TempDir dir;
  const std::string path = dir.file("system.flac");
  CHECK(wp_rec_start(path.c_str()) == WP_REC_ERR_UNSUPPORTED);
  CHECK(std::strcmp(wp_rec_error(), "System audio is recorded on the Mac only") == 0);
  CHECK(wp_rec_start_source(path.c_str(), 7) == WP_REC_ERR_UNSUPPORTED);
  CHECK(std::strcmp(wp_rec_error(), "Unknown recording source") == 0);
  CHECK(wp_rec_is_recording() == 0);
  CHECK(!exists(path));
}

void invalidStartsLeaveNothing() { // #162: the checks of the Mac apply as well
  CHECK(wp_rec_set_input(WP_REC_INPUT_TONE) == 0);
  CHECK(wp_rec_start_source(nullptr, WP_REC_SOURCE_MIC) == WP_REC_ERR_INVALID_PATH);
  CHECK(std::strcmp(wp_rec_error(), "No file path") == 0);
  TempDir dir;
  const std::string path = dir.file("armed.flac");
  CHECK(wp_rec_start_armed(path.c_str(), WP_REC_SOURCE_MIC, 1.0, 5.0) ==
        WP_REC_ERR_INVALID_ARGUMENT);
  CHECK(std::strcmp(wp_rec_error(), "Threshold or pause out of range") == 0);
  CHECK(wp_rec_start_armed_tail(path.c_str(), WP_REC_SOURCE_MIC, -30.0, 5.0, 10.5) ==
        WP_REC_ERR_INVALID_ARGUMENT);
  CHECK(wp_rec_is_recording() == 0);
  CHECK(!exists(path));
  // A folder that does not exist: no file.
  const std::string missing = utf8(dir.path / "missing" / "take.flac");
  CHECK(wp_rec_start_source(missing.c_str(), WP_REC_SOURCE_MIC) == WP_REC_ERR_FILE);
  CHECK(std::strcmp(wp_rec_error(), "FLAC file could not be created") == 0);
  CHECK(wp_rec_is_recording() == 0);
}

void deniedMicrophoneStartsNothing() { // #162/AK3: the privacy setting refuses the microphone
  CHECK(wp_rec_set_input(WP_REC_INPUT_DENIED) == 0);
  TempDir dir;
  const std::string path = dir.file("denied.flac");
  CHECK(wp_rec_start_source(path.c_str(), WP_REC_SOURCE_MIC) == WP_REC_ERR_ACCESS_DENIED);
  CHECK(std::strcmp(wp_rec_error(), "The system refuses access to the microphone") == 0);
  CHECK(wp_rec_is_recording() == 0);
  CHECK(wp_rec_start_armed_tail(path.c_str(), WP_REC_SOURCE_MIC, -30.0, 5.0, 1.0) ==
        WP_REC_ERR_ACCESS_DENIED);
  CHECK(wp_rec_is_recording() == 0);
  CHECK(wp_rec_gate_state() == WP_REC_GATE_OFF);
  CHECK(!exists(path));
}

void noInputDeviceStartsNothing() { // #162/AK1
  CHECK(wp_rec_set_input(WP_REC_INPUT_NONE) == 0);
  TempDir dir;
  const std::string path = dir.file("none.flac");
  CHECK(wp_rec_start_source(path.c_str(), WP_REC_SOURCE_MIC) == WP_REC_ERR_NO_INPUT);
  CHECK(std::strcmp(wp_rec_error(), "No input device could be opened") == 0);
  CHECK(wp_rec_is_recording() == 0);
  CHECK(!exists(path));
}

void deviceErrorsMapToTheirCodes() { // #162/AK3: only a refusal of access names the setting
  CHECK(wp::rec::micOpenError(MA_ACCESS_DENIED) == WP_REC_ERR_ACCESS_DENIED);
  for (const ma_result r : {MA_NO_DEVICE, MA_ERROR, MA_FAILED_TO_INIT_BACKEND,
                            MA_DEVICE_NOT_INITIALIZED, MA_INVALID_ARGS, MA_SUCCESS})
    CHECK(wp::rec::micOpenError(r) == WP_REC_ERR_NO_INPUT);
  CHECK(wp::rec::micStartError(MA_ACCESS_DENIED) == WP_REC_ERR_ACCESS_DENIED);
  for (const ma_result r : {MA_ERROR, MA_DEVICE_NOT_INITIALIZED, MA_INVALID_OPERATION, MA_SUCCESS})
    CHECK(wp::rec::micStartError(r) == WP_REC_ERR_START);
}

void nullBackendListsAnInputDevice() { // #162: the device list of given backends
  ma_backend backends[] = {ma_backend_null};
  CHECK(wp::rec::hasInputDevice(backends, 1));
  // Chosen by miniaudio itself, the null backend (no audio hardware) has no microphone.
  CHECK(!wp::rec::isSystemInput(false, ma_backend_null));
  CHECK(wp::rec::isSystemInput(true, ma_backend_null));
  CHECK(wp::rec::isSystemInput(false, ma_backend_wasapi));
  CHECK(wp::rec::isSystemInput(false, ma_backend_pulseaudio));
  ma_context ctx;
  CHECK(ma_context_init(backends, 1, nullptr, &ctx) == MA_SUCCESS);
  CHECK(wp::rec::hasInputDeviceOn(&ctx));
  ma_context_uninit(&ctx);
}

void micSourceOnTheNullBackend() { // #162: the device path of MicSource without a microphone
  ma_backend backends[] = {ma_backend_null};
  ma_context ctx;
  CHECK(ma_context_init(backends, 1, nullptr, &ctx) == MA_SUCCESS);
  {
    wp::rec::MicSource mic(&ctx);
    CHECK(mic.input() == WP_REC_INPUT_DEVICE);
    CHECK(mic.available());
    CHECK(mic.available()); // asked once, then kept
    CHECK(mic.open() == 0);
    CHECK(mic.sampleRate() > 0);
    TempDir dir;
    const std::string path = dir.file("null.flac");
    wp::rec::Capture capture;
    CHECK(capture.open(path.c_str(), mic.sampleRate(), wp::rec::FileFormat::Flac) == 0);
    CHECK(mic.start(capture) == 0);
    mic.close();
    CHECK(mic.sampleRate() == 0.0); // the device is closed
    capture.close();
    // An artificial input, then none: the next open closes the artificial one first.
    CHECK(mic.setInput(WP_REC_INPUT_SILENCE));
    CHECK(mic.open() == 0);
    CHECK(mic.sampleRate() == SimulatedInput::kSampleRate);
    CHECK(mic.setInput(WP_REC_INPUT_NONE));
    CHECK(!mic.available());
    CHECK(mic.open() == WP_REC_ERR_NO_INPUT);
    CHECK(mic.sampleRate() == 0.0);
    CHECK(!mic.setInput(9));
    CHECK(mic.input() == WP_REC_INPUT_NONE);
  }
  ma_context_uninit(&ctx);
}

// The first `frames` samples of a take of the sine from a fresh capture.
std::vector<float> takeStart(SimulatedInput &sim, const std::string &path, uint32_t frames) {
  wp::rec::Capture capture;
  CHECK(capture.open(path.c_str(), SimulatedInput::kSampleRate, wp::rec::FileFormat::Flac) == 0);
  sim.start(capture);
  sleepSeconds(0.1);
  sim.close();
  capture.close();
  Decoded d = decode(path);
  d.samples.resize(static_cast<size_t>(frames) * 2);
  return d.samples;
}

void simulatedTakesDiffer() { // #162: the library would keep only one of two identical takes
  TempDir dir;
  SimulatedInput sim;
  sim.setTone(true);
  const auto first = takeStart(sim, dir.file("one.flac"), 2048);
  const auto second = takeStart(sim, dir.file("two.flac"), 2048);
  CHECK(first.size() == second.size());
  CHECK(first != second);
  // Within a take one unbroken sine, block after block (here from frame 0 of a fresh input).
  std::vector<float> expected(2048 * 2);
  SimulatedInput::render(expected.data(), 2048, 0, true);
  float diff = 0;
  for (size_t i = 0; i < expected.size(); ++i)
    diff = std::max(diff, std::fabs(first[i] - expected[i]));
  CHECK(diff < 1e-6f);
}

void simulatedInputStopsWhenRestartedOrDestroyed() { // #162: never two threads, none left over
  TempDir dir;
  const std::string path = dir.file("restart.flac");
  wp::rec::Capture capture;
  CHECK(capture.open(path.c_str(), SimulatedInput::kSampleRate, wp::rec::FileFormat::Flac) == 0);
  {
    SimulatedInput sim;
    sim.start(capture);
    sim.start(capture); // stops the running thread first
    sleepSeconds(0.05);
  } // destroyed while running: stops its thread
  const long long frames = capture.meter().frames();
  CHECK(frames > 0);
  sleepSeconds(0.1);
  CHECK(capture.meter().frames() == frames);
  capture.close();
}

// ---- Artificial input ----

void simulatedInputRendersSineOrSilence() { // #162/AK4
  constexpr uint32_t kFrames = 4800;
  std::vector<float> silence(kFrames * 2, 1.0f);
  SimulatedInput::render(silence.data(), kFrames, 0, false);
  CHECK(std::all_of(silence.begin(), silence.end(), [](float v) { return v == 0.0f; }));
  std::vector<float> tone(kFrames * 2);
  SimulatedInput::render(tone.data(), kFrames, 0, true);
  float peak = 0;
  bool sameChannels = true;
  for (uint32_t i = 0; i < kFrames; ++i) {
    const double expected =
        SimulatedInput::kToneAmplitude *
        std::sin(6.283185307179586 * SimulatedInput::kToneHz * i / SimulatedInput::kSampleRate);
    CHECK(std::fabs(tone[2 * i] - expected) < 1e-6);
    sameChannels = sameChannels && tone[2 * i] == tone[2 * i + 1];
    peak = std::max(peak, std::fabs(tone[2 * i]));
  }
  CHECK(sameChannels);
  CHECK(peak > 0.249f && peak <= SimulatedInput::kToneAmplitude);
  // From a later position it continues the same sine (also across a full second).
  std::vector<float> later(100 * 2);
  SimulatedInput::render(later.data(), 100, 1000, true);
  for (uint32_t i = 0; i < 100; ++i)
    CHECK(std::fabs(later[2 * i] - tone[2 * (1000 + i)]) < 1e-6);
  SimulatedInput::render(later.data(), 100, 48000 + 1000, true);
  for (uint32_t i = 0; i < 100; ++i)
    CHECK(std::fabs(later[2 * i] - tone[2 * (1000 + i)]) < 1e-6);
}

void simulatedInputRunsInRealTime() { // #162/AK4: blocks at the pace of a device
  wp::rec::Capture capture;
  TempDir dir;
  const std::string path = dir.file("pace.flac");
  CHECK(capture.open(path.c_str(), SimulatedInput::kSampleRate, wp::rec::FileFormat::Flac) == 0);
  SimulatedInput sim;
  sim.setTone(true);
  CHECK(sim.tone());
  const auto begin = std::chrono::steady_clock::now();
  sim.start(capture);
  sleepSeconds(0.5);
  sim.close();
  const double elapsed =
      std::chrono::duration<double>(std::chrono::steady_clock::now() - begin).count();
  const double recorded =
      static_cast<double>(capture.meter().frames()) / SimulatedInput::kSampleRate;
  capture.close();
  // Not faster than real time (one block ahead at most), and not much slower.
  CHECK(recorded <= elapsed + 2.0 * wp::rec::kBlockFrames / SimulatedInput::kSampleRate);
  CHECK(recorded >= 0.3);
  CHECK(!capture.meter().onlySilence());
  // Closed: nothing arrives any more.
  const long long frames = capture.meter().frames();
  sleepSeconds(0.1);
  CHECK(capture.meter().frames() == frames);
  sim.close(); // twice is fine
}

// ---- Recording ----

void toneRecordsFlacWith24Bit() { // #162/AK2, AK4: microphone as FLAC 24 bit, umlauts in the path
  CHECK(wp_rec_set_input(WP_REC_INPUT_TONE) == 0);
  TempDir dir;
  const std::string path = dir.file("Recording \xC3\xA4\xC3\xB6\xC3\xBC.flac");
  CHECK(wp_rec_start_source(path.c_str(), WP_REC_SOURCE_MIC) == 0);
  CHECK(wp_rec_is_recording() == 1);
  CHECK(wp_rec_start_source(path.c_str(), WP_REC_SOURCE_MIC) == 0); // already running: no change
  sleepSeconds(1.0);
  CHECK(wp_rec_level() > 0.2f);
  CHECK(wp_rec_only_silence() == 0);
  CHECK(wp_rec_gate_state() == WP_REC_GATE_OFF);
  wp_rec_stop();
  CHECK(wp_rec_is_recording() == 0);
  const double seconds = wp_rec_seconds();
  CHECK(seconds > 0.7 && seconds < 1.5);
  sleepSeconds(0.1);
  CHECK(wp_rec_seconds() == seconds); // stopped: the input delivers nothing any more
  CHECK(wp_rec_kept_seconds() == seconds);
  CHECK(wp_rec_os_status() == 0);
  CHECK(exists(path));
  const StreamInfo info = streamInfo(path);
  CHECK(info.rate == 48000);
  CHECK(info.channels == 2);
  CHECK(info.bits == 24);
  const Decoded d = decode(path);
  CHECK(d.ok);
  CHECK(std::fabs(d.seconds() - seconds) < 0.01);
  CHECK(d.peak() > 0.24f && d.peak() < 0.26f);
  wp_rec_stop(); // twice is fine
}

void silenceIsReportedAsSilence() { // #162: only silence arrives (as without a signal)
  CHECK(wp_rec_set_input(WP_REC_INPUT_SILENCE) == 0);
  TempDir dir;
  const std::string path = dir.file("silence.flac");
  CHECK(wp_rec_start_source(path.c_str(), WP_REC_SOURCE_MIC) == 0);
  sleepSeconds(0.3);
  CHECK(wp_rec_only_silence() == 1);
  CHECK(wp_rec_level() == 0.0f);
  wp_rec_stop();
  const Decoded d = decode(path);
  CHECK(d.ok && d.peak() == 0.0f && d.seconds() > 0.1);
}

void armedRecordsThreePhases() { // #162/AK4 (in place of AK6): «Armed», three times sound
  CHECK(wp_rec_set_input(WP_REC_INPUT_SILENCE) == 0);
  TempDir dir;
  for (int take = 1; take <= 3; ++take) {
    const std::string path = dir.file("Take " + std::to_string(take) + " \xC3\xBC.flac");
    CHECK(wp_rec_start_armed_tail(path.c_str(), WP_REC_SOURCE_MIC, -30.0, 0.5, 0.2) == 0);
    CHECK(wp_rec_gate_state() == WP_REC_GATE_ARMED);
    sleepSeconds(0.3);
    CHECK(wp_rec_gate_state() == WP_REC_GATE_ARMED); // silence keeps it waiting
    CHECK(wp_rec_kept_seconds() == 0.0);
    CHECK(wp_rec_set_input(WP_REC_INPUT_TONE) == 0); // playing
    CHECK(waitForGate(WP_REC_GATE_RECORDING));
    sleepSeconds(0.5);
    CHECK(wp_rec_set_input(WP_REC_INPUT_SILENCE) == 0); // the pause after the phase
    CHECK(waitForGate(WP_REC_GATE_DONE));
    const double kept = wp_rec_kept_seconds();
    wp_rec_stop();
    CHECK(wp_rec_is_recording() == 0);
    // Up to 1 s before the sound (here 0.3 s and more of silence), the sound, 0.2 s after it.
    const Decoded d = decode(path);
    CHECK(d.ok);
    CHECK(streamInfo(path).bits == 24);
    CHECK(std::fabs(d.seconds() - kept) < 0.01);
    CHECK(d.seconds() > 0.9 && d.seconds() < 2.5);
    CHECK(d.peak() > 0.24f);
  }
  // Three files, one per phase.
  int files = 0;
  for (const auto &entry : fs::directory_iterator(dir.path))
    files += entry.path().extension() == ".flac" ? 1 : 0;
  CHECK(files == 3);
}

void stoppedWhileArmedKeepsNoSound() { // #162: stopped before the sound: an empty take
  CHECK(wp_rec_set_input(WP_REC_INPUT_SILENCE) == 0);
  TempDir dir;
  const std::string path = dir.file("armed.flac");
  CHECK(wp_rec_start_armed(path.c_str(), WP_REC_SOURCE_MIC, -30.0, 1.0) == 0);
  sleepSeconds(0.2);
  CHECK(wp_rec_gate_state() == WP_REC_GATE_ARMED);
  wp_rec_stop();
  CHECK(wp_rec_kept_seconds() == 0.0);
  const Decoded d = decode(path);
  CHECK(!d.ok || d.samples.empty());
}

// ---- Files with umlauts (#60: on Windows only as UTF-16) ----

void flacWriterOpensUtf8Paths() { // #162/AK2
  TempDir dir;
  const std::string path = dir.file("\xC3\x84nderung \xC3\xA9t\xC3\xA9.flac");
  wp::FlacWriter w;
  CHECK(w.open(path.c_str(), 44100, 2));
  const float frames[4] = {0.5f, -0.5f, 0.25f, -0.25f};
  CHECK(w.write(frames, 2));
  CHECK(w.close());
  CHECK(exists(path));
  const StreamInfo info = streamInfo(path);
  CHECK(info.rate == 44100 && info.channels == 2 && info.bits == 24);
  CHECK(decode(path).samples.size() == 4);
  // A file that cannot be created: false, no file.
  const std::string missing = utf8(dir.path / "missing" / "x.flac");
  CHECK(!w.open(missing.c_str(), 44100, 2));
  CHECK(!w.isOpen());
}

void wavFileOpensUtf8Paths() { // #162: the older WAV format as well
  TempDir dir;
  const std::string path = dir.file("\xC3\x9C"
                                    "berblick.wav");
  wp::rec::WavFile wav;
  CHECK(wav.open(path.c_str(), 48000));
  const float frames[4] = {0.5f, -0.5f, 0.25f, -0.25f};
  wav.write(frames, 2);
  wav.close();
  const Decoded d = decode(path);
  CHECK(d.ok && d.samples.size() == 4 && d.rate == 48000);
}

} // namespace

int main() {
  unknownInputIsRejected();
  withoutInputDeviceNothingIsAvailable();
  systemAudioIsMacOnly();
  invalidStartsLeaveNothing();
  deniedMicrophoneStartsNothing();
  noInputDeviceStartsNothing();
  deviceErrorsMapToTheirCodes();
  nullBackendListsAnInputDevice();
  micSourceOnTheNullBackend();
  simulatedInputStopsWhenRestartedOrDestroyed();
  simulatedTakesDiffer();
  simulatedInputRendersSineOrSilence();
  simulatedInputRunsInRealTime();
  toneRecordsFlacWith24Bit();
  silenceIsReportedAsSilence();
  armedRecordsThreePhases();
  stoppedWhileArmedKeepsNoSound();
  flacWriterOpensUtf8Paths();
  wavFileOpensUtf8Paths();
  std::printf("recorder_desktop_tests: %d checks, %d failed\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
