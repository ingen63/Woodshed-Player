// #101: whether a test program may replace the global operator new/delete. The ThreadSanitizer
// runtime brings its own operators (on Linux linked statically from libclang_rt.tsan_cxx), so a
// replacement fails to link with "multiple definition of operator delete". Under TSan the test
// programs keep the runtime's operators and skip the checks that need their own (allocation
// counts, failing allocations, memory limits); those run in the normal and the ASan/UBSan builds.
#pragma once

#if defined(__SANITIZE_THREAD__)
#define WP_REPLACE_NEW 0
#elif defined(__has_feature)
#if __has_feature(thread_sanitizer)
#define WP_REPLACE_NEW 0
#endif
#endif

#ifndef WP_REPLACE_NEW
#define WP_REPLACE_NEW 1
#endif
