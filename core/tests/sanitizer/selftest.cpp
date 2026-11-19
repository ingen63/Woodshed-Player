// Sanitizer self-test (#57/AK1, AK2): each mode contains one deliberate bug. In a sanitizer build
// the sanitizer must report it and end the program with a non-zero exit code; expect_finding.cmake
// checks both. Proves that a finding in the real tests fails the run.
#include <cstdio>
#include <cstring>
#include <memory>
#include <thread>

namespace {
volatile int gSink = 0;
int gShared = 0; // written by two threads without synchronisation (thread mode)
} // namespace

int main(int argc, char **argv) {
  const char *mode = argc > 1 ? argv[1] : "";
  if (std::strcmp(mode, "address") == 0) {
    auto buf = std::make_unique<int[]>(4);
    const int i = 4 + gSink; // one past the end, not visible to the compiler
    gSink = buf[i];          // heap-buffer-overflow
  } else if (std::strcmp(mode, "undefined") == 0) {
    int big = 0x7fffffff - gSink;
    big += 1 + gSink; // signed integer overflow
    gSink = big;
  } else if (std::strcmp(mode, "thread") == 0) {
    std::thread t([] { gShared = 1; }); // data race with the write below
    gShared = 2;
    t.join();
    gSink = gShared;
  } else {
    std::printf("usage: sanitizer_selftest address|undefined|thread\n");
    return 2;
  }
  std::printf("no finding (mode %s)\n", mode);
  return 0;
}
