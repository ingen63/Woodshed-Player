// FLAC file writer on libFLAC (#113), see flac_writer.hpp.
#include "flac_writer.hpp"

#include <algorithm>
#include <cmath>

namespace wp {

namespace {
constexpr uint32_t kMaxChannels = 8;
constexpr uint32_t kMaxRate = 655350;
// #116: bit depths libFLAC encodes (FLAC__MIN_BITS_PER_SAMPLE, FLAC__MAX_BITS_PER_SAMPLE).
constexpr uint32_t kMinMemoryBits = 4;
constexpr uint32_t kMaxMemoryBits = 32;
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
  if (!path || (bitsPerSample != 16 && bitsPerSample != 24))
    return false;
  return start(sampleRate, channels, bitsPerSample, path);
}

bool FlacWriter::openMemory(std::vector<uint8_t> *out, uint32_t sampleRate, uint32_t channels,
                            uint32_t bitsPerSample) {
  close();
  if (!out || bitsPerSample < kMinMemoryBits || bitsPerSample > kMaxMemoryBits)
    return false;
  out->clear();
  memory_ = out;
  memoryPos_ = 0;
  if (start(sampleRate, channels, bitsPerSample, nullptr))
    return true;
  memory_ = nullptr;
  return false;
}

bool FlacWriter::start(uint32_t sampleRate, uint32_t channels, uint32_t bitsPerSample,
                       const char *path) {
  if (channels < 1 || channels > kMaxChannels || sampleRate < 1 || sampleRate > kMaxRate)
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
  const FLAC__StreamEncoderInitStatus status =
      path
          ? FLAC__stream_encoder_init_file(e, path, nullptr, nullptr)
          : FLAC__stream_encoder_init_stream(e, writeMemory, seekMemory, tellMemory, nullptr, this);
  if (status != FLAC__STREAM_ENCODER_INIT_STATUS_OK) {
    FLAC__stream_encoder_delete(e);
    return false;
  }
  encoder_ = e;
  channels_ = channels;
  bits_ = bitsPerSample;
  return true;
}

FLAC__StreamEncoderWriteStatus FlacWriter::writeMemory(const FLAC__StreamEncoder *,
                                                       const FLAC__byte buffer[], size_t bytes,
                                                       uint32_t, uint32_t, void *self) {
  auto *w = static_cast<FlacWriter *>(self);
  std::vector<uint8_t> &out = *w->memory_;
  try {
    if (w->memoryPos_ + bytes > out.size())
      out.resize(w->memoryPos_ + bytes);
  } catch (...) { // no memory: libFLAC is C, nothing may be thrown through it
    return FLAC__STREAM_ENCODER_WRITE_STATUS_FATAL_ERROR;
  }
  std::copy(buffer, buffer + bytes, out.begin() + static_cast<std::ptrdiff_t>(w->memoryPos_));
  w->memoryPos_ += bytes;
  return FLAC__STREAM_ENCODER_WRITE_STATUS_OK;
}

FLAC__StreamEncoderSeekStatus FlacWriter::seekMemory(const FLAC__StreamEncoder *,
                                                     FLAC__uint64 offset, void *self) {
  auto *w = static_cast<FlacWriter *>(self);
  if (offset > w->memory_->size())
    return FLAC__STREAM_ENCODER_SEEK_STATUS_ERROR;
  w->memoryPos_ = static_cast<size_t>(offset);
  return FLAC__STREAM_ENCODER_SEEK_STATUS_OK;
}

FLAC__StreamEncoderTellStatus FlacWriter::tellMemory(const FLAC__StreamEncoder *,
                                                     FLAC__uint64 *offset, void *self) {
  *offset = static_cast<const FlacWriter *>(self)->memoryPos_;
  return FLAC__STREAM_ENCODER_TELL_STATUS_OK;
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

bool FlacWriter::writeInt(const int32_t *frames, uint32_t count) {
  if (!encoder_)
    return false;
  return FLAC__stream_encoder_process_interleaved(encoder_, frames, count) != 0;
}

bool FlacWriter::close() {
  if (!encoder_)
    return true;
  const bool ok = FLAC__stream_encoder_finish(encoder_) != 0;
  FLAC__stream_encoder_delete(encoder_);
  encoder_ = nullptr;
  memory_ = nullptr;
  return ok;
}

} // namespace wp
