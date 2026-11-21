// #10/AK4: fuzz target for a sequence of commands through the C API of wp_core.h: load, play,
// pause, seek, rate, loop, volume, metronome, waveform and rendering. #85 adds the rest of the web
// API (tracks of the loading worker, taking over PCM piece by piece), loading without waiting and
// the duration of a file.
//
// It drives wp_core_offline (core/tests/reference.cmake), the C API of wp_core.h without an audio
// device: the same wp::Player as the app's core (src/player.cpp) and the browser core, rendered
// here instead of by a device callback. The input is a small program: the first byte picks the
// sample rate, then each command is one byte plus its arguments (see Op). Arguments can be any
// value, including NaN, infinities and negative or huge numbers, as a caller could pass them.
//
// Invariants after every command: position and duration are finite, 0 <= position <= duration;
// the loop pass counter never decreases; the metronome tempo stays in 20–300 BPM; every rendered
// sample is finite; error codes are documented ones. Per command of #85 see the comment at each
// case and docs/TESTS.md (Fuzzing). A crash, a sanitizer finding (ASan, UBSan,
// #57) or a broken invariant aborts, so libFuzzer keeps the input and the run fails.
#include <climits>
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

// Longest generated title (#66): converting to the device rate and the peaks cost time in
// proportion to its length, but a longer title reaches no other code; loops wrap and titles end
// sooner. The start corpus uses 1.5 s.
constexpr int kMaxPcmSeconds = 2;

// Loads per input (#66): loading converts the whole title, the most expensive command. A program
// needs few (a title, a replacement, a failed load after a good one); further load commands read
// their arguments but load nothing, so every input stays a valid program.
constexpr int kMaxLoads = 4;

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
  kRenderLong,   // up to 1–64 blocks of 512 frames, so loops wrap and files end (see renderLong)
  kMetroStart,   //
  kMetroStop,    //
  kMetroBpm,     // i32
  kMetroMeter,   // i32
  kMetroSubdiv,  // i32
  kMetroVolume,  // raw float
  kMetroRamp,    // enabled, start, target, step, every
  kMetroRampSec, // enabled, start, target, seconds
  kWaveform,     // seconds start, seconds end, count 0–64
  // #85: appended, so the programs of the corpus keep their meaning.
  kTrackDecode,   // rate (anyRate), flags, u16 length, bytes: wp_web_track_decode
  kTrackConvert,  // channels, frames, source and target rate (any value), flags: track_convert
  kTrackWaveform, // seconds start, seconds end, count 0–64, on the current track
  kTrackFree,     //
  kTrackToPlayer, // chunk size: begin/append/commit of the whole track, as the web app does
  kPcmBegin,      // frames (anyCount)
  kPcmAppend,     // frames (anyCount), flags
  kPcmCommit,     //
  kLoadAsync,     // path kind, u16 length, bytes: wp_load_async, the load keeps running
  kLoadWait,      //
  kFileDuration,  // path kind, u16 length, bytes: wp_file_duration
  kNullArgs,      // every function of #85 with a null player, track or path
  kOpCount,
};

bool documented(int r) { return r <= 0 && r >= WP_ERR_UNSUPPORTED_SAMPLE_RATE; }

// #85: limits that keep one input fast and below the fuzzer's 2 GB; the arguments themselves can
// still be any value (see anyRate, anyCount and the cases).
constexpr int kMaxTrackFrames = 4 * 96000;  // longest converted track, in frames at its rate
constexpr int kMaxBeginFrames = 1 << 24;    // largest reservation of wp_web_pcm_begin (128 MiB)
constexpr int kAppendFrames = 8192;         // largest piece appended from generated samples
constexpr int kMaxConvertSamples = 1 << 20; // largest generated PCM input of track_convert
constexpr int kWebAudioMaxRate = 768000;    // highest rate of a Web Audio AudioContext

float rawFloat(wp::fuzz::Reader &in) {
  const uint32_t v = in.u32();
  float f;
  std::memcpy(&f, &v, sizeof f);
  return f;
}

// #85: a sample rate as a caller could pass it. Mostly a usual one; also below WP_MIN_SAMPLE_RATE
// (0, negative, INT_MIN), above the usual ones up to the Web Audio maximum, and any int up to
// INT_MAX. Decoding and converting at a rate above kWebAudioMaxRate get only a few input frames
// (see trackDecode, trackConvert), since the output grows with the rate.
int anyRate(wp::fuzz::Reader &in) {
  const uint8_t kind = in.byte();
  if (kind < 192)
    return kRates[kind % 5];
  if (kind < 216)
    return -static_cast<int>(in.u32() % 2147483648u) + static_cast<int>(kind % 2) * 7999;
  if (kind < 240)
    return 96001 + static_cast<int>(in.u32() % static_cast<uint32_t>(kWebAudioMaxRate - 96000));
  return in.i32();
}

// #85: a count (frames, channels): mostly 0–plausibleMax, sometimes negative, sometimes any int.
int anyCount(wp::fuzz::Reader &in, uint32_t plausibleMax) {
  const uint8_t kind = in.byte();
  if (kind < 200)
    return static_cast<int>(in.u32() % (plausibleMax + 1));
  if (kind < 230)
    return -static_cast<int>(in.u32() % 2147483648u);
  return in.i32();
}

// #85: generated samples; with `wild`, NaN, infinities and huge values among them, as decoded PCM
// from the browser could contain. Every converted sample must come out finite.
float sampleAt(size_t i, bool wild) {
  if (wild) {
    switch (i % 7) {
    case 1:
      return std::nanf("");
    case 3:
      return INFINITY;
    case 4:
      return -INFINITY;
    case 5:
      return 3e38f;
    default:
      break;
    }
  }
  return static_cast<float>(static_cast<double>(i % 2000) / 1000.0 - 1.0);
}

const float *rampBuffer() {
  static const std::vector<float> ramp = [] {
    std::vector<float> v(static_cast<size_t>(kAppendFrames) * 2);
    for (size_t i = 0; i < v.size(); ++i)
      v[i] = sampleAt(i, false);
    return v;
  }();
  return ramp.data();
}

// A mono 16-bit WAV of `frames` frames at `rate`, for decoding at an extreme rate.
std::vector<uint8_t> tinyWav(int frames, uint32_t rate) {
  const auto u32le = [](std::vector<uint8_t> &v, uint32_t x) {
    for (int i = 0; i < 4; ++i)
      v.push_back(static_cast<uint8_t>(x >> (8 * i)));
  };
  const auto u16le = [](std::vector<uint8_t> &v, uint16_t x) {
    v.push_back(static_cast<uint8_t>(x));
    v.push_back(static_cast<uint8_t>(x >> 8));
  };
  const auto tag = [](std::vector<uint8_t> &v, const char *t) { v.insert(v.end(), t, t + 4); };
  std::vector<uint8_t> w;
  const auto dataBytes = static_cast<uint32_t>(frames * 2);
  tag(w, "RIFF");
  u32le(w, 36 + dataBytes);
  tag(w, "WAVE");
  tag(w, "fmt ");
  u32le(w, 16);
  u16le(w, 1);
  u16le(w, 1);
  u32le(w, rate);
  u32le(w, rate * 2);
  u16le(w, 2);
  u16le(w, 16);
  tag(w, "data");
  u32le(w, dataBytes);
  for (int i = 0; i < frames; ++i)
    u16le(w, static_cast<uint16_t>(i * 8000));
  return w;
}

struct State {
  wp_player *p = nullptr;
  long long passes = 0;
  bool renderedLast = false; // the last command rendered, nothing changed since
  int loads = 0;
  // #85: the current track (NULL if none) and what the player has begun to take over: the C API
  // must answer each wp_web_pcm_* call exactly as this model expects.
  wp_web_track *track = nullptr;
  int trackRate = 0;
  bool pending = false;
  long long pendingFrames = 0;
  long long appended = 0;
  // #85: a load started with wp_load_async may change the title at any time: its thread publishes
  // duration and position 0 while a render block may still publish the old position. Until a
  // block renders after the load has ended, checks that compare two reads or a value before and
  // after a command (position <= duration, unchanged duration) are skipped.
  bool async = false;
};

void checkInvariants(State &s) {
  const double pos = WP_FUZZ_CALL(wp_position, s.p);
  const double dur = WP_FUZZ_CALL(wp_duration, s.p);
  WP_FUZZ_CHECK(std::isfinite(pos) && std::isfinite(dur));
  WP_FUZZ_CHECK(dur >= 0.0 && pos >= 0.0);
  if (!s.async)
    WP_FUZZ_CHECK(pos <= dur + 1e-9);
  const long long passes = WP_FUZZ_CALL(wp_loop_passes, s.p);
  WP_FUZZ_CHECK(passes >= s.passes);
  s.passes = passes;
  const int bpm = WP_FUZZ_CALL(wp_metro_bpm, s.p);
  WP_FUZZ_CHECK(bpm >= 20 && bpm <= 300);
}

void render(State &s, int frames) {
  const bool settled = s.async && WP_FUZZ_CALL(wp_load_state, s.p) != WP_LOAD_RUNNING;
  const float *out = WP_FUZZ_CALL(wp_web_render, s.p, frames);
  WP_FUZZ_CHECK(out != nullptr);
  const int n = frames < 1 ? 1 : (frames > WP_WEB_MAX_BLOCK ? WP_WEB_MAX_BLOCK : frames);
  for (int i = 0; i < n * 2; ++i)
    WP_FUZZ_CHECK(std::isfinite(out[i]));
  if (settled)
    s.async = false;
}

// #66: renders only as long as it can still change something. Without title or metronome
// playing the output stays silent, so one block is checked; a loop pass or the end of the title
// ends the command too, the next command can render on.
void renderLong(State &s, int blocks) {
  for (int i = 0; i < blocks; ++i) {
    const long long passes = WP_FUZZ_CALL(wp_loop_passes, s.p);
    render(s, 512);
    if (!WP_FUZZ_CALL(wp_is_playing, s.p) && !WP_FUZZ_CALL(wp_metro_is_running, s.p))
      break;
    if (WP_FUZZ_CALL(wp_loop_passes, s.p) != passes)
      break;
  }
}

void loadPcm(State &s, wp::fuzz::Reader &in) {
  const int channels = 1 + in.byte() % 4;
  const uint32_t rawFrames = in.u32();
  const int rate = kRates[in.byte() % 5];
  // 0 to kMaxPcmSeconds, evenly: most titles are short and cheap to load.
  const int frames = static_cast<int>(rawFrames % static_cast<uint32_t>(kMaxPcmSeconds * rate + 1));
  if (++s.loads > kMaxLoads)
    return;
  std::vector<float> pcm(static_cast<size_t>(frames) * channels);
  for (size_t i = 0; i < pcm.size(); ++i)
    pcm[i] = static_cast<float>(static_cast<double>(i % 2000) / 1000.0 - 1.0);
  const int r = WP_FUZZ_CALL(wp_web_load_pcm, s.p, pcm.empty() ? nullptr : pcm.data(), channels,
                             frames, rate);
  WP_FUZZ_CHECK(documented(r));
  if (r == WP_OK && !s.async)
    WP_FUZZ_CHECK(WP_FUZZ_CALL(wp_position, s.p) == 0.0 && !WP_FUZZ_CALL(wp_is_playing, s.p));
}

// #85: checks a track the core just made and keeps it as the current one (the previous is freed).
// Invariants: NULL exactly on an error, which is documented and reaches *err; otherwise at least
// one frame, duration = frames / rate (finite, > 0), every sample finite and within +-8.
void takeTrack(State &s, wp_web_track *t, int err, bool withErr, int rate) {
  if (withErr) {
    WP_FUZZ_CHECK(documented(err));
    WP_FUZZ_CHECK((t != nullptr) == (err == WP_OK));
    if (rate < WP_MIN_SAMPLE_RATE)
      WP_FUZZ_CHECK(err == WP_ERR_UNSUPPORTED_SAMPLE_RATE);
  }
  if (!t)
    return;
  const int frames = WP_FUZZ_CALL(wp_web_track_frames, t);
  const double duration = WP_FUZZ_CALL(wp_web_track_duration, t);
  const float *data = WP_FUZZ_CALL(wp_web_track_data, t);
  WP_FUZZ_CHECK(rate >= WP_MIN_SAMPLE_RATE && frames >= 1 && data != nullptr);
  WP_FUZZ_CHECK(std::isfinite(duration) && duration > 0.0);
  WP_FUZZ_CHECK(duration == static_cast<double>(frames) / rate);
  for (size_t i = 0; i < static_cast<size_t>(frames) * 2; ++i)
    WP_FUZZ_CHECK(std::isfinite(data[i]) && std::fabs(data[i]) <= 8.0f);
  WP_FUZZ_CALL(wp_web_track_free, s.track);
  s.track = t;
  s.trackRate = rate;
}

void trackDecode(State &s, wp::fuzz::Reader &in) {
  const int rate = anyRate(in);
  const uint8_t flags = in.byte();
  size_t got = 0;
  const uint8_t *bytes = in.take(in.u16(), got);
  if (++s.loads > kMaxLoads)
    return;
  // The output grows with the rate: above the Web Audio maximum only a WAV of 1–4 frames, so even
  // INT_MAX gives about 11 000 frames. (A whole file at such a rate would need gigabytes.)
  std::vector<uint8_t> wav;
  if (rate > kWebAudioMaxRate) {
    wav = tinyWav(1 + flags % 4, static_cast<uint32_t>(kWebAudioMaxRate));
    bytes = wav.data();
    got = wav.size();
  }
  const bool withErr = (flags & 0x80) == 0;
  int err = 1; // not a code: must be overwritten
  wp_web_track *t = WP_FUZZ_CALL(wp_web_track_decode,
                                 (flags & 0x40) ? nullptr
                                 : got          ? bytes
                                                : reinterpret_cast<const uint8_t *>(""),
                                 got, rate, withErr ? &err : nullptr);
  if ((flags & 0x40) && withErr)
    WP_FUZZ_CHECK(t == nullptr);
  takeTrack(s, t, err, withErr, rate);
}

void trackConvert(State &s, wp::fuzz::Reader &in) {
  int channels = anyCount(in, 8);
  int frames = anyCount(in, static_cast<uint32_t>(kMaxPcmSeconds * 96000));
  const int src = anyRate(in), dst = anyRate(in);
  const uint8_t flags = in.byte();
  if (++s.loads > kMaxLoads)
    return;
  // At most kMaxTrackFrames of output: fewer input frames when the target rate is higher.
  if (src >= WP_MIN_SAMPLE_RATE && dst >= WP_MIN_SAMPLE_RATE && frames > 0) {
    const double limit = static_cast<double>(kMaxTrackFrames) * src / dst;
    if (static_cast<double>(frames) > limit)
      frames = limit < 1.0 ? 1 : static_cast<int>(limit);
  }
  // The input must hold channels * frames samples; beyond kMaxConvertSamples it is NULL, which the
  // core rejects (after the rates).
  const long long samples =
      channels > 0 && frames > 0 ? static_cast<long long>(channels) * frames : 0;
  std::vector<float> pcm;
  const bool null = (flags & 0x40) || samples > kMaxConvertSamples;
  if (!null) {
    pcm.resize(static_cast<size_t>(samples > 0 ? samples : 1));
    for (size_t i = 0; i < pcm.size(); ++i)
      pcm[i] = sampleAt(i, flags & 1);
  }
  const bool withErr = (flags & 0x80) == 0;
  int err = 1;
  wp_web_track *t = WP_FUZZ_CALL(wp_web_track_convert, null ? nullptr : pcm.data(), channels,
                                 frames, src, dst, withErr ? &err : nullptr);
  if (withErr && (src < WP_MIN_SAMPLE_RATE || dst < WP_MIN_SAMPLE_RATE))
    WP_FUZZ_CHECK(err == WP_ERR_UNSUPPORTED_SAMPLE_RATE);
  else if (withErr && (null || channels < 1 || frames < 1))
    WP_FUZZ_CHECK(err == WP_ERR_INVALID_ARGUMENT);
  takeTrack(s, t, err, withErr, dst);
}

void checkWaveform(int r, int count, const float *mins, const float *maxs) {
  WP_FUZZ_CHECK(r == WP_OK || r == WP_ERR_INVALID_ARGUMENT);
  for (int i = 0; r == WP_OK && i < count; ++i)
    WP_FUZZ_CHECK(std::isfinite(mins[i]) && std::isfinite(maxs[i]) && mins[i] <= maxs[i]);
}

// #85: wp_web_pcm_begin/append/commit against the model in State. Begin discards an unfinished
// title; append takes at most the announced frames (more is rejected without reading); commit puts
// the title in place only if exactly the announced frames came, without peaks.
void pcmBegin(State &s, int frames) {
  const int r = WP_FUZZ_CALL(wp_web_pcm_begin, s.p, frames);
  s.pending = r == WP_OK;
  s.pendingFrames = s.pending ? frames : 0;
  s.appended = 0;
  if (frames < 1)
    WP_FUZZ_CHECK(r == WP_ERR_INVALID_ARGUMENT);
  else
    WP_FUZZ_CHECK(r == WP_OK || r == WP_ERR_OUT_OF_MEMORY);
}

void pcmAppend(State &s, const float *stereo, int frames) {
  const int r = WP_FUZZ_CALL(wp_web_pcm_append, s.p, stereo, frames);
  const bool fits = s.pending && stereo && frames >= 1 && frames <= s.pendingFrames - s.appended;
  WP_FUZZ_CHECK(r == (fits ? WP_OK : WP_ERR_INVALID_ARGUMENT));
  if (fits)
    s.appended += frames;
}

void pcmCommit(State &s) {
  const double before = WP_FUZZ_CALL(wp_duration, s.p);
  const int r = WP_FUZZ_CALL(wp_web_pcm_commit, s.p);
  const bool complete = s.pending && s.appended == s.pendingFrames;
  WP_FUZZ_CHECK(complete ? documented(r) : r == WP_ERR_INVALID_ARGUMENT);
  if (s.async) {
    // a running load may replace the title at any time (see State::async)
  } else if (r == WP_OK) {
    const double expected =
        static_cast<double>(s.pendingFrames) / WP_FUZZ_CALL(wp_web_sample_rate, s.p);
    WP_FUZZ_CHECK(std::fabs(WP_FUZZ_CALL(wp_duration, s.p) - expected) <= 1e-9 * (1.0 + expected));
    WP_FUZZ_CHECK(WP_FUZZ_CALL(wp_position, s.p) == 0.0 && !WP_FUZZ_CALL(wp_is_playing, s.p));
    float lo = 0.0f, hi = 0.0f; // no peaks after commit: the worker has the waveform
    WP_FUZZ_CHECK(WP_FUZZ_CALL(wp_waveform, s.p, 0.0, expected, 1, &lo, &hi) ==
                  WP_ERR_INVALID_ARGUMENT);
  } else {
    WP_FUZZ_CHECK(WP_FUZZ_CALL(wp_duration, s.p) == before);
  }
  s.pending = false;
  s.pendingFrames = s.appended = 0;
}

// #85: a path to load or measure: a file with the input bytes, a missing file, "" or a folder.
enum PathKind { kPathFile, kPathMissing, kPathEmpty, kPathFolder };

std::string pathFor(PathKind kind, const char *purpose, const uint8_t *bytes, size_t size) {
  switch (kind) {
  case kPathFile: {
    const std::string &path = wp::fuzz::tempFile(purpose);
    return wp::fuzz::writeFile(path, bytes, size) ? path : std::string();
  }
  case kPathMissing:
    return wp::fuzz::tempFile("missing") + "/none.wav";
  case kPathEmpty:
    return std::string();
  case kPathFolder:
    return ".";
  }
  return std::string();
}

void checkLoadState(wp_player *p) {
  const int state = WP_FUZZ_CALL(wp_load_state, p);
  WP_FUZZ_CHECK(state == WP_LOAD_IDLE || state == WP_LOAD_RUNNING || state == WP_LOAD_READY ||
                (state < 0 && documented(state)));
  const double progress = WP_FUZZ_CALL(wp_load_progress, p);
  WP_FUZZ_CHECK(progress >= 0.0 && progress <= 1.0);
}

// #85: wp_load_async returns at once and the load keeps running while the next commands render,
// seek or load again (which cancels it). Each load writes its own file: the running one may still
// read the previous.
void loadAsync(State &s, wp::fuzz::Reader &in) {
  const auto kind = static_cast<PathKind>(in.byte() % 4);
  size_t got = 0;
  const uint8_t *bytes = in.take(in.u16(), got);
  if (++s.loads > kMaxLoads)
    return;
  const std::string purpose = "async" + std::to_string(s.loads);
  const std::string path = pathFor(kind, purpose.c_str(), bytes, got);
  if (kind == kPathFile && path.empty())
    return;
  const int r = WP_FUZZ_CALL(wp_load_async, s.p, path.c_str());
  WP_FUZZ_CHECK(documented(r));
  if (kind == kPathEmpty)
    WP_FUZZ_CHECK(r == WP_ERR_INVALID_ARGUMENT);
  if (r != WP_OK)
    WP_FUZZ_CHECK(WP_FUZZ_CALL(wp_load_state, s.p) == r);
  else
    s.async = true;
  checkLoadState(s.p);
}

void loadWait(State &s) {
  const int r = WP_FUZZ_CALL(wp_load_wait, s.p);
  WP_FUZZ_CHECK(documented(r));
  const int state = WP_FUZZ_CALL(wp_load_state, s.p);
  WP_FUZZ_CHECK(state != WP_LOAD_RUNNING);
  WP_FUZZ_CHECK(r == (state < 0 ? state : WP_OK));
  checkLoadState(s.p);
}

// #85: the duration of a file without loading it: finite, either > 0 or a documented error code.
void fileDuration(wp::fuzz::Reader &in) {
  const auto kind = static_cast<PathKind>(in.byte() % 4);
  size_t got = 0;
  const uint8_t *bytes = in.take(in.u16(), got);
  const std::string path = pathFor(kind, "duration", bytes, got);
  if (kind == kPathFile && path.empty())
    return;
  const double d = WP_FUZZ_CALL(wp_file_duration, path.c_str());
  WP_FUZZ_CHECK(std::isfinite(d));
  if (d <= 0.0)
    WP_FUZZ_CHECK(d == std::floor(d) && d < 0.0 && documented(static_cast<int>(d)));
  if (kind == kPathMissing)
    WP_FUZZ_CHECK(d == WP_ERR_FILE_NOT_FOUND);
  if (kind == kPathEmpty)
    WP_FUZZ_CHECK(d == WP_ERR_INVALID_ARGUMENT);
}

// #85: every function of #85 with NULL where a player, track or path belongs.
void nullArgs(State &s) {
  float lo = 0.0f, hi = 0.0f;
  WP_FUZZ_CHECK(WP_FUZZ_CALL(wp_web_track_data, nullptr) == nullptr);
  WP_FUZZ_CHECK(WP_FUZZ_CALL(wp_web_track_frames, nullptr) == 0);
  WP_FUZZ_CHECK(WP_FUZZ_CALL(wp_web_track_duration, nullptr) == 0.0);
  WP_FUZZ_CHECK(WP_FUZZ_CALL(wp_web_track_waveform, nullptr, 0.0, 1.0, 1, &lo, &hi) ==
                WP_ERR_INVALID_ARGUMENT);
  WP_FUZZ_CALL(wp_web_track_free, nullptr);
  WP_FUZZ_CHECK(WP_FUZZ_CALL(wp_web_pcm_begin, nullptr, 1) == WP_ERR_INVALID_ARGUMENT);
  WP_FUZZ_CHECK(WP_FUZZ_CALL(wp_web_pcm_append, nullptr, rampBuffer(), 1) ==
                WP_ERR_INVALID_ARGUMENT);
  WP_FUZZ_CHECK(WP_FUZZ_CALL(wp_web_pcm_commit, nullptr) == WP_ERR_INVALID_ARGUMENT);
  WP_FUZZ_CHECK(WP_FUZZ_CALL(wp_load_async, nullptr, "x.wav") == WP_ERR_INVALID_ARGUMENT);
  WP_FUZZ_CHECK(WP_FUZZ_CALL(wp_load_async, s.p, nullptr) == WP_ERR_INVALID_ARGUMENT);
  WP_FUZZ_CHECK(WP_FUZZ_CALL(wp_load_wait, nullptr) == WP_ERR_INVALID_ARGUMENT);
  WP_FUZZ_CHECK(WP_FUZZ_CALL(wp_file_duration, nullptr) == WP_ERR_INVALID_ARGUMENT);
}

void step(State &s, wp::fuzz::Reader &in) {
  const auto op = static_cast<Op>(in.byte() % kOpCount);
  s.renderedLast = op == kRender || op == kRenderLong;
  switch (op) {
  case kLoadEncoded: {
    size_t got = 0;
    const uint8_t *bytes = in.take(in.u16(), got);
    if (++s.loads > kMaxLoads)
      break;
    const double before = WP_FUZZ_CALL(wp_duration, s.p);
    const int r = WP_FUZZ_CALL(wp_web_load_encoded, s.p,
                               got ? bytes : reinterpret_cast<const uint8_t *>(""), got);
    WP_FUZZ_CHECK(documented(r));
    // A failed load leaves the previous title in place.
    if (r != WP_OK && !s.async)
      WP_FUZZ_CHECK(WP_FUZZ_CALL(wp_duration, s.p) == before);
    break;
  }
  case kLoadPcm:
    loadPcm(s, in);
    break;
  case kLoadFile: {
    size_t got = 0;
    const uint8_t *bytes = in.take(in.u16(), got);
    if (++s.loads > kMaxLoads)
      break;
    const std::string &path = wp::fuzz::tempFile("capi");
    if (!wp::fuzz::writeFile(path, bytes, got))
      break;
    WP_FUZZ_CHECK(documented(WP_FUZZ_CALL(wp_load, s.p, path.c_str())));
    WP_FUZZ_CHECK(WP_FUZZ_CALL(wp_load_state, s.p) != WP_LOAD_RUNNING);
    const double progress = WP_FUZZ_CALL(wp_load_progress, s.p);
    WP_FUZZ_CHECK(progress >= 0.0 && progress <= 1.0);
    break;
  }
  case kPlay:
    WP_FUZZ_CALL(wp_play, s.p);
    break;
  case kPause:
    WP_FUZZ_CALL(wp_pause, s.p);
    break;
  case kSeek:
    WP_FUZZ_CALL(wp_seek, s.p, in.seconds());
    break;
  case kRate: {
    const uint8_t kind = in.byte();
    WP_FUZZ_CALL(wp_set_rate, s.p, kind < 128 ? 0.1 + 0.05 * (kind % 39) : in.rawDouble());
    break;
  }
  case kLoop: {
    const double a = in.seconds();
    WP_FUZZ_CALL(wp_set_loop, s.p, a, in.seconds());
    break;
  }
  case kVolume: {
    const uint8_t kind = in.byte();
    WP_FUZZ_CALL(wp_set_volume, s.p, kind < 128 ? static_cast<float>(kind) / 127.0f : rawFloat(in));
    break;
  }
  case kRender:
    render(s, static_cast<int>(in.u16()));
    break;
  case kRenderLong:
    renderLong(s, 1 + in.byte() % 64);
    break;
  case kMetroStart:
    WP_FUZZ_CALL(wp_metro_start, s.p);
    break;
  case kMetroStop:
    WP_FUZZ_CALL(wp_metro_stop, s.p);
    break;
  case kMetroBpm:
    WP_FUZZ_CALL(wp_metro_set_bpm, s.p, in.i32());
    break;
  case kMetroMeter:
    WP_FUZZ_CALL(wp_metro_set_meter, s.p, in.i32());
    break;
  case kMetroSubdiv:
    WP_FUZZ_CALL(wp_metro_set_subdivision, s.p, in.i32());
    break;
  case kMetroVolume:
    WP_FUZZ_CALL(wp_metro_set_volume, s.p, rawFloat(in));
    break;
  case kMetroRamp: {
    const int enabled = in.byte() & 1;
    const int start = in.i32(), target = in.i32(), stepBpm = in.i32();
    WP_FUZZ_CALL(wp_metro_set_ramp, s.p, enabled, start, target, stepBpm, in.i32());
    break;
  }
  case kMetroRampSec: {
    const int enabled = in.byte() & 1;
    const int start = in.i32(), target = in.i32();
    WP_FUZZ_CALL(wp_metro_set_ramp_timed, s.p, enabled, start, target, in.i32());
    break;
  }
  case kWaveform: {
    const double a = in.seconds(), b = in.seconds();
    const int count = in.byte() % 65;
    float mins[64], maxs[64];
    checkWaveform(WP_FUZZ_CALL(wp_waveform, s.p, a, b, count, mins, maxs), count, mins, maxs);
    break;
  }
  case kTrackDecode:
    trackDecode(s, in);
    break;
  case kTrackConvert:
    trackConvert(s, in);
    break;
  case kTrackWaveform: {
    const double a = in.seconds(), b = in.seconds();
    const int count = in.byte() % 65;
    float mins[64], maxs[64];
    const int r = WP_FUZZ_CALL(wp_web_track_waveform, s.track, a, b, count, mins, maxs);
    checkWaveform(r, count, mins, maxs);
    if (!s.track)
      WP_FUZZ_CHECK(r == WP_ERR_INVALID_ARGUMENT);
    break;
  }
  case kTrackFree:
    WP_FUZZ_CALL(wp_web_track_free, s.track);
    s.track = nullptr;
    break;
  case kTrackToPlayer: {
    // As the worklet takes over a track from the worker: in pieces between render blocks.
    const int chunk = 64 + in.u16() % kAppendFrames;
    if (!s.track)
      break;
    const int frames = WP_FUZZ_CALL(wp_web_track_frames, s.track);
    const float *data = WP_FUZZ_CALL(wp_web_track_data, s.track);
    pcmBegin(s, frames);
    for (int done = 0; s.pending && done < frames; done += chunk)
      pcmAppend(s, data + static_cast<size_t>(done) * 2,
                chunk < frames - done ? chunk : frames - done);
    pcmCommit(s);
    break;
  }
  case kPcmBegin: {
    const int frames = anyCount(in, 4 * kAppendFrames);
    pcmBegin(s, frames > kMaxBeginFrames ? kMaxBeginFrames : frames);
    break;
  }
  case kPcmAppend: {
    int frames = anyCount(in, kAppendFrames);
    const uint8_t flags = in.byte();
    // More than announced must be rejected before anything is read, so that call gets any count
    // with a small buffer; otherwise at most kAppendFrames, from the track or generated.
    const long long rest = s.pending ? s.pendingFrames - s.appended : 0;
    if (frames > kAppendFrames && frames <= rest)
      frames = kAppendFrames;
    const bool fromTrack = s.track && frames <= WP_FUZZ_CALL(wp_web_track_frames, s.track);
    const float *src = fromTrack ? WP_FUZZ_CALL(wp_web_track_data, s.track) : rampBuffer();
    pcmAppend(s, (flags & 0x80) ? nullptr : src, frames);
    break;
  }
  case kPcmCommit:
    pcmCommit(s);
    break;
  case kLoadAsync:
    loadAsync(s, in);
    break;
  case kLoadWait:
    loadWait(s);
    break;
  case kFileDuration:
    fileDuration(in);
    break;
  case kNullArgs:
    nullArgs(s);
    break;
  case kOpCount:
    break;
  }
}

} // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  wp::fuzz::Reader in(data, size);
  State s;
  s.p = WP_FUZZ_CALL(wp_web_create, kRates[in.byte() % 5]);
  WP_FUZZ_CHECK(s.p != nullptr);
  // At most 200 commands per input, so a single input never runs for long.
  for (int i = 0; i < 200 && !in.done(); ++i) {
    step(s, in);
    checkInvariants(s);
  }
  // A last block after the final change of state; not needed if the program ended with one.
  if (!s.renderedLast) {
    render(s, 256);
    checkInvariants(s);
  }
  WP_FUZZ_CALL(wp_web_track_free, s.track);
  // A load may still be running (#85): destroying the player cancels and joins it.
  WP_FUZZ_CALL(wp_destroy, s.p);
  return 0;
}
