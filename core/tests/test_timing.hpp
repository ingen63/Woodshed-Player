// Time limits in the tests (#57). They only hold in optimized builds without sanitizers; Debug
// and sanitizer builds (make test-core-debug, make sanitize, make sanitize-thread) run the same
// cases with the same audio tolerances but skip the time limits. Release (make test) checks them.
#pragma once

#if defined(NDEBUG) && !defined(WP_SANITIZED)
constexpr bool kTimingChecks = true;
#else
constexpr bool kTimingChecks = false;
#endif
