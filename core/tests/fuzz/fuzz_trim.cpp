// #116: fuzz target for trimming (wp::trim::trim) on raw bytes: WAV, FLAC, MP3, ADTS or anything
// else.
//
// The first two bytes choose start and end (in 1/16 s); the rest is the file, so seed files keep
// their layout after a two-byte prefix. A crash, a sanitizer finding or a broken invariant aborts.
//
// Invariants: the result is WP_OK or a documented error code; on an error there are no bytes. On
// success the new file has the format of the old one, start and end are finite with at least
// 1 s minus one frame between them (ADTS rounds to frames of up to 4096 samples), and trimming the
// new file again to its whole length succeeds or reports a documented error.
#include <cmath>
#include <cstddef>
#include <cstdint>

#include "fuzz_util.hpp"
#include "trim.hpp"
#include "wp_core.h"

namespace {

bool knownError(int r) {
  return r == WP_ERR_INVALID_ARGUMENT || r == WP_ERR_UNSUPPORTED_FORMAT ||
         r == WP_ERR_OUT_OF_MEMORY;
}

// Largest deviation of the cut from the request: an ADTS frame of 4 × 1024 samples at 7350 Hz.
constexpr double kSlack = 4.0 * 1024 / 7350;

} // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  const double start = size > 0 ? data[0] / 16.0 : 0.0;
  const double end = size > 1 ? start + data[1] / 16.0 : 0.0;
  const uint8_t *file = size > 2 ? data + 2 : data;
  const size_t n = size > 2 ? size - 2 : 0;
  const wp::trim::Result r = wp::trim::trim(file, n, start, end);
  if (r.code != WP_OK) {
    WP_FUZZ_CHECK(knownError(r.code));
    WP_FUZZ_CHECK(r.bytes.empty());
    return 0;
  }
  WP_FUZZ_CHECK(!r.bytes.empty());
  WP_FUZZ_CHECK(wp::trim::detect(r.bytes.data(), r.bytes.size()) == wp::trim::detect(file, n));
  WP_FUZZ_CHECK(std::isfinite(r.start) && std::isfinite(r.end));
  WP_FUZZ_CHECK(r.start >= 0 && r.end - r.start >= wp::trim::kMinSeconds - 2 * kSlack);
  const wp::trim::Result again = wp::trim::trim(r.bytes.data(), r.bytes.size(), 0, 1e9);
  WP_FUZZ_CHECK(again.code == WP_OK || knownError(again.code));
  return 0;
}
