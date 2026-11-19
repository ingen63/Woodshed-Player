// #10/AK4: fuzz target for the decoders (MP3, WAV, FLAC through miniaudio) on raw bytes.
//
// Every input is decoded twice: from memory (wp::decodeMemory, the path of the browser core and of
// wp_web_track_decode) at a sample rate chosen by the input, and from a file (wp::fileDuration, the
// duration probe of the library). A crash, a sanitizer finding (ASan, UBSan, #57) or a broken
// invariant aborts, so libFuzzer keeps the input as a finding and the run fails.
//
// Invariants: the result is kOk or a documented error code; on success there is at least one frame,
// the PCM holds exactly frames * 2 finite samples (stereo), and the waveform has finite peaks
// with minimum <= maximum;
// on failure nothing is left in the output. The file probe gives a positive duration or an error.
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>

#include "fuzz_util.hpp"
#include "player_core.hpp"
#include "waveform.hpp"

namespace {

constexpr int kRates[] = {8000, 22050, 44100, 48000, 96000};

bool knownError(int r) {
  return r == wp::kErrInvalidArgument || r == wp::kErrUnsupportedFormat ||
         r == wp::kErrOutOfMemory || r == wp::kErrFileUnreadable;
}

void checkMemory(const uint8_t *data, size_t size) {
  // The first byte picks the rate but stays part of the file, so seed files decode unchanged.
  const int rate = kRates[size > 0 ? data[0] % 5 : 2];
  wp::Source src;
  const int r =
      wp::decodeMemory(size > 0 ? data : reinterpret_cast<const uint8_t *>(""), size, rate, src);
  if (r != wp::kOk) {
    WP_FUZZ_CHECK(knownError(r));
    WP_FUZZ_CHECK(src.frames == 0 && src.data.empty());
    return;
  }
  WP_FUZZ_CHECK(src.frames > 0);
  WP_FUZZ_CHECK(src.data.size() == static_cast<size_t>(src.frames) * wp::Player::kChannels);
  for (const float s : src.data)
    WP_FUZZ_CHECK(std::isfinite(s));
  const wp::Peaks peaks(src.data.data(), src.frames, wp::Player::kChannels, rate);
  const double duration = static_cast<double>(src.frames) / rate;
  float mins[8], maxs[8];
  WP_FUZZ_CHECK(peaks.query(0.0, duration, 8, mins, maxs));
  for (int i = 0; i < 8; ++i)
    WP_FUZZ_CHECK(std::isfinite(mins[i]) && std::isfinite(maxs[i]) && mins[i] <= maxs[i]);
}

void checkFile(const uint8_t *data, size_t size) {
  const std::string &path = wp::fuzz::tempFile("decoder");
  if (!wp::fuzz::writeFile(path, data, size))
    return;
  const double d = wp::fileDuration(path);
  WP_FUZZ_CHECK(std::isfinite(d));
  WP_FUZZ_CHECK(d > 0 || knownError(static_cast<int>(d)));
}

} // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  checkMemory(data, size);
  checkFile(data, size);
  return 0;
}
