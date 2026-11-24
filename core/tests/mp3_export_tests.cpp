// MP3 export (#141/AK10, AK12, AK13, AK16, AK18): generated sine as WAV encoded to MP3 with LAME
// and read back with miniaudio. LAME is loaded from WP_LAME_PATH or the build of
// tools/build-lame.sh (local/lame); without it the encoding checks are skipped, WP_LAME_REQUIRED=1
// makes that a failure (#125).
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <functional>
#include <string>
#include <utility>
#include <vector>

#include "miniaudio_impl.hpp"
#include "mp3_export.hpp"
#include "player_core.hpp"
#include "test_required.hpp"
#include "wp_core.h"

namespace {

int failures = 0;
int checks = 0;

#define CHECK(cond)                                                                                \
  do {                                                                                             \
    ++checks;                                                                                      \
    if (!(cond)) {                                                                                 \
      ++failures;                                                                                  \
      std::printf("  FAILED %s:%d: %s\n", __FILE__, __LINE__, #cond);                              \
    }                                                                                              \
  } while (0)

namespace fs = std::filesystem;
namespace mp3 = wp::mp3;

constexpr double kPi = 3.14159265358979323846;

fs::path tmpDir() {
  static const fs::path dir = [] {
    auto d =
        fs::temp_directory_path() /
        ("wp_mp3_" + std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
    fs::create_directories(d);
    return d;
  }();
  return dir;
}

std::string lamePath() {
  if (const char *env = std::getenv("WP_LAME_PATH"))
    return env;
#ifdef __APPLE__
  return WP_LAME_DIR "/libmp3lame.dylib";
#else
  return WP_LAME_DIR "/libmp3lame.so";
#endif
}

void put16(std::ofstream &f, uint16_t v) { f.put(char(v & 0xff)).put(char(v >> 8)); }
void put32(std::ofstream &f, uint32_t v) {
  put16(f, uint16_t(v & 0xffff));
  put16(f, uint16_t(v >> 16));
}

// 16-bit PCM WAV: channel c is a sine of `freqs[c]` Hz at half scale.
fs::path wav(const std::string &name, int rate, const std::vector<double> &freqs, double seconds) {
  const fs::path p = tmpDir() / name;
  std::ofstream f(p, std::ios::binary);
  const auto channels = static_cast<uint16_t>(freqs.size());
  const auto frames = static_cast<uint32_t>(seconds * rate);
  const uint32_t data = frames * channels * 2;
  f.write("RIFF", 4);
  put32(f, 36 + data);
  f.write("WAVEfmt ", 8);
  put32(f, 16);
  put16(f, 1);
  put16(f, channels);
  put32(f, uint32_t(rate));
  put32(f, uint32_t(rate) * channels * 2);
  put16(f, uint16_t(channels * 2));
  put16(f, 16);
  f.write("data", 4);
  put32(f, data);
  for (uint32_t i = 0; i < frames; ++i)
    for (const double hz : freqs)
      put16(f, uint16_t(int16_t(std::lround(16384 * std::sin(2 * kPi * hz * i / rate)))));
  return p;
}

struct Decoded {
  int channels = 0;
  int rate = 0;
  std::vector<float> pcm; // interleaved
  long long frames() const { return channels ? (long long)pcm.size() / channels : 0; }
};

Decoded decode(const fs::path &p) {
  Decoded d;
  ma_decoder dec;
  ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, 0, 0);
  if (ma_decoder_init_file(p.string().c_str(), &cfg, &dec) != MA_SUCCESS)
    return d;
  d.channels = int(dec.outputChannels);
  d.rate = int(dec.outputSampleRate);
  std::vector<float> block(4096 * size_t(d.channels));
  for (;;) {
    ma_uint64 got = 0;
    ma_decoder_read_pcm_frames(&dec, block.data(), 4096, &got);
    if (got == 0)
      break;
    d.pcm.insert(d.pcm.end(), block.begin(), block.begin() + long(got) * d.channels);
  }
  ma_decoder_uninit(&dec);
  return d;
}

// Frequency of channel `c` from the zero crossings in the middle half.
double frequency(const Decoded &d, int c) {
  const long long n = d.frames();
  const long long from = n / 4, to = 3 * n / 4;
  int crossings = 0;
  for (long long i = from + 1; i < to; ++i) {
    const float a = d.pcm[size_t((i - 1) * d.channels + c)], b = d.pcm[size_t(i * d.channels + c)];
    if ((a < 0) != (b < 0))
      ++crossings;
  }
  const double seconds = double(to - from) / d.rate; // the frames counted above
  return crossings / 2.0 / seconds;
}

float peak(const Decoded &d, int c) {
  float m = 0;
  for (long long i = d.frames() / 4; i < 3 * d.frames() / 4; ++i)
    m = std::fmax(m, std::fabs(d.pcm[size_t(i * d.channels + c)]));
  return m;
}

std::vector<unsigned char> bytes(const fs::path &p) {
  std::ifstream f(p, std::ios::binary);
  return {std::istreambuf_iterator<char>(f), {}};
}

bool near(double a, double b, double tolerance) { return std::fabs(a - b) <= tolerance; }

int run(const fs::path &in, const fs::path &out, int kbps = 192,
        const volatile int *cancel = nullptr, volatile double *progress = nullptr) {
  return wp_mp3_export(lamePath().c_str(), in.string().c_str(), out.string().c_str(), kbps,
                       const_cast<int *>(cancel), const_cast<double *>(progress));
}

// ---- without LAME ----

void withoutLameNothingIsWritten() { // #141/AK16
  const fs::path in = wav("a.wav", 44100, {440}, 0.5), out = tmpDir() / "none.mp3";
  CHECK(wp_mp3_available("/nonexistent/libmp3lame.dylib") == 0);
  CHECK(wp_mp3_export("/nonexistent/libmp3lame.dylib", in.string().c_str(), out.string().c_str(),
                      192, nullptr, nullptr) == WP_ERR_ENCODER_UNAVAILABLE);
  CHECK(wp_mp3_export(nullptr, in.string().c_str(), out.string().c_str(), 192, nullptr, nullptr) ==
        WP_ERR_ENCODER_UNAVAILABLE);
  CHECK(wp_mp3_export("", in.string().c_str(), out.string().c_str(), 192, nullptr, nullptr) ==
        WP_ERR_ENCODER_UNAVAILABLE);
  CHECK(!fs::exists(out));
  // a library that is not LAME
#ifdef __APPLE__
  CHECK(wp_mp3_available("/usr/lib/libz.1.dylib") == 0);
#else
  CHECK(wp_mp3_available("libz.so.1") == 0);
#endif
  CHECK(std::strcmp(wp::errorMessage(WP_ERR_ENCODER_UNAVAILABLE), "MP3 encoder not available") ==
        0);
  CHECK(std::strcmp(wp::errorMessage(WP_ERR_FILE_UNWRITABLE), "File cannot be written") == 0);
}

// ---- with LAME ----

void loadsLameOnce() {
  CHECK(wp_mp3_available(lamePath().c_str()) == 1);
  const mp3::Lame *a = mp3::loadLame(lamePath().c_str());
  CHECK(a != nullptr);
  CHECK(mp3::loadLame(lamePath().c_str()) == a);
}

void stereoSineAt48kBecomes44kMp3() { // #141/AK10, AK18
  const fs::path in = wav("stereo48.wav", 48000, {440, 660}, 2), out = tmpDir() / "stereo.mp3";
  volatile double progress = -1;
  CHECK(run(in, out, 192, nullptr, &progress) == WP_OK);
  CHECK(progress == 1.0);
  const Decoded d = decode(out);
  CHECK(d.rate == 44100);
  CHECK(d.channels == 2);
  // 2 s; the decoder may add LAME's delay and padding (less than three MP3 frames)
  CHECK(d.frames() >= 2 * 44100 - 1152);
  CHECK(d.frames() <= 2 * 44100 + 3 * 1152);
  CHECK(near(frequency(d, 0), 440, 5));
  CHECK(near(frequency(d, 1), 660, 5));
  CHECK(near(peak(d, 0), 0.5, 0.05));
  CHECK(near(peak(d, 1), 0.5, 0.05));
}

void monoStaysMono() { // #141/AK10: the channels of the source
  const fs::path in = wav("mono.wav", 44100, {1000}, 1), out = tmpDir() / "mono.mp3";
  CHECK(run(in, out) == WP_OK);
  const Decoded d = decode(out);
  CHECK(d.channels == 1);
  CHECK(d.rate == 44100);
  CHECK(near(frequency(d, 0), 1000, 10));
}

void moreThanTwoChannelsBecomeStereo() {
  const fs::path in = wav("quad.wav", 44100, {440, 440, 440, 440}, 1), out = tmpDir() / "quad.mp3";
  CHECK(run(in, out) == WP_OK);
  const Decoded d = decode(out);
  CHECK(d.channels == 2);
  CHECK(near(frequency(d, 0), 440, 5));
}

void startsWithLameInfoFrameAndNoTag() { // #141/AK8: the app writes the tag in front
  const fs::path in = wav("info.wav", 44100, {440}, 1), out = tmpDir() / "info.mp3";
  CHECK(run(in, out) == WP_OK);
  const auto b = bytes(out);
  CHECK(b.size() > 200);
  CHECK(b[0] == 0xff && (b[1] & 0xe0) == 0xe0); // MPEG frame sync, no ID3
  const std::string head(b.begin(), b.begin() + 200);
  CHECK(head.find("Info") != std::string::npos); // CBR info frame
  CHECK(head.find("LAME") != std::string::npos);
  CHECK(std::string(b.end() - 128, b.end()).rfind("TAG", 0) != 0); // no ID3v1 either
}

void bitrateGivesTheSize() { // #141/AK10: at least 192 kbit/s
  const fs::path in = wav("rate.wav", 44100, {440, 550}, 4);
  for (const int kbps : {32, 192, 320}) {
    const fs::path out = tmpDir() / ("rate" + std::to_string(kbps) + ".mp3");
    CHECK(run(in, out, kbps) == WP_OK);
    const double expected = kbps * 1000.0 / 8 * 4;
    CHECK(near(double(fs::file_size(out)), expected, expected * 0.05));
  }
  for (const int kbps : {31, 321, 0, -192}) {
    const fs::path out = tmpDir() / "badrate.mp3";
    CHECK(run(in, out, kbps) == WP_ERR_INVALID_ARGUMENT);
    CHECK(!fs::exists(out));
  }
}

void cancelRemovesTheFile() { // #141/AK12
  const fs::path in = wav("cancel.wav", 44100, {440}, 1), out = tmpDir() / "cancel.mp3";
  volatile int cancel = 1;
  volatile double progress = -1;
  CHECK(run(in, out, 192, &cancel, &progress) == WP_ERR_CANCELLED);
  CHECK(!fs::exists(out));
  CHECK(progress == 0.0);
  cancel = 0;
  CHECK(run(in, out, 192, &cancel) == WP_OK);
  CHECK(fs::exists(out));
}

// Reader that stops with an error after `good` blocks; `cancelAfter` sets the flag after that
// block.
class ScriptedReader final : public mp3::PcmReader {
public:
  ScriptedReader(int channelCount, int good, std::function<void()> afterBlock = nullptr)
      : good_(good), after_(std::move(afterBlock)) {
    channels = channelCount;
    sampleRate = 44100;
    frames = 4096LL * 10;
  }
  long long read(float *out, long long count) override {
    if (blocks_ == good_)
      return wp::kErrUnsupportedFormat;
    for (long long i = 0; i < count * channels; ++i)
      out[i] = float(0.5 * std::sin(i * 0.05));
    ++blocks_;
    if (after_)
      after_();
    return count;
  }

private:
  int good_;
  int blocks_ = 0;
  std::function<void()> after_;
};

void readErrorRemovesTheFile() { // #141/AK13
  const mp3::Lame *lame = mp3::loadLame(lamePath().c_str());
  const fs::path out = tmpDir() / "broken.mp3";
  ScriptedReader r(2, 3);
  volatile double progress = 0;
  CHECK(mp3::encode(*lame, r, out.string().c_str(), 192, nullptr, &progress) ==
        wp::kErrUnsupportedFormat);
  CHECK(!fs::exists(out));
  CHECK(near(progress, 0.3, 1e-9)); // three of ten blocks
}

void cancelBetweenBlocks() { // #141/AK12: a half-written file is removed
  const mp3::Lame *lame = mp3::loadLame(lamePath().c_str());
  const fs::path out = tmpDir() / "half.mp3";
  volatile int cancel = 0;
  int blocks = 0;
  ScriptedReader r(1, 100, [&] {
    if (++blocks == 2)
      cancel = 1;
  });
  CHECK(mp3::encode(*lame, r, out.string().c_str(), 192, &cancel, nullptr) == wp::kErrCancelled);
  CHECK(blocks == 2);
  CHECK(!fs::exists(out));
}

void progressWithoutKnownLength() { // #141/AK12: without a length no fraction until the end
  const mp3::Lame *lame = mp3::loadLame(lamePath().c_str());
  const fs::path out = tmpDir() / "unknown.mp3";
  volatile double progress = -1;
  std::vector<double> seen;
  ScriptedReader r(2, 3, [&] {
    const double now = progress;
    seen.push_back(now);
  });
  r.frames = 0; // unknown
  CHECK(mp3::encode(*lame, r, out.string().c_str(), 192, nullptr, &progress) ==
        wp::kErrUnsupportedFormat);
  CHECK(seen == std::vector<double>({0.0, 0.0, 0.0}));
}

void badInputAndOutput() { // #141/AK13: named per title by the app
  const fs::path in = wav("ok.wav", 44100, {440}, 0.5);
  CHECK(run(tmpDir() / "missing.wav", tmpDir() / "m.mp3") == WP_ERR_FILE_NOT_FOUND);
  CHECK(!fs::exists(tmpDir() / "m.mp3"));
  const fs::path junk = tmpDir() / "junk.wav";
  std::ofstream(junk) << "this is not audio at all, not even close";
  CHECK(run(junk, tmpDir() / "j.mp3") == WP_ERR_UNSUPPORTED_FORMAT);
  CHECK(!fs::exists(tmpDir() / "j.mp3"));
  CHECK(run(in, tmpDir() / "no" / "such" / "dir.mp3") == WP_ERR_FILE_UNWRITABLE);
  CHECK(wp_mp3_export(lamePath().c_str(), nullptr, "x.mp3", 192, nullptr, nullptr) ==
        WP_ERR_INVALID_ARGUMENT);
  CHECK(wp_mp3_export(lamePath().c_str(), in.string().c_str(), nullptr, 192, nullptr, nullptr) ==
        WP_ERR_INVALID_ARGUMENT);
  int code = 0;
  CHECK(mp3::openMiniaudio(nullptr, code) == nullptr);
  CHECK(code == wp::kErrInvalidArgument);
  CHECK(mp3::openSystem(nullptr, code) == nullptr);
}

void readerReportsTheSource() {
  int code = -100;
  auto r = mp3::openMiniaudio(wav("src.wav", 22050, {440}, 0.5).string().c_str(), code);
  CHECK(code == wp::kOk);
  CHECK(r != nullptr);
  if (r) {
    CHECK(r->channels == 1);
    CHECK(r->sampleRate == 22050);
    CHECK(r->frames == 11025);
  }
}

#ifdef __APPLE__
// #141/AK10: M4A (AAC) through the system decoder; the file is made with the system's encoder.
void m4aThroughTheSystem() {
  const fs::path in = tmpDir() / "aac.m4a", out = tmpDir() / "aac.mp3";
  const std::string make = "/usr/bin/afconvert -f m4af -d aac '" +
                           wav("aac.wav", 44100, {440, 440}, 1).string() + "' '" + in.string() +
                           "' 2>/dev/null";
  // NOLINTNEXTLINE(bugprone-command-processor): a fixed command of the test, paths made above
  if (std::system(make.c_str()) != 0) {
    std::printf("  skip: afconvert not available\n");
    return;
  }
  CHECK(run(in, out) == WP_OK);
  const Decoded d = decode(out);
  CHECK(d.channels == 2);
  CHECK(near(frequency(d, 0), 440, 5));
  // the reader knows the length (1 s; AAC adds no more than its priming)
  int code = -100;
  auto r = mp3::openSystem(in.string().c_str(), code);
  CHECK(code == wp::kOk);
  CHECK(r != nullptr && r->frames >= 44100 && r->frames <= 44100 + 4096);
  // mono stays mono
  const fs::path mono = tmpDir() / "mono.m4a", monoOut = tmpDir() / "mono_aac.mp3";
  const std::string makeMono = "/usr/bin/afconvert -f m4af -d aac '" +
                               wav("mono_aac.wav", 44100, {440}, 1).string() + "' '" +
                               mono.string() + "' 2>/dev/null";
  // NOLINTNEXTLINE(bugprone-command-processor): a fixed command of the test, paths made above
  CHECK(std::system(makeMono.c_str()) == 0);
  auto m = mp3::openSystem(mono.string().c_str(), code);
  CHECK(m != nullptr && m->channels == 1);
  CHECK(run(mono, monoOut) == WP_OK);
  CHECK(decode(monoOut).channels == 1);
  // a file the system cannot read either
  const fs::path junk = tmpDir() / "junk.m4a";
  std::ofstream(junk) << "not an m4a";
  CHECK(mp3::openSystem(junk.string().c_str(), code) == nullptr);
  CHECK(code == wp::kErrUnsupportedFormat);
}
#endif

} // namespace

int main() {
  std::vector<std::pair<std::string, std::function<void()>>> tests = {
      {"withoutLameNothingIsWritten", withoutLameNothingIsWritten},
  };
  const std::string reason = "no LAME at " + lamePath() + " (tools/build-lame.sh)";
  if (wptest::needs(wptest::kLameRequired, wp_mp3_available(lamePath().c_str()) == 1,
                    reason.c_str(), failures)) {
    tests.insert(tests.end(),
                 {
                     {"loadsLameOnce", loadsLameOnce},
                     {"stereoSineAt48kBecomes44kMp3", stereoSineAt48kBecomes44kMp3},
                     {"monoStaysMono", monoStaysMono},
                     {"moreThanTwoChannelsBecomeStereo", moreThanTwoChannelsBecomeStereo},
                     {"startsWithLameInfoFrameAndNoTag", startsWithLameInfoFrameAndNoTag},
                     {"bitrateGivesTheSize", bitrateGivesTheSize},
                     {"cancelRemovesTheFile", cancelRemovesTheFile},
                     {"readErrorRemovesTheFile", readErrorRemovesTheFile},
                     {"cancelBetweenBlocks", cancelBetweenBlocks},
                     {"progressWithoutKnownLength", progressWithoutKnownLength},
                     {"badInputAndOutput", badInputAndOutput},
                     {"readerReportsTheSource", readerReportsTheSource},
#ifdef __APPLE__
                     {"m4aThroughTheSystem", m4aThroughTheSystem},
#endif
                 });
  }
  for (const auto &[name, fn] : tests) {
    const int before = failures;
    fn();
    std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name.c_str());
  }
  std::error_code ec;
  fs::remove_all(tmpDir(), ec);
  std::printf("%d checks, %d failures\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
