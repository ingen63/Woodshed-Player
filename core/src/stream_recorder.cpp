// Recording without threads (#157), see stream_recorder.hpp.
#include "stream_recorder.hpp"

#include <algorithm>
#include <cmath>
#include <iterator>

namespace wp::rec {

namespace {
// FLAC stream: "fLaC", then the STREAMINFO block (4 bytes header, 34 bytes data).
constexpr size_t kStreamInfo = 8;
// Within STREAMINFO: the 36-bit sample count starts in the low 4 bits of byte 13, the MD5 is 18–33.
constexpr size_t kTotalSamples = kStreamInfo + 13;
constexpr size_t kMd5 = kStreamInfo + 18;
constexpr size_t kMd5Size = 16;
constexpr size_t kStreamInfoEnd = kMd5 + kMd5Size;
} // namespace

StreamRecorder::~StreamRecorder() {
  cut_ = true; // write() drops what the encoder still hands out
  flac_.close();
}

bool StreamRecorder::start(uint32_t sampleRate, uint32_t channels, const GateConfig *gate) {
  flac_.close();
  ok_ = false;
  cut_ = false;
  inAudio_ = false;
  frames_ = 0;
  kept_ = 0;
  peak_ = 0.0f;
  onlySilence_ = true;
  out_.clear();
  outOffset_ = 0;
  end_ = 0;
  pendingSamples_ = 0;
  storedSamples_ = 0;
  lastTakeOffset_ = 0;
  lastTakeSamples_ = 0;
  header_.clear();
  channels_ = channels;
  armed_ = gate != nullptr;
  if (armed_ && !gate_.init(sampleRate, channels, *gate))
    return false;
  ok_ = flac_.openSink(this, sampleRate, channels);
  return ok_;
}

bool StreamRecorder::feed(const float *frames, uint32_t count) {
  if (!ok_ || cut_)
    return false;
  float peak = 0.0f;
  const size_t n = static_cast<size_t>(count) * channels_;
  for (size_t i = 0; i < n; ++i)
    peak = std::max(peak, std::fabs(frames[i]));
  peak_ = std::max(peak_, peak);
  if (peak > kStreamSilenceThreshold)
    onlySilence_ = false;
  frames_ += count;
  if (armed_)
    gate_.feed(frames, count, *this);
  else
    write(frames, count);
  return ok_;
}

bool StreamRecorder::finish() {
  if (!ok_ || cut_)
    return cut_;
  if (armed_)
    gate_.finish(*this);
  ok_ = flac_.close() && ok_;
  return ok_;
}

void StreamRecorder::write(const float *frames, uint32_t count) {
  if (count == 0)
    return;
  kept_ += count;
  if (!flac_.write(frames, count))
    ok_ = false;
}

bool StreamRecorder::write(uint64_t offset, const uint8_t *data, size_t size, uint32_t samples) {
  if (cut_)
    return true; // after cut(): the rest of the encoder goes nowhere
  const uint64_t to = offset + size;
  if (offset == end_) {
    if (samples > 0)
      inAudio_ = true;
    try {
      if (!inAudio_)
        header_.insert(header_.end(), data, data + size);
      out_.insert(out_.end(), data, data + size);
    } catch (...) { // no memory: libFLAC is C, nothing may be thrown through it
      return false;
    }
    pendingSamples_ += samples;
    end_ = to;
    return true;
  }
  // Closing: the stream info is rewritten. It lies in the header (and in out_ if not taken yet).
  if (offset > end_ || to > header_.size())
    return false;
  std::copy(data, data + size, header_.begin() + static_cast<std::ptrdiff_t>(offset));
  for (uint64_t i = std::max(offset, outOffset_); i < to; ++i)
    out_[static_cast<size_t>(i - outOffset_)] = data[i - offset];
  return true;
}

void StreamRecorder::take() {
  lastTakeOffset_ = outOffset_;
  lastTakeSamples_ = storedSamples_;
  storedSamples_ += pendingSamples_;
  pendingSamples_ = 0;
  outOffset_ += out_.size();
  out_.clear();
}

uint64_t StreamRecorder::cut() {
  cut_ = true;
  ok_ = false;
  out_.clear();
  pendingSamples_ = 0;
  flac_.close(); // its last bytes are dropped (write() above)
  patchTotalSamples(lastTakeSamples_);
  outOffset_ = lastTakeOffset_;
  return lastTakeOffset_;
}

void StreamRecorder::patchTotalSamples(uint64_t samples) {
  if (header_.size() < kStreamInfoEnd)
    return; // nothing stored yet: no stream info to fix
  header_[kTotalSamples] =
      static_cast<uint8_t>((header_[kTotalSamples] & 0xF0) | ((samples >> 32) & 0x0F));
  for (size_t i = 0; i < 4; ++i)
    header_[kTotalSamples + 1 + i] = static_cast<uint8_t>(samples >> (24 - 8 * i));
  std::fill_n(header_.begin() + static_cast<std::ptrdiff_t>(kMd5), kMd5Size, uint8_t{0});
}

int StreamRecorder::gate() const { return armed_ ? static_cast<int>(gate_.state()) : kGateOff; }

float StreamRecorder::takeLevel() {
  const float p = peak_;
  peak_ = 0.0f;
  return p;
}

} // namespace wp::rec
