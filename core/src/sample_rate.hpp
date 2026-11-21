#pragma once

namespace wp {

// Lowest sample rate the core accepts, as WP_MIN_SAMPLE_RATE in wp_core.h (#76). The only place
// it is set (#81): the player rejects rates below it, engine and metronome raise them to it. Below
// it the time stretch divides by zero (block size 0).
constexpr int kMinSampleRate = 8000;

} // namespace wp
