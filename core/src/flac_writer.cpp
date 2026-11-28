// FLAC file writer on libFLAC (#113), see flac_writer.hpp.
#include "flac_writer.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <string>

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX // std::min, std::max and std::clamp instead of the macros of windows.h
#endif
#include <windows.h>
#endif

namespace wp {

namespace {
constexpr uint32_t kMaxChannels = 8;
constexpr uint32_t kMaxRate = 655350;
// #116: bit depths libFLAC encodes (FLAC__MIN_BITS_PER_SAMPLE, FLAC__MAX_BITS_PER_SAMPLE).
constexpr uint32_t kMinMemoryBits = 4;
constexpr uint32_t kMaxMemoryBits = 32;
// Compression level of the flac tool's default: fast enough for live recording, small files.
constexpr uint32_t kCompression = 5;

// #162: creates the file at the UTF-8 path `path` for writing and rewriting (libFLAC goes back to
// the stream info when it closes). On Windows a narrow path means the ANSI code page, so names with
// umlauts would fail there; the path goes in as UTF-16.
FILE *createFile(const char *path) {
#ifdef _WIN32
  const int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, nullptr, 0);
  if (n > 0) {
    std::wstring wide(static_cast<size_t>(n), L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide.data(), n);
    return _wfopen(wide.c_str(), L"w+b");
  }
#endif
  return std::fopen(path, "w+b"); // NOLINT(cppcoreguidelines-owning-memory): libFLAC closes it
}
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

bool FlacWriter::openSink(FlacSink *sink, uint32_t sampleRate, uint32_t channels,
                          uint32_t bitsPerSample) {
  close();
  if (!sink || (bitsPerSample != 16 && bitsPerSample != 24))
    return false;
  sink_ = sink;
  memoryPos_ = 0;
  sinkEnd_ = 0;
  if (start(sampleRate, channels, bitsPerSample, nullptr))
    return true;
  sink_ = nullptr;
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
  FILE *file = path ? createFile(path) : nullptr;
  if (path && !file) {
    FLAC__stream_encoder_delete(e);
    return false;
  }
  // With a file libFLAC owns it from here and closes it when the encoder finishes or is deleted
  // (also after a failed init), which the analyzer cannot see through the C library.
  // NOLINTNEXTLINE(clang-analyzer-unix.Stream)
  const FLAC__StreamEncoderInitStatus status =
      file ? FLAC__stream_encoder_init_FILE(e, file, nullptr, nullptr)
           : FLAC__stream_encoder_init_stream(e, sink_ ? writeSink : writeMemory, seekMemory,
                                              tellMemory, nullptr, this);
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

FLAC__StreamEncoderWriteStatus FlacWriter::writeSink(const FLAC__StreamEncoder *,
                                                     const FLAC__byte buffer[], size_t bytes,
                                                     uint32_t samples, uint32_t, void *self) {
  auto *w = static_cast<FlacWriter *>(self);
  if (!w->sink_->write(w->memoryPos_, buffer, bytes, samples))
    return FLAC__STREAM_ENCODER_WRITE_STATUS_FATAL_ERROR;
  w->memoryPos_ += bytes;
  w->sinkEnd_ = std::max(w->sinkEnd_, w->memoryPos_);
  return FLAC__STREAM_ENCODER_WRITE_STATUS_OK;
}

FLAC__StreamEncoderSeekStatus FlacWriter::seekMemory(const FLAC__StreamEncoder *,
                                                     FLAC__uint64 offset, void *self) {
  auto *w = static_cast<FlacWriter *>(self);
  if (offset > (w->sink_ ? w->sinkEnd_ : w->memory_->size()))
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
  sink_ = nullptr;
  return ok;
}

} // namespace wp
