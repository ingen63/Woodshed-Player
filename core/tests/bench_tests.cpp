// Performance and load tests of the core (#59), the counterpart of VivaPlan's bench.rs and stress
// test. They run nightly (make bench, ctest -L bench), not in make test: the core only registers
// them with -DWP_BENCH=ON (core/CMakeLists.txt). Measured values: docs/TESTS.md.
//
//   bench_tests stretch    #59/AK1: computing time per buffer (512 frames, 44.1 kHz, stereo) of the
//                          time stretch at the rates 0.1, 0.25, 0.5, 1.0 and 2.0; fails if the mean
//                          (or the 99th percentile) of a rate needs more than 50 % of the
//                          real-time budget (11.6 ms).
//   bench_tests long-file  #59/AK2: a generated 60-minute stereo WAV (written to the temp folder,
//                          deleted afterwards) is loaded, its waveform computed and the whole title
//                          rendered offline; the peak memory is measured against kLongFileLimit.
//   bench_tests memory-limit  #59/AK4: the limit itself works (self-test).
//   bench_tests reserve-fallback  #75/AK1: a 6-minute title still loads when reserving its length
//                          from the header fails (the allocator fails that request once).
//
// #59/AK4: every run has a memory limit, so that a bug cannot bring the machine down:
// - all platforms: the program counts the bytes of every operator new/delete (the decoded audio,
//   the waveform and the stretch buffers are std::vector) and throws std::bad_alloc above the limit
//   of the case; the core turns that into kErrOutOfMemory and the test fails;
// - Linux (workflow): setrlimit(RLIMIT_AS) caps the whole address space as well, so malloc inside
//   miniaudio and everything else counts too. macOS does not enforce RLIMIT_AS (nor RLIMIT_DATA or
//   RLIMIT_RSS) for mmap-based allocations, there the counting allocator is the limit;
// - after each case the peak heap is checked against the limit, the peak resident size (getrusage
//   ru_maxrss) against the limit plus kRssAllowance.
#include <sys/resource.h>

#if defined(__APPLE__)
#include <malloc/malloc.h>
#else
#include <malloc.h>
#endif

#include <algorithm>
#include <atomic>
#include <chrono>
#include <climits>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <memory>
#include <new>
#include <string>
#include <utility>
#include <vector>

#include "engine.hpp"
#include "player_core.hpp"
#include "test_timing.hpp"

#if defined(__unix__) || defined(__APPLE__)
#include <unistd.h>
#endif

namespace {

// ---- Counting allocator with a limit (#59/AK4) ----

// Sizes come from the allocator itself (malloc_size, malloc_usable_size) rather than a header in
// front of the block: libc++ may free memory it allocated before main with this operator delete.
// The counter is signed, so such a block cannot wrap it around.
constexpr std::size_t kMinAlign = alignof(std::max_align_t);
std::atomic<long long> gLive{0};
std::atomic<long long> gPeak{0};
std::atomic<long long> gLimit{LLONG_MAX};
// #75/AK1: the first allocation of at least this many bytes fails once (reserve-fallback)
std::atomic<long long> gFailOnceFrom{LLONG_MAX};

std::size_t blockSize(void *p) {
#if defined(__APPLE__)
  return malloc_size(p);
#else
  return malloc_usable_size(p);
#endif
}

void *countedNew(std::size_t n, std::size_t align) {
  if (static_cast<long long>(n) >= gFailOnceFrom.load(std::memory_order_relaxed) &&
      gFailOnceFrom.exchange(LLONG_MAX) != LLONG_MAX)
    throw std::bad_alloc();
  void *p = nullptr;
  if (posix_memalign(&p, std::max(align, kMinAlign), n ? n : 1) != 0)
    throw std::bad_alloc();
  const auto size = static_cast<long long>(blockSize(p));
  const long long live = gLive.fetch_add(size, std::memory_order_relaxed) + size;
  if (live > gLimit.load(std::memory_order_relaxed)) {
    gLive.fetch_sub(size, std::memory_order_relaxed);
    std::free(p);
    throw std::bad_alloc();
  }
  long long peak = gPeak.load(std::memory_order_relaxed);
  while (live > peak && !gPeak.compare_exchange_weak(peak, live, std::memory_order_relaxed)) {
  }
  return p;
}

void countedDelete(void *p) noexcept {
  if (!p)
    return;
  gLive.fetch_sub(static_cast<long long>(blockSize(p)), std::memory_order_relaxed);
  std::free(p);
}

void *nothrowNew(std::size_t n, std::size_t align) noexcept {
  try {
    return countedNew(n, align);
  } catch (...) {
    return nullptr;
  }
}

} // namespace

void *operator new(std::size_t n) { return countedNew(n, kMinAlign); }
void *operator new[](std::size_t n) { return countedNew(n, kMinAlign); }
void *operator new(std::size_t n, const std::nothrow_t &) noexcept {
  return nothrowNew(n, kMinAlign);
}
void *operator new[](std::size_t n, const std::nothrow_t &) noexcept {
  return nothrowNew(n, kMinAlign);
}
void *operator new(std::size_t n, std::align_val_t a) {
  return countedNew(n, static_cast<std::size_t>(a));
}
void *operator new[](std::size_t n, std::align_val_t a) {
  return countedNew(n, static_cast<std::size_t>(a));
}
void operator delete(void *p) noexcept { countedDelete(p); }
void operator delete[](void *p) noexcept { countedDelete(p); }
void operator delete(void *p, std::size_t) noexcept { countedDelete(p); }
void operator delete[](void *p, std::size_t) noexcept { countedDelete(p); }
void operator delete(void *p, std::align_val_t) noexcept { countedDelete(p); }
void operator delete[](void *p, std::align_val_t) noexcept { countedDelete(p); }
void operator delete(void *p, std::size_t, std::align_val_t) noexcept { countedDelete(p); }
void operator delete[](void *p, std::size_t, std::align_val_t) noexcept { countedDelete(p); }

namespace {

int failures = 0;

#define CHECK(cond)                                                                                \
  do {                                                                                             \
    if (!(cond)) {                                                                                 \
      ++failures;                                                                                  \
      std::printf("  FAILED %s:%d: %s\n", __FILE__, __LINE__, #cond);                              \
    }                                                                                              \
  } while (0)

constexpr std::size_t kMiB = 1024 * 1024;
constexpr int kSr = 44100;
constexpr int kBuffer = 512;
constexpr double kPi = 3.14159265358979323846;
// #59/AK1: share of the real-time budget a rate may need at most
constexpr double kMaxBudgetShare = 0.5;
// #59/AK4: memory limits of the cases (heap and peak resident size)
constexpr std::size_t kStretchLimit = 256 * kMiB;
constexpr int kLongFileMinutes = 60;
// 60 min stereo f32 are 1211 MiB of decoded audio, the waveform 38 MiB more. #75/AK2: at most 1.2
// times the samples. Before #75 the peak was 2425 MiB: beyond the first 5 minutes the decode
// buffer grew geometrically and held 40 and 80 minutes of capacity at once; now the length from
// the header is reserved once after 5 minutes (5 + 60 minutes at once).
constexpr std::size_t kLongFileSamples =
    static_cast<std::size_t>(kLongFileMinutes) * 60 * kSr * 2 * sizeof(float);
constexpr std::size_t kLongFileLimit = kLongFileSamples * 6 / 5;
// The resident size adds code, thread stacks and memory the allocator keeps after a free; on macOS
// it varied by 860 MiB between runs of the same case (memory compression), the heap peak not at
// all.
constexpr std::size_t kRssAllowance = 512 * kMiB;

using Clock = std::chrono::steady_clock;

double seconds(Clock::duration d) { return std::chrono::duration<double>(d).count(); }

std::size_t peakRss() {
  rusage u{};
  getrusage(RUSAGE_SELF, &u);
#if defined(__APPLE__)
  return static_cast<std::size_t>(u.ru_maxrss); // bytes
#else
  return static_cast<std::size_t>(u.ru_maxrss) * 1024; // KiB
#endif
}

// #59/AK4: limit of the process. The counting allocator applies everywhere; on Linux the address
// space is capped as well (with room for code, thread stacks and malloc arenas).
void setMemoryLimit(std::size_t bytes) {
  gLimit.store(static_cast<long long>(bytes));
#if defined(__linux__) && !defined(WP_SANITIZED)
  const rlim_t cap = static_cast<rlim_t>(bytes) + 1024 * kMiB;
  rlimit r{cap, cap};
  if (setrlimit(RLIMIT_AS, &r) != 0)
    std::printf("  setrlimit(RLIMIT_AS) failed, only the counting allocator applies\n");
#endif
  std::printf("  memory limit %zu MiB\n", bytes / kMiB);
}

void checkMemory(const char *name, std::size_t limit) {
  const auto heap = static_cast<std::size_t>(std::max(0LL, gPeak.load()));
  const std::size_t rss = peakRss();
  std::printf("BENCH %s.peak_heap_mib %.1f\n", name, static_cast<double>(heap) / kMiB);
  std::printf("BENCH %s.peak_rss_mib %.1f (limit %zu)\n", name, static_cast<double>(rss) / kMiB,
              (limit + kRssAllowance) / kMiB);
  CHECK(heap <= limit);
  CHECK(rss <= limit + kRssAllowance);
}

// Test signal: two detuned tones per channel and a little noise, so the stretch has partials and
// transients to track (silence would be cheaper than music).
float signal(long long i, int channel, std::uint32_t &noise) {
  noise = noise * 1664525u + 1013904223u;
  const double t = static_cast<double>(i) / kSr;
  const double f = channel == 0 ? 220.0 : 330.0;
  const double env = 0.6 + 0.4 * std::sin(2 * kPi * 0.5 * t);
  const double n = (static_cast<double>(noise >> 8) / (1 << 24) - 0.5) * 0.05;
  return static_cast<float>(
      env * (0.3 * std::sin(2 * kPi * f * t) + 0.2 * std::sin(2 * kPi * f * 1.51 * t)) + n);
}

// ---- #59/AK1: time stretch per buffer ----

void stretchPerBuffer() {
  std::printf("#59/AK1 time stretch per buffer (%d frames, %d Hz, stereo)\n", kBuffer, kSr);
  setMemoryLimit(kStretchLimit);
  constexpr double kSourceSeconds = 120;
  std::vector<float> data(static_cast<std::size_t>(kSourceSeconds * kSr) * 2);
  std::uint32_t noise = 1;
  for (std::size_t i = 0; i < data.size() / 2; ++i) {
    data[i * 2] = signal(static_cast<long long>(i), 0, noise);
    data[i * 2 + 1] = signal(static_cast<long long>(i), 1, noise);
  }
  const double budget = static_cast<double>(kBuffer) / kSr;
  std::vector<float> out(kBuffer * 2);
  constexpr int kWarmup = 200;
  constexpr int kMeasured = 2000; // 23 s of output; at rate 2.0 that reads 46 s of the source
  for (double rate : {0.1, 0.25, 0.5, 1.0, 2.0}) {
    wp::Engine e;
    e.setSource(data, 2, kSr);
    e.setRate(rate);
    e.play();
    for (int i = 0; i < kWarmup; ++i)
      e.render(out.data(), kBuffer);
    std::vector<double> times;
    times.reserve(kMeasured);
    bool finite = true;
    for (int i = 0; i < kMeasured; ++i) {
      const auto t0 = Clock::now();
      e.render(out.data(), kBuffer);
      times.push_back(seconds(Clock::now() - t0));
      for (float x : out)
        finite = finite && std::isfinite(x);
    }
    CHECK(finite);
    CHECK(e.playing());
    double sum = 0;
    for (double t : times)
      sum += t;
    const double mean = sum / kMeasured;
    std::sort(times.begin(), times.end());
    const double p99 = times[static_cast<std::size_t>(kMeasured * 0.99)];
    const double worst = times.back();
    std::printf("BENCH stretch.rate_%.2f mean %.3f ms (%.1f %%), p99 %.3f ms (%.1f %%), max %.3f "
                "ms (%.1f %%)\n",
                rate, mean * 1e3, 100 * mean / budget, p99 * 1e3, 100 * p99 / budget, worst * 1e3,
                100 * worst / budget);
    // the mean is the criterion; the 99th percentile must hold too, so that the uneven block work
    // of the stretch cannot hide behind cheap buffers
    for (const auto &[what, value] : {std::pair{"mean", mean}, std::pair{"p99", p99}}) {
      if (kTimingChecks && value > kMaxBudgetShare * budget) {
        ++failures;
        std::printf(
            "  FAILED rate %.2f: %s needs %.1f %% of the real-time budget (limit %.0f %%)\n", rate,
            what, 100 * value / budget, 100 * kMaxBudgetShare);
      }
    }
  }
  checkMemory("stretch", kStretchLimit);
}

// ---- #59/AK2: a 60-minute file ----

void put16(std::ofstream &f, std::uint16_t v) {
  const char b[2] = {static_cast<char>(v & 0xff), static_cast<char>(v >> 8)};
  f.write(b, 2);
}
void put32(std::ofstream &f, std::uint32_t v) {
  for (int i = 0; i < 4; ++i)
    f.put(static_cast<char>((v >> (8 * i)) & 0xff));
}

// 16-bit PCM WAV, written in blocks (the file is 605 MiB, the program never holds it whole).
bool writeLongWav(const std::string &path, long long frames) {
  std::ofstream f(path, std::ios::binary);
  if (!f)
    return false;
  const auto bytes = static_cast<std::uint32_t>(frames * 4);
  f.write("RIFF", 4);
  put32(f, 36 + bytes);
  f.write("WAVEfmt ", 8);
  put32(f, 16);
  put16(f, 1); // PCM
  put16(f, 2);
  put32(f, kSr);
  put32(f, kSr * 4);
  put16(f, 4);
  put16(f, 16);
  f.write("data", 4);
  put32(f, bytes);
  std::vector<std::int16_t> block(65536 * 2);
  std::uint32_t noise = 7;
  for (long long done = 0; done < frames;) {
    const long long n = std::min<long long>(65536, frames - done);
    for (long long i = 0; i < n; ++i)
      for (int c = 0; c < 2; ++c)
        block[static_cast<std::size_t>(i * 2 + c)] =
            static_cast<std::int16_t>(std::lround(signal(done + i, c, noise) * 32767));
    // WAV is little-endian like every platform the core runs on
    f.write(reinterpret_cast<const char *>(block.data()), static_cast<std::streamsize>(n * 4));
    done += n;
  }
  return static_cast<bool>(f);
}

void longFile() {
  std::printf("#59/AK2 %d-minute stereo file: load, waveform, offline render\n", kLongFileMinutes);
  setMemoryLimit(kLongFileLimit);
  const long long frames = static_cast<long long>(kLongFileMinutes) * 60 * kSr;
  const std::string path =
      (std::filesystem::temp_directory_path() /
       ("wp_bench_long_" + std::to_string(static_cast<long long>(getpid())) + ".wav"))
          .string();
  auto t0 = Clock::now();
  const bool written = writeLongWav(path, frames);
  CHECK(written);
  std::printf("BENCH long_file.write_s %.2f\n", seconds(Clock::now() - t0));
  if (!written) {
    std::filesystem::remove(path);
    return;
  }
  {
    wp::Player p(kSr);
    t0 = Clock::now();
    const int loaded = p.load(path);
    std::printf("BENCH long_file.load_s %.2f (incl. waveform)\n", seconds(Clock::now() - t0));
    std::filesystem::remove(path);
    CHECK(loaded == wp::kOk);
    if (loaded != wp::kOk) {
      std::printf("  load: %s\n", wp::errorMessage(loaded));
      return;
    }
    wp::Engine &e = p.engine();
    CHECK(e.frames() == frames);

    // waveform: overview and a detail range, as the timeline asks for them
    std::vector<float> mins(2000);
    std::vector<float> maxs(2000);
    t0 = Clock::now();
    const int overview = p.waveform(0, e.duration(), 2000, mins.data(), maxs.data());
    const int detail = p.waveform(1800, 1810, 2000, mins.data(), maxs.data());
    std::printf("BENCH long_file.waveform_ms %.2f (2 queries)\n", seconds(Clock::now() - t0) * 1e3);
    CHECK(overview == wp::kOk);
    CHECK(detail == wp::kOk);
    CHECK(*std::max_element(maxs.begin(), maxs.end()) > 0.3f);

    // the whole title offline, at tempo 1.0, until playback stops at the end
    std::vector<float> out(kBuffer * 2);
    e.play();
    long long rendered = 0;
    bool finite = true;
    double energy = 0;
    t0 = Clock::now();
    const long long most = frames + 10 * kSr;
    do {
      p.render(out.data(), kBuffer);
      rendered += kBuffer;
      for (float x : out) {
        finite = finite && std::isfinite(x);
        energy += static_cast<double>(x) * x;
      }
    } while ((e.playing() || rendered < kBuffer * 4) && rendered < most);
    const double renderS = seconds(Clock::now() - t0);
    std::printf("BENCH long_file.render_s %.2f (%.0fx real time)\n", renderS,
                static_cast<double>(frames) / kSr / renderS);
    CHECK(finite);
    CHECK(!e.playing());
    CHECK(rendered >= frames);
    CHECK(rendered < most);
    CHECK(energy / static_cast<double>(rendered * 2) > 0.01);
  }
  checkMemory("long_file", kLongFileLimit);
}

// ---- #75/AK1: a failed reservation falls back to growing ----

void reserveFallback() {
  std::printf("#75/AK1 reserving the header length fails, loading keeps growing\n");
  const long long frames = 6LL * 60 * kSr; // 6 min: decodes to 121 MiB
  const std::string path =
      (std::filesystem::temp_directory_path() /
       ("wp_bench_fallback_" + std::to_string(static_cast<long long>(getpid())) + ".wav"))
          .string();
  CHECK(writeLongWav(path, frames));
  wp::Player p(kSr);
  // above the first 5 minutes (101 MiB) and below the reservation of 6 minutes (121 MiB)
  gFailOnceFrom = 110LL * static_cast<long long>(kMiB);
  const int loaded = p.load(path);
  std::filesystem::remove(path);
  std::printf("  load: %s\n", wp::errorMessage(loaded));
  CHECK(gFailOnceFrom.load() == LLONG_MAX); // the reservation was tried and failed
  CHECK(loaded == wp::kOk);
  CHECK(p.engine().frames() == frames);
  std::vector<float> out(kBuffer * 2);
  p.engine().seek(p.engine().duration() - 1.0);
  p.engine().play();
  p.render(out.data(), kBuffer);
  CHECK(*std::max_element(out.begin(), out.end()) > 0.01f);
}

// ---- #59/AK4: the limit holds ----

void memoryLimitHolds() {
  std::printf("#59/AK4 memory limit self-test\n");
  const std::string path =
      (std::filesystem::temp_directory_path() /
       ("wp_bench_limit_" + std::to_string(static_cast<long long>(getpid())) + ".wav"))
          .string();
  CHECK(writeLongWav(path, 60LL * kSr)); // 1 min, decodes to 20 MiB
  wp::Player p(kSr);
  // the limit is set once (RLIMIT_AS cannot be raised again): 16 MiB above what is in use now
  setMemoryLimit(static_cast<std::size_t>(std::max(0LL, gLive.load())) + 16 * kMiB);
  bool thrown = false;
  try {
    std::vector<float> big(32 * kMiB); // 128 MiB
    big[0] = 1;
  } catch (const std::bad_alloc &) {
    thrown = true;
  }
  CHECK(thrown);
  // the core reports the exhausted limit as an error instead of crashing
  const int loaded = p.load(path);
  std::filesystem::remove(path);
  std::printf("  load under the limit: %s\n", wp::errorMessage(loaded));
  CHECK(loaded == wp::kErrOutOfMemory);
  std::vector<float> small(kMiB); // 4 MiB within the limit
  CHECK(small.size() == kMiB);
#if defined(__linux__) && !defined(WP_SANITIZED)
  // the address space limit (+1 GiB) also stops malloc outside operator new
  void *raw = std::malloc(2048 * kMiB);
  CHECK(raw == nullptr);
  std::free(raw);
#endif
}

} // namespace

int main(int argc, char **argv) {
  const std::string mode = argc > 1 ? argv[1] : "";
  if (mode == "stretch") {
    stretchPerBuffer();
  } else if (mode == "long-file") {
    longFile();
  } else if (mode == "memory-limit") {
    memoryLimitHolds();
  } else if (mode == "reserve-fallback") {
    reserveFallback();
  } else {
    std::printf("usage: bench_tests stretch|long-file|memory-limit|reserve-fallback\n");
    return 2;
  }
  if (!kTimingChecks)
    std::printf("time limits skipped (no optimized build)\n");
  std::printf(failures ? "%d failed\n" : "all passed\n", failures);
  return failures ? 1 : 0;
}
