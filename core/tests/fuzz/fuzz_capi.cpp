// #10/AK4: fuzz target for a sequence of commands through the C API of wp_core.h: load, play,
// pause, seek, rate, loop, volume, metronome, waveform and rendering.
//
// It drives wp_core_offline (core/tests/reference.cmake), the C API of wp_core.h without an audio
// device: the same wp::Player as the app's core (src/player.cpp) and the browser core, rendered
// here instead of by a device callback. The input is a small program: the first byte picks the
// sample rate, then each command is one byte plus its arguments (see Op). Arguments can be any
// value, including NaN, infinities and negative or huge numbers, as a caller could pass them.
//
// Invariants after every command: position and duration are finite, 0 <= position <= duration;
// the loop pass counter never decreases; the metronome tempo stays in 20–300 BPM; every rendered
// sample is finite; error codes are documented ones. A crash, a sanitizer finding (ASan, UBSan,
// #57) or a broken invariant aborts, so libFuzzer keeps the input and the run fails.
#include <cmath>
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include "fuzz_util.hpp"
#include "wp_core_web.h"

namespace {

constexpr int kRates[] = {8000, 22050, 44100, 48000, 96000};

enum Op : uint8_t {
  kLoadEncoded, // u16 length, then that many bytes of an audio file (MP3, WAV, FLAC or garbage)
  kLoadPcm,     // channels, frames, source rate: a generated ramp
  kLoadFile,    // u16 length, bytes written to a temporary file, loaded by path (background thread)
  kPlay,
  kPause,
  kSeek,         // seconds
  kRate,         // raw double, or a step of 0.05 in 0.1–2.0
  kLoop,         // seconds a, seconds b
  kVolume,       // raw float or 0–1
  kRender,       // u16 frames (clamped to 1–WP_WEB_MAX_BLOCK by the API)
  kRenderLong,   // 1–64 blocks of 512 frames, so loops wrap and files end
  kMetroStart,   //
  kMetroStop,    //
  kMetroBpm,     // i32
  kMetroMeter,   // i32
  kMetroSubdiv,  // i32
  kMetroVolume,  // raw float
  kMetroRamp,    // enabled, start, target, step, every
  kMetroRampSec, // enabled, start, target, seconds
  kWaveform,     // seconds start, seconds end, count 0–64
  kOpCount,
};

bool documented(int r) { return r <= 0 && r >= WP_ERR_BUSY; }

float rawFloat(wp::fuzz::Reader &in) {
  const uint32_t v = in.u32();
  float f;
  std::memcpy(&f, &v, sizeof f);
  return f;
}

struct State {
  wp_player *p = nullptr;
  long long passes = 0;
};

void checkInvariants(State &s) {
  const double pos = wp_position(s.p);
  const double dur = wp_duration(s.p);
  WP_FUZZ_CHECK(std::isfinite(pos) && std::isfinite(dur));
  WP_FUZZ_CHECK(dur >= 0.0);
  WP_FUZZ_CHECK(pos >= 0.0 && pos <= dur + 1e-9);
  const long long passes = wp_loop_passes(s.p);
  WP_FUZZ_CHECK(passes >= s.passes);
  s.passes = passes;
  const int bpm = wp_metro_bpm(s.p);
  WP_FUZZ_CHECK(bpm >= 20 && bpm <= 300);
}

void render(State &s, int frames) {
  const float *out = wp_web_render(s.p, frames);
  WP_FUZZ_CHECK(out != nullptr);
  const int n = frames < 1 ? 1 : (frames > WP_WEB_MAX_BLOCK ? WP_WEB_MAX_BLOCK : frames);
  for (int i = 0; i < n * 2; ++i)
    WP_FUZZ_CHECK(std::isfinite(out[i]));
}

void loadPcm(State &s, wp::fuzz::Reader &in) {
  const int channels = 1 + in.byte() % 4;
  const int frames = static_cast<int>(in.u32() % 200000); // up to ~4.5 s at 44.1 kHz
  const int rate = kRates[in.byte() % 5];
  std::vector<float> pcm(static_cast<size_t>(frames) * channels);
  for (size_t i = 0; i < pcm.size(); ++i)
    pcm[i] = static_cast<float>(static_cast<double>(i % 2000) / 1000.0 - 1.0);
  const int r = wp_web_load_pcm(s.p, pcm.empty() ? nullptr : pcm.data(), channels, frames, rate);
  WP_FUZZ_CHECK(documented(r));
  if (r == WP_OK)
    WP_FUZZ_CHECK(wp_position(s.p) == 0.0 && !wp_is_playing(s.p));
}

void step(State &s, wp::fuzz::Reader &in) {
  switch (static_cast<Op>(in.byte() % kOpCount)) {
  case kLoadEncoded: {
    size_t got = 0;
    const uint8_t *bytes = in.take(in.u16(), got);
    const double before = wp_duration(s.p);
    const int r =
        wp_web_load_encoded(s.p, got ? bytes : reinterpret_cast<const uint8_t *>(""), got);
    WP_FUZZ_CHECK(documented(r));
    // A failed load leaves the previous title in place.
    if (r != WP_OK)
      WP_FUZZ_CHECK(wp_duration(s.p) == before);
    break;
  }
  case kLoadPcm:
    loadPcm(s, in);
    break;
  case kLoadFile: {
    size_t got = 0;
    const uint8_t *bytes = in.take(in.u16(), got);
    const std::string &path = wp::fuzz::tempFile("capi");
    if (!wp::fuzz::writeFile(path, bytes, got))
      break;
    WP_FUZZ_CHECK(documented(wp_load(s.p, path.c_str())));
    WP_FUZZ_CHECK(wp_load_state(s.p) != WP_LOAD_RUNNING);
    const double progress = wp_load_progress(s.p);
    WP_FUZZ_CHECK(progress >= 0.0 && progress <= 1.0);
    break;
  }
  case kPlay:
    wp_play(s.p);
    break;
  case kPause:
    wp_pause(s.p);
    break;
  case kSeek:
    wp_seek(s.p, in.seconds());
    break;
  case kRate: {
    const uint8_t kind = in.byte();
    wp_set_rate(s.p, kind < 128 ? 0.1 + 0.05 * (kind % 39) : in.rawDouble());
    break;
  }
  case kLoop: {
    const double a = in.seconds();
    wp_set_loop(s.p, a, in.seconds());
    break;
  }
  case kVolume: {
    const uint8_t kind = in.byte();
    wp_set_volume(s.p, kind < 128 ? static_cast<float>(kind) / 127.0f : rawFloat(in));
    break;
  }
  case kRender:
    render(s, static_cast<int>(in.u16()));
    break;
  case kRenderLong: {
    const int blocks = 1 + in.byte() % 64;
    for (int i = 0; i < blocks; ++i)
      render(s, 512);
    break;
  }
  case kMetroStart:
    wp_metro_start(s.p);
    break;
  case kMetroStop:
    wp_metro_stop(s.p);
    break;
  case kMetroBpm:
    wp_metro_set_bpm(s.p, in.i32());
    break;
  case kMetroMeter:
    wp_metro_set_meter(s.p, in.i32());
    break;
  case kMetroSubdiv:
    wp_metro_set_subdivision(s.p, in.i32());
    break;
  case kMetroVolume:
    wp_metro_set_volume(s.p, rawFloat(in));
    break;
  case kMetroRamp: {
    const int enabled = in.byte() & 1;
    const int start = in.i32(), target = in.i32(), stepBpm = in.i32();
    wp_metro_set_ramp(s.p, enabled, start, target, stepBpm, in.i32());
    break;
  }
  case kMetroRampSec: {
    const int enabled = in.byte() & 1;
    const int start = in.i32(), target = in.i32();
    wp_metro_set_ramp_timed(s.p, enabled, start, target, in.i32());
    break;
  }
  case kWaveform: {
    const double a = in.seconds(), b = in.seconds();
    const int count = in.byte() % 65;
    float mins[64], maxs[64];
    const int r = wp_waveform(s.p, a, b, count, mins, maxs);
    WP_FUZZ_CHECK(r == WP_OK || r == WP_ERR_INVALID_ARGUMENT);
    for (int i = 0; r == WP_OK && i < count; ++i)
      WP_FUZZ_CHECK(std::isfinite(mins[i]) && std::isfinite(maxs[i]) && mins[i] <= maxs[i]);
    break;
  }
  case kOpCount:
    break;
  }
}

} // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  wp::fuzz::Reader in(data, size);
  State s;
  s.p = wp_web_create(kRates[in.byte() % 5]);
  WP_FUZZ_CHECK(s.p != nullptr);
  // At most 200 commands per input, so a single input never runs for long.
  for (int i = 0; i < 200 && !in.done(); ++i) {
    step(s, in);
    checkInvariants(s);
  }
  render(s, 256);
  checkInvariants(s);
  wp_destroy(s.p);
  return 0;
}
