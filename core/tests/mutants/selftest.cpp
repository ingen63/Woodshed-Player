// Self-test of the mutation run (#11/AK4): two functions where one mutant each turns a loop into an
// endless one. Built with Mull like the core (core/build-mutants), together with the memory guard.
// make mutants runs it first and checks the outcome (app/tool/mutants.dart):
// - fill(): `i += 1` becomes `i -= 1`, i wraps around and the loop keeps appending to the vector;
//   the memory guard ends the process (exit code 86), the mutant counts as killed;
// - count(): the same mutation without memory; only the time limit per mutant stops it (timeout).
// Unmutated, both loops run three times and the program ends with 0.
#include <cstddef>
#include <cstdio>
#include <vector>

namespace {

std::vector<std::size_t> fill(std::size_t n) {
  std::vector<std::size_t> v;
  for (std::size_t i = 0; i != n; i += 1)
    v.push_back(i);
  return v;
}

std::size_t count(std::size_t n) {
  volatile std::size_t k = 0; // volatile: the loop is not replaced by a closed form
  for (std::size_t i = 0; i != n; i += 1)
    k = k + 1;
  return k;
}

} // namespace

int main() {
  const bool ok = fill(3).size() == 3 && count(3) == 3;
  std::printf("mutants selftest: %s\n", ok ? "ok" : "FAILED");
  return ok ? 0 : 1;
}
