// FLAC file writer on libFLAC (#113). Takes interleaved float frames and stores them as integer
// samples. Independent of the recording, so other features that write FLAC (e.g. trimming a file)
// can use it as well.
#pragma once

#include <FLAC/stream_encoder.h>

#include <cstdint>
#include <vector>

namespace wp {

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
  // Appends `count` interleaved frames; values outside −1…1 are clipped. false on an encoder error
  // or when no file is open.
  bool write(const float *frames, uint32_t count);
  // Encodes the rest and writes the stream info (length, MD5). false if that fails; the file is
  // closed either way.
  bool close();
  [[nodiscard]] bool isOpen() const { return encoder_ != nullptr; }

  // Float sample to the integer range of `bits` bits, clipped and rounded to the nearest value.
  static int32_t toInt(float v, uint32_t bits);

private:
  FLAC__StreamEncoder *encoder_ = nullptr;
  uint32_t channels_ = 0;
  uint32_t bits_ = 0;
  std::vector<FLAC__int32> buffer_;
};

} // namespace wp
