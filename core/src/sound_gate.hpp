// Armed recording (#140): sound and silence detection on the recorded stream. While armed the gate
// keeps the last second in a ring and writes nothing; the first sample above the threshold starts
// the file one second before it. After `silenceSeconds` without a sample above the threshold the
// gate is done; the file ends `postrollSeconds` (2 s for the command line, 1 s for the armed
// practice recording, #147) after the last loud sample. Pauses shorter than that stay in the file.
// Stopped before that, finish() keeps the held pause, so the file ends where it was stopped (#147).
// Runs on the writer thread of a Capture (not the audio thread), so it may block and allocates only
// in init(). Platform-independent and tested with generated audio
// (core/tests/sound_gate_tests.cpp).
#pragma once

#include <atomic>
#include <cstdint>
#include <vector>

namespace wp::rec {

// Lead-in and default tail of an armed recording (#140): kept before the first and after the last
// sample above the threshold.
constexpr double kPrerollSeconds = 1.0;
constexpr double kPostrollSeconds = 2.0;
// #147: range of the tail.
constexpr double kMinPostrollSeconds = 0.0;
constexpr double kMaxPostrollSeconds = 10.0;

// Valid range of the settings (wp_rec_start_armed rejects values outside).
constexpr double kMinThresholdDb = -120.0;
constexpr double kMaxThresholdDb = 0.0;
constexpr double kMinSilenceSeconds = 0.1;
// The silence after the tail is held in memory until sound returns or the pause ends: at most
// 58 s, about 22 MB at 48 kHz (89 MB at 192 kHz).
constexpr double kMaxSilenceSeconds = 60.0;

struct GateConfig {
  // A sample counts as sound when its magnitude on any channel exceeds this level.
  double thresholdDb = -50.0;
  // The recording ends after this much uninterrupted silence. Never shorter than the tail.
  double silenceSeconds = 5.0;
  // #147: kept after the last sample above the threshold.
  double postrollSeconds = kPostrollSeconds;
  // All settings within their range (NaN is not).
  [[nodiscard]] bool valid() const {
    return thresholdDb >= kMinThresholdDb && thresholdDb <= kMaxThresholdDb &&
           silenceSeconds >= kMinSilenceSeconds && silenceSeconds <= kMaxSilenceSeconds &&
           postrollSeconds >= kMinPostrollSeconds && postrollSeconds <= kMaxPostrollSeconds;
  }
};

// Receives the frames the gate keeps, interleaved, in stream order.
class FrameSink {
public:
  virtual ~FrameSink() = default;
  virtual void write(const float *frames, uint32_t count) = 0;

protected:
  FrameSink() = default;
  FrameSink(const FrameSink &) = default;
  FrameSink &operator=(const FrameSink &) = default;
};

enum class GateState : int { Armed = 1, Recording = 2, Done = 3 };

class SoundGate {
public:
  // Allocates the lead-in ring and the buffer for the silence after the tail. false if the
  // settings are out of range (see above) or the rate or channel count is not positive.
  bool init(double sampleRate, uint32_t channels, const GateConfig &config);
  // Feeds `count` interleaved frames; hands what is kept to `sink`. Frames after the end are
  // ignored.
  void feed(const float *frames, uint32_t count, FrameSink &sink);
  // #147: the recording was stopped: a pause held so far belongs to it, so the file ends where it
  // was stopped. Nothing while armed or done.
  void finish(FrameSink &sink);

  [[nodiscard]] GateState state() const { return state_.load(); }
  // Frames handed to the sink so far.
  [[nodiscard]] long long keptFrames() const { return kept_.load(); }
  // Stream index of the first and last sample above the threshold, -1 before the first.
  [[nodiscard]] long long firstSound() const { return first_; }
  [[nodiscard]] long long lastSound() const { return last_; }
  // Linear threshold for the level in dBFS.
  static float linear(double db);

private:
  [[nodiscard]] bool loud(const float *frame) const;
  void emit(const float *frames, uint32_t count, FrameSink &sink);
  void startRecording(FrameSink &sink);
  void feedRecording(const float *frames, uint32_t count, FrameSink &sink);

  uint32_t channels_ = 0;
  float threshold_ = 0.0f;
  long long preroll_ = 0;  // frames of the lead-in
  long long postroll_ = 0; // frames of the tail
  long long silence_ = 0;  // frames of silence that end the recording (>= postroll_)
  std::atomic<GateState> state_{GateState::Armed};
  std::atomic<long long> kept_{0};
  long long pos_ = 0; // stream index of the next frame
  long long first_ = -1;
  long long last_ = -1;
  // Lead-in: ring of the last preroll_ frames while armed.
  std::vector<float> pre_;
  long long preCount_ = 0; // frames written into the ring so far (all of them, not capped)
  // Silence after the tail, held until sound comes back (written) or the recording ends (dropped).
  std::vector<float> pending_;
  long long pendingFrames_ = 0;
};

} // namespace wp::rec
