// Trimming MP4/M4A (#120), part of wp::trim (see trim.hpp). Internal to the trim library.
#pragma once

#include "trim.hpp"

#include <cstddef>
#include <cstdint>

namespace wp::trim {

// Samples [first, last) of a file with `total` samples at `rate` for the requested seconds; false
// if fewer than kMinSeconds remain (NaN included). Shared by all formats (trim.cpp).
bool sampleRange(double start, double end, long long total, double rate, long long &first,
                 long long &last);

// Cuts an MP4/M4A file with one AAC or ALAC track at the nearest sample (frame) boundaries without
// encoding again, see trim.hpp.
Result trimMp4(const uint8_t *data, size_t size, double start, double end);

} // namespace wp::trim
