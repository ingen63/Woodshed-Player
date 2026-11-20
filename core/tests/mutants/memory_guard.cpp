// Memory guard of the mutation build (#11/AK4), linked into every test program of
// core/build-mutants (make mutants). A mutant can turn a loop into an endless one that keeps
// filling a vector; without a limit the test processes of a mutation run can exhaust the memory of
// the machine (in VivaPlan that ended in a kernel panic). macOS does not enforce RLIMIT_AS, and
// several test programs already replace operator new for their own checks (engine_tests,
// realtime_tests), so the limit is a thread that watches the physical footprint of its own
// process: above WP_TEST_MEMORY_LIMIT_MB (default 1024) it prints a message and ends the process
// with exit code 86. Mull counts that as killed (the test fails). On Linux the address space is
// capped as well (limit + 1 GiB, as in bench_tests), so a sudden large allocation fails at once.
//
// The thread polls every 2 ms and allocates nothing while it runs. Touching memory takes time
// (about 1 GiB in 100 ms or more), so the process ends at most a few MiB above the limit.
#if defined(__APPLE__)
#include <mach/mach.h>
#else
#include <sys/resource.h>
#include <unistd.h>
#endif

#include <chrono>
#include <cstddef>
#include <cstdio>
#include <cstdlib>
#include <thread>

namespace {

constexpr std::size_t kMiB = 1024 * 1024;
constexpr int kExitCode = 86;

std::size_t limitBytes() {
  const char *env = std::getenv("WP_TEST_MEMORY_LIMIT_MB");
  const long mib = env != nullptr ? std::strtol(env, nullptr, 10) : 0;
  return static_cast<std::size_t>(mib > 0 ? mib : 1024) * kMiB;
}

// Physical memory of this process (macOS: the footprint that Activity Monitor shows, including
// compressed pages; Linux: the resident set).
std::size_t footprint() {
#if defined(__APPLE__)
  task_vm_info_data_t info{};
  mach_msg_type_number_t count = TASK_VM_INFO_COUNT;
  if (task_info(mach_task_self(), TASK_VM_INFO, reinterpret_cast<task_info_t>(&info), &count) !=
      KERN_SUCCESS)
    return 0;
  return static_cast<std::size_t>(info.phys_footprint);
#else
  std::FILE *f = std::fopen("/proc/self/statm", "r");
  if (f == nullptr)
    return 0;
  unsigned long size = 0;
  unsigned long resident = 0;
  const int n = std::fscanf(f, "%lu %lu", &size, &resident);
  std::fclose(f);
  return n == 2 ? static_cast<std::size_t>(resident) * static_cast<std::size_t>(getpagesize()) : 0;
#endif
}

struct MemoryGuard {
  MemoryGuard() {
    const std::size_t limit = limitBytes();
#if defined(__linux__) && !defined(WP_SANITIZED)
    const rlim_t cap = static_cast<rlim_t>(limit + 1024 * kMiB);
    rlimit r{cap, cap};
    setrlimit(RLIMIT_AS, &r);
#endif
    std::thread([limit] {
      for (;;) {
        const std::size_t used = footprint();
        if (used > limit) {
          std::fprintf(stderr, "memory guard (#11): %zu MiB in use, limit %zu MiB\n", used / kMiB,
                       limit / kMiB);
          std::_Exit(kExitCode);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(2));
      }
    }).detach();
  }
};

const MemoryGuard gGuard;

} // namespace
