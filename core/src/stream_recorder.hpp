// Recording without threads, audio device or file system (#157), for the browser: the caller feeds
// the input block by block (from an AudioWorklet), takes the encoded FLAC in pieces and stores them
// (in the OPFS). An armed recording runs through the same SoundGate as natively (sound_gate.cpp):
// 1 s before the first sound, the tail after the last, shorter pauses kept. The file is FLAC with
// 24 bits like every native recording (#118). When the recording ends, header() is the start of the
// file with the final stream info (length, MD5), to be written over the first bytes. If storing a
// piece fails (the storage is full), cut() ends the file before that piece and fixes the header to
// what was stored. Platform-independent and tested natively with generated audio
// (core/tests/stream_recorder_tests.cpp); the web core exports it as wp_web_rec_* (wp_core_web.h).
#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

#include "flac_writer.hpp"
#include "sound_gate.hpp"

namespace wp::rec {

// A block whose peak stays at or below this counts as silence (as recorder_core.hpp).
constexpr float kStreamSilenceThreshold = 1e-4f;

// Gate state of a recording without arming (WP_REC_GATE_OFF).
constexpr int kGateOff = 0;

class StreamRecorder final : private FrameSink, private FlacSink {
public:
  StreamRecorder() = default;
  StreamRecorder(const StreamRecorder &) = delete;
  StreamRecorder &operator=(const StreamRecorder &) = delete;
  // Closes an unfinished encoder first: its last bytes would go to members destroyed before it.
  ~StreamRecorder() override;

  // Starts a recording of `channels` channels at `sampleRate`; armed with `gate`, otherwise every
  // frame is kept. false if the rate, the channels or the gate settings are out of range.
  bool start(uint32_t sampleRate, uint32_t channels, const GateConfig *gate);
  // Feeds `count` interleaved frames. false once the encoder failed (the recording is over).
  bool feed(const float *frames, uint32_t count);
  // Ends the recording: a held pause is kept (as SoundGate::finish), the encoder writes the rest
  // and the final stream info into header(). false if the encoder failed.
  bool finish();

  // Encoded bytes not taken yet; they belong at outOffset() in the file.
  [[nodiscard]] const uint8_t *out() const { return out_.data(); }
  [[nodiscard]] size_t outSize() const { return out_.size(); }
  [[nodiscard]] uint64_t outOffset() const { return outOffset_; }
  // The caller has stored the bytes of out(); they are dropped here.
  void take();
  // #157/AK8: the bytes of the last take() could not be stored. The file ends before them: the
  // header now counts only the samples stored before (MD5 unknown, as FLAC allows), the recording
  // is over and gives no more bytes. Returns the length of the file.
  uint64_t cut();

  // Start of the file (marker and metadata) as it must stand at offset 0; final after finish() or
  // cut().
  [[nodiscard]] const uint8_t *header() const { return header_.data(); }
  [[nodiscard]] size_t headerSize() const { return header_.size(); }

  // WP_REC_GATE_* (kGateOff without arming).
  [[nodiscard]] int gate() const;
  // Frames fed so far, and frames kept for the file.
  [[nodiscard]] long long frames() const { return frames_; }
  [[nodiscard]] long long keptFrames() const { return kept_; }
  // Highest peak since the last call (0–1 and above); resets it.
  float takeLevel();
  // Only silence so far (no input).
  [[nodiscard]] bool onlySilence() const { return onlySilence_; }

private:
  void write(const float *frames, uint32_t count) override; // FrameSink: kept frames
  bool write(uint64_t offset, const uint8_t *data, size_t size, uint32_t samples) override;
  void patchTotalSamples(uint64_t samples);

  FlacWriter flac_;
  SoundGate gate_;
  uint32_t channels_ = 0;
  bool armed_ = false;
  bool ok_ = false;      // started and the encoder has not failed
  bool cut_ = false;     // cut(): nothing more goes into the file
  bool inAudio_ = false; // the first audio frame came: the header is complete
  long long frames_ = 0;
  long long kept_ = 0;
  float peak_ = 0.0f;
  bool onlySilence_ = true;
  std::vector<uint8_t> out_;
  uint64_t outOffset_ = 0;
  uint64_t end_ = 0;            // bytes of the stream so far
  uint64_t pendingSamples_ = 0; // samples in out_
  uint64_t storedSamples_ = 0;  // samples in the bytes taken so far
  uint64_t lastTakeOffset_ = 0; // offset and samples before the last take()
  uint64_t lastTakeSamples_ = 0;
  std::vector<uint8_t> header_;
};

} // namespace wp::rec
