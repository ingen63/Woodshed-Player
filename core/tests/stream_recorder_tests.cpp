// Recording in the browser (#157): StreamRecorder with generated sine and silence, the FLAC put
// together from its pieces as the web worker stores them and decoded again by the core. No audio
// device, no file. Runs natively and under WASM (core/web/web.cmake).
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <memory>
#include <vector>

#include "player_core.hpp"
#include "stream_recorder.hpp"
#include "wp_core.h"

namespace {

int failures = 0;
int checks = 0;

#define CHECK(cond)                                                                                \
  do {                                                                                             \
    ++checks;                                                                                      \
    if (!(cond)) {                                                                                 \
      ++failures;                                                                                  \
      std::printf("  FAILED %s:%d: %s\n", __FILE__, __LINE__, #cond);                              \
    }                                                                                              \
  } while (0)

using wp::rec::GateConfig;
using wp::rec::StreamRecorder;

constexpr double kPi = 3.14159265358979323846;
constexpr uint32_t kRate = 48000;
// One step of a 24-bit sample.
constexpr double kStep24 = 1.0 / 8388607.0;
// Start and end of the kept audio within ±10 ms.
constexpr long long kTolerance = kRate / 100;

long long frames(double seconds) { return std::llround(seconds * kRate); }

// Interleaved test signal of `channels` channels from parts of sine and silence.
class Signal {
public:
  explicit Signal(uint32_t channels = 2) : channels_(channels) {}
  // `seconds` of a sine of `hz` with peak `amplitude`; starts at its peak.
  Signal &tone(double seconds, float amplitude = 0.5f, double hz = 440.0) {
    const auto n = frames(seconds);
    for (long long i = 0; i < n; ++i) {
      const auto v = static_cast<float>(amplitude * std::cos(2.0 * kPi * hz * i / kRate));
      for (uint32_t c = 0; c < channels_; ++c)
        samples_.push_back(c == 0 ? v : -v);
    }
    return *this;
  }
  Signal &silence(double seconds) {
    samples_.insert(samples_.end(), static_cast<size_t>(frames(seconds)) * channels_, 0.0f);
    return *this;
  }
  [[nodiscard]] const std::vector<float> &samples() const { return samples_; }
  [[nodiscard]] uint32_t frameCount() const {
    return static_cast<uint32_t>(samples_.size() / channels_);
  }
  [[nodiscard]] uint32_t channels() const { return channels_; }

private:
  uint32_t channels_;
  std::vector<float> samples_;
};

// The file as the worker stores it: each piece at its offset, the header over the start at the end.
struct Stored {
  std::vector<uint8_t> file;
  int pieces = 0;
  void store(StreamRecorder &r) {
    if (r.outSize() == 0)
      return;
    const auto at = static_cast<size_t>(r.outOffset());
    CHECK(at == file.size()); // pieces come in order, without gaps
    file.resize(std::max(file.size(), at + r.outSize()));
    std::copy(r.out(), r.out() + r.outSize(), file.begin() + static_cast<std::ptrdiff_t>(at));
    r.take();
    ++pieces;
  }
  void close(StreamRecorder &r) {
    store(r);
    CHECK(r.headerSize() <= file.size());
    std::copy(r.header(), r.header() + r.headerSize(), file.begin());
  }
};

// Feeds `signal` in blocks of `block` frames, storing after each block; finishes unless told not
// to.
Stored record(StreamRecorder &r, const Signal &signal, uint32_t block = 128, bool finish = true) {
  Stored s;
  const uint32_t total = signal.frameCount();
  for (uint32_t done = 0; done < total;) {
    const uint32_t n = std::min(block, total - done);
    CHECK(r.feed(signal.samples().data() + static_cast<size_t>(done) * signal.channels(), n));
    s.store(r);
    done += n;
  }
  if (finish) {
    CHECK(r.finish());
    s.close(r);
  }
  return s;
}

// Decodes the FLAC with the core (stereo at kRate).
wp::Source decode(const std::vector<uint8_t> &file) {
  wp::Source out;
  CHECK(wp::decodeMemory(file.data(), file.size(), kRate, out) == WP_OK);
  return out;
}

// Sample count of the stream info (36 bits from byte 21).
uint64_t headerTotal(const std::vector<uint8_t> &file) {
  uint64_t v = file[21] & 0x0F;
  for (size_t i = 22; i < 26; ++i)
    v = (v << 8) | file[i];
  return v;
}

bool md5Unknown(const std::vector<uint8_t> &file) {
  return std::all_of(file.begin() + 26, file.begin() + 42, [](uint8_t b) { return b == 0; });
}

long long firstAbove(const wp::Source &s, float threshold) {
  for (long long i = 0; i < s.frames; ++i)
    if (std::fabs(s.data[static_cast<size_t>(i) * 2]) > threshold)
      return i;
  return -1;
}

long long lastAbove(const wp::Source &s, float threshold) {
  for (long long i = s.frames - 1; i >= 0; --i)
    if (std::fabs(s.data[static_cast<size_t>(i) * 2]) > threshold)
      return i;
  return -1;
}

bool near(long long actual, long long expected) {
  return std::llabs(actual - expected) <= kTolerance;
}

const float kThreshold = wp::rec::SoundGate::linear(-30.0);

// ---- Without arming: the record button ----

// #157/AK3: every frame goes into a FLAC file that the core plays; the samples come back within one
// 24-bit step, the stream info has the length and an MD5.
void plainRecordingIsLosslessFlac() {
  StreamRecorder r;
  CHECK(r.start(kRate, 2, nullptr));
  CHECK(r.gate() == WP_REC_GATE_OFF);
  Signal sig;
  sig.tone(0.5, 0.25f, 1000.0).silence(0.25).tone(0.25);
  Stored s = record(r, sig);
  CHECK(s.pieces > 1); // stored in blocks while recording, not at the end
  CHECK(r.frames() == sig.frameCount());
  CHECK(r.keptFrames() == sig.frameCount());
  const wp::Source d = decode(s.file);
  CHECK(d.frames == sig.frameCount());
  double maxDiff = 0;
  for (size_t i = 0; i < sig.samples().size() && i < d.data.size(); ++i)
    maxDiff = std::max(maxDiff, std::fabs(static_cast<double>(d.data[i]) - sig.samples()[i]));
  CHECK(maxDiff <= kStep24);
  CHECK(headerTotal(s.file) == sig.frameCount());
  CHECK(!md5Unknown(s.file));
  CHECK(s.file[0] == 'f' && s.file[1] == 'L' && s.file[2] == 'a' && s.file[3] == 'C');
}

// #157/AK2: a 1 kHz sine at -12 dBFS arrives with its level (±1 dB, here exact to a 24-bit step).
void levelArrivesUnchanged() {
  StreamRecorder r;
  CHECK(r.start(kRate, 2, nullptr));
  const auto amp = static_cast<float>(std::pow(10.0, -12.0 / 20.0));
  Signal sig;
  sig.tone(1.0, amp, 1000.0);
  const wp::Source d = decode(record(r, sig, 4096).file);
  float peak = 0;
  for (float v : d.data)
    peak = std::max(peak, std::fabs(v));
  const double db = 20.0 * std::log10(peak);
  CHECK(std::fabs(db - -12.0) <= 0.01);
}

// Mono input (a single microphone channel) becomes a mono FLAC that plays on both channels.
void monoInput() {
  StreamRecorder r;
  CHECK(r.start(kRate, 1, nullptr));
  Signal sig(1);
  sig.tone(0.2);
  const wp::Source d = decode(record(r, sig).file);
  CHECK(d.frames == sig.frameCount());
  CHECK(std::fabs(d.data[0] - 0.5f) <= kStep24 && std::fabs(d.data[1] - 0.5f) <= kStep24);
}

// Nothing taken until the end: the whole file is one piece, the stream info already rewritten in
// it.
void finishBeforeTakingRewritesThePiece() {
  StreamRecorder r;
  CHECK(r.start(kRate, 2, nullptr));
  Signal sig;
  sig.tone(0.3);
  for (uint32_t done = 0; done < sig.frameCount(); done += 100)
    CHECK(r.feed(sig.samples().data() + static_cast<size_t>(done) * 2,
                 std::min<uint32_t>(100, sig.frameCount() - done)));
  CHECK(r.finish());
  CHECK(r.outOffset() == 0);
  std::vector<uint8_t> whole(r.out(), r.out() + r.outSize());
  CHECK(std::equal(r.header(), r.header() + r.headerSize(), whole.begin()));
  CHECK(headerTotal(whole) == sig.frameCount());
  CHECK(decode(whole).frames == sig.frameCount());
}

// Level for the meter: the highest peak since the last call, then 0; only silence until a sample
// rises above the silence threshold.
void levelAndSilence() {
  StreamRecorder r;
  CHECK(r.start(kRate, 2, nullptr));
  Signal quiet;
  quiet.silence(0.1);
  CHECK(r.feed(quiet.samples().data(), quiet.frameCount()));
  CHECK(r.onlySilence());
  CHECK(r.takeLevel() == 0.0f);
  Signal loud;
  loud.tone(0.1, 0.25f);
  CHECK(r.feed(loud.samples().data(), loud.frameCount()));
  CHECK(!r.onlySilence());
  CHECK(std::fabs(r.takeLevel() - 0.25f) < 1e-6f);
  CHECK(r.takeLevel() == 0.0f);
  CHECK(r.feed(quiet.samples().data(), quiet.frameCount()));
  CHECK(!r.onlySilence()); // stays false once sound came
  CHECK(r.finish());
}

// A second start begins a new file: nothing of the first one is left in the pieces or the header.
void startAgainBeginsANewFile() {
  StreamRecorder r;
  CHECK(r.start(kRate, 2, nullptr));
  const size_t head = r.outSize(); // only the header so far
  CHECK(head > 0 && r.headerSize() == head);
  Signal sig;
  sig.tone(0.2);
  CHECK(r.feed(sig.samples().data(), sig.frameCount()));
  CHECK(r.outSize() > head);
  CHECK(r.start(kRate, 2, nullptr));
  CHECK(r.outSize() == head);
  CHECK(r.headerSize() == head);
  CHECK(r.outOffset() == 0);
}

// The peak covers every sample of the block (also the last one of the last channel); a peak exactly
// at the silence threshold is still silence.
void peakOverTheWholeBlock() {
  StreamRecorder r;
  CHECK(r.start(kRate, 2, nullptr));
  std::vector<float> block(2 * 256, 0.0f);
  block.back() = 0.25f;
  CHECK(r.feed(block.data(), 256));
  CHECK(std::fabs(r.takeLevel() - 0.25f) < 1e-6f);
  StreamRecorder q;
  CHECK(q.start(kRate, 2, nullptr));
  std::vector<float> edge(2 * 16, wp::rec::kStreamSilenceThreshold);
  CHECK(q.feed(edge.data(), 16));
  CHECK(q.onlySilence());
}

// FLAC with 16 bits through a sink; other depths are refused.
class Bytes final : public wp::FlacSink {
public:
  bool write(uint64_t offset, const uint8_t *data, size_t size, uint32_t) override {
    if (offset + size > bytes.size())
      bytes.resize(offset + size);
    std::copy(data, data + size, bytes.begin() + static_cast<std::ptrdiff_t>(offset));
    return true;
  }
  std::vector<uint8_t> bytes;
};

void sinkBitDepths() {
  Bytes sink;
  wp::FlacWriter w;
  CHECK(w.openSink(&sink, kRate, 2, 16));
  const float frame[2] = {0.5f, -0.5f};
  CHECK(w.write(frame, 1));
  CHECK(w.close());
  CHECK(decode(sink.bytes).frames == 1);
  CHECK(!w.openSink(&sink, kRate, 2, 20));
  CHECK(!w.openSink(nullptr, kRate, 2, 24));
}

// A recorder destroyed without finish() (the worker ends with the page): the encoder's last bytes
// go nowhere instead of into members already destroyed (found under WASM; ASan in make sanitize).
void destroyWithoutFinish() {
  Signal sig;
  sig.tone(0.5);
  auto r = std::make_unique<StreamRecorder>();
  CHECK(r->start(kRate, 2, nullptr));
  CHECK(r->feed(sig.samples().data(), sig.frameCount()));
  r.reset();
  CHECK(r == nullptr);
}

// ---- Armed: «Armed» in the browser, the same gate as natively ----

// #157/AK4, AK5: 1 s before the first sound, a short pause kept, 1 s after the last; the longer
// pause ends the recording (gate done) and later sound is not kept.
void armedLeadInPauseAndTail() {
  StreamRecorder r;
  const GateConfig g{-30.0, 2.0, 1.0};
  CHECK(r.start(kRate, 2, &g));
  CHECK(r.gate() == WP_REC_GATE_ARMED);
  Signal before;
  before.silence(3.0);
  Stored s = record(r, before, 128, false);
  CHECK(r.gate() == WP_REC_GATE_ARMED);
  CHECK(r.keptFrames() == 0);
  CHECK(s.file.size() == r.headerSize()); // only the header while armed, no audio
  Signal take;
  take.tone(1.0).silence(1.5).tone(1.0).silence(2.5).tone(0.5);
  const uint32_t total = take.frameCount();
  for (uint32_t done = 0; done < total; done += 128) {
    CHECK(r.feed(take.samples().data() + static_cast<size_t>(done) * 2,
                 std::min<uint32_t>(128, total - done)));
    s.store(r);
    if (done == 128)
      CHECK(r.gate() == WP_REC_GATE_RECORDING);
  }
  CHECK(r.gate() == WP_REC_GATE_DONE);
  CHECK(r.finish());
  s.close(r);
  const wp::Source d = decode(s.file);
  // 1 s lead-in + 1 s tone + 1.5 s pause + 1 s tone + 1 s tail
  CHECK(near(d.frames, frames(5.5)));
  CHECK(d.frames == r.keptFrames());
  CHECK(near(firstAbove(d, kThreshold), frames(1.0)));
  CHECK(near(lastAbove(d, kThreshold), frames(4.5)));
  CHECK(headerTotal(s.file) == static_cast<uint64_t>(d.frames));
}

// #157/AK4: stopped in a pause (space bar), the file keeps the pause up to the stop.
void armedStopInAPauseKeepsIt() {
  StreamRecorder r;
  const GateConfig g{-30.0, 5.0, 1.0};
  CHECK(r.start(kRate, 2, &g));
  Signal sig;
  sig.silence(0.5).tone(1.0).silence(3.0);
  const wp::Source d = decode(record(r, sig).file);
  CHECK(r.gate() == WP_REC_GATE_RECORDING);
  CHECK(near(d.frames, frames(0.5 + 1.0 + 3.0))); // lead-in only 0.5 s: the stream began there
}

// Stopped while armed: no sound, nothing kept; the file is only the header.
void armedStopWithoutSound() {
  StreamRecorder r;
  const GateConfig g{-30.0, 5.0, 1.0};
  CHECK(r.start(kRate, 2, &g));
  Signal sig;
  sig.silence(1.0);
  record(r, sig);
  CHECK(r.keptFrames() == 0);
  CHECK(r.gate() == WP_REC_GATE_ARMED);
}

// Settings out of range are refused, as natively.
void invalidSettings() {
  StreamRecorder r;
  const GateConfig bad{-30.0, 0.0, 1.0};
  CHECK(!r.start(kRate, 2, &bad));
  CHECK(!r.start(kRate, 0, nullptr));
  CHECK(!r.start(kRate, 9, nullptr));
  CHECK(!r.start(0, 2, nullptr));
  float frame[2] = {0.5f, 0.5f};
  CHECK(!r.feed(frame, 1)); // not started
  CHECK(!r.finish());
  CHECK(r.start(kRate, 2, nullptr)); // a valid start after a refused one
  CHECK(r.feed(frame, 1));
  CHECK(r.finish());
}

// ---- Storage full (#157/AK8) ----

// The last piece could not be stored: the file ends before it, the stream info counts exactly the
// samples stored, the MD5 is unknown; the core plays what was stored.
void cutKeepsWhatWasStored() {
  StreamRecorder r;
  CHECK(r.start(kRate, 2, nullptr));
  Signal sig;
  sig.tone(2.0);
  Stored s = record(r, sig, 4096, false);
  CHECK(s.pieces > 2);
  // One more piece that does not fit.
  Signal more;
  more.tone(0.5);
  for (uint32_t done = 0; done < more.frameCount() && r.outSize() == 0; done += 4096)
    CHECK(r.feed(more.samples().data() + static_cast<size_t>(done) * 2,
                 std::min<uint32_t>(4096, more.frameCount() - done)));
  CHECK(r.outSize() > 0);
  const uint64_t failedAt = r.outOffset();
  r.take(); // handed over, but storing it failed
  Signal after;
  after.tone(0.5);
  for (uint32_t done = 0; done < after.frameCount() && r.outSize() == 0; done += 4096)
    CHECK(r.feed(after.samples().data() + static_cast<size_t>(done) * 2,
                 std::min<uint32_t>(4096, after.frameCount() - done)));
  CHECK(r.outSize() > 0); // more bytes waiting: dropped with the cut
  const uint64_t length = r.cut();
  CHECK(length == failedAt);
  CHECK(length == s.file.size());
  CHECK(r.outSize() == 0);
  float frame[2] = {0.5f, 0.5f};
  CHECK(!r.feed(frame, 1)); // over
  CHECK(r.finish());        // nothing more to finish
  CHECK(r.outSize() == 0);
  std::copy(r.header(), r.header() + r.headerSize(), s.file.begin());
  CHECK(md5Unknown(s.file));
  const wp::Source d = decode(s.file);
  CHECK(d.frames > frames(1.5));
  CHECK(d.frames <= sig.frameCount());
  CHECK(headerTotal(s.file) == static_cast<uint64_t>(d.frames));
}

// The very first piece did not fit: the file is empty, nothing to fix.
void cutBeforeAnythingStored() {
  StreamRecorder r;
  CHECK(r.start(kRate, 2, nullptr));
  Signal sig;
  sig.tone(0.5);
  const uint32_t total = sig.frameCount();
  for (uint32_t done = 0; done < total && r.outSize() == 0; done += 4096)
    CHECK(r.feed(sig.samples().data() + static_cast<size_t>(done) * 2,
                 std::min<uint32_t>(4096, total - done)));
  r.take();
  CHECK(r.cut() == 0);
}

void run(const char *name, void (*test)()) {
  const int before = failures;
  test();
  std::printf("%s %s\n", failures == before ? "ok  " : "FAIL", name);
}

} // namespace

int main() {
  run("#157/AK3 plainRecordingIsLosslessFlac", plainRecordingIsLosslessFlac);
  run("#157/AK2 levelArrivesUnchanged", levelArrivesUnchanged);
  run("#157 monoInput", monoInput);
  run("#157 finishBeforeTakingRewritesThePiece", finishBeforeTakingRewritesThePiece);
  run("#157 levelAndSilence", levelAndSilence);
  run("#157 startAgainBeginsANewFile", startAgainBeginsANewFile);
  run("#157 peakOverTheWholeBlock", peakOverTheWholeBlock);
  run("#157 sinkBitDepths", sinkBitDepths);
  run("#157 destroyWithoutFinish", destroyWithoutFinish);
  run("#157/AK4 armedLeadInPauseAndTail", armedLeadInPauseAndTail);
  run("#157/AK4 armedStopInAPauseKeepsIt", armedStopInAPauseKeepsIt);
  run("#157 armedStopWithoutSound", armedStopWithoutSound);
  run("#157 invalidSettings", invalidSettings);
  run("#157/AK8 cutKeepsWhatWasStored", cutKeepsWhatWasStored);
  run("#157/AK8 cutBeforeAnythingStored", cutBeforeAnythingStored);
  std::printf("%d checks, %d failures\n", checks, failures);
  return failures == 0 ? 0 : 1;
}
