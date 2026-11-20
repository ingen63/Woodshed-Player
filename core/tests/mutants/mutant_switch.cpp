// Fast mutant switch of the mutation build (#11/AK3), linked into every test program of
// core/build-mutants together with the memory guard.
//
// Mull compiles every mutated function into a trampoline that asks getenv(<mutant id>) on every
// call which variant to run; mull-runner activates a mutant by setting the environment variable of
// that name. In the render loops (per sample) that is millions of getenv calls, each taking the
// environment lock of libc: the metronome tests needed 65 s instead of 0.7 s, the engine tests did
// not finish within 200 s. This getenv answers the mutant ids (names starting with «cxx_», the
// prefix of every Mull mutator) from the list read once from the environment at the first call;
// every other name goes to the getenv of libc. The program defines getenv itself, so the linker
// binds the calls of the statically linked core to it; the shared library wp_core (capi_tests)
// keeps the libc getenv (its tests are short). Nothing changes which mutant runs, only how fast
// the answer comes.
#include <dlfcn.h>

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <cstring>

#if defined(__APPLE__)
#include <crt_externs.h>
#else
extern char **environ; // NOLINT(readability-redundant-declaration): POSIX declares it nowhere
#endif

namespace {

constexpr const char kPrefix[] = "cxx_";
constexpr std::size_t kPrefixLength = sizeof(kPrefix) - 1;
constexpr int kMaxActive = 8;

using GetenvFn = char *(*)(const char *);

struct Active {
  const char *names[kMaxActive] = {};       // "<mutant id>=<value>" entries of the environment
  std::size_t nameLengths[kMaxActive] = {}; // length of the id part
  int count = 0;
};

char **environment() {
#if defined(__APPLE__)
  return *_NSGetEnviron();
#else
  return environ;
#endif
}

// The mutant ids set when the program started (mull-runner sets one per run).
const Active &active() {
  static const Active list = [] {
    Active a;
    for (char **e = environment(); e != nullptr && *e != nullptr && a.count < kMaxActive; ++e) {
      if (std::strncmp(*e, kPrefix, kPrefixLength) != 0)
        continue;
      const char *eq = std::strchr(*e, '=');
      if (eq == nullptr)
        continue;
      a.names[a.count] = *e;
      a.nameLengths[a.count] = static_cast<std::size_t>(eq - *e);
      ++a.count;
    }
    return a;
  }();
  return list;
}

// Mutant ids known to be inactive: Mull passes the same constant string of a mutant on every call,
// so the address is the key. Direct-mapped, without locks: a stored address only ever means
// «inactive» (the active mutants do not change while the program runs), so a race between two
// threads writing one slot only loses a cache entry. Active ids always take the comparison.
constexpr std::size_t kSlots = 1 << 14;
std::atomic<const char *> gInactive[kSlots];

std::size_t slotOf(const char *name) {
  return (reinterpret_cast<std::uintptr_t>(name) >> 3) & (kSlots - 1);
}

char *lookup(const char *name) {
  const Active &a = active();
  const std::size_t n = std::strlen(name);
  for (int i = 0; i < a.count; ++i) {
    if (a.nameLengths[i] == n && std::strncmp(a.names[i], name, n) == 0)
      return const_cast<char *>(a.names[i] + n + 1);
  }
  return nullptr;
}

GetenvFn libcGetenv() {
  static const auto fn = reinterpret_cast<GetenvFn>(dlsym(RTLD_NEXT, "getenv"));
  return fn;
}

} // namespace

// NOLINTNEXTLINE(bugprone-reserved-identifier,cert-dcl37-c,cert-dcl51-cpp): replaces libc's getenv
extern "C" char *getenv(const char *name) {
  if (name != nullptr && std::strncmp(name, kPrefix, kPrefixLength) == 0) {
    std::atomic<const char *> &slot = gInactive[slotOf(name)];
    if (slot.load(std::memory_order_relaxed) == name)
      return nullptr;
    char *value = lookup(name);
    if (value == nullptr)
      slot.store(name, std::memory_order_relaxed);
    return value;
  }
  return libcGetenv()(name);
}
