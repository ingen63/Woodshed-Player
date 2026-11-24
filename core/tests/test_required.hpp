// #125: checks that need something special (an audio device, an optimized build) are skipped with a
// reason in the output. In the CI job that provides the resource, a variable
// WP_<RESOURCE>_REQUIRED=1 turns the skip into a failure. Unset or empty: skip; 1: required; any
// other value: failure that names the variable and the allowed value. The Dart side:
// app/test/required_resource.dart. Variables, tests and jobs: docs/TESTS.md «Pflicht-Variablen
// (#125)».
#pragma once

#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace wptest {

constexpr const char *kAudioDeviceRequired = "WP_AUDIO_DEVICE_REQUIRED";
constexpr const char *kOptimizedBuildRequired = "WP_OPTIMIZED_BUILD_REQUIRED";
constexpr const char *kLameRequired = "WP_LAME_REQUIRED"; // #141: MP3 encoder (tools/build-lame.sh)

enum class Requirement { Optional, Required, Invalid };

inline Requirement requirement(const char *value) {
  if (value == nullptr || *value == '\0')
    return Requirement::Optional;
  if (std::strcmp(value, "1") == 0)
    return Requirement::Required;
  return Requirement::Invalid;
}

// Whether the checks that need the resource can run. Without it they are skipped with [reason]
// in the output; a failure is counted if [variable] is 1 or its value is invalid.
inline bool needs(const char *variable, bool available, const char *reason, int &failures,
                  std::FILE *out = stdout) {
  const char *value = std::getenv(variable); // NOLINT(concurrency-mt-unsafe): no thread sets it
  switch (requirement(value)) {
  case Requirement::Invalid:
    std::fprintf(out, "  FAILED %s=%s is not allowed: use 1 (required) or leave it empty (skip)\n",
                 variable, value);
    ++failures;
    return false;
  case Requirement::Required:
    if (!available) {
      std::fprintf(out, "  FAILED %s, but %s=1 requires it\n", reason, variable);
      ++failures;
    }
    return available;
  case Requirement::Optional:
    if (!available)
      std::fprintf(out, "  skipped: %s (set %s=1 to require it)\n", reason, variable);
    return available;
  }
  return false;
}

} // namespace wptest
