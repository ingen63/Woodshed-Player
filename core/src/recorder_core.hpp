// Platform-independent part of the recording (#68): level meter, ring buffer, WAV file and the
// copy of the tap data into the ring. recorder_mac.mm only drives Core Audio (process tap,
// aggregate device, IOProc) and hands each input buffer list to Capture::push. Everything here
// runs without an audio device and is tested by core/tests/recorder_tests.cpp.
#pragma once

#include <atomic>
#include <cstdint>
#include <thread>

#include "miniaudio_impl.hpp"

namespace wp::rec {

// The WAV file is always stereo float32 at the device rate.
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

// Ring buffer, WAV file and writer thread of one recording, plus the level meter.
class Capture {
public:
  Capture() = default;
  Capture(const Capture &) = delete;
  Capture &operator=(const Capture &) = delete;
  ~Capture();

  // Allocates the ring (kRingSeconds), creates the WAV file and starts the writer thread.
  // 0, WP_REC_ERR_OUT_OF_MEMORY or WP_REC_ERR_FILE. After an error close() cleans up.
  int open(const char *path, double sampleRate);
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

private:
  void writerLoop();

  LevelMeter meter_;
  FrameRing ring_;
  WavFile wav_;
  std::thread writer_;
  std::atomic<bool> writerRun_{false};
};

} // namespace wp::rec
