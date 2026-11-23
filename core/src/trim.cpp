// Trimming the start and end of an audio file (#116), see trim.hpp.
#include "trim.hpp"
#include "trim_mp4.hpp"

#include "flac_writer.hpp"
#include "miniaudio_impl.hpp"
#include "wp_core.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <new>
#include <stdexcept>

namespace wp::trim {

namespace {

// ---- Bytes ----

uint32_t be16(const uint8_t *p) { return (uint32_t{p[0]} << 8) | p[1]; }
uint32_t be24(const uint8_t *p) { return (uint32_t{p[0]} << 16) | (uint32_t{p[1]} << 8) | p[2]; }
uint32_t be32(const uint8_t *p) { return (be16(p) << 16) | be16(p + 2); }
uint32_t le16(const uint8_t *p) { return uint32_t{p[0]} | (uint32_t{p[1]} << 8); }
uint32_t le32(const uint8_t *p) { return le16(p) | (le16(p + 2) << 16); }

void putLe32(uint8_t *p, uint32_t v) {
  for (int i = 0; i < 4; ++i)
    p[i] = static_cast<uint8_t>(v >> (8 * i));
}
void putBe32(uint8_t *p, uint32_t v) {
  for (int i = 0; i < 4; ++i)
    p[i] = static_cast<uint8_t>(v >> (8 * (3 - i)));
}

bool tagAt(const uint8_t *data, size_t size, size_t pos, const char *tag) {
  const size_t n = std::strlen(tag);
  return pos <= size && size - pos >= n && std::memcmp(data + pos, tag, n) == 0;
}

void append(std::vector<uint8_t> &out, const uint8_t *from, size_t n) {
  out.insert(out.end(), from, from + n);
}

// End of the ID3v2 tags at the start of the file (0 if there is none). A tag longer than the file
// ends there.
size_t id3v2End(const uint8_t *data, size_t size) {
  size_t p = 0;
  while (tagAt(data, size, p, "ID3") && size - p >= 10) {
    const uint8_t *h = data + p;
    if ((h[6] | h[7] | h[8] | h[9]) & 0x80)
      break; // not synchsafe: no tag
    const size_t body = (size_t{h[6]} << 21) | (size_t{h[7]} << 14) | (size_t{h[8]} << 7) | h[9];
    const size_t footer = (h[5] & 0x10) ? 10 : 0;
    p = std::min(size, p + 10 + body + footer);
  }
  return p;
}

// Start of the tags after the audio of an MP3 or ADTS file: ID3v1 (128 bytes «TAG»), an APEv2 tag
// before it or at the end, Lyrics3 v2 before the ID3v1 tag. `from` is where the audio begins.
size_t trailingTagsStart(const uint8_t *data, size_t size, size_t from) {
  size_t end = size;
  if (end - from >= 128 && tagAt(data, size, end - 128, "TAG"))
    end -= 128;
  if (end - from >= 15 && tagAt(data, size, end - 9, "LYRICS200")) {
    const uint8_t *d = data + end - 15;
    size_t len = 0;
    bool digits = true;
    for (int i = 0; i < 6; ++i) {
      digits = digits && d[i] >= '0' && d[i] <= '9';
      len = len * 10 + static_cast<size_t>(d[i] - '0');
    }
    if (digits && end - from >= len + 15)
      end -= len + 15;
  }
  if (end - from >= 32 && tagAt(data, size, end - 32, "APETAGEX")) {
    const uint8_t *f = data + end - 32;
    const size_t len = le32(f + 12) + ((le32(f + 20) & 0x80000000u) ? 32 : 0);
    if (len >= 32 && end - from >= len)
      end -= len;
  }
  return end;
}

// CRC-16 as LAME computes it for its tag (polynomial 0x8005, reflected, initial 0).
uint16_t crc16(const uint8_t *data, size_t n, uint16_t crc = 0) {
  for (size_t i = 0; i < n; ++i) {
    crc ^= data[i];
    for (int b = 0; b < 8; ++b)
      crc =
          (crc & 1) ? static_cast<uint16_t>((crc >> 1) ^ 0xA001) : static_cast<uint16_t>(crc >> 1);
  }
  return crc;
}

Result failure(int code) {
  Result r;
  r.code = code;
  return r;
}

// ---- WAV ----

Result trimWav(const uint8_t *data, size_t size, double start, double end) {
  const size_t riff = id3v2End(data, size);
  size_t p = riff + 12;
  size_t fmt = 0, fact = 0, dataHeader = 0, dataSize = 0;
  while (p <= size && size - p >= 8) {
    const uint32_t len = le32(data + p + 4);
    if (tagAt(data, size, p, "fmt ") && len >= 16 && size - p - 8 >= 16)
      fmt = p + 8;
    else if (tagAt(data, size, p, "fact") && len >= 4 && size - p - 8 >= 4)
      fact = p + 8;
    else if (tagAt(data, size, p, "data")) {
      dataHeader = p;
      dataSize = std::min<size_t>(len, size - p - 8); // streaming files: 0xFFFFFFFF
      break;
    }
    if (size - p - 8 < size_t{len} + (len & 1))
      break; // runs past the end (no overflow on 32 bits)
    p += 8 + size_t{len} + (len & 1);
  }
  if (!fmt || !dataHeader)
    return failure(WP_ERR_UNSUPPORTED_FORMAT);
  uint32_t tag = le16(data + fmt);
  const uint32_t fmtLen = le32(data + fmt - 4);
  if (tag == 0xFFFE && fmtLen >= 26 && size - fmt >= 26)
    tag = le16(data + fmt + 24); // WAVE_FORMAT_EXTENSIBLE: the sub format
  const uint32_t rate = le32(data + fmt + 4);
  const uint32_t align = le16(data + fmt + 12);
  if ((tag != 1 && tag != 3) || rate == 0 || align == 0)
    return failure(WP_ERR_UNSUPPORTED_FORMAT);
  long long first = 0, last = 0;
  if (!sampleRange(start, end, static_cast<long long>(dataSize / align), rate, first, last))
    return failure(WP_ERR_INVALID_ARGUMENT);

  const size_t body = dataHeader + 8;
  const size_t keep = static_cast<size_t>(last - first) * align;
  const size_t afterData = std::min(size, body + dataSize + (dataSize & 1));
  Result r;
  r.bytes.reserve(dataHeader + 8 + keep + 1 + (size - afterData));
  append(r.bytes, data, dataHeader + 4);
  r.bytes.resize(r.bytes.size() + 4);
  putLe32(r.bytes.data() + dataHeader + 4, static_cast<uint32_t>(keep));
  append(r.bytes, data + body + static_cast<size_t>(first) * align, keep);
  if (keep & 1)
    r.bytes.push_back(0);
  append(r.bytes, data + afterData, size - afterData);
  putLe32(r.bytes.data() + riff + 4, static_cast<uint32_t>(r.bytes.size() - riff - 8));
  if (fact)
    putLe32(r.bytes.data() + fact, static_cast<uint32_t>(last - first));
  r.start = static_cast<double>(first) / rate;
  r.end = static_cast<double>(last) / rate;
  return r;
}

// ---- FLAC ----

struct FlacBlock {
  uint8_t type;
  size_t pos; // header
  size_t len; // body
};

// Metadata blocks after «fLaC» at `pos`; false if they run past the end. `framesStart` is where the
// audio frames begin.
bool flacBlocks(const uint8_t *data, size_t size, size_t pos, std::vector<FlacBlock> &blocks,
                size_t &framesStart) {
  size_t p = pos + 4;
  for (;;) {
    if (p > size || size - p < 4)
      return false;
    const uint8_t h = data[p];
    const size_t len = be24(data + p + 1);
    if (size - p - 4 < len)
      return false;
    blocks.push_back({static_cast<uint8_t>(h & 0x7F), p, len});
    p += 4 + len;
    if (h & 0x80)
      break;
  }
  framesStart = p;
  return true;
}

class Decoder {
public:
  Decoder() = default;
  Decoder(const Decoder &) = delete;
  Decoder &operator=(const Decoder &) = delete;
  ~Decoder() {
    if (open_)
      ma_decoder_uninit(&dec_);
  }
  bool init(const uint8_t *data, size_t size) {
    const ma_decoder_config cfg = ma_decoder_config_init(ma_format_s32, 0, 0);
    open_ = ma_decoder_init_memory(data, size, &cfg, &dec_) == MA_SUCCESS;
    return open_;
  }
  ma_decoder &get() { return dec_; }

private:
  ma_decoder dec_{};
  bool open_ = false;
};

Result trimFlac(const uint8_t *data, size_t size, double start, double end) {
  const size_t pos = id3v2End(data, size);
  std::vector<FlacBlock> blocks;
  size_t framesStart = 0;
  if (!flacBlocks(data, size, pos, blocks, framesStart) || blocks[0].type != 0 ||
      blocks[0].len < 34)
    return failure(WP_ERR_UNSUPPORTED_FORMAT);
  const uint8_t *info = data + blocks[0].pos + 4;
  const uint32_t rate = (uint32_t{info[10]} << 12) | (uint32_t{info[11]} << 4) | (info[12] >> 4);
  const uint32_t channels = ((info[12] >> 1) & 7) + 1;
  const uint32_t bits = (((info[12] & 1u) << 4) | (info[13] >> 4)) + 1;

  Decoder decoder;
  if (!decoder.init(data + pos, size - pos))
    return failure(WP_ERR_UNSUPPORTED_FORMAT);
  ma_decoder &dec = decoder.get();
  ma_uint64 total = 0;
  if (ma_decoder_get_length_in_pcm_frames(&dec, &total) != MA_SUCCESS || total == 0 ||
      dec.outputChannels != channels || dec.outputSampleRate != rate)
    return failure(WP_ERR_UNSUPPORTED_FORMAT);
  long long first = 0, last = 0;
  if (!sampleRange(start, end, static_cast<long long>(total), rate, first, last))
    return failure(WP_ERR_INVALID_ARGUMENT);

  std::vector<uint8_t> encoded;
  FlacWriter writer;
  if (!writer.openMemory(&encoded, rate, channels, bits))
    return failure(WP_ERR_UNSUPPORTED_FORMAT);
  // The decoder delivers every depth left-aligned in 32 bits; the samples are multiples of this.
  const int64_t scale = int64_t{1} << (32 - bits);
  constexpr ma_uint64 kChunk = 4096;
  std::vector<int32_t> buf(kChunk * channels);
  // #116 (found by fuzz_trim): the part before the start is decoded and dropped instead of seeking.
  // dr_flac's seek (binary search, also through a seek table) converts infinity to an integer on a
  // damaged file (undefined behaviour); decoding in order is the path the player takes as well.
  for (ma_uint64 skip = static_cast<ma_uint64>(first); skip > 0;) {
    ma_uint64 got = 0;
    const ma_result rr = ma_decoder_read_pcm_frames(&dec, buf.data(), std::min(skip, kChunk), &got);
    if (got == 0 || (rr != MA_SUCCESS && rr != MA_AT_END))
      return failure(WP_ERR_UNSUPPORTED_FORMAT); // shorter than its header says: damaged
    skip -= got;
  }
  ma_uint64 left = static_cast<ma_uint64>(last - first);
  while (left > 0) {
    ma_uint64 got = 0;
    const ma_result rr = ma_decoder_read_pcm_frames(&dec, buf.data(), std::min(left, kChunk), &got);
    if (got == 0 || (rr != MA_SUCCESS && rr != MA_AT_END))
      return failure(WP_ERR_UNSUPPORTED_FORMAT); // shorter than its header says: damaged
    for (size_t i = 0; i < got * channels; ++i)
      buf[i] = static_cast<int32_t>(buf[i] / scale);
    if (!writer.writeInt(buf.data(), static_cast<uint32_t>(got)))
      return failure(WP_ERR_OUT_OF_MEMORY); // the only way encoding into memory fails
    left -= got;
  }
  if (!writer.close())
    return failure(WP_ERR_OUT_OF_MEMORY);

  std::vector<FlacBlock> fresh;
  size_t freshFrames = 0;
  if (!flacBlocks(encoded.data(), encoded.size(), 0, fresh, freshFrames))
    return failure(WP_ERR_UNSUPPORTED_FORMAT);
  // New stream info; the old tags, pictures, application data and padding (the seek table and cue
  // sheet would point to the old audio); blocks of the encoder (its Vorbis comment) only where the
  // old file had none of that type.
  std::vector<std::pair<const uint8_t *, size_t>> keep;
  keep.emplace_back(encoded.data() + fresh[0].pos, 4 + fresh[0].len);
  auto has = [&](uint8_t type) {
    return std::any_of(blocks.begin(), blocks.end(),
                       [&](const FlacBlock &b) { return b.type == type; });
  };
  for (const FlacBlock &b : blocks)
    if (b.type != 0 && b.type != 3 && b.type != 5 && b.type != 127)
      keep.emplace_back(data + b.pos, 4 + b.len);
  for (size_t i = 1; i < fresh.size(); ++i)
    if (!has(fresh[i].type))
      keep.emplace_back(encoded.data() + fresh[i].pos, 4 + fresh[i].len);

  Result r;
  append(r.bytes, data, pos + 4); // ID3v2 before the stream (if any) and «fLaC»
  for (size_t i = 0; i < keep.size(); ++i) {
    const size_t at = r.bytes.size();
    append(r.bytes, keep[i].first, keep[i].second);
    r.bytes[at] = static_cast<uint8_t>((r.bytes[at] & 0x7F) | (i + 1 == keep.size() ? 0x80 : 0));
  }
  append(r.bytes, encoded.data() + freshFrames, encoded.size() - freshFrames);
  r.start = static_cast<double>(first) / rate;
  r.end = static_cast<double>(last) / rate;
  return r;
}

// ---- MP3 ----

struct Mp3Frame {
  size_t pos = 0;
  size_t len = 0;
  int version = 0; // 3 MPEG-1, 2 MPEG-2, 0 MPEG-2.5
  int bitrateIndex = 0;
  int rateIndex = 0;
  int rate = 0;
  int samples = 0;  // per frame
  int sideInfo = 0; // bytes
  bool crc = false;
  bool mono = false;

  size_t mainData() const {
    const size_t head = 4 + (crc ? 2 : 0) + static_cast<size_t>(sideInfo);
    return len > head ? len - head : 0;
  }
};

constexpr std::array<int, 15> kBitrateV1 = {0,   32,  40,  48,  56,  64,  80, 96,
                                            112, 128, 160, 192, 224, 256, 320};
constexpr std::array<int, 15> kBitrateV2 = {0,  8,  16, 24,  32,  40,  48, 56,
                                            64, 80, 96, 112, 128, 144, 160};
constexpr std::array<int, 3> kRateV1 = {44100, 48000, 32000};

int frameLength(int version, int bitrateIndex, int rate, int padding) {
  const int kbps = (version == 3 ? kBitrateV1 : kBitrateV2)[static_cast<size_t>(bitrateIndex)];
  return (version == 3 ? 144000 : 72000) * kbps / rate + padding;
}

// Layer III frame header at `p`; false if there is none (free format counts as none).
bool mp3Header(const uint8_t *data, size_t size, size_t p, Mp3Frame &f) {
  if (p > size || size - p < 4)
    return false;
  const uint8_t *h = data + p;
  if (h[0] != 0xFF || (h[1] & 0xE0) != 0xE0)
    return false;
  const int version = (h[1] >> 3) & 3;
  const int layer = (h[1] >> 1) & 3;
  const int bitrateIndex = h[2] >> 4;
  const int rateIndex = (h[2] >> 2) & 3;
  if (version == 1 || layer != 1 || bitrateIndex == 0 || bitrateIndex == 15 || rateIndex == 3)
    return false;
  f.pos = p;
  f.version = version;
  f.bitrateIndex = bitrateIndex;
  f.rateIndex = rateIndex;
  f.rate = kRateV1[static_cast<size_t>(rateIndex)] >> (version == 3 ? 0 : version == 2 ? 1 : 2);
  f.crc = (h[1] & 1) == 0;
  f.mono = (h[3] >> 6) == 3;
  f.samples = version == 3 ? 1152 : 576;
  f.sideInfo = version == 3 ? (f.mono ? 17 : 32) : (f.mono ? 9 : 17);
  f.len = static_cast<size_t>(frameLength(version, bitrateIndex, f.rate, (h[2] >> 1) & 1));
  return true;
}

// Bytes of the bit reservoir the frame takes from the frames before it.
size_t mainDataBegin(const uint8_t *data, const Mp3Frame &f) {
  const uint8_t *s = data + f.pos + 4 + (f.crc ? 2 : 0);
  return f.version == 3 ? ((size_t{s[0]} << 1) | (s[1] >> 7)) : s[0];
}

bool sameStream(const Mp3Frame &a, const Mp3Frame &b) {
  return a.version == b.version && a.rateIndex == b.rateIndex && a.mono == b.mono;
}

// The frames in [from, to): a frame counts if it fits and (to resync after junk) the next one
// follows or it ends the audio.
std::vector<Mp3Frame> mp3Frames(const uint8_t *data, size_t from, size_t to) {
  std::vector<Mp3Frame> frames;
  size_t p = from;
  while (p < to) {
    Mp3Frame f;
    Mp3Frame next;
    const bool ok = mp3Header(data, to, p, f) && f.mainData() > 0 && f.len <= to - p &&
                    (frames.empty() || sameStream(frames[0], f));
    const bool confirmed = ok && (!frames.empty() || p + f.len == to ||
                                  (mp3Header(data, to, p + f.len, next) && sameStream(f, next)));
    if (confirmed) {
      frames.push_back(f);
      p += f.len;
    } else {
      ++p; // junk between frames: look for the next one
    }
  }
  return frames;
}

// Info/Xing frame (LAME) at the start: frames before it and its encoder delay and padding.
struct LameInfo {
  bool header = false; // the first frame is an Info/Xing/VBRI frame without audio
  bool lame = false;   // with a LAME tag that the decoder honours
  size_t lamePos = 0;  // its 36 bytes
  int delay = 0;
  int padding = 0;
};

constexpr size_t kXingFields = 4 + 4 + 4 + 4 + 100 + 4; // id, flags, frames, bytes, TOC, quality
constexpr size_t kLameTag = 36;
constexpr int kDecoderDelay = 529; // the decoder delay LAME tags assume
constexpr int kMaxField = 4095;    // 12 bits for delay and padding

LameInfo lameInfo(const uint8_t *data, const Mp3Frame &f) {
  LameInfo info;
  const size_t xing = 4 + static_cast<size_t>(f.sideInfo);
  const uint8_t *b = data + f.pos;
  if (f.len >= 40 && std::memcmp(b + 36, "VBRI", 4) == 0) {
    info.header = true;
    return info;
  }
  // #116: LAME writes its tag right after the side information even in a frame with a CRC; dr_mp3
  // does not take such a frame for an Info frame and plays it as audio. So does the cut.
  if (f.crc || f.len < xing + 8 ||
      (std::memcmp(b + xing, "Xing", 4) != 0 && std::memcmp(b + xing, "Info", 4) != 0))
    return info;
  info.header = true;
  const uint32_t flags = be32(b + xing + 4);
  size_t lame = xing + 8 + ((flags & 1) ? 4 : 0) + ((flags & 2) ? 4 : 0) + ((flags & 4) ? 100 : 0) +
                ((flags & 8) ? 4 : 0);
  if (f.len < lame + kLameTag)
    return info;
  info.lame = true;
  info.lamePos = f.pos + lame;
  const uint8_t *t = data + info.lamePos;
  info.delay = static_cast<int>((uint32_t{t[21]} << 4) | (t[22] >> 4));
  info.padding = static_cast<int>(((t[22] & 0x0Fu) << 8) | t[23]);
  return info;
}

// Smallest bit rate index of `a`'s stream whose frame (without padding) holds `bytes` after the
// header and side information; 0 if none does.
int bitrateFor(const Mp3Frame &a, size_t bytes) {
  for (int index = 1; index < 15; ++index)
    if (static_cast<size_t>(frameLength(a.version, index, a.rate, 0)) >=
        4 + static_cast<size_t>(a.sideInfo) + bytes)
      return index;
  return 0;
}

// An empty frame of `a`'s stream with bit rate `index`, without CRC, all side information zero:
// it decodes as silence and takes nothing from the bit reservoir.
std::vector<uint8_t> emptyFrame(const uint8_t *data, const Mp3Frame &a, int index) {
  std::vector<uint8_t> f(static_cast<size_t>(frameLength(a.version, index, a.rate, 0)), 0);
  f[0] = 0xFF;
  f[1] = static_cast<uint8_t>(data[a.pos + 1] | 1); // no CRC
  f[2] = static_cast<uint8_t>((index << 4) | (a.rateIndex << 2));
  f[3] = data[a.pos + 3];
  return f;
}

// A new Info/Xing frame (LAME tag with delay and padding) for frames of `a`'s stream with the
// lengths `out`, whose bytes are `audio`.
std::vector<uint8_t> infoFrame(const uint8_t *data, const Mp3Frame &a,
                               const std::vector<size_t> &out, const std::vector<uint8_t> &audio,
                               bool vbr, const LameInfo &old, int delay, int padding) {
  const size_t xing = 4 + static_cast<size_t>(a.sideInfo);
  const int index = bitrateFor(a, kXingFields + kLameTag);
  if (index == 0)
    return {}; // cannot happen with the bit rates of Layer III, checked anyway
  std::vector<uint8_t> f = emptyFrame(data, a, index);
  const size_t count = out.size();
  const size_t total = f.size() + audio.size();
  uint8_t *x = f.data() + xing;
  std::copy_n(vbr ? "Xing" : "Info", 4, x); // a tag of 4 bytes, no terminating zero
  putBe32(x + 4, 0x0F);
  putBe32(x + 8, static_cast<uint32_t>(count));
  putBe32(x + 12, static_cast<uint32_t>(total));
  // Seek table: for every percent of the duration the byte position as a fraction of 256.
  size_t frame = 0, offset = f.size();
  for (size_t i = 0; i < 100; ++i) {
    const size_t target = i * count / 100;
    while (frame < target)
      offset += out[frame++];
    x[16 + i] = static_cast<uint8_t>(std::min<size_t>(255, offset * 256 / total));
  }
  uint8_t *t = x + kXingFields;
  if (old.lame)
    std::memcpy(t, data + old.lamePos, kLameTag);
  else
    std::copy_n("LAME3.100", 9, t); // the version decoders look for in a tag of this layout
  t[21] = static_cast<uint8_t>(delay >> 4);
  t[22] = static_cast<uint8_t>(((delay & 0x0F) << 4) | (padding >> 8));
  t[23] = static_cast<uint8_t>(padding & 0xFF);
  putBe32(t + 28, static_cast<uint32_t>(total));
  const uint16_t music = crc16(audio.data(), audio.size());
  t[32] = static_cast<uint8_t>(music >> 8);
  t[33] = static_cast<uint8_t>(music & 0xFF);
  const uint16_t tag = crc16(f.data(), static_cast<size_t>(t - f.data()) + 34);
  t[34] = static_cast<uint8_t>(tag >> 8);
  t[35] = static_cast<uint8_t>(tag & 0xFF);
  return f;
}

// The last `n` bytes of main data before frame `j`'s own (the bit reservoir it may draw on); fewer
// at the start of the stream.
std::vector<uint8_t> mainDataBefore(const uint8_t *data, const std::vector<Mp3Frame> &frames,
                                    size_t j, size_t n) {
  std::vector<uint8_t> bytes(n);
  size_t have = 0;
  while (have < n && j > 0) {
    const Mp3Frame &f = frames[--j];
    const size_t len = f.mainData();
    const uint8_t *end = data + f.pos + f.len;
    const size_t take = std::min(len, n - have);
    std::copy(end - take, end, bytes.end() - static_cast<std::ptrdiff_t>(have + take));
    have += take;
  }
  bytes.erase(bytes.begin(), bytes.end() - static_cast<std::ptrdiff_t>(have));
  return bytes;
}

Result trimMp3(const uint8_t *data, size_t size, double start, double end) {
  const size_t audio = id3v2End(data, size);
  const size_t tags = trailingTagsStart(data, size, audio);
  std::vector<Mp3Frame> frames = mp3Frames(data, audio, tags);
  if (frames.empty())
    return failure(WP_ERR_UNSUPPORTED_FORMAT);
  const LameInfo old = lameInfo(data, frames[0]);
  if (old.header)
    frames.erase(frames.begin());
  if (frames.empty())
    return failure(WP_ERR_UNSUPPORTED_FORMAT);
  const long long spf = frames[0].samples; // samples per frame
  const int rate = frames[0].rate;
  // The decoder skips delay + 529 samples at the start and padding − 529 at the end (with a LAME
  // tag; without one it plays every sample of every frame).
  const long long skip = old.lame ? old.delay + kDecoderDelay : 0;
  const long long n = static_cast<long long>(frames.size());
  const long long total = n * spf - (old.lame ? old.delay + old.padding : 0);
  long long s0 = 0, s1 = 0;
  if (!sampleRange(start, end, total, rate, s0, s1))
    return failure(WP_ERR_INVALID_ARGUMENT);

  // Positions in all samples the frames decode to.
  const long long r0 = s0 + skip, r1 = s1 + skip;
  const auto k0 = static_cast<size_t>(std::min(n - 1, r0 / spf));
  const auto last = static_cast<size_t>(std::clamp((r1 + spf - 1) / spf - 1, 0LL, n - 1));
  std::vector<size_t> out; // lengths of the frames
  std::vector<uint8_t> bytes;
  // Within the first frame the file starts as it is. Later, two frames come before the first
  // audible one k0: an empty frame whose main data end with the bit reservoir that k0 − 1 and k0
  // draw on (a decoder like minimp3 gives no output at all for a frame missing its reservoir, which
  // would shift everything by a frame), and k0 − 1 for the overlap of the filter bank. The delay of
  // the LAME tag skips both.
  size_t from = 0;
  long long base = 0; // sample (of all the old frames decode to) at the start of the new file
  if (k0 > 0) {
    from = k0 - 1;
    const size_t before = frames[k0 - 1].mainData();
    const size_t want = std::max(mainDataBegin(data, frames[k0 - 1]),
                                 mainDataBegin(data, frames[k0]) -
                                     std::min(mainDataBegin(data, frames[k0]), before));
    const std::vector<uint8_t> reservoir = mainDataBefore(data, frames, k0 - 1, want);
    const int index = bitrateFor(frames[k0], reservoir.size());
    if (index == 0)
      return failure(WP_ERR_UNSUPPORTED_FORMAT); // a reservoir larger than any frame: damaged
    std::vector<uint8_t> empty = emptyFrame(data, frames[k0], index);
    std::copy(reservoir.begin(), reservoir.end(),
              empty.end() - static_cast<std::ptrdiff_t>(reservoir.size()));
    append(bytes, empty.data(), empty.size());
    out.push_back(empty.size());
    base = (static_cast<long long>(k0) - 2) * spf;
  }
  bool vbr = false;
  for (size_t i = from; i <= last; ++i) {
    append(bytes, data + frames[i].pos, frames[i].len);
    out.push_back(frames[i].len);
    vbr = vbr || frames[i].bitrateIndex != frames[from].bitrateIndex;
  }
  // A start within the first 529 samples of a file without a LAME tag: the decoder skips 529.
  const int delay = static_cast<int>(std::max(0LL, r0 - base - kDecoderDelay));
  const long long startSample = base + delay + kDecoderDelay - skip;
  const int padding = static_cast<int>(
      std::min<long long>(kMaxField, static_cast<long long>(last + 1) * spf - r1 + kDecoderDelay));

  const std::vector<uint8_t> info =
      infoFrame(data, frames[k0], out, bytes, vbr, old, delay, padding);
  if (info.empty())
    return failure(WP_ERR_UNSUPPORTED_FORMAT);
  Result r;
  r.bytes.reserve(audio + info.size() + bytes.size() + (size - tags));
  append(r.bytes, data, audio);
  append(r.bytes, info.data(), info.size());
  append(r.bytes, bytes.data(), bytes.size());
  append(r.bytes, data + tags, size - tags);
  r.start = static_cast<double>(startSample) / rate;
  r.end = static_cast<double>(s1) / rate;
  return r;
}

// ---- AAC in ADTS ----

constexpr std::array<int, 13> kAdtsRates = {96000, 88200, 64000, 48000, 44100, 32000, 24000,
                                            22050, 16000, 12000, 11025, 8000,  7350};

struct AdtsFrame {
  size_t pos;
  size_t len;
  long long samples;
};

bool adtsHeader(const uint8_t *data, size_t size, size_t p, AdtsFrame &f, int &rateIndex) {
  if (p > size || size - p < 7)
    return false;
  const uint8_t *h = data + p;
  if (h[0] != 0xFF || (h[1] & 0xF6) != 0xF0)
    return false;
  rateIndex = (h[2] >> 2) & 0x0F;
  const size_t len = ((size_t{h[3]} & 3) << 11) | (size_t{h[4]} << 3) | (h[5] >> 5);
  const size_t head = (h[1] & 1) ? 7 : 9;
  if (rateIndex >= static_cast<int>(kAdtsRates.size()) || len < head)
    return false;
  f = {p, len, 1024LL * ((h[6] & 3) + 1)};
  return true;
}

Result trimAdts(const uint8_t *data, size_t size, double start, double end) {
  const size_t audio = id3v2End(data, size);
  const size_t tags = trailingTagsStart(data, size, audio);
  std::vector<AdtsFrame> frames;
  std::vector<long long> at{0}; // first sample of each frame, then the total
  int rateIndex = -1;
  for (size_t p = audio; p < tags;) {
    AdtsFrame f{};
    int ri = 0;
    if (adtsHeader(data, tags, p, f, ri) && f.len <= tags - p &&
        (rateIndex < 0 || ri == rateIndex)) {
      rateIndex = ri;
      frames.push_back(f);
      at.push_back(at.back() + f.samples);
      p += f.len;
    } else {
      ++p;
    }
  }
  if (frames.empty())
    return failure(WP_ERR_UNSUPPORTED_FORMAT);
  const int rate = kAdtsRates[static_cast<size_t>(rateIndex)];
  long long s0 = 0, s1 = 0;
  if (!sampleRange(start, end, at.back(), rate, s0, s1))
    return failure(WP_ERR_INVALID_ARGUMENT);
  // The frame boundaries nearest to the requested samples.
  auto nearest = [&](long long s) {
    const auto it = std::lower_bound(at.begin(), at.end(), s);
    if (it == at.begin())
      return size_t{0};
    const auto i = static_cast<size_t>(it - at.begin());
    return (it == at.end() || *it - s > s - at[i - 1]) ? i - 1 : i;
  };
  const size_t first = nearest(s0);
  const size_t stop = std::max(first + 1, nearest(s1));
  Result r;
  append(r.bytes, data, audio);
  for (size_t i = first; i < stop; ++i)
    append(r.bytes, data + frames[i].pos, frames[i].len);
  append(r.bytes, data + tags, size - tags);
  r.start = static_cast<double>(at[first]) / rate;
  r.end = static_cast<double>(at[stop]) / rate;
  return r;
}

} // namespace

// ---- The range ----

bool sampleRange(double start, double end, long long total, double rate, long long &first,
                 long long &last) {
  if (!(rate > 0) || total <= 0 || std::isnan(start) || std::isnan(end))
    return false;
  const double duration = static_cast<double>(total) / rate;
  start = std::clamp(start, 0.0, duration);
  end = std::clamp(end, 0.0, duration);
  if (end - start < kMinSeconds - 1e-9)
    return false;
  first = std::clamp(std::llround(start * rate), 0LL, total);
  last = std::clamp(std::llround(end * rate), first, total);
  return true;
}

Format detect(const uint8_t *data, size_t size) {
  if (!data)
    return Format::Unknown;
  const size_t p = id3v2End(data, size);
  if (tagAt(data, size, p, "fLaC"))
    return Format::Flac;
  if (tagAt(data, size, p, "RIFF") && tagAt(data, size, p + 8, "WAVE"))
    return Format::Wav;
  if (tagAt(data, size, p + 4, "ftyp"))
    return Format::Mp4;
  AdtsFrame a{};
  int rateIndex = 0;
  if (adtsHeader(data, size, p, a, rateIndex))
    return Format::Adts;
  Mp3Frame f;
  if (mp3Header(data, size, p, f))
    return Format::Mp3;
  return Format::Unknown;
}

Result trim(const uint8_t *data, size_t size, double start, double end) {
  try {
    switch (detect(data, size)) {
    case Format::Wav:
      return trimWav(data, size, start, end);
    case Format::Flac:
      return trimFlac(data, size, start, end);
    case Format::Mp3:
      return trimMp3(data, size, start, end);
    case Format::Adts:
      return trimAdts(data, size, start, end);
    case Format::Mp4:
      return trimMp4(data, size, start, end);
    case Format::Unknown:
      break;
    }
    return failure(WP_ERR_UNSUPPORTED_FORMAT);
  } catch (const std::bad_alloc &) {
    return failure(WP_ERR_OUT_OF_MEMORY);
  } catch (const std::length_error &) {
    return failure(WP_ERR_OUT_OF_MEMORY);
  }
}

} // namespace wp::trim
