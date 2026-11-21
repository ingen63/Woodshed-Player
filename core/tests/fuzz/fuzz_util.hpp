// Helpers of the fuzz targets (#10/AK4): invariant checks that abort (so libFuzzer and the replay
// tests see a finding), a reader for the input bytes, a temporary file per process and a record of
// the C API functions reached (#86).
#pragma once

#include <cstddef>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <set>
#include <string>

#if defined(_WIN32)
#include <process.h>
#define WP_FUZZ_PID _getpid()
#else
#include <unistd.h>
#define WP_FUZZ_PID getpid()
#endif

// A broken invariant is a finding: message and abort, like a sanitizer report.
#define WP_FUZZ_CHECK(cond)                                                                        \
  do {                                                                                             \
    if (!(cond)) {                                                                                 \
      std::fprintf(stderr, "FUZZ INVARIANT FAILED %s:%d: %s\n", __FILE__, __LINE__, #cond);        \
      std::abort();                                                                                \
    }                                                                                              \
  } while (0)

// #86: calls a function of the C API and notes its name, so the replay test fuzz_capi_reached can
// tell which functions the checked-in inputs reach. The replay program finds every function a
// target calls by these calls in its source; a call to wp_* without WP_FUZZ_CALL fails that test.
#define WP_FUZZ_CALL(fn, ...) (::wp::fuzz::reached(#fn), fn(__VA_ARGS__))

namespace wp::fuzz {

// #86: names of the C API functions reached so far; recorded only while `tracking` is set (replay
// with --reached), so the libFuzzer programs pay a single branch per call.
struct ReachedApi {
  bool tracking = false;
  std::set<std::string> names;
};

inline ReachedApi &reachedApi() {
  static ReachedApi r;
  return r;
}

inline void reached(const char *name) {
  ReachedApi &r = reachedApi();
  if (r.tracking)
    r.names.insert(name);
}

// Reads values from the input; past the end it yields zeros, so every input is a valid program.
class Reader {
public:
  Reader(const uint8_t *data, size_t size) : data_(data), size_(size) {}

  bool done() const { return pos_ >= size_; }
  size_t remaining() const { return pos_ < size_ ? size_ - pos_ : 0; }

  uint8_t byte() { return pos_ < size_ ? data_[pos_++] : 0; }

  uint16_t u16() {
    const uint16_t lo = byte();
    return static_cast<uint16_t>(lo | (byte() << 8));
  }

  uint32_t u32() {
    uint32_t v = 0;
    for (int i = 0; i < 4; ++i)
      v |= static_cast<uint32_t>(byte()) << (8 * i);
    return v;
  }

  int32_t i32() {
    const uint32_t v = u32();
    int32_t r;
    std::memcpy(&r, &v, sizeof r);
    return r;
  }

  // Any bit pattern, including NaN, infinities, subnormals and huge values.
  double rawDouble() {
    uint64_t v = 0;
    for (int i = 0; i < 8; ++i)
      v |= static_cast<uint64_t>(byte()) << (8 * i);
    double d;
    std::memcpy(&d, &v, sizeof d);
    return d;
  }

  // Mostly plausible seconds (0–20 s in 1/100 s), sometimes a raw double: the interesting cases
  // (loop bounds near the end, seeks inside the title) are reached quickly, the extreme ones too.
  double seconds() {
    const uint8_t kind = byte();
    if (kind < 200)
      return static_cast<double>(u32() % 2001) / 100.0;
    if (kind < 230)
      return -static_cast<double>(u32() % 2001) / 100.0;
    return rawDouble();
  }

  // Next `n` bytes (fewer at the end).
  const uint8_t *take(size_t n, size_t &got) {
    got = n < remaining() ? n : remaining();
    const uint8_t *p = data_ + pos_;
    pos_ += got;
    return p;
  }

private:
  const uint8_t *data_;
  size_t size_;
  size_t pos_ = 0;
};

// One temporary file per process and purpose, in TMPDIR (or the working directory).
inline const std::string &tempFile(const char *purpose) {
  static const std::string dir = [] {
    const char *t = std::getenv("TMPDIR");
    std::string d = t && *t ? t : ".";
    if (d.back() != '/')
      d += '/';
    return d;
  }();
  static thread_local std::string path;
  path = dir + "wp_fuzz_" + purpose + "_" + std::to_string(WP_FUZZ_PID);
  return path;
}

inline bool writeFile(const std::string &path, const uint8_t *data, size_t size) {
  std::FILE *f = std::fopen(path.c_str(), "wb");
  if (!f)
    return false;
  const bool ok = size == 0 || std::fwrite(data, 1, size, f) == size;
  return std::fclose(f) == 0 && ok;
}

} // namespace wp::fuzz
