// Armed recording (#140): sound and silence detection (SoundGate) with generated sine and silence,
// alone and inside a Capture that writes FLAC. No audio device.
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <functional>
#include <string>
#include <thread>
#include <utility>
#include <vector>

#include "player_core.hpp"
#include "recorder_core.hpp"
#include "sound_gate.hpp"
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

using wp::rec::Capture;
using wp::rec::FileFormat;
using wp::rec::FrameSink;
using wp::rec::GateConfig;
using wp::rec::GateState;
using wp::rec::SoundGate;
using wp::rec::TapBuffer;

namespace fs = std::filesystem;

constexpr double kPi = 3.14159265358979323846;
constexpr uint32_t kRate = 48000;
// #140: start and end of the file within ±10 ms.
constexpr long long kTolerance = kRate / 100;

// Interleaved stereo test signal built from parts of sine and silence.
class Signal {
public:
  // `seconds` of a 440 Hz sine with peak `amplitude` (default -6 dBFS).
  Signal &tone(double seconds, float amplitude = 0.5f) {
    const auto n = frames(seconds);
    for (long long i = 0; i < n; ++i) {
      // Starts at its peak, so the first frame of the tone is already above the threshold.
      const auto v = static_cast<float>(amplitude * std::cos(2.0 * kPi * 440.0 * i / kRate));
      samples_.push_back(v);
      samples_.push_back(v);
    }
    return *this;
  }
  Signal &silence(double seconds) {
    samples_.insert(samples_.end(), static_cast<size_t>(frames(seconds)) * 2, 0.0f);
    return *this;
  }
  // `seconds` of a constant level (both channels), e.g. hiss below or at the threshold.
  Signal &level(double seconds, float value) {
    samples_.insert(samples_.end(), static_cast<size_t>(frames(seconds)) * 2, value);
    return *this;
  }
  [[nodiscard]] const std::vector<float> &samples() const { return samples_; }
  [[nodiscard]] uint32_t frameCount() const { return static_cast<uint32_t>(samples_.size() / 2); }
  static long long frames(double seconds) { return std::llround(seconds * kRate); }

private:
  std::vector<float> samples_;
};

// Collects what the gate keeps.
class Collect : public FrameSink {
public:
  void write(const float *frames, uint32_t count) override {
    samples.insert(samples.end(), frames, frames + static_cast<size_t>(count) * 2);
    ++writes;
  }
  [[nodiscard]] long long frames() const { return static_cast<long long>(samples.size() / 2); }
  std::vector<float> samples;
  int writes = 0;
};

// Feeds `signal` in blocks of `block` frames into a fresh gate; returns the kept frames.
Collect run(SoundGate &gate, const Signal &signal, uint32_t block = 4096,
            const GateConfig &config = {}) {
  Collect sink;
  CHECK(gate.init(kRate, 2, config));
  const uint32_t total = signal.frameCount();
  for (uint32_t done = 0; done < total;) {
    const uint32_t n = std::min(block, total - done);
    gate.feed(signal.samples().data() + static_cast<size_t>(done) * 2, n, sink);
    done += n;
  }
  return sink;
}

bool near(long long actual, long long expected) {
  return std::llabs(actual - expected) <= kTolerance;
}

// Index of the first kept frame above `threshold`, -1 if none.
long long firstAbove(const Collect &c, float threshold) {
  for (long long i = 0; i < c.frames(); ++i)
    if (std::fabs(c.samples[static_cast<size_t>(i) * 2]) > threshold)
      return i;
  return -1;
}

// Index of the last kept frame above `threshold`, -1 if none.
long long lastAbove(const Collect &c, float threshold) {
  for (long long i = c.frames() - 1; i >= 0; --i)
    if (std::fabs(c.samples[static_cast<size_t>(i) * 2]) > threshold)
      return i;
  return -1;
}

const float kThreshold = SoundGate::linear(-50.0);

// ---- The gate alone ----

void armedKeepsNothingBelowThreshold() { // #140/AK7
  // Hiss just below -50 dBFS (and exactly at it) for 10 s: armed, nothing kept.
  Signal s;
  s.level(5.0, kThreshold * 0.9f).level(5.0, kThreshold).silence(1.0);
  SoundGate gate;
  const Collect c = run(gate, s);
  CHECK(gate.state() == GateState::Armed);
  CHECK(c.frames() == 0);
  CHECK(c.writes == 0);
  CHECK(gate.keptFrames() == 0);
  CHECK(gate.firstSound() == -1);
  CHECK(gate.lastSound() == -1);
}

void recordingStartsOneSecondBeforeTheFirstSound() { // #140/AK8, #140/AK20
  // 3 s silence, 1 s tone, 6 s silence: the file holds 1 s before the tone, the tone, 2 s after.
  Signal s;
  s.silence(3.0).tone(1.0).silence(6.0);
  SoundGate gate;
  const Collect c = run(gate, s);
  CHECK(gate.firstSound() == Signal::frames(3.0));
  CHECK(near(firstAbove(c, kThreshold), Signal::frames(1.0)));
  CHECK(firstAbove(c, kThreshold) == Signal::frames(1.0)); // exact to the frame
  // The lead-in is the recorded silence before the tone, nothing cut.
  CHECK(std::all_of(c.samples.begin(), c.samples.begin() + Signal::frames(1.0) * 2,
                    [](float v) { return v == 0.0f; }));
  // The tone is complete and unchanged.
  const long long toneFrames = Signal::frames(1.0);
  for (long long i = 0; i < toneFrames * 2; ++i)
    if (c.samples[static_cast<size_t>(Signal::frames(1.0) * 2 + i)] !=
        s.samples()[static_cast<size_t>(Signal::frames(3.0) * 2 + i)]) {
      CHECK(false);
      break;
    }
}

void leadInFromTheRingAfterLongArming() { // #140/AK8: the ring keeps only the last second
  // 1 s of a quiet marker level, then 20 s silence, then the tone: the marker is long gone.
  Signal s;
  s.level(1.0, kThreshold * 0.5f).silence(20.0).tone(0.5).silence(6.0);
  SoundGate gate;
  const Collect c = run(gate, s, 1000);
  CHECK(firstAbove(c, kThreshold) == Signal::frames(1.0));
  CHECK(firstAbove(c, kThreshold * 0.1f) == Signal::frames(1.0)); // only silence before the tone
}

void leadInShorterWhenSoundComesEarly() { // #140/AK8: no invented audio before the arming
  Signal s;
  s.silence(0.3).tone(1.0).silence(6.0);
  SoundGate gate;
  const Collect c = run(gate, s);
  CHECK(firstAbove(c, kThreshold) == Signal::frames(0.3));
  CHECK(c.frames() == Signal::frames(0.3 + 1.0 + 2.0));
}

void soundAtTheVeryFirstFrame() { // #140/AK8
  Signal s;
  s.tone(1.0).silence(6.0);
  SoundGate gate;
  const Collect c = run(gate, s);
  CHECK(gate.firstSound() == 0);
  CHECK(firstAbove(c, kThreshold) == 0);
  CHECK(c.frames() == Signal::frames(3.0));
}

void recordingEndsTwoSecondsAfterTheLastSound() { // #140/AK9, #140/AK20
  // 1 s silence, 2 s tone, 8 s silence: done after 5 s of silence, the file ends 2 s after the
  // tone.
  Signal s;
  s.silence(1.0).tone(2.0).silence(8.0);
  SoundGate gate;
  const Collect c = run(gate, s);
  CHECK(gate.state() == GateState::Done);
  const long long last = lastAbove(c, kThreshold);
  CHECK(near(c.frames() - 1 - last, Signal::frames(2.0)));
  CHECK(c.frames() - 1 - last == Signal::frames(2.0)); // exact to the frame
  CHECK(gate.lastSound() - gate.firstSound() == last - firstAbove(c, kThreshold));
  CHECK(c.frames() == Signal::frames(1.0 + 2.0) + Signal::frames(2.0));
  CHECK(gate.keptFrames() == c.frames());
}

void stopsAfterFiveSecondsOfSilence() { // #140/AK9, #140/AK20
  // Not done 1 frame before 5 s of silence, done at 5 s.
  const long long silence = Signal::frames(5.0);
  Signal s;
  s.tone(1.0).silence(5.0);
  SoundGate gate;
  Collect sink;
  CHECK(gate.init(kRate, 2, {}));
  const auto total = s.frameCount();
  gate.feed(s.samples().data(), total - 1, sink);
  CHECK(gate.state() == GateState::Recording);
  gate.feed(s.samples().data() + static_cast<size_t>(total - 1) * 2, 1, sink);
  CHECK(gate.state() == GateState::Done);
  CHECK(gate.lastSound() == Signal::frames(1.0) - 1);
  CHECK(sink.frames() == Signal::frames(1.0) + Signal::frames(2.0));
  // Silence is counted from the frame after the last loud one.
  CHECK(static_cast<long long>(total) - 1 - gate.lastSound() == silence);
  // Afterwards nothing is kept any more, not even new sound.
  Signal more;
  more.tone(1.0);
  gate.feed(more.samples().data(), more.frameCount(), sink);
  CHECK(gate.state() == GateState::Done);
  CHECK(sink.frames() == Signal::frames(3.0));
}

void shortPausesStayInTheRecording() { // #140/AK10, #140/AK20
  // Tone 2 s, silence 4 s, tone 2 s: one recording with all three parts.
  Signal s;
  s.silence(2.0).tone(2.0).silence(4.0).tone(2.0).silence(7.0);
  SoundGate gate;
  const Collect c = run(gate, s);
  CHECK(gate.state() == GateState::Done);
  // 1 s lead-in + 2 + 4 + 2 + 2 s tail.
  CHECK(c.frames() == Signal::frames(1.0 + 2.0 + 4.0 + 2.0 + 2.0));
  // The pause is in the file as recorded: the second tone starts 7 s after the start of the file.
  const long long second = Signal::frames(1.0 + 2.0 + 4.0);
  CHECK(std::fabs(c.samples[static_cast<size_t>(second) * 2]) > kThreshold);
  CHECK(std::fabs(c.samples[static_cast<size_t>(second - 1) * 2]) == 0.0f);
  CHECK(c.samples == std::vector<float>(s.samples().begin() + Signal::frames(1.0) * 2,
                                        s.samples().begin() + Signal::frames(12.0) * 2));
}

void pauseJustBelowTheLimitKeepsRecording() { // #140/AK10: 4.99 s pause
  Signal s;
  s.tone(1.0).silence(4.99).tone(1.0).silence(6.0);
  SoundGate gate;
  const Collect c = run(gate, s, 333);
  CHECK(c.frames() ==
        Signal::frames(1.0) + Signal::frames(4.99) + Signal::frames(1.0) + Signal::frames(2.0));
}

void silenceAndThresholdCanBeChanged() { // #140/AK11
  // --silence 3: a 4 s pause ends the recording, the second tone is not in it.
  Signal s;
  s.tone(1.0).silence(4.0).tone(1.0).silence(4.0);
  SoundGate gate;
  Collect c = run(gate, s, 4096, {-50.0, 3.0});
  CHECK(gate.state() == GateState::Done);
  CHECK(c.frames() == Signal::frames(3.0));
  // --silence 1 (shorter than the tail): still 2 s after the last sound, done after 2 s.
  c = run(gate, s, 4096, {-50.0, 1.0});
  CHECK(c.frames() == Signal::frames(3.0));
  // --threshold -20: a tone at -26 dBFS does not start it, one at -14 dBFS does.
  Signal quiet;
  quiet.tone(1.0, 0.05f).silence(1.0);
  c = run(gate, quiet, 4096, {-20.0, 5.0});
  CHECK(gate.state() == GateState::Armed);
  CHECK(c.frames() == 0);
  Signal loud;
  loud.silence(0.5).tone(1.0, 0.2f).silence(6.0);
  c = run(gate, loud, 4096, {-20.0, 5.0});
  CHECK(gate.state() == GateState::Done);
  CHECK(c.frames() == Signal::frames(0.5 + 1.0 + 2.0));
  // At the default threshold the quiet tone counts.
  c = run(gate, quiet, 4096, {});
  CHECK(gate.state() == GateState::Recording);
}

void soundOnOneChannelCounts() { // #140/AK8: any channel above the threshold
  std::vector<float> frames(Signal::frames(2.0) * 2, 0.0f);
  frames[static_cast<size_t>(Signal::frames(1.5)) * 2 + 1] = 0.1f; // right channel only
  SoundGate gate;
  Collect sink;
  CHECK(gate.init(kRate, 2, {}));
  gate.feed(frames.data(), static_cast<uint32_t>(frames.size() / 2), sink);
  CHECK(gate.firstSound() == Signal::frames(1.5));
  CHECK(gate.state() == GateState::Recording);
  // Negative samples count by magnitude.
  frames.assign(frames.size(), 0.0f);
  frames[static_cast<size_t>(Signal::frames(0.25)) * 2] = -0.1f;
  CHECK(gate.init(kRate, 2, {}));
  gate.feed(frames.data(), static_cast<uint32_t>(frames.size() / 2), sink);
  CHECK(gate.firstSound() == Signal::frames(0.25));
}

void blockSizeDoesNotMatter() { // #140/AK8, AK9, AK10: same file for any block size
  Signal s;
  s.silence(1.7).tone(0.9).silence(3.3).tone(0.4).level(1.0, kThreshold * 0.5f).silence(6.0);
  SoundGate gate;
  const Collect whole = run(gate, s, s.frameCount());
  for (const uint32_t block : {1u, 7u, 512u, 4096u, 48000u}) {
    const Collect c = run(gate, s, block);
    CHECK(c.samples == whole.samples);
  }
  CHECK(whole.frames() == Signal::frames(1.0 + 0.9 + 3.3 + 0.4 + 2.0));
}

void initRejectsSettingsOutOfRange() { // #140/AK11
  SoundGate gate;
  CHECK(gate.init(kRate, 2, {-120.0, 0.1}));
  CHECK(gate.init(kRate, 2, {0.0, 3600.0}));
  CHECK(!gate.init(kRate, 2, {-120.5, 5.0}));
  CHECK(!gate.init(kRate, 2, {0.5, 5.0}));
  CHECK(!gate.init(kRate, 2, {-50.0, 0.05}));
  CHECK(!gate.init(kRate, 2, {-50.0, 3601.0}));
  CHECK(!gate.init(kRate, 2, {std::nan(""), 5.0}));
  CHECK(!gate.init(kRate, 2, {-50.0, std::nan("")}));
  CHECK(!gate.init(0, 2, {}));
  CHECK(!gate.init(-1, 2, {}));
  CHECK(!gate.init(kRate, 0, {}));
}

void initStartsOver() { // #140: a gate used before starts armed again
  Signal s;
  s.tone(1.0).silence(6.0);
  SoundGate gate;
  run(gate, s);
  CHECK(gate.state() == GateState::Done);
  CHECK(gate.init(kRate, 2, {}));
  CHECK(gate.state() == GateState::Armed);
  CHECK(gate.keptFrames() == 0);
  CHECK(gate.firstSound() == -1);
  CHECK(gate.lastSound() == -1);
  // The old lead-in does not leak into the next recording.
  Signal next;
  next.silence(0.2).tone(0.5).silence(6.0);
  const Collect c = run(gate, next);
  CHECK(c.frames() == Signal::frames(0.2 + 0.5 + 2.0));
}

void thresholdIsLinear() { // #140/AK7: -50 dBFS
  CHECK(std::fabs(SoundGate::linear(-50.0) - 0.0031623f) < 1e-6f);
  CHECK(std::fabs(SoundGate::linear(0.0) - 1.0f) < 1e-6f);
  CHECK(std::fabs(SoundGate::linear(-20.0) - 0.1f) < 1e-6f);
}

// ---- Inside a Capture (writer thread, FLAC file) ----

struct TempFile {
  fs::path path;
  TempFile() {
    const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
    path = fs::temp_directory_path() / ("wp_sound_gate_test_" + std::to_string(stamp) + ".flac");
  }
  TempFile(const TempFile &) = delete;
  TempFile &operator=(const TempFile &) = delete;
  ~TempFile() {
    std::error_code ec;
    fs::remove(path, ec);
  }
};

void push(Capture &c, const Signal &s) {
  constexpr uint32_t kBlock = 512;
  const uint32_t total = s.frameCount();
  for (uint32_t done = 0; done < total;) {
    const uint32_t n = std::min(kBlock, total - done);
    while (c.ring().capacity() - c.ring().availableRead() < n)
      std::this_thread::sleep_for(std::chrono::milliseconds(1));
    const TapBuffer b{2, n * 2 * static_cast<uint32_t>(sizeof(float)),
                      s.samples().data() + static_cast<size_t>(done) * 2};
    c.push(&b, 1, {2, false});
    done += n;
  }
}

void armedCaptureWritesOnlyTheSound() { // #140/AK8, AK9: the FLAC file of an armed recording
  Signal s;
  s.silence(3.0).tone(2.0).silence(6.0);
  TempFile f;
  Capture c;
  const GateConfig gate{};
  CHECK(c.open(f.path.string().c_str(), kRate, FileFormat::Flac, &gate) == 0);
  CHECK(c.gated());
  push(c, s);
  c.close();
  CHECK(c.gate().state() == GateState::Done);
  CHECK(c.meter().frames() == s.frameCount()); // everything recorded, only part written
  CHECK(c.gate().keptFrames() == Signal::frames(5.0));
  CHECK(std::fabs(wp::fileDuration(f.path.string()) - 5.0) <= 0.01);
}

void armedCaptureWithoutSoundStaysEmpty() { // #140/AK7, AK14: aborted while armed
  Signal s;
  s.silence(3.0);
  TempFile f;
  Capture c;
  const GateConfig gate{};
  CHECK(c.open(f.path.string().c_str(), kRate, FileFormat::Flac, &gate) == 0);
  push(c, s);
  c.close();
  CHECK(c.gate().state() == GateState::Armed);
  CHECK(c.gate().keptFrames() == 0);
}

void captureWithoutGateIsNotArmed() { // #140: an ordinary recording keeps everything
  Signal s;
  s.silence(1.0).tone(0.5);
  TempFile f;
  Capture c;
  CHECK(c.open(f.path.string().c_str(), kRate, FileFormat::Flac) == 0);
  CHECK(!c.gated());
  push(c, s);
  c.close();
  CHECK(std::fabs(wp::fileDuration(f.path.string()) - 1.5) <= 0.01);
}

void captureRejectsGateOutOfRange() { // #140/AK11
  TempFile f;
  Capture c;
  const GateConfig gate{-50.0, 0.0};
  CHECK(c.open(f.path.string().c_str(), kRate, FileFormat::Flac, &gate) ==
        WP_REC_ERR_INVALID_ARGUMENT);
  c.close();
  CHECK(!fs::exists(f.path));
}

} // namespace

int main() {
  const std::vector<std::pair<std::string, std::function<void()>>> tests = {
      {"armedKeepsNothingBelowThreshold", armedKeepsNothingBelowThreshold},
      {"recordingStartsOneSecondBeforeTheFirstSound", recordingStartsOneSecondBeforeTheFirstSound},
      {"leadInFromTheRingAfterLongArming", leadInFromTheRingAfterLongArming},
      {"leadInShorterWhenSoundComesEarly", leadInShorterWhenSoundComesEarly},
      {"soundAtTheVeryFirstFrame", soundAtTheVeryFirstFrame},
      {"recordingEndsTwoSecondsAfterTheLastSound", recordingEndsTwoSecondsAfterTheLastSound},
      {"stopsAfterFiveSecondsOfSilence", stopsAfterFiveSecondsOfSilence},
      {"shortPausesStayInTheRecording", shortPausesStayInTheRecording},
      {"pauseJustBelowTheLimitKeepsRecording", pauseJustBelowTheLimitKeepsRecording},
      {"silenceAndThresholdCanBeChanged", silenceAndThresholdCanBeChanged},
      {"soundOnOneChannelCounts", soundOnOneChannelCounts},
      {"blockSizeDoesNotMatter", blockSizeDoesNotMatter},
      {"initRejectsSettingsOutOfRange", initRejectsSettingsOutOfRange},
      {"initStartsOver", initStartsOver},
      {"thresholdIsLinear", thresholdIsLinear},
      {"armedCaptureWritesOnlyTheSound", armedCaptureWritesOnlyTheSound},
      {"armedCaptureWithoutSoundStaysEmpty", armedCaptureWithoutSoundStaysEmpty},
      {"captureWithoutGateIsNotArmed", captureWithoutGateIsNotArmed},
      {"captureRejectsGateOutOfRange", captureRejectsGateOutOfRange},
  };
  for (const auto &[name, fn] : tests) {
    const int before = failures;
    fn();
    std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name.c_str());
  }
  std::printf("%d checks, %d failures\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
