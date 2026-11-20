// Sanitizer self-test (#57/AK1, AK2): each mode contains one deliberate bug. In a sanitizer build
// the sanitizer must report it and end the program with a non-zero exit code; expect_finding.cmake
// checks both. Proves that a finding in the real tests fails the run.
#include <atomic>
#include <cstdio>
#include <cstring>
#include <memory>
#include <thread>

namespace {
volatile int gSink = 0;
int gShared = 0; // written by two threads without synchronisation (thread mode)

// Fixed order for the race (#63): relaxed atomics create no happens-before edge for TSan, so the
// two writes to gShared stay unordered while the schedule is the same in every run, under load
// too. The second thread still lives when the main thread writes, so TSan can restore both stacks.
std::atomic<int> gStep{0};

void waitForStep(int step) {
  while (gStep.load(std::memory_order_relaxed) < step) {
    std::this_thread::yield();
  }
}

void deterministicRace() {
  std::thread t([] {
    gShared = 1; // first write
    gStep.store(1, std::memory_order_relaxed);
    waitForStep(2); // stay alive until the main thread has written
  });
  waitForStep(1);
  gShared = 2; // second write, races with the first one
  gStep.store(2, std::memory_order_relaxed);
  t.join();
  gSink = gShared;
}
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
    deterministicRace();
  } else {
    std::printf("usage: sanitizer_selftest address|undefined|thread\n");
    return 2;
  }
  std::printf("no finding (mode %s)\n", mode);
  return 0;
}
