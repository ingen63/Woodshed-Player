// FLAC file writer on libFLAC (#113). Takes interleaved float frames and stores them as integer
// samples. Independent of the recording, so other features that write FLAC (e.g. trimming a file)
// can use it as well.
#pragma once

#include <FLAC/stream_encoder.h>

#include <cstddef>
#include <cstdint>
#include <vector>

namespace wp {

// #157: receives the encoded stream piece by piece instead of a file or a vector (the browser
// stores it in blocks). `offset` is where the bytes belong in the file: the end of what came so
// far, or (only when the encoder closes) a place before it, to rewrite the stream info. `samples`
// is the number of samples per channel in the bytes, 0 for metadata.
class FlacSink {
public:
  virtual ~FlacSink() = default;
  virtual bool write(uint64_t offset, const uint8_t *data, size_t size, uint32_t samples) = 0;

protected:
  FlacSink() = default;
  FlacSink(const FlacSink &) = default;
  FlacSink &operator=(const FlacSink &) = default;
};

class FlacWriter {
public:
  // Bits per sample of the recording: 24 keeps quiet takes (no input gain) above the noise floor.
  static constexpr uint32_t kDefaultBits = 24;

  FlacWriter() = default;
  FlacWriter(const FlacWriter &) = delete;
  FlacWriter &operator=(const FlacWriter &) = delete;
  ~FlacWriter();

  // Creates the file. Closes an open file first. false if the arguments are outside what FLAC
  // stores (1–8 channels, 16 or 24 bits, rate 1–655350 Hz) or the file cannot be created.
  bool open(const char *path, uint32_t sampleRate, uint32_t channels,
            uint32_t bitsPerSample = kDefaultBits);
  // #116: encodes into `out` instead of a file (cleared first); close() rewrites the stream info
  // there. Takes 4–32 bits per sample, so a FLAC file of any depth can be encoded again unchanged.
  // false if the arguments are outside what FLAC stores.
  bool openMemory(std::vector<uint8_t> *out, uint32_t sampleRate, uint32_t channels,
                  uint32_t bitsPerSample);
  // #157: hands the encoded stream to `sink`, which must outlive the writer or the next open.
  // false if the arguments are outside what FLAC stores (1–8 channels, 16 or 24 bits).
  bool openSink(FlacSink *sink, uint32_t sampleRate, uint32_t channels,
                uint32_t bitsPerSample = kDefaultBits);
  // Appends `count` interleaved frames; values outside −1…1 are clipped. false on an encoder error
  // or when no file is open.
  bool write(const float *frames, uint32_t count);
  // #116: appends `count` interleaved integer frames, each already within the range of the bit
  // depth (lossless). false on an encoder error, also when memory runs out, or when nothing is
  // open.
  bool writeInt(const int32_t *frames, uint32_t count);
  // Encodes the rest and writes the stream info (length, MD5). false if that fails; the file is
  // closed either way.
  bool close();
  [[nodiscard]] bool isOpen() const { return encoder_ != nullptr; }

  // Float sample to the integer range of `bits` bits, clipped and rounded to the nearest value.
  static int32_t toInt(float v, uint32_t bits);

private:
  bool start(uint32_t sampleRate, uint32_t channels, uint32_t bitsPerSample, const char *path);
  static FLAC__StreamEncoderWriteStatus writeSink(const FLAC__StreamEncoder *,
                                                  const FLAC__byte buffer[], size_t bytes,
                                                  uint32_t samples, uint32_t frame, void *self);
  static FLAC__StreamEncoderWriteStatus writeMemory(const FLAC__StreamEncoder *,
                                                    const FLAC__byte buffer[], size_t bytes,
                                                    uint32_t samples, uint32_t frame, void *self);
  static FLAC__StreamEncoderSeekStatus seekMemory(const FLAC__StreamEncoder *, FLAC__uint64 offset,
                                                  void *self);
  static FLAC__StreamEncoderTellStatus tellMemory(const FLAC__StreamEncoder *, FLAC__uint64 *offset,
                                                  void *self);

  FLAC__StreamEncoder *encoder_ = nullptr;
  std::vector<uint8_t> *memory_ = nullptr; // #116: target of openMemory, else null
  FlacSink *sink_ = nullptr;               // #157: target of openSink, else null
  size_t memoryPos_ = 0;                   // write position in memory_ or for sink_
  size_t sinkEnd_ = 0;                     // #157: bytes handed to sink_ so far (end of the stream)
  uint32_t channels_ = 0;
  uint32_t bits_ = 0;
  std::vector<FLAC__int32> buffer_;
};

} // namespace wp
