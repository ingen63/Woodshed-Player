// #10/AK2, AK4: replays fixed inputs through a fuzz target without libFuzzer, as an ordinary ctest
// case in every build (Release, Debug, ASan/UBSan, TSan). Arguments are files or directories; the
// regression inputs come first, then the start corpus. Any finding aborts (WP_FUZZ_CHECK or a
// sanitizer), so the test fails and names the input it was running.
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

namespace fs = std::filesystem;

int main(int argc, char **argv) {
  int runs = 0;
  for (int a = 1; a < argc; ++a) {
    std::vector<fs::path> files;
    const fs::path arg = argv[a];
    if (fs::is_directory(arg)) {
      for (const auto &e : fs::directory_iterator(arg))
        if (e.is_regular_file() && e.path().filename().string()[0] != '.')
          files.push_back(e.path());
      std::sort(files.begin(), files.end());
    } else if (fs::is_regular_file(arg)) {
      files.push_back(arg);
    } else {
      std::fprintf(stderr, "missing input: %s\n", argv[a]);
      return 1;
    }
    for (const auto &f : files) {
      std::ifstream in(f, std::ios::binary);
      const std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(in)),
                                       std::istreambuf_iterator<char>());
      std::fprintf(stderr, "replay %s (%zu bytes)\n", f.string().c_str(), bytes.size());
      LLVMFuzzerTestOneInput(bytes.data(), bytes.size());
      ++runs;
    }
  }
  std::printf("%d inputs replayed without finding\n", runs);
  return runs > 0 ? 0 : 1;
}
