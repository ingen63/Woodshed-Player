// Trimming MP4/M4A (#120), see trim.hpp. The samples (AAC or ALAC packets) are copied without
// encoding again; the cut lies at the sample boundaries nearest to the requested times. Before the
// first sample of an AAC track come its pre-roll samples (the decoder needs the one before for the
// overlap of its filter bank), and an edit list (`elst`) tells the decoder to skip them and the
// encoder delay (priming), so the file starts without a click or offset. The sample tables in
// `moov` are written anew for the kept samples, which go into one `mdat` where the first one was;
// all other boxes (tags in `udta`/`meta`/`ilst` with the cover, the sample description) stay as
// they are, and the gapless information of iTunes (`iTunSMPB`) is rewritten to match.
#include "trim_mp4.hpp"

#include "wp_core.h"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <limits>
#include <stdexcept>
#include <string>
#include <vector>

namespace wp::trim {

namespace {

// ---- Bytes and boxes ----

constexpr uint32_t fourcc(const char (&s)[5]) {
  return (uint32_t{static_cast<uint8_t>(s[0])} << 24) |
         (uint32_t{static_cast<uint8_t>(s[1])} << 16) |
         (uint32_t{static_cast<uint8_t>(s[2])} << 8) | uint32_t{static_cast<uint8_t>(s[3])};
}

uint32_t rd32(const uint8_t *p) {
  return (uint32_t{p[0]} << 24) | (uint32_t{p[1]} << 16) | (uint32_t{p[2]} << 8) | p[3];
}
uint64_t rd64(const uint8_t *p) { return (uint64_t{rd32(p)} << 32) | rd32(p + 4); }
void set32(uint8_t *p, uint32_t v) {
  for (int i = 0; i < 4; ++i)
    p[i] = static_cast<uint8_t>(v >> (24 - 8 * i));
}
void set64(uint8_t *p, uint64_t v) {
  set32(p, static_cast<uint32_t>(v >> 32));
  set32(p + 4, static_cast<uint32_t>(v));
}
void put32(std::vector<uint8_t> &o, uint32_t v) {
  o.resize(o.size() + 4);
  set32(o.data() + o.size() - 4, v);
}
void put64(std::vector<uint8_t> &o, uint64_t v) {
  o.resize(o.size() + 8);
  set64(o.data() + o.size() - 8, v);
}

struct Box {
  size_t pos = 0;  // of the header
  size_t head = 0; // length of the header: 8, or 16 with a 64-bit size
  size_t size = 0; // header and body
  uint32_t type = 0;

  const uint8_t *body(const uint8_t *d) const { return d + pos + head; }
  size_t bodySize() const { return size - head; }
  size_t end() const { return pos + size; }
};

using Boxes = std::vector<Box>;

// The boxes in [from, to); false if one runs past `to`. Fewer than 8 bytes at the end (the zero
// terminator some writers put into `udta`) are ignored.
bool boxes(const uint8_t *d, size_t from, size_t to, Boxes &out) {
  for (size_t p = from; to - p >= 8;) {
    uint64_t size = rd32(d + p);
    size_t head = 8;
    if (size == 1) {
      if (to - p < 16)
        return false;
      size = rd64(d + p + 8);
      head = 16;
    } else if (size == 0) {
      size = to - p; // up to the end
    }
    if (size < head || size > to - p)
      return false;
    out.push_back({p, head, static_cast<size_t>(size), rd32(d + p + 4)});
    p += static_cast<size_t>(size);
  }
  return true;
}

// The boxes inside `b`, after `skip` bytes of its body (the version and flags of `meta`).
bool children(const uint8_t *d, const Box &b, Boxes &out, size_t skip = 0) {
  return b.bodySize() >= skip && boxes(d, b.pos + b.head + skip, b.end(), out);
}

const Box *find(const Boxes &v, uint32_t type) {
  const auto it = std::find_if(v.begin(), v.end(), [&](const Box &b) { return b.type == type; });
  return it == v.end() ? nullptr : &*it;
}

// The only child of type `type` inside `b`; nullptr if it is missing or `b` is damaged.
const Box *child(const uint8_t *d, const Box *b, uint32_t type, Boxes &store) {
  store.clear();
  return b && children(d, *b, store) ? find(store, type) : nullptr;
}

// Whether the body of a full box with a duration (mvhd, tkhd, mdhd) is long enough: `v0` bytes in
// version 0, `v1` in version 1. The version byte is read only once the body has room for it.
bool fits(const uint8_t *d, const Box &b, size_t v0, size_t v1) {
  return b.bodySize() >= v0 && b.bodySize() >= (b.body(d)[0] == 1 ? v1 : v0);
}

// ---- Output ----

using Out = std::vector<uint8_t>;

size_t open(Out &o, uint32_t type) {
  const size_t at = o.size();
  put32(o, 0);
  put32(o, type);
  return at;
}
void close(Out &o, size_t at) {
  if (o.size() - at > std::numeric_limits<uint32_t>::max())
    throw std::length_error("box too large"); // cannot happen: smaller than the old one
  set32(o.data() + at, static_cast<uint32_t>(o.size() - at));
}
void raw(Out &o, const uint8_t *d, const Box &b) { o.insert(o.end(), d + b.pos, d + b.end()); }

// Copies a box whose body holds a duration after its version and flags (mvhd, tkhd, mdhd) and sets
// it: 32 bits at `at0` in version 0, 64 bits at `at1` in version 1.
void withDuration(Out &o, const uint8_t *d, const Box &b, size_t at0, size_t at1, uint64_t dur) {
  const size_t start = o.size() + b.head;
  raw(o, d, b);
  if (o[start] == 1)
    set64(o.data() + start + at1, dur);
  else
    set32(o.data() + start + at0,
          static_cast<uint32_t>(std::min<uint64_t>(dur, std::numeric_limits<uint32_t>::max())));
}

// ---- Sample tables ----

// Entries of a full box: count at `countAt`, then entries of `width` bytes; false if they do not
// fit into the body.
struct Table {
  const uint8_t *p = nullptr; // first entry
  uint32_t count = 0;
};

bool table(const uint8_t *d, const Box *b, size_t countAt, size_t width, Table &t) {
  if (!b || b->bodySize() < countAt + 4)
    return false;
  t.count = rd32(b->body(d) + countAt);
  t.p = b->body(d) + countAt + 4;
  return t.count <= (b->bodySize() - countAt - 4) / width;
}

// Run-length entries (sample count, 4 bytes of value) of `t` for the samples [from, to).
void clipRuns(const Table &t, uint64_t from, uint64_t to, Out &o, uint32_t &count) {
  uint64_t at = 0;
  for (uint32_t i = 0; i < t.count && at < to; ++i) {
    const uint64_t n = rd32(t.p + 8 * size_t{i});
    const uint64_t a = std::max(at, from), b = std::min(at + n, to);
    if (a < b) {
      put32(o, static_cast<uint32_t>(b - a));
      o.insert(o.end(), t.p + 8 * size_t{i} + 4, t.p + 8 * size_t{i} + 8);
      ++count;
    }
    at += n;
  }
}

// ---- iTunes gapless information ----

// The text of `iTunSMPB` in moov/udta/meta/ilst: " 00000000 PPPPPPPP RRRRRRRR NNNNNNNNNNNNNNNN …"
// with the priming P, the remainder R and the count N of samples that play (hexadecimal).
struct Smpb {
  size_t pos = 0; // of the text in the file; 0: none
  size_t len = 0;
  size_t field[4] = {}; // where the first four fields start in the text
  size_t width[4] = {};
  uint64_t value[4] = {};
};

bool parseSmpb(const uint8_t *text, size_t len, Smpb &s) {
  size_t p = 0;
  for (int f = 0; f < 4; ++f) {
    while (p < len && text[p] == ' ')
      ++p;
    const size_t from = p;
    uint64_t v = 0;
    for (; p < len && text[p] != ' ' && text[p] != 0; ++p) {
      const int c = text[p];
      const int digit = c >= '0' && c <= '9'   ? c - '0'
                        : c >= 'A' && c <= 'F' ? c - 'A' + 10
                        : c >= 'a' && c <= 'f' ? c - 'a' + 10
                                               : -1;
      if (digit < 0 || p - from >= 16)
        return false;
      v = (v << 4) | static_cast<uint64_t>(digit);
    }
    if (p == from)
      return false;
    s.field[f] = from;
    s.width[f] = p - from;
    s.value[f] = v;
  }
  return true;
}

Smpb findSmpb(const uint8_t *d, const Boxes &moov) {
  Smpb s;
  Boxes udta, meta, ilst;
  const Box *u = find(moov, fourcc("udta"));
  if (!u || !children(d, *u, udta))
    return s;
  const Box *m = find(udta, fourcc("meta"));
  if (!m || (!children(d, *m, meta, 4) && (meta.clear(), !children(d, *m, meta))))
    return s;
  const Box *l = find(meta, fourcc("ilst"));
  if (!l || !children(d, *l, ilst))
    return s;
  for (const Box &item : ilst) {
    Boxes parts;
    if (item.type != fourcc("----") || !children(d, item, parts))
      continue;
    const Box *name = find(parts, fourcc("name"));
    const Box *data = find(parts, fourcc("data"));
    if (!name || !data || name->bodySize() != 12 || data->bodySize() < 8 ||
        std::string(reinterpret_cast<const char *>(name->body(d)) + 4, 8) != "iTunSMPB")
      continue;
    Smpb found;
    found.pos = data->pos + data->head + 8;
    found.len = data->bodySize() - 8;
    if (parseSmpb(d + found.pos, found.len, found))
      return found;
  }
  return s;
}

// Writes priming, remainder and count into the copy of the text at `text`; fields too narrow for a
// value stay as they are.
void writeSmpb(uint8_t *text, const Smpb &s, uint64_t priming, uint64_t remainder, uint64_t count) {
  const uint64_t values[3] = {priming, remainder, count};
  for (int f = 1; f < 4; ++f) {
    const size_t w = s.width[f];
    if (w < 16 && (values[f - 1] >> (4 * w)) != 0)
      continue;
    for (size_t i = 0; i < w; ++i)
      text[s.field[f] + i] =
          static_cast<uint8_t>("0123456789ABCDEF"[(values[f - 1] >> (4 * (w - 1 - i))) & 15]);
  }
}

// ---- The audio track ----

struct Track {
  const Box *trak = nullptr, *tkhd = nullptr, *mdia = nullptr, *mdhd = nullptr, *minf = nullptr,
            *stbl = nullptr;
  Boxes trakKids, mdiaKids, minfKids, stblKids;
  uint32_t timescale = 0;
  uint32_t codec = 0;
};

// The track's boxes; false if one it needs is missing or damaged.
bool openTrack(const uint8_t *d, const Box &trak, Track &t) {
  t.trak = &trak;
  if (!children(d, trak, t.trakKids))
    return false;
  t.tkhd = find(t.trakKids, fourcc("tkhd"));
  t.mdia = find(t.trakKids, fourcc("mdia"));
  if (!t.tkhd || !t.mdia || !children(d, *t.mdia, t.mdiaKids))
    return false;
  t.mdhd = find(t.mdiaKids, fourcc("mdhd"));
  t.minf = find(t.mdiaKids, fourcc("minf"));
  if (!t.mdhd || !t.minf || !children(d, *t.minf, t.minfKids))
    return false;
  t.stbl = find(t.minfKids, fourcc("stbl"));
  if (!t.stbl || !children(d, *t.stbl, t.stblKids))
    return false;
  if (!fits(d, *t.tkhd, 24, 36) || !fits(d, *t.mdhd, 20, 32))
    return false;
  const uint8_t *md = t.mdhd->body(d);
  t.timescale = rd32(md + (md[0] == 1 ? 20 : 12));
  return t.timescale > 0;
}

// Handler of a track (`soun` for audio); 0 if there is none.
uint32_t handler(const uint8_t *d, const Box &trak) {
  Boxes kids, mdia;
  const Box *m = child(d, &trak, fourcc("mdia"), kids);
  const Box *h = m && children(d, *m, mdia) ? find(mdia, fourcc("hdlr")) : nullptr;
  return h && h->bodySize() >= 12 ? rd32(h->body(d) + 8) : 0;
}

// Pre-roll of AAC in samples from a `roll` sample group (version 1, entries of 2 bytes): the
// largest distance, at least 1 and at most 8.
uint64_t preroll(const uint8_t *d, const Track &t) {
  if (t.codec != fourcc("mp4a"))
    return 0; // ALAC packets decode on their own
  uint64_t roll = 1;
  for (const Box &b : t.stblKids) {
    const uint8_t *p = b.body(d);
    if (b.type != fourcc("sgpd") || b.bodySize() < 16 || p[0] != 1 ||
        rd32(p + 4) != fourcc("roll") || rd32(p + 8) != 2)
      continue;
    const uint32_t n =
        std::min<uint32_t>(rd32(p + 12), static_cast<uint32_t>((b.bodySize() - 16) / 2));
    for (uint32_t i = 0; i < n; ++i) {
      const auto distance = static_cast<int16_t>((p[16 + 2 * i] << 8) | p[17 + 2 * i]);
      roll = std::max<uint64_t>(roll, static_cast<uint64_t>(std::abs(int{distance})));
    }
  }
  return std::min<uint64_t>(roll, 8);
}

Result failure(int code) {
  Result r;
  r.code = code;
  return r;
}

constexpr uint64_t kMaxTime = uint64_t{1} << 53; // exact in a double
constexpr uint64_t kMaxSize = 0xFFFF0000u;       // 4 GiB less room for the edit list

} // namespace

Result trimMp4(const uint8_t *d, size_t size, double start, double end) {
  constexpr int kDamaged = WP_ERR_UNSUPPORTED_FORMAT;
  // The new file is never larger than the old one by more than its edit list, so its chunk offsets
  // and mdat size fit into 32 bits. Larger files (beyond the memory of the web core anyway) are
  // refused.
  if (size > kMaxSize)
    return failure(WP_ERR_OUT_OF_MEMORY);
  Boxes top, moov;
  if (!boxes(d, 0, size, top))
    return failure(kDamaged);
  if (find(top, fourcc("moof")))
    return failure(WP_ERR_FRAGMENTED);
  const Box *moovBox = find(top, fourcc("moov"));
  if (!moovBox ||
      std::count_if(top.begin(), top.end(),
                    [](const Box &b) { return b.type == fourcc("moov"); }) != 1 ||
      !children(d, *moovBox, moov))
    return failure(kDamaged);
  if (find(moov, fourcc("mvex")))
    return failure(WP_ERR_FRAGMENTED);
  const Box *mvhd = find(moov, fourcc("mvhd"));
  if (!mvhd || !fits(d, *mvhd, 20, 32))
    return failure(kDamaged);
  const uint32_t movieScale = rd32(mvhd->body(d) + (mvhd->body(d)[0] == 1 ? 20 : 12));

  // One audio track; other tracks (chapters, a cover as video) are dropped.
  const Box *audio = nullptr;
  for (const Box &b : moov) {
    if (b.type != fourcc("trak") || handler(d, b) != fourcc("soun"))
      continue;
    if (audio)
      return failure(WP_ERR_MULTIPLE_TRACKS);
    audio = &b;
  }
  Track t;
  if (!audio || movieScale == 0 || !openTrack(d, *audio, t))
    return failure(kDamaged);

  // Sample description: one entry, AAC or ALAC.
  const Box *stsd = find(t.stblKids, fourcc("stsd"));
  if (!stsd || stsd->bodySize() < 16 || rd32(stsd->body(d) + 4) != 1)
    return failure(kDamaged);
  t.codec = rd32(stsd->body(d) + 12);
  if (t.codec != fourcc("mp4a") && t.codec != fourcc("alac"))
    return failure(kDamaged);

  // Sample times, sizes and places.
  Table stts, stsc, chunkTable, ctts;
  const Box *stsz = find(t.stblKids, fourcc("stsz"));
  const Box *co64 = find(t.stblKids, fourcc("co64"));
  const Box *cttsBox = find(t.stblKids, fourcc("ctts"));
  if (!table(d, find(t.stblKids, fourcc("stts")), 4, 8, stts) ||
      !table(d, find(t.stblKids, fourcc("stsc")), 4, 12, stsc) ||
      !table(d, co64 ? co64 : find(t.stblKids, fourcc("stco")), 4, co64 ? 8 : 4, chunkTable) ||
      (cttsBox && !table(d, cttsBox, 4, 8, ctts)) || !stsz || stsz->bodySize() < 12)
    return failure(kDamaged);
  const uint32_t fixedSize = rd32(stsz->body(d) + 4);
  const size_t n = rd32(stsz->body(d) + 8);
  if (n == 0 || (fixedSize == 0 && n > (stsz->bodySize() - 12) / 4) ||
      (fixedSize != 0 && n > size / fixedSize))
    return failure(kDamaged);
  auto sampleSize = [&](size_t i) {
    return fixedSize ? fixedSize : rd32(stsz->body(d) + 12 + 4 * i);
  };

  std::vector<uint64_t> times(n + 1, 0); // start of each sample, then the end (media time scale)
  size_t i = 0;
  for (uint32_t e = 0; e < stts.count; ++e) {
    const uint32_t count = rd32(stts.p + 8 * size_t{e});
    const uint32_t delta = rd32(stts.p + 8 * size_t{e} + 4);
    for (uint32_t k = 0; k < count; ++k, ++i) {
      if (i == n || times[i] > kMaxTime)
        return failure(kDamaged);
      times[i + 1] = times[i] + delta;
    }
  }
  if (i != n || times[n] == 0 || times[n] > kMaxTime)
    return failure(kDamaged);

  std::vector<uint64_t> offset(n);
  std::vector<uint32_t> chunkOf(n);
  if (stsc.count == 0 || rd32(stsc.p) != 1)
    return failure(kDamaged);
  i = 0;
  for (uint32_t c = 0, e = 0; c < chunkTable.count && i < n; ++c) {
    while (e + 1 < stsc.count && rd32(stsc.p + 12 * size_t{e + 1}) <= c + 1)
      ++e;
    const uint32_t perChunk = rd32(stsc.p + 12 * size_t{e} + 4);
    uint64_t o = co64 ? rd64(chunkTable.p + 8 * size_t{c}) : rd32(chunkTable.p + 4 * size_t{c});
    for (uint32_t k = 0; k < perChunk && i < n; ++k, ++i) {
      const uint64_t len = sampleSize(i);
      if (o > size || len > size - o)
        return failure(kDamaged); // outside the file
      offset[i] = o;
      chunkOf[i] = c;
      o += len;
    }
  }
  if (i != n)
    return failure(kDamaged);

  // What plays of the media: an edit list, else the gapless information of iTunes, else all.
  const uint64_t total = times[n];
  uint64_t e0 = 0, e1 = total;
  Boxes edts;
  const Box *elst = child(d, find(t.trakKids, fourcc("edts")), fourcc("elst"), edts);
  const Smpb smpb = findSmpb(d, moov);
  if (elst) {
    const uint8_t *b = elst->body(d);
    const bool v1 = elst->bodySize() >= 4 && b[0] == 1;
    Table entries;
    if (!table(d, elst, 4, v1 ? 20 : 12, entries))
      return failure(kDamaged);
    for (uint32_t k = 0; k < entries.count; ++k) {
      const uint8_t *p = entries.p + (v1 ? 20 : 12) * size_t{k};
      const auto media =
          v1 ? static_cast<int64_t>(rd64(p + 8)) : int64_t{static_cast<int32_t>(rd32(p + 4))};
      if (media == -1)
        continue; // an empty edit: nothing plays
      const uint64_t segment = v1 ? rd64(p) : rd32(p);
      if (media < 0 || static_cast<uint64_t>(media) >= total)
        return failure(kDamaged);
      e0 = static_cast<uint64_t>(media);
      const double length = std::round(static_cast<double>(segment) * t.timescale / movieScale);
      if (segment != 0 && length < static_cast<double>(total - e0))
        e1 = e0 + static_cast<uint64_t>(length);
      break;
    }
  } else if (smpb.pos) {
    const uint64_t priming = smpb.value[1], remainder = smpb.value[2], count = smpb.value[3];
    const uint64_t to = count ? priming + count : (remainder < total ? total - remainder : 0);
    if (priming < total && to > priming && to <= total) {
      e0 = priming;
      e1 = to;
    }
  }
  if (e1 <= e0)
    return failure(kDamaged);

  long long s0 = 0, s1 = 0;
  if (!sampleRange(start, end, static_cast<long long>(e1 - e0), t.timescale, s0, s1))
    return failure(WP_ERR_INVALID_ARGUMENT);
  // The sample boundaries nearest to the requested media times.
  auto nearest = [&](uint64_t m) {
    const auto it = std::lower_bound(times.begin(), times.end(), m);
    if (it == times.begin())
      return size_t{0};
    const auto k = static_cast<size_t>(it - times.begin());
    return (it == times.end() || *it - m > m - times[k - 1]) ? k - 1 : k;
  };
  const size_t k0 = std::min(n - 1, nearest(e0 + static_cast<uint64_t>(s0)));
  const size_t k1 = std::max(k0 + 1, nearest(e0 + static_cast<uint64_t>(s1)));
  const uint64_t m0 = std::max(times[k0], e0), m1 = std::min(times[k1], e1);
  if (m1 <= m0)
    return failure(kDamaged);
  const size_t kp = k0 - static_cast<size_t>(std::min<uint64_t>(k0, preroll(d, t)));
  const uint64_t base = times[kp];
  const uint64_t mediaTime = m0 - base;            // skipped at the start: pre-roll and priming
  const uint64_t mediaDuration = times[k1] - base; // of all kept samples
  const auto duration = static_cast<uint64_t>(
      std::llround(static_cast<double>(m1 - m0) * movieScale / t.timescale)); // what plays

  // The kept samples in chunks: a new chunk wherever an old one began.
  struct Chunk {
    uint64_t from = 0; // in the old file
    uint64_t len = 0;
    uint32_t samples = 0;
  };
  std::vector<Chunk> chunks;
  for (size_t k = kp; k < k1; ++k) {
    if (k == kp || chunkOf[k] != chunkOf[k - 1])
      chunks.push_back({offset[k], 0, 0});
    chunks.back().len += sampleSize(k);
    ++chunks.back().samples;
  }

  // ---- moov ----
  Out m;
  size_t offsetsAt = 0; // of the first chunk offset in `m`
  const size_t moovAt = open(m, fourcc("moov"));
  for (const Box &b : moov) {
    if (b.type == fourcc("mvhd")) {
      withDuration(m, d, b, 16, 24, duration);
    } else if (b.type == fourcc("trak")) {
      if (&b != audio)
        continue;
      const size_t trakAt = open(m, fourcc("trak"));
      for (const Box &tb : t.trakKids) {
        if (tb.type == fourcc("tkhd")) {
          withDuration(m, d, tb, 20, 28, duration);
          // the edit list: skip the pre-roll and the priming, play `duration`
          const size_t edtsAt = open(m, fourcc("edts"));
          const size_t elstAt = open(m, fourcc("elst"));
          const bool wide = duration > std::numeric_limits<uint32_t>::max() ||
                            mediaTime > static_cast<uint64_t>(std::numeric_limits<int32_t>::max());
          put32(m, wide ? 0x01000000u : 0);
          put32(m, 1);
          if (wide) {
            put64(m, duration);
            put64(m, mediaTime);
          } else {
            put32(m, static_cast<uint32_t>(duration));
            put32(m, static_cast<uint32_t>(mediaTime));
          }
          put32(m, 0x00010000); // rate 1.0
          close(m, elstAt);
          close(m, edtsAt);
        } else if (tb.type == fourcc("mdia")) {
          const size_t mdiaAt = open(m, fourcc("mdia"));
          for (const Box &mb : t.mdiaKids) {
            if (mb.type == fourcc("mdhd")) {
              withDuration(m, d, mb, 16, 24, mediaDuration);
            } else if (mb.type == fourcc("minf")) {
              const size_t minfAt = open(m, fourcc("minf"));
              for (const Box &nb : t.minfKids) {
                if (nb.type != fourcc("stbl")) {
                  raw(m, d, nb);
                  continue;
                }
                const size_t stblAt = open(m, fourcc("stbl"));
                for (const Box &sb : t.stblKids) {
                  const uint32_t type = sb.type;
                  if (type == fourcc("stsd") || type == fourcc("sgpd")) {
                    raw(m, d, sb);
                  } else if (type == fourcc("stts")) {
                    const size_t at = open(m, type);
                    put32(m, 0);
                    const size_t countAt = m.size();
                    put32(m, 0);
                    uint32_t count = 0;
                    for (size_t k = kp; k < k1; ++k) {
                      const auto delta = static_cast<uint32_t>(times[k + 1] - times[k]);
                      if (count > 0 && rd32(m.data() + m.size() - 4) == delta) {
                        set32(m.data() + m.size() - 8, rd32(m.data() + m.size() - 8) + 1);
                      } else {
                        put32(m, 1);
                        put32(m, delta);
                        ++count;
                      }
                    }
                    set32(m.data() + countAt, count);
                    close(m, at);
                  } else if (type == fourcc("ctts") || type == fourcc("sbgp")) {
                    const size_t at = open(m, type);
                    const uint8_t *b = sb.body(d);
                    if (sb.bodySize() < 4)
                      return failure(kDamaged);
                    const size_t head = type == fourcc("ctts") ? 4 : (b[0] == 1 ? 12 : 8);
                    Table runs;
                    if (!table(d, &sb, head, 8, runs))
                      return failure(kDamaged);
                    m.insert(m.end(), b, b + head);
                    const size_t countAt = m.size();
                    put32(m, 0);
                    uint32_t count = 0;
                    clipRuns(runs, kp, k1, m, count);
                    set32(m.data() + countAt, count);
                    close(m, at);
                  } else if (type == fourcc("stsc")) {
                    const size_t at = open(m, type);
                    put32(m, 0);
                    const size_t countAt = m.size();
                    put32(m, 0);
                    uint32_t count = 0, last = 0;
                    for (size_t c = 0; c < chunks.size(); ++c) {
                      if (c > 0 && chunks[c].samples == last)
                        continue;
                      last = chunks[c].samples;
                      put32(m, static_cast<uint32_t>(c + 1));
                      put32(m, last);
                      put32(m, 1);
                      ++count;
                    }
                    set32(m.data() + countAt, count);
                    close(m, at);
                  } else if (type == fourcc("stsz")) {
                    const size_t at = open(m, type);
                    put32(m, 0);
                    put32(m, fixedSize);
                    put32(m, static_cast<uint32_t>(k1 - kp));
                    for (size_t k = kp; k < k1 && fixedSize == 0; ++k)
                      put32(m, sampleSize(k));
                    close(m, at);
                  } else if (type == fourcc("stco") || type == fourcc("co64")) {
                    const size_t at = open(m, fourcc("stco"));
                    put32(m, 0);
                    put32(m, static_cast<uint32_t>(chunks.size()));
                    offsetsAt = m.size();
                    m.resize(m.size() + chunks.size() * 4);
                    close(m, at);
                  } // the rest (sync samples, dependencies …) describes the old samples: dropped
                }
                close(m, stblAt);
              }
              close(m, minfAt);
            } else {
              raw(m, d, mb);
            }
          }
          close(m, mdiaAt);
        } else if (tb.type != fourcc("edts") && tb.type != fourcc("tref")) {
          raw(m, d, tb); // the references pointed to tracks that are gone
        }
      }
      close(m, trakAt);
    } else {
      const size_t at = m.size();
      raw(m, d, b);
      if (smpb.pos && smpb.pos >= b.pos && smpb.pos < b.end())
        writeSmpb(m.data() + at + (smpb.pos - b.pos), smpb, mediaTime, times[k1] - m1, m1 - m0);
    }
  }
  close(m, moovAt);

  // ---- The file: the boxes in their order, the new moov, one mdat with the kept samples ----
  uint64_t payload = 0;
  for (const Chunk &c : chunks)
    payload += c.len;
  Result r;
  size_t moovOut = 0, dataOut = 0;
  bool haveData = false;
  for (const Box &b : top) {
    if (b.type == fourcc("moov")) {
      moovOut = r.bytes.size();
      r.bytes.insert(r.bytes.end(), m.begin(), m.end());
    } else if (b.type == fourcc("mdat")) {
      if (haveData)
        continue;
      put32(r.bytes, static_cast<uint32_t>(payload + 8));
      put32(r.bytes, fourcc("mdat"));
      dataOut = r.bytes.size();
      for (const Chunk &c : chunks)
        r.bytes.insert(r.bytes.end(), d + c.from, d + c.from + c.len);
      haveData = true;
    } else if (b.type != fourcc("free") && b.type != fourcc("skip") && b.type != fourcc("wide")) {
      raw(r.bytes, d, b);
    }
  }
  if (!haveData || offsetsAt == 0)
    return failure(kDamaged);
  uint64_t at = dataOut;
  for (size_t c = 0; c < chunks.size(); ++c) {
    set32(r.bytes.data() + moovOut + offsetsAt + 4 * c, static_cast<uint32_t>(at));
    at += chunks[c].len;
  }
  r.start = static_cast<double>(m0 - e0) / t.timescale;
  r.end = static_cast<double>(m1 - e0) / t.timescale;
  return r;
}

} // namespace wp::trim
