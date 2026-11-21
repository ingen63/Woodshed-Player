// #10/AK2, AK4: replays fixed inputs through a fuzz target without libFuzzer, as an ordinary ctest
// case in every build (Release, Debug, ASan/UBSan, TSan). Arguments are files or directories; the
// regression inputs come first, then the start corpus. Any finding aborts (WP_FUZZ_CHECK or a
// sanitizer), so the test fails and names the input it was running.
//
// #86: with `--reached <source of the target>` first, it also checks that the inputs together
// reach every C API function the target calls. The functions are read from the source (each call
// is WP_FUZZ_CALL(wp_..., ...), see fuzz_util.hpp), so a new command is checked without a list to
// keep up to date. The test fails and names each function no input reached, and each call to wp_*
// without WP_FUZZ_CALL (it could not be checked).
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <regex>
#include <set>
#include <sstream>
#include <string>
#include <vector>

#include "fuzz_util.hpp"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

namespace fs = std::filesystem;

namespace {

struct CalledApi {
  std::set<std::string> tracked;   // WP_FUZZ_CALL(wp_x, ...)
  std::set<std::string> untracked; // wp_x(...) called directly
};

bool scanSource(const char *path, CalledApi &api) {
  std::ifstream in(path);
  if (!in)
    return false;
  std::stringstream buf;
  buf << in.rdbuf();
  // Comments may name functions with a parenthesis after them; they call nothing.
  std::string code = std::regex_replace(buf.str(), std::regex(R"(//[^\n]*|/\*[\s\S]*?\*/)"), "");
  const std::regex call(R"(WP_FUZZ_CALL\(\s*(wp_\w+)\s*,)");
  for (std::sregex_iterator it(code.begin(), code.end(), call), end; it != end; ++it)
    api.tracked.insert((*it)[1].str());
  code = std::regex_replace(code, call, "");
  const std::regex direct(R"(\b(wp_\w+)\s*\()");
  for (std::sregex_iterator it(code.begin(), code.end(), direct), end; it != end; ++it)
    api.untracked.insert((*it)[1].str());
  return true;
}

} // namespace

int main(int argc, char **argv) {
  int first = 1;
  const char *source = nullptr;
  if (argc > 2 && std::string(argv[1]) == "--reached") {
    source = argv[2];
    first = 3;
    wp::fuzz::reachedApi().tracking = true;
  }
  int runs = 0;
  for (int a = first; a < argc; ++a) {
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
  if (runs == 0)
    return 1;
  if (source == nullptr)
    return 0;

  CalledApi api;
  if (!scanSource(source, api)) {
    std::fprintf(stderr, "cannot read source: %s\n", source);
    return 1;
  }
  if (api.tracked.empty()) {
    std::fprintf(stderr, "no WP_FUZZ_CALL in %s\n", source);
    return 1;
  }
  const std::set<std::string> &reached = wp::fuzz::reachedApi().names;
  size_t notReached = 0;
  for (const auto &name : api.tracked)
    if (reached.count(name) == 0) {
      std::fprintf(stderr, "C API function not reached by any input: %s\n", name.c_str());
      ++notReached;
    }
  for (const auto &name : api.untracked)
    std::fprintf(stderr, "C API function called without WP_FUZZ_CALL: %s\n", name.c_str());
  std::printf("%zu of %zu C API functions reached\n", api.tracked.size() - notReached,
              api.tracked.size());
  return notReached == 0 && api.untracked.empty() ? 0 : 1;
}
