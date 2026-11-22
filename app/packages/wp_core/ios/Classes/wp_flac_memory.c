// libFLAC (#113), built with the core's config.h (core/src/flac_config).
#define HAVE_CONFIG_H 1
// Third-party code: its warnings are not ours (same as SYSTEM in core/CMakeLists.txt).
#pragma clang diagnostic ignored "-Weverything"
#include "../../../../../core/third_party/flac/src/libFLAC/memory.c"
