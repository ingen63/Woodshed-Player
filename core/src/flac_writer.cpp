// FLAC file writer on libFLAC (#113), see flac_writer.hpp.
#include "flac_writer.hpp"

#include <algorithm>
#include <cmath>

namespace wp {

namespace {
constexpr uint32_t kMaxChannels = 8;
constexpr uint32_t kMaxRate = 655350;
// Compression level of the flac tool's default: fast enough for live recording, small files.
constexpr uint32_t kCompression = 5;
} // namespace

FlacWriter::~FlacWriter() { close(); }

int32_t FlacWriter::toInt(float v, uint32_t bits) {
  const double max = static_cast<double>((1u << (bits - 1)) - 1);
  const double x = std::clamp(static_cast<double>(v), -1.0, 1.0) * max;
  return static_cast<int32_t>(std::lround(x));
}

bool FlacWriter::open(const char *path, uint32_t sampleRate, uint32_t channels,
                      uint32_t bitsPerSample) {
  close();
  if (!path || channels < 1 || channels > kMaxChannels || sampleRate < 1 || sampleRate > kMaxRate ||
      (bitsPerSample != 16 && bitsPerSample != 24))
    return false;
  FLAC__StreamEncoder *e = FLAC__stream_encoder_new();
  if (!e)
    return false;
  FLAC__stream_encoder_set_channels(e, channels);
  FLAC__stream_encoder_set_bits_per_sample(e, bitsPerSample);
  FLAC__stream_encoder_set_sample_rate(e, sampleRate);
  FLAC__stream_encoder_set_compression_level(e, kCompression);
  // Rates outside the streamable subset (e.g. 192 kHz with large blocks) are still valid FLAC.
  FLAC__stream_encoder_set_streamable_subset(e, false);
  if (FLAC__stream_encoder_init_file(e, path, nullptr, nullptr) !=
      FLAC__STREAM_ENCODER_INIT_STATUS_OK) {
    FLAC__stream_encoder_delete(e);
    return false;
  }
  encoder_ = e;
  channels_ = channels;
  bits_ = bitsPerSample;
  return true;
}

bool FlacWriter::write(const float *frames, uint32_t count) {
  if (!encoder_)
    return false;
  const size_t n = static_cast<size_t>(count) * channels_;
  buffer_.resize(n);
  for (size_t i = 0; i < n; ++i)
    buffer_[i] = toInt(frames[i], bits_);
  return FLAC__stream_encoder_process_interleaved(encoder_, buffer_.data(), count) != 0;
}

bool FlacWriter::close() {
  if (!encoder_)
    return true;
  const bool ok = FLAC__stream_encoder_finish(encoder_) != 0;
  FLAC__stream_encoder_delete(encoder_);
  encoder_ = nullptr;
  return ok;
}

} // namespace wp
