// Real-time safety of the render path (#57/AK4): wp::Player::render() is what the audio device
// callback calls (src/player.cpp). While it renders offline with tempo != 1, a loop, the metronome,
// seeks and a title change, the render thread must not allocate or free memory and must not take a
// blocking lock.
//
// Counted in the render thread only:
// - every replaceable operator new/delete (all platforms, all builds except ThreadSanitizer,
//   whose runtime brings its own: #101, replace_new.hpp);
// - on Linux with glibc and without sanitizers also malloc, calloc, realloc, free, posix_memalign,
//   aligned_alloc and pthread_mutex_lock (the sanitizers bring their own malloc and lock hooks).
// On macOS malloc and locks cannot be interposed from the test program; there the operator new
// count and the lock-free atomics below apply, the Linux run in the workflow covers the rest.
#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <new>
#include <vector>

#include "player_core.hpp"
#include "replace_new.hpp"

#if defined(__linux__) && defined(__GLIBC__) && !defined(WP_SANITIZED)
#define WP_COUNT_LIBC 1
#include <dlfcn.h>
#include <pthread.h>
#else
#define WP_COUNT_LIBC 0
#endif

namespace {
thread_local bool tCount = false;
std::atomic<long> gAllocs{0};
std::atomic<long> gLocks{0};

#if WP_REPLACE_NEW
void *countedNew(std::size_t n) {
  if (tCount)
    gAllocs.fetch_add(1, std::memory_order_relaxed);
  if (void *p = std::malloc(n ? n : 1))
    return p;
  throw std::bad_alloc();
}
void *countedNewAligned(std::size_t n, std::align_val_t al) {
  if (tCount)
    gAllocs.fetch_add(1, std::memory_order_relaxed);
  void *p = nullptr;
  const std::size_t a = std::max(static_cast<std::size_t>(al), sizeof(void *));
  if (posix_memalign(&p, a, n ? n : 1) == 0)
    return p;
  throw std::bad_alloc();
}
void countedDelete(void *p) noexcept {
  if (p && tCount)
    gAllocs.fetch_add(1, std::memory_order_relaxed);
  std::free(p);
}
#endif
} // namespace

#if WP_REPLACE_NEW
void *operator new(std::size_t n) { return countedNew(n); }
void *operator new[](std::size_t n) { return countedNew(n); }
void *operator new(std::size_t n, const std::nothrow_t &) noexcept {
  try {
    return countedNew(n);
  } catch (...) {
    return nullptr;
  }
}
void *operator new[](std::size_t n, const std::nothrow_t &) noexcept {
  try {
    return countedNew(n);
  } catch (...) {
    return nullptr;
  }
}
void *operator new(std::size_t n, std::align_val_t a) { return countedNewAligned(n, a); }
void *operator new[](std::size_t n, std::align_val_t a) { return countedNewAligned(n, a); }
void operator delete(void *p) noexcept { countedDelete(p); }
void operator delete[](void *p) noexcept { countedDelete(p); }
void operator delete(void *p, std::size_t) noexcept { countedDelete(p); }
void operator delete[](void *p, std::size_t) noexcept { countedDelete(p); }
void operator delete(void *p, std::align_val_t) noexcept { countedDelete(p); }
void operator delete[](void *p, std::align_val_t) noexcept { countedDelete(p); }
void operator delete(void *p, std::size_t, std::align_val_t) noexcept { countedDelete(p); }
void operator delete[](void *p, std::size_t, std::align_val_t) noexcept { countedDelete(p); }
#endif

#if WP_COUNT_LIBC
// glibc declares these functions noexcept (__THROW) and exports its allocator as __libc_*; the
// wrappers count and forward without dlsym, so there is no recursion. pthread_mutex_lock is looked
// up once before counting starts.
extern "C" {
void *__libc_malloc(size_t);           // NOLINT(bugprone-reserved-identifier)
void *__libc_calloc(size_t, size_t);   // NOLINT(bugprone-reserved-identifier)
void *__libc_realloc(void *, size_t);  // NOLINT(bugprone-reserved-identifier)
void *__libc_memalign(size_t, size_t); // NOLINT(bugprone-reserved-identifier)
void __libc_free(void *);              // NOLINT(bugprone-reserved-identifier)

void *malloc(size_t n) noexcept {
  if (tCount)
    gAllocs.fetch_add(1, std::memory_order_relaxed);
  return __libc_malloc(n);
}
void *calloc(size_t c, size_t n) noexcept {
  if (tCount)
    gAllocs.fetch_add(1, std::memory_order_relaxed);
  return __libc_calloc(c, n);
}
void *realloc(void *p, size_t n) noexcept {
  if (tCount)
    gAllocs.fetch_add(1, std::memory_order_relaxed);
  return __libc_realloc(p, n);
}
void free(void *p) noexcept {
  if (p && tCount)
    gAllocs.fetch_add(1, std::memory_order_relaxed);
  __libc_free(p);
}
int posix_memalign(void **out, size_t a, size_t n) noexcept {
  if (tCount)
    gAllocs.fetch_add(1, std::memory_order_relaxed);
  void *p = __libc_memalign(a, n);
  if (!p)
    return 12; // ENOMEM
  *out = p;
  return 0;
}
void *aligned_alloc(size_t a, size_t n) noexcept {
  if (tCount)
    gAllocs.fetch_add(1, std::memory_order_relaxed);
  return __libc_memalign(a, n);
}

using LockFn = int (*)(pthread_mutex_t *);
LockFn realLock() {
  static const LockFn fn = reinterpret_cast<LockFn>(dlsym(RTLD_NEXT, "pthread_mutex_lock"));
  return fn;
}
int pthread_mutex_lock(pthread_mutex_t *m) noexcept {
  if (tCount)
    gLocks.fetch_add(1, std::memory_order_relaxed);
  return realLock()(m);
}
} // extern "C"
#endif

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

// The audio thread only shares atomics with the control threads. A std::atomic that is not
// lock-free would hide a lock in the render path.
static_assert(std::atomic<bool>::is_always_lock_free, "atomic<bool> must be lock-free");
static_assert(std::atomic<int>::is_always_lock_free, "atomic<int> must be lock-free");
static_assert(std::atomic<long long>::is_always_lock_free, "atomic<long long> must be lock-free");
static_assert(std::atomic<float>::is_always_lock_free, "atomic<float> must be lock-free");
static_assert(std::atomic<double>::is_always_lock_free, "atomic<double> must be lock-free");
static_assert(std::atomic<std::size_t>::is_always_lock_free, "atomic<size_t> must be lock-free");

constexpr int kSr = 48000;
constexpr double kPi = 3.14159265358979323846;

std::unique_ptr<wp::Source> sine(double freq, double seconds) {
  auto s = std::make_unique<wp::Source>();
  s->frames = static_cast<long long>(seconds * kSr);
  s->data.resize(static_cast<size_t>(s->frames) * 2);
  for (long long i = 0; i < s->frames; ++i) {
    const float v = static_cast<float>(0.5 * std::sin(2 * kPi * freq * i / kSr));
    s->data[i * 2] = v;
    s->data[i * 2 + 1] = v;
  }
  return s;
}

// #57/AK4: 0 allocations and 0 blocking locks in Player::render() with tempo != 1, loop and
// metronome (with subdivisions, accents, ramp), seeks, volume and a title change.
void renderPathIsRealtimeSafe() {
  wp::Player p(kSr);
  CHECK(p.setSource(sine(440, 6.0)) == wp::kOk); // waveform is computed here, not counted
  wp::Engine &e = p.engine();
  wp::Metronome &m = p.metronome();
  auto next = sine(220, 5.0);
  std::vector<float> out(512 * 2);
  long long rendered = 0;
  bool finite = true;
  auto block = [&](int n) {
    for (int i = 0; i < n; ++i) {
      p.render(out.data(), 512);
      rendered += 512;
      for (float x : out)
        finite = finite && std::isfinite(x);
    }
  };

  gAllocs = 0;
  gLocks = 0;
  tCount = true; // from here on this thread is the audio thread; commands go through the queues
  m.setMeter(3);
  m.setSubdivision(4);
  m.setRamp(true, 80, 120, 10, 1);
  m.start();
  e.setLoop(1.0, 3.0);
  e.setRate(0.75); // tempo != 1: time stretching
  e.play();
  block(200); // about 2.1 s of output, several loop passes at 0.75
  e.setRate(1.5);
  e.seek(2.5);
  block(150);
  e.setVolume(0.5f);
  m.setTimedRamp(true, 90, 140, 10);
  m.setVolume(0.3f);
  e.setRate(0.5);
  block(100);
  tCount = false;

  // A new title is submitted from a control thread (allocated there); installing it and retiring
  // the old one in the render thread allocates nothing either.
  const long long passesBefore = e.loopPasses();
  CHECK(e.submitSource(std::move(next)));
  tCount = true;
  block(5);
  e.setLoop(1.0, 2.5);
  e.setRate(1.25);
  e.play();
  block(150);
  tCount = false;

  CHECK(gAllocs.load() == 0);
  CHECK(gLocks.load() == 0);
  if (gAllocs.load() != 0 || gLocks.load() != 0)
    std::printf("  render thread: %ld allocations or frees, %ld mutex locks\n", gAllocs.load(),
                gLocks.load());
  e.collectGarbage();
  // The scenario really ran: output finite, both titles loaded, the loop was passed.
  CHECK(finite);
  CHECK(rendered == 605LL * 512);
  CHECK(std::fabs(e.duration() - 5.0) < 1e-9);
  CHECK(e.playing());
  CHECK(e.rate() == 1.25);
  CHECK(passesBefore >= 1);
  CHECK(e.position() >= 1.0 - 1e-6 && e.position() <= 2.5 + 1e-6);
}

// The counter itself works: an allocation in the counted thread is seen (also through malloc on
// Linux), so 0 above is not an artefact of a broken hook.
void counterSeesAllocations() {
  if (!WP_REPLACE_NEW) {
    std::printf("  skipped: no operator new of its own under ThreadSanitizer (#101)\n");
    return;
  }
  gAllocs = 0;
  tCount = true;
  auto *v = new std::vector<int>(100);
  delete v;
  tCount = false;
  CHECK(gAllocs.load() >= 4); // vector object and its buffer, each allocated and freed
#if WP_COUNT_LIBC
  gAllocs = 0;
  gLocks = 0;
  tCount = true;
  void *raw = std::malloc(64);
  std::free(raw);
  pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;
  pthread_mutex_lock(&mu);
  pthread_mutex_unlock(&mu);
  tCount = false;
  CHECK(gAllocs.load() == 2);
  CHECK(gLocks.load() == 1);
#endif
}

} // namespace

int main() {
  counterSeesAllocations();
  std::printf("%s counterSeesAllocations\n", failures == 0 ? "ok  " : "FAIL");
  const int before = failures;
  renderPathIsRealtimeSafe();
  std::printf("%s renderPathIsRealtimeSafe\n", failures == before ? "ok  " : "FAIL");
  std::printf("libc hooks (malloc, pthread_mutex_lock): %s\n", WP_COUNT_LIBC ? "on" : "off");
  std::printf("%d checks, %d failures\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
