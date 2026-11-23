// #120: trimming MP4/M4A (src/trim_mp4.cpp). The test reads the sample tables of the result with
// its own small MP4 reader and compares the kept samples with the original ones byte for byte; on
// Apple platforms the system decoder (ExtAudioFile, which honours the edit list) also decodes the
// result and the clicks of the test audio must lie where the cut puts them. clicks3.m4a (AAC) and
// clicks3_alac.m4a (ALAC) are 3 s stereo at 44.1 kHz with clicks at 0.5, 1.0, 2.0 and 2.5 s, tagged
// with title, artist, album and a cover (core/tools/make_test_audio.sh). Variants of the files
// (moov after mdat, 64-bit offsets, several tracks, fragments …) are built here.
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

#include "trim.hpp"
#include "wp_core.h"

#if defined(__APPLE__) && !defined(__EMSCRIPTEN__)
#include <AudioToolbox/AudioToolbox.h>
#include <unistd.h>
#define WP_SYSTEM_DECODER 1
#endif

namespace {

int failures = 0;

#define CHECK(cond)                                                                                \
  do {                                                                                             \
    if (!(cond)) {                                                                                 \
      ++failures;                                                                                  \
      std::printf("  FAILED %s:%d: %s\n", __FILE__, __LINE__, #cond);                              \
    }                                                                                              \
  } while (0)

using Bytes = std::vector<uint8_t>;
using wp::trim::Format;

constexpr int kRate = 44100;
constexpr double kMaxDeviation = 0.050; // #120/AK2
constexpr uint32_t kPriming = 2112;     // of the AAC encoder (afconvert)

Bytes readFile(const std::string &name) {
  std::ifstream f(std::string(WP_TEST_AUDIO_DIR) + "/" + name, std::ios::binary);
  return Bytes(std::istreambuf_iterator<char>(f), {});
}

uint32_t be32(const uint8_t *p) {
  return (uint32_t{p[0]} << 24) | (uint32_t{p[1]} << 16) | (uint32_t{p[2]} << 8) | p[3];
}
uint64_t be64(const uint8_t *p) { return (uint64_t{be32(p)} << 32) | be32(p + 4); }
void put32(Bytes &b, uint32_t v) {
  for (int i = 0; i < 4; ++i)
    b.push_back(static_cast<uint8_t>(v >> (24 - 8 * i)));
}
void put64(Bytes &b, uint64_t v) {
  put32(b, static_cast<uint32_t>(v >> 32));
  put32(b, static_cast<uint32_t>(v));
}
void set32(uint8_t *p, uint32_t v) {
  for (int i = 0; i < 4; ++i)
    p[i] = static_cast<uint8_t>(v >> (24 - 8 * i));
}
uint32_t type(const char *t) { return be32(reinterpret_cast<const uint8_t *>(t)); }

bool contains(const Bytes &hay, const Bytes &needle) {
  return std::search(hay.begin(), hay.end(), needle.begin(), needle.end()) != hay.end();
}

// ---- A small MP4 tree: containers are parsed, everything else stays as bytes ----

struct Node {
  uint32_t type = 0;
  Bytes body;             // leaves
  std::vector<Node> kids; // containers
  bool container = false;
};

bool isContainer(uint32_t t) {
  for (const char *c : {"moov", "trak", "mdia", "minf", "stbl", "edts"})
    if (t == type(c))
      return true;
  return false;
}

std::vector<Node> parse(const uint8_t *p, size_t n) {
  std::vector<Node> out;
  size_t at = 0;
  while (n - at >= 8) {
    uint64_t size = be32(p + at);
    size_t head = 8;
    if (size == 1) {
      size = be64(p + at + 8);
      head = 16;
    } else if (size == 0) {
      size = n - at;
    }
    Node node;
    node.type = be32(p + at + 4);
    node.container = isContainer(node.type);
    if (node.container)
      node.kids = parse(p + at + head, static_cast<size_t>(size) - head);
    else
      node.body.assign(p + at + head, p + at + size);
    out.push_back(std::move(node));
    at += static_cast<size_t>(size);
  }
  return out;
}

void write(const Node &node, Bytes &out) {
  Bytes body;
  if (node.container)
    for (const Node &k : node.kids)
      write(k, body);
  else
    body = node.body;
  put32(out, static_cast<uint32_t>(body.size() + 8));
  put32(out, node.type);
  out.insert(out.end(), body.begin(), body.end());
}

Bytes write(const std::vector<Node> &nodes) {
  Bytes out;
  for (const Node &n : nodes)
    write(n, out);
  return out;
}

Node *find(std::vector<Node> &nodes, const char *t) {
  for (Node &n : nodes)
    if (n.type == type(t))
      return &n;
  return nullptr;
}

// The node at a path like {"moov", "trak", "mdia"} (first match at each step).
Node *at(std::vector<Node> &nodes, std::initializer_list<const char *> path) {
  std::vector<Node> *level = &nodes;
  Node *n = nullptr;
  for (const char *t : path) {
    n = find(*level, t);
    if (!n)
      return nullptr;
    level = &n->kids;
  }
  return n;
}

Node *stbl(std::vector<Node> &file) { return at(file, {"moov", "trak", "mdia", "minf", "stbl"}); }

// Adds `delta` to every chunk offset (stco or co64) of every track.
void shiftOffsets(std::vector<Node> &file, int64_t delta) {
  for (Node &trak : find(file, "moov")->kids) {
    if (trak.type != type("trak"))
      continue;
    for (Node &t : at(trak.kids, {"mdia", "minf", "stbl"})->kids) {
      const bool wide = t.type == type("co64");
      if (!wide && t.type != type("stco"))
        continue;
      const uint32_t n = be32(t.body.data() + 4);
      for (uint32_t i = 0; i < n; ++i) {
        uint8_t *p = t.body.data() + 8 + (wide ? 8 : 4) * i;
        if (wide) {
          const uint64_t v = be64(p) + static_cast<uint64_t>(delta);
          set32(p, static_cast<uint32_t>(v >> 32));
          set32(p + 4, static_cast<uint32_t>(v));
        } else {
          set32(p, static_cast<uint32_t>(static_cast<int64_t>(be32(p)) + delta));
        }
      }
    }
  }
}

// Start of the payload of the first mdat in a written file.
size_t mdatPayload(const Bytes &f) {
  size_t p = 0;
  while (p + 8 <= f.size()) {
    uint64_t size = be32(f.data() + p);
    const size_t head = size == 1 ? 16 : 8;
    if (size == 1)
      size = be64(f.data() + p + 8);
    if (be32(f.data() + p + 4) == type("mdat"))
      return p + head;
    p += static_cast<size_t>(size);
  }
  return 0;
}

// Writes `file` and moves the chunk offsets along with its mdat (which `original` had at `from`).
Bytes rewrite(std::vector<Node> file, size_t from) {
  const size_t to = mdatPayload(write(file));
  shiftOffsets(file, static_cast<int64_t>(to) - static_cast<int64_t>(from));
  return write(file);
}

// ---- What a file holds: the audio track's samples, times, edit list and codec ----

struct Info {
  bool ok = false;
  uint32_t codec = 0;
  uint32_t tracks = 0;
  uint32_t timescale = 0;
  uint64_t mediaDuration = 0; // mdhd
  uint64_t movieDuration = 0; // mvhd
  bool edit = false;
  int64_t mediaTime = 0; // of the edit list
  uint64_t editDuration = 0;
  std::vector<uint32_t> deltas;
  std::vector<Bytes> samples;
  uint32_t chunks = 0;
  bool hasTref = false;
  int elstVersion = -1;
  uint64_t trackDuration = 0; // tkhd
  uint32_t stscEntries = 0;
  uint32_t sttsEntries = 0;
  size_t stszBody = 0;
  bool trakUdta = false;
};

Info info(const Bytes &f) {
  Info r;
  std::vector<Node> file = parse(f.data(), f.size());
  Node *moov = find(file, "moov");
  if (!moov)
    return r;
  for (const Node &k : moov->kids)
    r.tracks += k.type == type("trak");
  const Node *mvhd = find(moov->kids, "mvhd");
  r.movieDuration =
      mvhd->body[0] == 1 ? be64(mvhd->body.data() + 24) : be32(mvhd->body.data() + 16);
  Node *trak = find(moov->kids, "trak");
  r.hasTref = find(trak->kids, "tref") != nullptr;
  r.trakUdta = find(trak->kids, "udta") != nullptr;
  const Node *tkhd = find(trak->kids, "tkhd");
  r.trackDuration =
      tkhd->body[0] == 1 ? be64(tkhd->body.data() + 28) : be32(tkhd->body.data() + 20);
  if (Node *elst = at(trak->kids, {"edts", "elst"})) {
    const uint8_t *e = elst->body.data();
    r.edit = be32(e + 4) == 1;
    r.elstVersion = e[0];
    r.editDuration = e[0] == 1 ? be64(e + 8) : be32(e + 8);
    r.mediaTime =
        e[0] == 1 ? static_cast<int64_t>(be64(e + 16)) : static_cast<int32_t>(be32(e + 12));
  }
  const Node *mdhd = at(trak->kids, {"mdia", "mdhd"});
  r.timescale = be32(mdhd->body.data() + (mdhd->body[0] == 1 ? 20 : 12));
  r.mediaDuration =
      mdhd->body[0] == 1 ? be64(mdhd->body.data() + 24) : be32(mdhd->body.data() + 16);
  Node *s = at(trak->kids, {"mdia", "minf", "stbl"});
  r.codec = be32(find(s->kids, "stsd")->body.data() + 12);
  const Node *stts = find(s->kids, "stts");
  r.sttsEntries = be32(stts->body.data() + 4);
  for (uint32_t i = 0; i < be32(stts->body.data() + 4); ++i)
    for (uint32_t k = 0; k < be32(stts->body.data() + 8 + 8 * i); ++k)
      r.deltas.push_back(be32(stts->body.data() + 12 + 8 * i));
  const Node *stsz = find(s->kids, "stsz");
  const uint32_t fixed = be32(stsz->body.data() + 4), n = be32(stsz->body.data() + 8);
  r.stszBody = stsz->body.size();
  const Node *stsc = find(s->kids, "stsc");
  const Node *co = find(s->kids, "stco");
  const bool wide = co == nullptr;
  if (wide)
    co = find(s->kids, "co64");
  r.chunks = be32(co->body.data() + 4);
  const uint32_t entries = be32(stsc->body.data() + 4);
  r.stscEntries = entries;
  uint32_t sample = 0;
  for (uint32_t c = 0, e = 0; c < r.chunks; ++c) {
    while (e + 1 < entries && be32(stsc->body.data() + 8 + 12 * (e + 1)) <= c + 1)
      ++e;
    uint64_t o = wide ? be64(co->body.data() + 8 + 8 * c) : be32(co->body.data() + 8 + 4 * c);
    for (uint32_t k = 0; k < be32(stsc->body.data() + 8 + 12 * e + 4) && sample < n; ++k) {
      const uint32_t len = fixed ? fixed : be32(stsz->body.data() + 12 + 4 * sample);
      if (o + len > f.size())
        return r;
      r.samples.emplace_back(f.begin() + static_cast<long>(o),
                             f.begin() + static_cast<long>(o + len));
      o += len;
      ++sample;
    }
  }
  r.ok = sample == n && r.deltas.size() == n;
  return r;
}

// The fields of iTunSMPB (priming, remainder, count); all zero if there is none.
struct Smpb {
  uint64_t priming = 0, remainder = 0, count = 0;
};
Smpb smpb(const Bytes &f) {
  Smpb s;
  const std::string text(f.begin(), f.end());
  const size_t at = text.find("iTunSMPB");
  if (at == std::string::npos)
    return s;
  const size_t data = at + 8 + 16; // name, then the data box header, type and locale
  const char *p = text.c_str() + data;
  uint64_t v[4] = {};
  for (uint64_t &field : v) {
    char *end = nullptr;
    field = std::strtoull(p, &end, 16);
    if (end == p)
      return s;
    p = end;
  }
  s.priming = v[1];
  s.remainder = v[2];
  s.count = v[3];
  return s;
}

// ---- The system decoder ----

#ifdef WP_SYSTEM_DECODER
// Left channel of the file as the system decodes it (float, 44.1 kHz); empty if it cannot.
std::vector<float> systemDecode(const Bytes &b) {
  char path[] = "/tmp/wp_trim_mp4_XXXXXX";
  const int fd = mkstemp(path);
  if (fd < 0)
    return {};
  const bool written = ::write(fd, b.data(), b.size()) == static_cast<ssize_t>(b.size());
  close(fd);
  std::vector<float> left;
  CFURLRef url =
      CFURLCreateFromFileSystemRepresentation(nullptr, reinterpret_cast<const UInt8 *>(path),
                                              static_cast<CFIndex>(std::strlen(path)), false);
  ExtAudioFileRef file = nullptr;
  if (written && ExtAudioFileOpenURL(url, &file) == noErr) {
    AudioStreamBasicDescription fmt{};
    fmt.mSampleRate = kRate;
    fmt.mFormatID = kAudioFormatLinearPCM;
    fmt.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    fmt.mChannelsPerFrame = 2;
    fmt.mBitsPerChannel = 32;
    fmt.mBytesPerFrame = fmt.mBytesPerPacket = 8;
    fmt.mFramesPerPacket = 1;
    if (ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat, sizeof fmt, &fmt) ==
        noErr) {
      std::vector<float> buf(2 * 4096);
      for (;;) {
        AudioBufferList list{};
        list.mNumberBuffers = 1;
        list.mBuffers[0].mNumberChannels = 2;
        list.mBuffers[0].mDataByteSize = static_cast<UInt32>(buf.size() * sizeof(float));
        list.mBuffers[0].mData = buf.data();
        UInt32 frames = 4096;
        if (ExtAudioFileRead(file, &frames, &list) != noErr || frames == 0)
          break;
        for (UInt32 i = 0; i < frames; ++i)
          left.push_back(buf[2 * i]);
      }
    }
    ExtAudioFileDispose(file);
  }
  CFRelease(url);
  unlink(path);
  return left;
}

// Frame of the first click (above 0.3) at or after `from`; -1 if there is none.
long long click(const std::vector<float> &v, long long from = 0) {
  for (auto i = static_cast<size_t>(std::max(0LL, from)); i < v.size(); ++i)
    if (std::fabs(v[i]) > 0.3f)
      return static_cast<long long>(i);
  return -1;
}

// The decoded result is (end − start) long and has its clicks where the cut puts them (the first
// one after the start at `first` seconds of the old file, the next one `gap` seconds later),
// without a click at the start (#120/AK2).
void checkDecoded(const wp::trim::Result &r, double first = 1.0, double gap = 1.0) {
  const std::vector<float> v = systemDecode(r.bytes);
  CHECK(!v.empty());
  CHECK(std::llabs(static_cast<long long>(v.size()) - std::llround((r.end - r.start) * kRate)) <=
        1);
  const long long at = click(v);
  CHECK(std::llabs(at - std::llround((first - r.start) * kRate)) <= 16); // the first click
  CHECK(std::llabs(click(v, at + 4410) - (at + std::llround(gap * kRate))) <= 16);
  float startPeak = 0;
  for (size_t i = 0; i < 441 && i < v.size(); ++i)
    startPeak = std::max(startPeak, std::fabs(v[i]));
  CHECK(startPeak < 0.01f); // no click at the cut
}
#else
void checkDecoded(const wp::trim::Result &, double = 1.0, double = 1.0) {}
#endif

// ---- Tests ----

void aacAtFrameBoundaries() { // #120/AK2
  const Bytes in = readFile("clicks3.m4a");
  CHECK(wp::trim::detect(in.data(), in.size()) == Format::Mp4);
  const Info old = info(in);
  CHECK(old.ok && old.codec == type("mp4a") && old.samples.size() == 132);
  const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
  CHECK(r.code == WP_OK);
  CHECK(wp::trim::detect(r.bytes.data(), r.bytes.size()) == Format::Mp4);
  // media time = presentation + 2112 (priming): 0.7 s → 32982 → frame 32 (32768), 2.2 s → 99132 →
  // frame 97 (99328)
  CHECK(r.start == (32 * 1024.0 - kPriming) / kRate);
  CHECK(r.end == (97 * 1024.0 - kPriming) / kRate);
  CHECK(std::fabs(r.start - 0.7) <= kMaxDeviation && std::fabs(r.end - 2.2) <= kMaxDeviation);
  // frames 31 (pre-roll) to 96, unchanged; the edit list skips the pre-roll frame
  const Info cut = info(r.bytes);
  CHECK(cut.ok && cut.codec == type("mp4a") && cut.tracks == 1);
  CHECK(cut.samples.size() == 66);
  CHECK(std::equal(cut.samples.begin(), cut.samples.end(), old.samples.begin() + 31));
  CHECK(std::all_of(cut.deltas.begin(), cut.deltas.end(), [](uint32_t d) { return d == 1024; }));
  CHECK(cut.edit && cut.mediaTime == 1024 && cut.editDuration == 65 * 1024 && cut.elstVersion == 0);
  CHECK(cut.mediaDuration == 66 * 1024 && cut.movieDuration == 65 * 1024 &&
        cut.trackDuration == 65 * 1024);
  // one chunk per old chunk that holds kept samples, chunks of the same size share an stsc entry,
  // one size per sample
  CHECK(cut.chunks == 4 && cut.stscEntries == 3 && cut.sttsEntries == 1);
  CHECK(cut.stszBody == 12 + 4 * 66);
  // the other boxes of the track stay (sound header, data reference)
  std::vector<Node> tree = parse(r.bytes.data(), r.bytes.size());
  CHECK(at(tree, {"moov", "trak", "mdia", "minf", "smhd"}) != nullptr &&
        at(tree, {"moov", "trak", "mdia", "minf", "dinf"}) != nullptr &&
        at(tree, {"moov", "trak", "mdia", "hdlr"}) != nullptr);
  checkDecoded(r);
  // up to the end: the last boundary before the end of what played (frame 131), not the remainder
  const wp::trim::Result tail = wp::trim::trim(in.data(), in.size(), 0.5, 99.0);
  CHECK(tail.code == WP_OK && tail.end == (131 * 1024.0 - kPriming) / kRate);
}

void alacAtFrameBoundaries() { // #120/AK2
  const Bytes in = readFile("clicks3_alac.m4a");
  const Info old = info(in);
  CHECK(old.ok && old.codec == type("alac") && old.samples.size() == 33);
  const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
  CHECK(r.code == WP_OK);
  // packets of 4096 samples, no priming: 0.7 s → 30870 → packet 8 (32768); 2.2 s → 97020 →
  // packet 24 (98304)
  CHECK(r.start == 8 * 4096.0 / kRate && r.end == 24 * 4096.0 / kRate);
  CHECK(std::fabs(r.start - 0.7) <= kMaxDeviation && std::fabs(r.end - 2.2) <= kMaxDeviation);
  const Info cut = info(r.bytes);
  CHECK(cut.ok && cut.codec == type("alac"));
  CHECK(cut.samples.size() == 16);
  CHECK(std::equal(cut.samples.begin(), cut.samples.end(), old.samples.begin() + 8));
  CHECK(cut.edit && cut.mediaTime == 0 && cut.editDuration == 16 * 4096); // no pre-roll
  checkDecoded(r);
  // its edit list starts at media time 0: trimmed again to its whole length, it stays as it is
  const wp::trim::Result again = wp::trim::trim(r.bytes.data(), r.bytes.size(), 0.0, 99.0);
  CHECK(again.code == WP_OK && again.bytes == r.bytes);
  // up to the end: the last, shorter packet stays
  // 1.5 s → 66150 → packet 16 (65536, 1.486 s)
  const wp::trim::Result tail = wp::trim::trim(in.data(), in.size(), 1.5, 99.0);
  CHECK(tail.code == WP_OK && tail.start == 16 * 4096.0 / kRate && tail.end == 3.0);
  const Info t = info(tail.bytes);
  CHECK(t.ok && t.samples.size() == 17 && t.deltas.back() == 3 * kRate - 32 * 4096);
  checkDecoded(tail, 2.0, 0.5);
}

void keepsTags() { // #120/AK3
  for (const char *name : {"clicks3.m4a", "clicks3_alac.m4a"}) {
    const Bytes in = readFile(name);
    const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
    CHECK(r.code == WP_OK);
    std::vector<Node> file = parse(in.data(), in.size());
    // every tag (title, artist, album, cover) is in the new file as it was
    Bytes udta;
    write(*at(file, {"moov", "udta"}), udta);
    for (const char *tag : {"\xa9nam",
                            "\xa9"
                            "ART",
                            "\xa9"
                            "alb",
                            "covr"}) {
      const Bytes name(tag, tag + 4);
      const auto it = std::search(udta.begin(), udta.end(), name.begin(), name.end());
      CHECK(it - udta.begin() >= 4);
      if (it - udta.begin() < 4)
        continue;
      const size_t len = be32(&*(it - 4));
      const Bytes item(it - 4, it - 4 + static_cast<long>(len));
      CHECK(contains(r.bytes, item));
    }
    const std::string text(r.bytes.begin(), r.bytes.end());
    CHECK(text.find("Test Artist") != std::string::npos && text.find("IEND") != std::string::npos);
  }
  // the gapless information of iTunes matches the edit list: 1024 skipped, 66560 play, none after
  const Bytes in = readFile("clicks3.m4a");
  const Smpb before = smpb(in);
  CHECK(before.priming == kPriming && before.remainder == 756 && before.count == 3 * kRate);
  const wp::trim::Result r = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
  const Smpb after = smpb(r.bytes);
  CHECK(after.priming == 1024 && after.remainder == 0 && after.count == 65 * 1024);
  CHECK(r.bytes.size() <= in.size());
}

void trimmedAgain() { // #120/AK2: the edit list of a trimmed file is honoured when it is trimmed
                      // again
  const Bytes in = readFile("clicks3.m4a");
  const wp::trim::Result once = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
  const wp::trim::Result all = wp::trim::trim(once.bytes.data(), once.bytes.size(), 0.0, 99.0);
  CHECK(all.code == WP_OK && all.start == 0.0 && all.bytes == once.bytes);
  CHECK(std::fabs(all.end - (once.end - once.start)) < 1e-9);
  // [0.2, 1.4] of the trimmed file (which starts at 0.6951 s of the original)
  const wp::trim::Result twice = wp::trim::trim(once.bytes.data(), once.bytes.size(), 0.2, 1.4);
  CHECK(twice.code == WP_OK);
  CHECK(std::fabs(twice.start - 0.2) <= kMaxDeviation &&
        std::fabs(twice.end - 1.4) <= kMaxDeviation);
  const Info i = info(twice.bytes);
  CHECK(i.ok && i.edit && i.mediaTime == 1024);
  // its samples are those of the original file: 0.2 s → media 9844 of the trimmed file → frame 10,
  // pre-roll 9; the trimmed file begins with frame 31 of the original
  const Info old = info(in);
  CHECK(std::equal(i.samples.begin(), i.samples.end(), old.samples.begin() + 40));
  checkDecoded(twice, 1.0 - once.start);
  // from the very start: nothing before the old start plays, the priming stays skipped
  const wp::trim::Result head = wp::trim::trim(in.data(), in.size(), 0.0, 1.2);
  CHECK(head.code == WP_OK && head.start == 0.0);
  const Info h = info(head.bytes);
  CHECK(h.ok && h.mediaTime == kPriming - 1024 && h.samples.front() == old.samples[1]);
  checkDecoded(head, 0.5, 0.5);
}

void layouts() { // #120/AK2: moov after mdat, 64-bit offsets and sizes, constant sample size …
  const Bytes in = readFile("clicks3.m4a");
  const wp::trim::Result plain = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
  const Info expected = info(plain.bytes);
  const size_t from = mdatPayload(in);
  auto same = [&](const Bytes &variant) {
    const wp::trim::Result r = wp::trim::trim(variant.data(), variant.size(), 0.7, 2.2);
    if (!(r.code == WP_OK && r.start == plain.start && r.end == plain.end))
      std::printf("  variant: code %d start %.6f end %.6f\n", r.code, r.start, r.end);
    CHECK(r.code == WP_OK && r.start == plain.start && r.end == plain.end);
    const Info i = info(r.bytes);
    CHECK(i.ok && i.samples == expected.samples && i.mediaTime == expected.mediaTime);
    return r;
  };
  // moov after mdat (and no free box): the new file keeps that order
  {
    std::vector<Node> f = parse(in.data(), in.size());
    std::vector<Node> moved = {f[0], *find(f, "mdat"), *find(f, "moov")};
    const wp::trim::Result r = same(rewrite(moved, from));
    std::vector<Node> out = parse(r.bytes.data(), r.bytes.size());
    CHECK(out.size() == 3 && out[1].type == type("mdat") && out[2].type == type("moov"));
  }
  // 64-bit chunk offsets and an mdat with a 64-bit size
  {
    std::vector<Node> f = parse(in.data(), in.size());
    for (Node &t : stbl(f)->kids) {
      if (t.type != type("stco"))
        continue;
      Bytes b(t.body.begin(), t.body.begin() + 8);
      for (uint32_t i = 0; i < be32(t.body.data() + 4); ++i)
        put64(b, be32(t.body.data() + 8 + 4 * i));
      t.type = type("co64");
      t.body = b;
    }
    Bytes out = write(f);
    const size_t mdat = mdatPayload(out) - 8;
    Bytes wide(out.begin(), out.begin() + static_cast<long>(mdat));
    put32(wide, 1);
    put32(wide, type("mdat"));
    put64(wide, out.size() - mdat + 8);
    wide.insert(wide.end(), out.begin() + static_cast<long>(mdat) + 8, out.end());
    std::vector<Node> again = parse(wide.data(), wide.size());
    shiftOffsets(again, static_cast<int64_t>(mdatPayload(wide)) - static_cast<int64_t>(from));
    Bytes fixed = write(again);
    // write() gives the mdat an 8-byte header again: keep the 64-bit one
    fixed.resize(mdatPayload(fixed) - 8);
    fixed.insert(fixed.end(), wide.begin() + static_cast<long>(mdatPayload(wide)) - 16, wide.end());
    same(fixed);
  }
  // an edit list of version 1 with two empty edits first, as some writers put them; it ends where
  // iTunSMPB does, so trimming up to the end gives the same end as without it
  auto withEdit = [&](int version, uint64_t segment, int64_t media, int empties) {
    std::vector<Node> f = parse(in.data(), in.size());
    Node *trak = at(f, {"moov", "trak"});
    Node edts{type("edts"), {}, {}, true};
    Node elst{type("elst"), {}, {}, false};
    put32(elst.body, version == 1 ? 0x01000000 : 0);
    put32(elst.body, static_cast<uint32_t>(empties + 1));
    for (int e = 0; e <= empties; ++e) {
      const uint64_t seg = e < empties ? 0 : segment;
      const auto mt = static_cast<uint64_t>(e < empties ? -1 : media);
      if (version == 1) {
        put64(elst.body, seg);
        put64(elst.body, mt);
      } else {
        put32(elst.body, static_cast<uint32_t>(seg));
        put32(elst.body, static_cast<uint32_t>(mt));
      }
      put32(elst.body, 0x00010000);
    }
    edts.kids.push_back(elst);
    trak->kids.insert(trak->kids.begin() + 1, edts);
    return rewrite(f, from);
  };
  const wp::trim::Result plainTail = wp::trim::trim(in.data(), in.size(), 1.0, 99.0);
  {
    const Bytes v = withEdit(1, 3 * kRate, kPriming, 2);
    same(v);
    const wp::trim::Result tail = wp::trim::trim(v.data(), v.size(), 1.0, 99.0);
    CHECK(tail.code == WP_OK && tail.end == plainTail.end);
  }
  // an edit of length 0 plays everything from its media time on: up to the very end
  {
    const Bytes v = withEdit(0, 0, kPriming, 0);
    same(v);
    const wp::trim::Result tail = wp::trim::trim(v.data(), v.size(), 1.0, 99.0);
    CHECK(tail.code == WP_OK && tail.end == (132 * 1024.0 - kPriming) / kRate);
  }
  // iTunSMPB with a count of 0 (the end follows from the remainder), and with hex digits in both
  // cases (priming 10, count 0x20faf)
  auto withSmpb = [&](const char *text) {
    std::vector<Node> f = parse(in.data(), in.size());
    Node *udta = at(f, {"moov", "udta"});
    const std::string body(udta->body.begin(), udta->body.end());
    const size_t pos = body.find("iTunSMPB") + 8 + 16;
    std::copy(text, text + std::strlen(text), udta->body.begin() + static_cast<long>(pos));
    return write(f);
  };
  same(withSmpb(" 00000000 00000840 000002F4 0000000000000000"));
  {
    const Bytes v = withSmpb(" 00000000 0000000A 000002F4 0000000000020faf");
    const wp::trim::Result r = wp::trim::trim(v.data(), v.size(), 0.7, 2.2);
    // 0.7 s → media 30880 → frame 30
    CHECK(r.code == WP_OK && r.start == (30 * 1024.0 - 10) / kRate);
    // the pre-roll frame 29 is skipped; frame 30 starts after the priming, so all of it plays
    CHECK(smpb(r.bytes).priming == 1024 && smpb(r.bytes).count == 65 * 1024);
  }
  // a QuickTime meta box without version and flags: iTunSMPB is found as well
  {
    std::vector<Node> f = parse(in.data(), in.size());
    Node *udta = at(f, {"moov", "udta"});
    const std::string body(udta->body.begin(), udta->body.end());
    const size_t meta = body.find("meta") - 4;
    udta->body.erase(udta->body.begin() + static_cast<long>(meta) + 8,
                     udta->body.begin() + static_cast<long>(meta) + 12);
    set32(udta->body.data() + meta, be32(udta->body.data() + meta) - 4);
    same(rewrite(f, from));
  }
  // movie, track and media headers of version 1 (64-bit times and durations)
  {
    std::vector<Node> f = parse(in.data(), in.size());
    auto widen = [](Node *n, bool track) {
      const Bytes b = n->body;
      Bytes w = {1, 0, 0, 0};
      put64(w, be32(b.data() + 4));  // creation
      put64(w, be32(b.data() + 8));  // modification
      put32(w, be32(b.data() + 12)); // time scale or track ID
      if (track)
        put32(w, be32(b.data() + 16)); // reserved
      const size_t dur = track ? 20 : 16;
      put64(w, be32(b.data() + dur));
      w.insert(w.end(), b.begin() + static_cast<long>(dur) + 4, b.end());
      n->body = w;
    };
    widen(at(f, {"moov", "mvhd"}), false);
    widen(at(f, {"moov", "trak", "tkhd"}), true);
    widen(at(f, {"moov", "trak", "mdia", "mdhd"}), false);
    const wp::trim::Result r = same(rewrite(f, from));
    const Info i = info(r.bytes);
    CHECK(i.movieDuration == 65 * 1024 && i.trackDuration == 65 * 1024 &&
          i.mediaDuration == 66 * 1024 && i.timescale == kRate);
  }
  // the times in several runs, and a last chunk that claims more samples than there are
  {
    std::vector<Node> f = parse(in.data(), in.size());
    Node *stts = find(stbl(f)->kids, "stts");
    stts->body.resize(4);
    put32(stts->body, 3);
    for (const uint32_t count : {10u, 20u, 102u}) {
      put32(stts->body, count);
      put32(stts->body, 1024);
    }
    // a new stsc entry for the last chunk only, with 5 samples more than it holds
    Node *stsc = find(stbl(f)->kids, "stsc");
    const uint32_t entries = be32(stsc->body.data() + 4);
    const uint32_t chunks = be32(find(stbl(f)->kids, "stco")->body.data() + 4);
    const uint32_t perChunk = be32(stsc->body.data() + 8 + 12 * (entries - 1) + 4);
    CHECK(be32(stsc->body.data() + 8 + 12 * (entries - 1)) < chunks);
    put32(stsc->body, chunks);
    put32(stsc->body, perChunk + 5);
    put32(stsc->body, 1);
    set32(stsc->body.data() + 4, entries + 1);
    same(rewrite(f, from));
  }
  // the samples in chunks of 1 to 7 samples with 3 bytes of junk between the chunks, an stsc entry
  // for each chunk
  {
    const Info old = info(in);
    std::vector<Node> f = parse(in.data(), in.size());
    Bytes payload;
    Node *stsc = find(stbl(f)->kids, "stsc");
    Node *stco = find(stbl(f)->kids, "stco");
    const Node *stsz = find(stbl(f)->kids, "stsz");
    const uint32_t n = be32(stsz->body.data() + 8);
    stsc->body.resize(8);
    stco->body.resize(8);
    uint32_t chunks = 0;
    uint64_t offset = from;
    for (uint32_t sample = 0; sample < n; ++chunks) {
      const uint32_t count = std::min(n - sample, chunks % 7 + 1);
      put32(stsc->body, chunks + 1);
      put32(stsc->body, count);
      put32(stsc->body, 1);
      put32(stco->body, static_cast<uint32_t>(offset + payload.size()));
      for (uint32_t k = 0; k < count; ++k, ++sample)
        payload.insert(payload.end(), old.samples[sample].begin(), old.samples[sample].end());
      payload.insert(payload.end(), {0xEE, 0xEE, 0xEE});
    }
    set32(stsc->body.data() + 4, chunks);
    set32(stco->body.data() + 4, chunks);
    find(f, "mdat")->body = payload;
    const Bytes v = rewrite(f, from);
    CHECK(info(v).ok && info(v).samples == info(in).samples);
    same(v);
  }
}

// #120: a file with times of 2^30 per second and frames of one second: what plays (40 s) does not
// fit into 32 bits, so the edit list gets version 1.
void wideEditList() {
  const Bytes in = readFile("clicks3.m4a");
  std::vector<Node> f = parse(in.data(), in.size());
  constexpr uint32_t kScale = 1u << 30;
  set32(at(f, {"moov", "mvhd"})->body.data() + 12, kScale);
  set32(at(f, {"moov", "trak", "mdia", "mdhd"})->body.data() + 12, kScale);
  set32(find(stbl(f)->kids, "stts")->body.data() + 12, kScale);
  Node *udta = at(f, {"moov", "udta"}); // no priming: iTunSMPB of zeros
  const std::string body(udta->body.begin(), udta->body.end());
  const char *zeros = " 00000000 00000000 00000000 0000000000000000";
  std::copy(zeros, zeros + std::strlen(zeros),
            udta->body.begin() + static_cast<long>(body.find("iTunSMPB") + 8 + 16));
  const Bytes v = write(f);
  const wp::trim::Result r = wp::trim::trim(v.data(), v.size(), 10.0, 50.0);
  CHECK(r.code == WP_OK);
  CHECK(r.start == 10.0 && r.end == 50.0);
  const Info i = info(r.bytes);
  CHECK(i.ok && i.elstVersion == 1 && i.mediaTime == kScale &&
        i.editDuration == uint64_t{40} * kScale);
  CHECK(i.movieDuration == 0xFFFFFFFFu); // version 0 headers keep the largest value they hold
}

void stblVariants() { // #120/AK2: ctts, roll groups, sync samples, a chapter track
  const Bytes in = readFile("clicks3.m4a");
  const size_t from = mdatPayload(in);
  std::vector<Node> f = parse(in.data(), in.size());
  Node *s = stbl(f);
  const uint32_t n = 132;
  Node ctts{type("ctts"), {}, {}, false};
  put32(ctts.body, 0);
  put32(ctts.body, 3);
  put32(ctts.body, 30); // samples 0–29 offset 0 (ending where the kept ones start), 30–39 offset 3,
  put32(ctts.body, 0);  // 40–131 offset 7
  put32(ctts.body, 10);
  put32(ctts.body, 3);
  put32(ctts.body, n - 40);
  put32(ctts.body, 7);
  Node sgpd{type("sgpd"), {}, {}, false};
  put32(sgpd.body, 0x01000000);
  put32(sgpd.body, type("roll"));
  put32(sgpd.body, 2);
  put32(sgpd.body, 2);
  for (const uint8_t b : {0xFF, 0xFF, 0xFF, 0xFE}) // roll distances −1 and −2
    sgpd.body.push_back(b);
  Node sbgp{type("sbgp"), {}, {}, false};
  put32(sbgp.body, 0);
  put32(sbgp.body, type("roll"));
  put32(sbgp.body, 1);
  put32(sbgp.body, 50); // only the first 50 samples belong to a group
  put32(sbgp.body, 1);
  Node stss{type("stss"), {}, {}, false};
  put32(stss.body, 0);
  put32(stss.body, 1);
  put32(stss.body, 1);
  s->kids.push_back(ctts);
  s->kids.push_back(sgpd);
  s->kids.push_back(sbgp);
  s->kids.push_back(stss);
  // a chapter track (text) and a reference to it
  Node *moov = find(f, "moov");
  Node text = *find(moov->kids, "trak");
  Node *hdlr = at(text.kids, {"mdia", "hdlr"});
  set32(hdlr->body.data() + 8, type("text"));
  moov->kids.insert(moov->kids.begin() + 2, text);
  Node tref{type("tref"), {}, {}, false};
  put32(tref.body, 12);
  put32(tref.body, type("chap"));
  put32(tref.body, 2);
  find(moov->kids, "trak")->kids.push_back(tref);
  // the audio track's own user data stays
  find(moov->kids, "trak")
      ->kids.push_back(Node{type("udta"), {0, 0, 0, 8, 'n', 'a', 'm', 'e'}, {}, false});
  const Bytes variant = rewrite(f, from);
  CHECK(info(variant).tracks == 2);

  const wp::trim::Result r = wp::trim::trim(variant.data(), variant.size(), 0.7, 2.2);
  CHECK(r.code == WP_OK);
  const Info i = info(r.bytes);
  CHECK(i.ok && i.tracks == 1 && !i.hasTref && i.trakUdta);
  // a roll distance of 2: two frames of pre-roll (30 and 31), the edit list skips both
  CHECK(i.samples.size() == 67 && i.mediaTime == 2048);
  CHECK(r.start == (32 * 1024.0 - kPriming) / kRate);
  std::vector<Node> out = parse(r.bytes.data(), r.bytes.size());
  Node *o = stbl(out);
  CHECK(find(o->kids, "stss") == nullptr);
  CHECK(find(o->kids, "sgpd")->body == sgpd.body);
  // ctts: samples 30–39 offset 3, 40–96 offset 7 (nothing of the run that ends at 30); sbgp: 30–49
  // in group 1, the rest in none
  const Bytes c = find(o->kids, "ctts")->body;
  CHECK(c.size() == 8 + 2 * 8 && be32(c.data() + 4) == 2 && be32(c.data() + 8) == 10 &&
        be32(c.data() + 12) == 3 && be32(c.data() + 16) == 57 && be32(c.data() + 20) == 7);
  const Bytes g = find(o->kids, "sbgp")->body;
  CHECK(g.size() == 12 + 8 && be32(g.data() + 8) == 1 && be32(g.data() + 12) == 20 &&
        be32(g.data() + 16) == 1);
  // constant sample size: stays constant
  std::vector<Node> fixed = parse(in.data(), in.size());
  Node *z = find(stbl(fixed)->kids, "stsz");
  Node *c2 = find(stbl(fixed)->kids, "stco");
  z->body.resize(12);
  set32(z->body.data() + 4, 4);
  // every sample 4 bytes: chunk offsets 4 × samples before them
  const Node *stsc = find(stbl(fixed)->kids, "stsc");
  uint32_t sample = 0;
  for (uint32_t ch = 0, e = 0; ch < be32(c2->body.data() + 4); ++ch) {
    const uint32_t entries = be32(stsc->body.data() + 4);
    while (e + 1 < entries && be32(stsc->body.data() + 8 + 12 * (e + 1)) <= ch + 1)
      ++e;
    set32(c2->body.data() + 8 + 4 * ch, static_cast<uint32_t>(from + 4 * sample));
    sample += be32(stsc->body.data() + 8 + 12 * e + 4);
  }
  const Bytes small = rewrite(fixed, from);
  const wp::trim::Result rs = wp::trim::trim(small.data(), small.size(), 0.7, 2.2);
  CHECK(rs.code == WP_OK);
  std::vector<Node> so = parse(rs.bytes.data(), rs.bytes.size());
  const Bytes sz = find(stbl(so)->kids, "stsz")->body;
  CHECK(sz.size() == 12 && be32(sz.data() + 4) == 4 && be32(sz.data() + 8) == 66);
  CHECK(info(rs.bytes).ok);
}

void refused() { // #120/AK5
  const Bytes in = readFile("clicks3.m4a");
  const size_t from = mdatPayload(in);
  auto code = [](const Bytes &b) { return wp::trim::trim(b.data(), b.size(), 0.7, 2.2).code; };
  // two audio tracks
  {
    std::vector<Node> f = parse(in.data(), in.size());
    Node *moov = find(f, "moov");
    moov->kids.push_back(*find(moov->kids, "trak"));
    CHECK(code(rewrite(f, from)) == WP_ERR_MULTIPLE_TRACKS);
  }
  // fragmented: mvex in moov, or a moof box
  {
    std::vector<Node> f = parse(in.data(), in.size());
    find(f, "moov")->kids.push_back(Node{type("mvex"), {}, {}, false});
    CHECK(code(rewrite(f, from)) == WP_ERR_FRAGMENTED);
    std::vector<Node> g = parse(in.data(), in.size());
    g.push_back(Node{type("moof"), Bytes(8, 0), {}, false});
    CHECK(code(write(g)) == WP_ERR_FRAGMENTED);
  }
  // no audio track, another codec, two sample descriptions
  {
    std::vector<Node> f = parse(in.data(), in.size());
    set32(at(f, {"moov", "trak", "mdia", "hdlr"})->body.data() + 8, type("vide"));
    CHECK(code(write(f)) == WP_ERR_UNSUPPORTED_FORMAT);
    std::vector<Node> g = parse(in.data(), in.size());
    set32(find(stbl(g)->kids, "stsd")->body.data() + 12, type("Opus"));
    CHECK(code(write(g)) == WP_ERR_UNSUPPORTED_FORMAT);
    std::vector<Node> h = parse(in.data(), in.size());
    set32(find(stbl(h)->kids, "stsd")->body.data() + 4, 2);
    CHECK(code(write(h)) == WP_ERR_UNSUPPORTED_FORMAT);
  }
  // damaged: cut off inside the audio data, inside moov, tables that disagree
  {
    Bytes cut = in;
    cut.resize(in.size() - 200);
    CHECK(code(cut) == WP_ERR_UNSUPPORTED_FORMAT);
    Bytes head = in;
    head.resize(600);
    CHECK(code(head) == WP_ERR_UNSUPPORTED_FORMAT);
    std::vector<Node> f = parse(in.data(), in.size());
    Node *stsz = find(stbl(f)->kids, "stsz");
    set32(stsz->body.data() + 8, be32(stsz->body.data() + 8) - 1); // one sample less than stts
    CHECK(code(write(f)) == WP_ERR_UNSUPPORTED_FORMAT);
    std::vector<Node> g = parse(in.data(), in.size());
    Node *stsc = find(stbl(g)->kids, "stsc");
    set32(stsc->body.data() + 8, 2); // the first entry must start at chunk 1
    CHECK(code(write(g)) == WP_ERR_UNSUPPORTED_FORMAT);
    std::vector<Node> h = parse(in.data(), in.size());
    find(h, "moov")->kids.erase(find(h, "moov")->kids.begin()); // no mvhd
    CHECK(code(write(h)) == WP_ERR_UNSUPPORTED_FORMAT);
    std::vector<Node> k = parse(in.data(), in.size());
    k.erase(k.begin() + 3); // no mdat
    CHECK(code(write(k)) == WP_ERR_UNSUPPORTED_FORMAT);
    // the last sample reaches past the end of the file
    Bytes shorter = in;
    shorter.pop_back();
    const size_t mdat = mdatPayload(shorter) - 8;
    set32(shorter.data() + mdat, be32(shorter.data() + mdat) - 1);
    CHECK(code(shorter) == WP_ERR_UNSUPPORTED_FORMAT);
    // a 64-bit box size cut off at the end
    Bytes wideHead = in;
    put32(wideHead, 1);
    put32(wideHead, type("free"));
    put32(wideHead, 0);
    CHECK(code(wideHead) == WP_ERR_UNSUPPORTED_FORMAT);
    // no time scale; an edit list that plays nothing (1 of 10^6 s rounds to no sample)
    std::vector<Node> noScale = parse(in.data(), in.size());
    set32(at(noScale, {"moov", "trak", "mdia", "mdhd"})->body.data() + 12, 0);
    CHECK(code(write(noScale)) == WP_ERR_UNSUPPORTED_FORMAT);
    std::vector<Node> e = parse(in.data(), in.size());
    set32(at(e, {"moov", "mvhd"})->body.data() + 12, 1000000);
    Node edts{type("edts"), {}, {}, true};
    Node elst{type("elst"), {}, {}, false};
    put32(elst.body, 0);
    put32(elst.body, 1);
    put32(elst.body, 1);
    put32(elst.body, kPriming);
    put32(elst.body, 0x00010000);
    edts.kids.push_back(elst);
    at(e, {"moov", "trak"})->kids.push_back(edts);
    CHECK(code(rewrite(e, from)) == WP_ERR_UNSUPPORTED_FORMAT);
    std::vector<Node> two = parse(in.data(), in.size());
    two.insert(two.begin() + 1, *find(two, "moov")); // two moov boxes
    CHECK(code(write(two)) == WP_ERR_UNSUPPORTED_FORMAT);
  }
  // from 4 GiB on (the size is checked before anything is read)
  if constexpr (sizeof(size_t) > 4)
    CHECK(wp::trim::trim(in.data(), size_t{1} << 32, 0.7, 2.2).code == WP_ERR_OUT_OF_MEMORY);
  // too short a range, NaN
  CHECK(code(Bytes(in)) == WP_OK);
  CHECK(wp::trim::trim(in.data(), in.size(), 1.0, 1.5).code == WP_ERR_INVALID_ARGUMENT);
  CHECK(wp::trim::trim(in.data(), in.size(), NAN, 1.5).code == WP_ERR_INVALID_ARGUMENT);
}

void capi() { // #120/AK4: the C API (FFI natively, the WASM core in the browser) cuts M4A as well
  const Bytes in = readFile("clicks3.m4a");
  wp_trim_result *r = nullptr;
  CHECK(wp_trim(in.data(), in.size(), 0.7, 2.2, &r) == WP_OK && r);
  const wp::trim::Result direct = wp::trim::trim(in.data(), in.size(), 0.7, 2.2);
  const auto *p = static_cast<const uint8_t *>(wp_trim_data(r));
  CHECK(Bytes(p, p + wp_trim_size(r)) == direct.bytes);
  CHECK(wp_trim_start(r) == direct.start && wp_trim_end(r) == direct.end);
  wp_trim_free(r);
  std::vector<Node> f = parse(in.data(), in.size());
  find(f, "moov")->kids.push_back(Node{type("mvex"), {}, {}, false});
  const Bytes frag = write(f);
  r = nullptr;
  CHECK(wp_trim(frag.data(), frag.size(), 0.7, 2.2, &r) == WP_ERR_FRAGMENTED && !r);
}

void run(const char *name, void (*test)()) {
  const int before = failures;
  test();
  std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name);
}

} // namespace

// #120 regression (found bug 44, fuzz regression trim/m4a_empty_mvhd_at_end): an mvhd box without
// a body at the very end of the file. The check of its length read the version byte first, one byte
// past the end of the file (AddressSanitizer under make sanitize). Expected: refused as damaged.
void emptyMvhdAtTheEnd() {
  const Bytes m4a = {
      0x00, 0x00, 0x00, 0x10, 'f', 't', 'y', 'p', 'M', '4', 'A', ' ', 0, 0, 0, 0, // ftyp M4A
      0x00, 0x00, 0x00, 0x10, 'm', 'o', 'o', 'v',                                 // moov
      0x00, 0x00, 0x00, 0x08, 'm', 'v', 'h', 'd', // mvhd without a body, the last byte of the file
  };
  CHECK(wp::trim::trim(m4a.data(), m4a.size(), 0.5, 2.0).code == WP_ERR_UNSUPPORTED_FORMAT);
}

int main() {
  std::setvbuf(stdout, nullptr, _IONBF, 0);
#ifdef WP_SYSTEM_DECODER
  std::printf("(results also decoded by the system decoder)\n");
#endif
  run("#120/AK2 AAC at frame boundaries, pre-roll skipped by the edit list", aacAtFrameBoundaries);
  run("#120/AK2 ALAC at packet boundaries", alacAtFrameBoundaries);
  run("#120/AK3 tags and cover kept, iTunSMPB rewritten", keepsTags);
  run("#120/AK2 a trimmed file trimmed again", trimmedAgain);
  run("#120/AK2 moov after mdat, 64-bit offsets, edit lists, iTunSMPB, headers of version 1",
      layouts);
  run("#120/AK2 ctts, roll groups, sync samples, chapter track", stblVariants);
  run("#120/AK2 edit list of version 1 for long durations", wideEditList);
  run("#120/AK5 several audio tracks, fragmented, damaged", refused);
  run("#120/AK4 C API", capi);
  run("#120 regression (found bug 44): empty mvhd at the end of the file", emptyMvhdAtTheEnd);
  std::printf("%s\n", failures == 0 ? "all MP4 trim tests passed" : "MP4 trim tests FAILED");
  return failures == 0 ? 0 : 1;
}
