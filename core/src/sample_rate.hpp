#pragma once

namespace wp {

// Lowest sample rate the core accepts, as WP_MIN_SAMPLE_RATE in wp_core.h (#76). The only place
// it is set (#81): the player rejects rates below it, engine and metronome raise them to it. Below
// it the time stretch divides by zero (block size 0).
constexpr int kMinSampleRate = 8000;

// Highest sample rate the core accepts, as WP_MAX_SAMPLE_RATE in wp_core.h (#97). Set only here.
// Above it the player, loading, decoding and converting report kErrUnsupportedSampleRate: the
// decoded output grows with the rate (INT_MAX Hz made gigabytes from a two-second file).
constexpr int kMaxSampleRate = 192000;

// Whether the core works at `rate` (both limits included).
constexpr bool sampleRateSupported(int rate) {
  return rate >= kMinSampleRate && rate <= kMaxSampleRate;
}

// Rate to run an output device at whose own rate is `deviceRate`: its own rate up to
// kMaxSampleRate, the limit above it; the platform converts to the hardware rate (#97/AK6).
constexpr int outputRate(int deviceRate) {
  return deviceRate > kMaxSampleRate ? kMaxSampleRate : deviceRate;
}

} // namespace wp
