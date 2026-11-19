#include "waveform.hpp"

#include <algorithm>
#include <cmath>

namespace wp {

Peaks::Peaks(const float *interleaved, long long frames, int channels, int sampleRate)
    : frames_(std::max(0LL, frames)), sampleRate_(sampleRate) {
  if (!interleaved || channels < 1 || frames_ == 0) {
    frames_ = 0;
    return;
  }
  const long long blocks = (frames_ + kBlockFrames - 1) / kBlockFrames;
  min_.resize(static_cast<size_t>(blocks));
  max_.resize(static_cast<size_t>(blocks));
  const float *s = interleaved;
  for (long long b = 0; b < blocks; ++b) {
    const long long n = std::min<long long>(kBlockFrames, frames_ - b * kBlockFrames) * channels;
    float lo = 0.0f, hi = 0.0f;
    for (long long i = 0; i < n; ++i) {
      lo = std::min(lo, s[i]);
      hi = std::max(hi, s[i]);
    }
    s += n;
    min_[static_cast<size_t>(b)] = std::max(-1.0f, lo);
    max_[static_cast<size_t>(b)] = std::min(1.0f, hi);
  }
}

bool Peaks::query(double start, double end, int count, float *mins, float *maxs) const {
  if (frames_ == 0 || count < 1 || !mins || !maxs)
    return false;
  if (!std::isfinite(start) || !std::isfinite(end) || start >= end)
    return false;
  // Eine Frame-Länge Spielraum am Ende, damit die gemeldete Dauer selbst als Ende gilt.
  const double dur = duration();
  if (start < 0.0 || start >= dur || end > dur + 1.0 / sampleRate_)
    return false;
  end = std::min(end, dur);

  const long long blocks = static_cast<long long>(min_.size());
  const double f0 = start * sampleRate_;
  const double step = (end - start) * sampleRate_ / count;
  for (int i = 0; i < count; ++i) {
    const double a = f0 + step * i;
    const double z = f0 + step * (i + 1);
    long long b0 = static_cast<long long>(std::floor(a / kBlockFrames));
    long long b1 = static_cast<long long>(std::ceil(z / kBlockFrames));
    b0 = std::clamp(b0, 0LL, blocks - 1);
    b1 = std::clamp(b1, b0 + 1, blocks);
    float lo = min_[static_cast<size_t>(b0)], hi = max_[static_cast<size_t>(b0)];
    for (long long b = b0 + 1; b < b1; ++b) {
      lo = std::min(lo, min_[static_cast<size_t>(b)]);
      hi = std::max(hi, max_[static_cast<size_t>(b)]);
    }
    mins[i] = lo;
    maxs[i] = hi;
  }
  return true;
}

} // namespace wp
