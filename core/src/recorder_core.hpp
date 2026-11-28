// Platform-independent part of the recording (#68): level meter, ring buffer, WAV or FLAC file and
// the copy of the tap data into the ring. recorder_mac.mm only drives Core Audio (process tap,
// aggregate device, IOProc) and hands each input buffer list to Capture::push. The microphone
// (#113) is miniaudio's capture device (MicInput). Everything here runs without an audio device
// (MicInput on miniaudio's null backend) and is tested by core/tests/recorder_tests.cpp.
#pragma once

#include <atomic>
#include <cstdint>
#include <thread>

#include "flac_writer.hpp"
#include "miniaudio_impl.hpp"
#include "sound_gate.hpp"
#include "wp_core.h"

namespace wp::rec {

// The file is always stereo at the device rate: FLAC as 24-bit integers (every recording since
// #118), WAV as float32 (older recordings, kept for tests).
constexpr int kChannels = 2;
// A block whose peak stays at or below this counts as silence (macOS delivers digital silence
// without the permission for system audio).
constexpr float kSilenceThreshold = 1e-4f;
// Frames per block copied from the tap into the ring.
constexpr uint32_t kBlockFrames = 1024;
// Frames the writer thread takes from the ring at once.
constexpr uint32_t kWriteFrames = 4096;
// The ring holds this many seconds of audio.
constexpr double kRingSeconds = 2.0;

// One buffer of the input buffer list (same fields as Core Audio's AudioBuffer).
struct TapBuffer {
  uint32_t channels = 0; // channels in this buffer (interleaved)
  uint32_t bytes = 0;    // size of data in bytes
  const float *data = nullptr;
};

// Layout of the tap data. Without interleaving every channel has its own buffer.
struct TapFormat {
  uint32_t channels = 2;
  bool nonInterleaved = false;
};

// Peak level and length of the recording; written by the audio thread, read by the UI.
class LevelMeter {
public:
  void reset();
  // One block from the tap: its peak and its number of frames.
  void add(float blockPeak, uint32_t blockFrames);
  // Highest peak since the last call; resets it to 0.
  float takeLevel() { return peak_.exchange(0.0f); }
  [[nodiscard]] bool onlySilence() const { return onlySilence_.load(); }
  [[nodiscard]] long long frames() const { return frames_.load(); }

private:
  std::atomic<float> peak_{0.0f};
  std::atomic<long long> frames_{0};
  std::atomic<bool> onlySilence_{true};
};

// Lock-free ring of interleaved stereo float frames: one writer (audio thread), one reader.
class FrameRing {
public:
  FrameRing() = default;
  FrameRing(const FrameRing &) = delete;
  FrameRing &operator=(const FrameRing &) = delete;
  ~FrameRing();

  // Allocates the ring; call uninit() before initializing it again.
  bool init(uint32_t capacityFrames);
  void uninit();
  [[nodiscard]] bool ready() const { return ready_; }
  [[nodiscard]] uint32_t capacity();
  // Copies up to `count` frames; frames that do not fit are dropped instead of blocking.
  // Returns the number of frames written.
  uint32_t write(const float *frames, uint32_t count);
  [[nodiscard]] uint32_t availableRead();
  // Contiguous frames to read: at most `frames`, the actual number is returned in `frames`.
  // nullptr when nothing can be read.
  const float *acquireRead(uint32_t &frames);
  void commitRead(uint32_t frames);

private:
  ma_pcm_rb rb_{};
  bool ready_ = false;
};

// WAV file, stereo float32 (miniaudio writes the header and fixes the sizes on close).
class WavFile {
public:
  WavFile() = default;
  WavFile(const WavFile &) = delete;
  WavFile &operator=(const WavFile &) = delete;
  ~WavFile();

  // Closes an open file first.
  bool open(const char *path, uint32_t sampleRate);
  void write(const float *frames, uint32_t count);
  void close();
  [[nodiscard]] bool isOpen() const { return open_; }

private:
  ma_encoder encoder_{};
  bool open_ = false;
};

// Format of the recorded file: system audio (#118) and microphone (#113) as FLAC; WAV was the
// format of the system audio before #118.
enum class FileFormat { Wav, Flac };

// Ring buffer, file and writer thread of one recording, plus the level meter.
class Capture {
public:
  Capture() = default;
  Capture(const Capture &) = delete;
  Capture &operator=(const Capture &) = delete;
  ~Capture();

  // Allocates the ring (kRingSeconds), creates the file and starts the writer thread.
  // With `gate` the recording is armed (#140): the writer thread hands the frames to a SoundGate,
  // which writes only from one second before the first sound to two seconds after the last.
  // 0, WP_REC_ERR_INVALID_ARGUMENT (gate settings), WP_REC_ERR_OUT_OF_MEMORY or WP_REC_ERR_FILE.
  // After an error close() cleans up.
  int open(const char *path, double sampleRate, FileFormat format,
           const GateConfig *gate = nullptr);
  // Stops the writer after it has written everything in the ring, closes the file and frees the
  // ring. The level meter keeps its values (length of the finished recording).
  void close();

  // Audio thread: takes the tap buffers out of the input buffer list and appends their frames to
  // the ring as stereo. If the device has inputs of its own (e.g. an audio interface), their
  // buffers come first; the tap data is in the last buffers. Mono is copied to both channels,
  // channels beyond the second are ignored.
  void push(const TapBuffer *buffers, uint32_t count, const TapFormat &format);

  LevelMeter &meter() { return meter_; }
  FrameRing &ring() { return ring_; }
  // #140: whether this recording is armed, and its gate (state and kept frames).
  [[nodiscard]] bool gated() const { return gated_; }
  [[nodiscard]] const SoundGate &gate() const { return gate_; }

private:
  // Writes the frames the gate keeps into the file.
  class FileSink : public FrameSink {
  public:
    explicit FileSink(Capture &capture) : capture_(capture) {}
    void write(const float *frames, uint32_t count) override {
      capture_.writeFrames(frames, count);
    }

  private:
    Capture &capture_;
  };

  void writerLoop();
  void writeFrames(const float *frames, uint32_t count);

  LevelMeter meter_;
  FrameRing ring_;
  WavFile wav_;
  FlacWriter flac_;
  SoundGate gate_;
  bool gated_ = false;
  std::thread writer_;
  std::atomic<bool> writerRun_{false};
};

// #162: the code of a failed start of the input device: WP_REC_ERR_ACCESS_DENIED if the system
// refused access (MA_ACCESS_DENIED, e.g. the microphone privacy setting of Windows), otherwise
// WP_REC_ERR_NO_INPUT.
int micOpenError(ma_result result);
// #162: the code of a failed start of an opened input device: WP_REC_ERR_ACCESS_DENIED for
// MA_ACCESS_DENIED, otherwise WP_REC_ERR_START.
int micStartError(ma_result result);

// #162: whether miniaudio lists an input device on `context`.
bool hasInputDeviceOn(ma_context *context);
// #162: whether the devices of `backend` count: always if the backends were `chosen` (tests), else
// not those of the null backend.
bool isSystemInput(bool chosen, ma_backend backend);
// #162: the same on a context of its own with `backends` (nullptr: miniaudio picks the backend; its
// null backend, the fallback without audio hardware, then counts as no input device).
bool hasInputDevice(const ma_backend *backends = nullptr, ma_uint32 backendCount = 0);

// Microphone (#113): the default input device of the system through miniaudio, handed to a Capture
// as stereo float (mono inputs on both channels). Without the permission macOS delivers silence.
class MicInput {
public:
  MicInput() = default;
  MicInput(const MicInput &) = delete;
  MicInput &operator=(const MicInput &) = delete;
  ~MicInput();

  // Opens the default input device on `context` (nullptr: miniaudio picks the backend) at its own
  // rate. false if there is no input device or it cannot be opened.
  bool open(ma_context *context = nullptr);
  // Rate of the opened device in Hz, 0 if none is open.
  [[nodiscard]] double sampleRate() const;
  // Starts delivering to `capture`, which must already be open. false if the device does not start.
  bool start(Capture &capture);
  // Stops and closes the device; afterwards nothing reaches the capture any more.
  void close();
  // #162: miniaudio's result of the last open() or start(), MA_SUCCESS if both worked.
  [[nodiscard]] ma_result result() const { return result_; }

  // Audio thread: hands `frames` interleaved stereo float frames of the device to `capture`.
  static void deliver(Capture &capture, const float *input, uint32_t frames);

private:
  static void onData(ma_device *device, void *output, const void *input, ma_uint32 frames);

  ma_device
      device_{}; // NOLINT(bugprone-invalid-enum-default-initialization): zeroed miniaudio struct
  bool open_ = false;
  ma_result result_ = MA_SUCCESS;
  Capture *capture_ = nullptr;
};

// #162: an artificial microphone for tests and the smoke tests on machines without one (the CI
// runners): a sine or silence, handed to a Capture at real-time pace from its own thread, in blocks
// of kBlockFrames like a device.
class SimulatedInput {
public:
  static constexpr double kSampleRate = 48000;
  static constexpr double kToneHz = 440;
  // Peak of the sine, about -12 dBFS: above every threshold of an armed recording but 0 dBFS.
  static constexpr float kToneAmplitude = 0.25f;

  SimulatedInput() = default;
  SimulatedInput(const SimulatedInput &) = delete;
  SimulatedInput &operator=(const SimulatedInput &) = delete;
  ~SimulatedInput();

  // Starts delivering to `capture`, which must already be open; stops a running delivery first.
  void start(Capture &capture);
  // Stops the thread; afterwards nothing reaches the capture any more.
  void close();
  // Sine (true) or silence (false), also while it runs.
  void setTone(bool tone) { tone_.store(tone); }
  [[nodiscard]] bool tone() const { return tone_.load(); }

  // `frames` stereo frames from frame `position` on: the sine if `tone`, otherwise silence.
  static void render(float *out, uint32_t frames, uint64_t position, bool tone);

private:
  void loop(Capture &capture);

  std::thread thread_;
  std::atomic<bool> run_{false};
  std::atomic<bool> tone_{false};
};

// #162: what the microphone of a recording reads, chosen with wp_rec_set_input: the default input
// device of the system (normal), or for tests an artificial input (silence or sine), a device that
// refuses access or no device at all.
class MicSource {
public:
  MicSource() = default;
  // Tests: the device of `context` (e.g. miniaudio's null backend) instead of the system's.
  explicit MicSource(ma_context *context) : context_(context) {}

  // WP_REC_INPUT_*; false (and no change) for an unknown value. Between silence and sine a running
  // artificial input switches at once; every other change applies to the next open().
  bool setInput(int input);
  [[nodiscard]] int input() const { return input_.load(); }
  // Whether there is something to record: the device only if miniaudio lists an input device
  // (asked once, then kept), the artificial inputs and the refusing device always, none never.
  bool available();
  // Opens the input. 0, WP_REC_ERR_NO_INPUT or WP_REC_ERR_ACCESS_DENIED.
  int open();
  // Rate of the opened input in Hz, 0 if none is open.
  [[nodiscard]] double sampleRate() const;
  // Starts delivering to `capture`, which must already be open. 0, WP_REC_ERR_START or
  // WP_REC_ERR_ACCESS_DENIED.
  int start(Capture &capture);
  // Stops and closes the input; afterwards nothing reaches the capture any more.
  void close();

private:
  ma_context *context_ = nullptr; // nullptr: miniaudio picks the backend
  std::atomic<int> input_{WP_REC_INPUT_DEVICE};
  int device_ = -1; // whether miniaudio lists an input device; -1 until asked
  MicInput mic_;
  SimulatedInput sim_;
  bool simOpen_ = false;
};

} // namespace wp::rec
