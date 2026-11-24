// MP3 export (#141), see mp3_export.hpp.
#include "mp3_export.hpp"

#include <cstdio>
#include <map>
#include <mutex>
#include <vector>

#include <dlfcn.h>

#include "miniaudio_impl.hpp"
#include "player_core.hpp"
#include "sample_rate.hpp"

namespace wp::mp3 {

// ---- LAME, declared here from its public API (lame.h of LAME 3.100); never linked ----

struct LameFlags; // lame_global_flags
using LameInit = LameFlags *(*)();
using LameSetInt = int (*)(LameFlags *, int);
using LameInitParams = int (*)(LameFlags *);
using LameEncodeInterleaved = int (*)(LameFlags *, const float *, int, unsigned char *, int);
using LameEncodeChannels = int (*)(LameFlags *, const float *, const float *, int, unsigned char *,
                                   int);
using LameFlush = int (*)(LameFlags *, unsigned char *, int);
using LameTagFrame = size_t (*)(const LameFlags *, unsigned char *, size_t);
using LameClose = int (*)(LameFlags *);

struct Lame {
  LameInit init = nullptr;
  LameSetInt setInSampleRate = nullptr;
  LameSetInt setOutSampleRate = nullptr;
  LameSetInt setChannels = nullptr;
  LameSetInt setMode = nullptr;
  LameSetInt setBitrate = nullptr;
  LameSetInt setQuality = nullptr;
  LameSetInt setWriteId3Automatic = nullptr;
  LameInitParams initParams = nullptr;
  LameEncodeInterleaved encodeInterleaved = nullptr;
  LameEncodeChannels encodeChannels = nullptr;
  LameFlush flush = nullptr;
  LameTagFrame tagFrame = nullptr;
  LameClose close = nullptr;
};

namespace {

constexpr int kModeJointStereo = 1; // MPEG_mode in lame.h
constexpr int kModeMono = 3;
constexpr int kQuality = 2;        // 0 best … 9 fastest; 2 is LAME's "high quality"
constexpr long long kBlock = 4096; // frames per block

template <typename F> bool symbol(void *handle, const char *name, F &out) {
  out = reinterpret_cast<F>(
      dlsym(handle, name)); // NOLINT(cppcoreguidelines-pro-type-reinterpret-cast)
  return out != nullptr;
}

class MiniaudioReader final : public PcmReader {
public:
  ma_decoder decoder{};
  bool ready = false;
  long long read(float *out, long long count) override {
    ma_uint64 got = 0;
    const ma_result r =
        ma_decoder_read_pcm_frames(&decoder, out, static_cast<ma_uint64>(count), &got);
    if (r != MA_SUCCESS && r != MA_AT_END)
      return kErrUnsupportedFormat;
    return static_cast<long long>(got);
  }
  ~MiniaudioReader() override {
    if (ready)
      ma_decoder_uninit(&decoder);
  }
};

// Removes the output file unless kept.
class Output {
public:
  explicit Output(const char *path) : path_(path), file_(std::fopen(path, "wb")) {}
  ~Output() {
    if (file_)
      std::fclose(file_);
    if (!kept_)
      std::remove(path_);
  }
  Output(const Output &) = delete;
  Output &operator=(const Output &) = delete;
  bool open() const { return file_ != nullptr; }
  // Also for size 0 (LAME has nothing yet): fwrite writes nothing and returns 0.
  bool write(const unsigned char *data, size_t size) {
    return std::fwrite(data, 1, size, file_) == size;
  }
  bool rewriteStart(const unsigned char *data, size_t size) {
    return std::fseek(file_, 0, SEEK_SET) == 0 && std::fwrite(data, 1, size, file_) == size;
  }
  bool keep() {
    kept_ = std::fclose(file_) == 0;
    file_ = nullptr;
    return kept_;
  }

private:
  const char *path_;
  std::FILE *file_;
  bool kept_ = false;
};

class Encoder {
public:
  explicit Encoder(const Lame &l) : lame(l), flags(l.init()) {}
  ~Encoder() {
    if (flags)
      lame.close(flags);
  }
  Encoder(const Encoder &) = delete;
  Encoder &operator=(const Encoder &) = delete;
  const Lame &lame;
  LameFlags *flags;
};

} // namespace

std::unique_ptr<PcmReader> openMiniaudio(const char *path, int &code) {
  if (!path) {
    code = kErrInvalidArgument;
    return nullptr;
  }
  auto r = std::make_unique<MiniaudioReader>();
  ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, 0, 0);
  ma_result res = ma_decoder_init_file(path, &cfg, &r->decoder);
  if (res == MA_SUCCESS && r->decoder.outputChannels > 2) {
    // more than two channels: mixed to stereo by miniaudio
    ma_decoder_uninit(&r->decoder);
    cfg = ma_decoder_config_init(ma_format_f32, 2, 0);
    res = ma_decoder_init_file(path, &cfg, &r->decoder);
  }
  if (res != MA_SUCCESS) {
    code = res == MA_DOES_NOT_EXIST ? kErrFileNotFound : kErrUnsupportedFormat;
    return nullptr;
  }
  r->ready = true;
  r->channels = static_cast<int>(r->decoder.outputChannels);
  r->sampleRate = static_cast<int>(r->decoder.outputSampleRate);
  ma_uint64 length = 0;
  if (ma_decoder_get_length_in_pcm_frames(&r->decoder, &length) == MA_SUCCESS)
    r->frames = static_cast<long long>(length);
  if (!sampleRateSupported(r->sampleRate)) {
    code = kErrUnsupportedSampleRate;
    return nullptr;
  }
  code = kOk;
  return r;
}

const Lame *loadLame(const char *path) {
  static std::mutex mutex;
  static std::map<std::string, Lame> loaded; // never unloaded
  if (!path || !*path)
    return nullptr;
  const std::lock_guard<std::mutex> lock(mutex);
  const auto found = loaded.find(path);
  if (found != loaded.end())
    return &found->second;
  void *h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
  if (!h)
    return nullptr;
  Lame l;
  const bool all =
      symbol(h, "lame_init", l.init) && symbol(h, "lame_set_in_samplerate", l.setInSampleRate) &&
      symbol(h, "lame_set_out_samplerate", l.setOutSampleRate) &&
      symbol(h, "lame_set_num_channels", l.setChannels) && symbol(h, "lame_set_mode", l.setMode) &&
      symbol(h, "lame_set_brate", l.setBitrate) && symbol(h, "lame_set_quality", l.setQuality) &&
      symbol(h, "lame_set_write_id3tag_automatic", l.setWriteId3Automatic) &&
      symbol(h, "lame_init_params", l.initParams) &&
      symbol(h, "lame_encode_buffer_interleaved_ieee_float", l.encodeInterleaved) &&
      symbol(h, "lame_encode_buffer_ieee_float", l.encodeChannels) &&
      symbol(h, "lame_encode_flush", l.flush) && symbol(h, "lame_get_lametag_frame", l.tagFrame) &&
      symbol(h, "lame_close", l.close);
  if (!all) {
    dlclose(h);
    return nullptr;
  }
  return &loaded.emplace(path, l).first->second;
}

int encode(const Lame &lame, PcmReader &in, const char *path, int kbps, const volatile int *cancel,
           volatile double *progress) {
  if (!path || kbps < kMinBitrate || kbps > kMaxBitrate || in.channels < 1 || in.channels > 2)
    return kErrInvalidArgument;
  Encoder enc(lame);
  if (!enc.flags)
    return kErrOutOfMemory;
  LameFlags *gf = enc.flags;
  lame.setInSampleRate(gf, in.sampleRate);
  lame.setOutSampleRate(gf, kSampleRate);
  lame.setChannels(gf, in.channels);
  lame.setMode(gf, in.channels == 1 ? kModeMono : kModeJointStereo);
  lame.setBitrate(gf, kbps);
  lame.setQuality(gf, kQuality);
  lame.setWriteId3Automatic(gf, 0); // the app writes the tag
  if (lame.initParams(gf) < 0)
    return kErrInvalidArgument;

  Output out(path);
  if (!out.open())
    return kErrFileUnwritable;
  std::vector<float> pcm(static_cast<size_t>(kBlock * in.channels));
  // LAME's rule for the worst case: 1.25 × samples + 7200 bytes
  std::vector<unsigned char> mp3(static_cast<size_t>(kBlock * 5 / 4 + 7200));
  long long done = 0;
  if (progress)
    *progress = 0;
  for (;;) {
    if (cancel && *cancel)
      return kErrCancelled;
    const long long got = in.read(pcm.data(), kBlock);
    if (got < 0)
      return static_cast<int>(got);
    if (got == 0)
      break;
    const int n = static_cast<int>(got);
    const int bytes =
        in.channels == 2
            ? lame.encodeInterleaved(gf, pcm.data(), n, mp3.data(), static_cast<int>(mp3.size()))
            : lame.encodeChannels(gf, pcm.data(), pcm.data(), n, mp3.data(),
                                  static_cast<int>(mp3.size()));
    // The buffer is as large as LAME asks for, so only its memory can fail (-2).
    if (bytes < 0)
      return kErrOutOfMemory;
    if (!out.write(mp3.data(), static_cast<size_t>(bytes)))
      return kErrFileUnwritable;
    done += got;
    if (progress && in.frames > 0)
      *progress = static_cast<double>(done) / static_cast<double>(in.frames);
  }
  const int tail = lame.flush(gf, mp3.data(), static_cast<int>(mp3.size()));
  if (tail < 0)
    return kErrOutOfMemory;
  if (!out.write(mp3.data(), static_cast<size_t>(tail)))
    return kErrFileUnwritable;
  // LAME's info frame (length, encoder delay and padding for gapless playback) replaces the empty
  // frame it wrote first. LAME gives at most the buffer's size, 0 without an info frame; writing 0
  // bytes changes nothing.
  const size_t tagSize = lame.tagFrame(gf, mp3.data(), mp3.size());
  if (!out.rewriteStart(mp3.data(), tagSize))
    return kErrFileUnwritable;
  if (!out.keep())
    return kErrFileUnwritable;
  if (progress)
    *progress = 1;
  return kOk;
}

int exportFile(const char *lamePath, const char *inPath, const char *outPath, int kbps,
               const volatile int *cancel, volatile double *progress) {
  if (!inPath || !outPath)
    return kErrInvalidArgument;
  const Lame *lame = loadLame(lamePath);
  if (!lame)
    return kErrEncoderUnavailable;
  int code = kOk;
  std::unique_ptr<PcmReader> in = openMiniaudio(inPath, code);
  if (!in && code == kErrUnsupportedFormat) {
    int system = kOk;
    in = openSystem(inPath, system);
    if (in)
      code = kOk;
  }
  if (!in)
    return code;
  return encode(*lame, *in, outPath, kbps, cancel, progress);
}

} // namespace wp::mp3
