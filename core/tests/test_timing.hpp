// Time limits in the tests (#57). They only hold in optimized builds without sanitizers; Debug
// and sanitizer builds (make test-core-debug, make sanitize, make sanitize-thread) run the same
// cases with the same audio tolerances but skip the time limits. Release (make test) checks them.
// #125: the skip is reported; WP_OPTIMIZED_BUILD_REQUIRED=1 (job «bench») makes it a failure.
#pragma once

#include "test_required.hpp"

// #60: not with MSVC either: the limits are calibrated on clang (macOS and Linux, where the jobs
// «checks» and «bench» measure them); the Windows job checks behaviour only. The counter-check of
// #159 runs on a scripted clock and does not depend on this switch.
#if defined(NDEBUG) && !defined(WP_SANITIZED) && !defined(_MSC_VER)
constexpr bool kTimingChecks = true;
#else
constexpr bool kTimingChecks = false;
#endif

// Reports once per test program whether the time limits run (see test_required.hpp).
inline void reportTimingChecks(int &failures) {
  wptest::needs(wptest::kOptimizedBuildRequired, kTimingChecks,
                "no optimized build, time limits skipped", failures);
}
