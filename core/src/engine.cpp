#include "engine.hpp"

#include <algorithm>
#include <cmath>

#include "signalsmith-stretch/signalsmith-stretch.h"

namespace wp {

namespace {
constexpr int kChunk = 4096; // grösster Block pro process()-Aufruf
}

struct Engine::Stretch {
  // Fester Startwert: gleiche Eingabe ergibt gleiche Ausgabe (Tests, Golden-Dateien).
  signalsmith::stretch::SignalsmithStretch<float> s{42};
  std::vector<float *> in, out;
  std::vector<float> seekBuf;
};

Engine::Engine() : stretch_(std::make_unique<Stretch>()) { configure(2, 44100); }

Engine::~Engine() {
  Command c;
  while (commands_.pop(c))
    delete c.source;
  collectGarbage();
  delete source_;
}

void Engine::configure(int channels, int sampleRate) {
  channels_ = std::clamp(channels, 1, 16);
  sampleRate_ = std::max(1, sampleRate);
  auto &st = *stretch_;
  st.s.presetDefault(channels_, static_cast<float>(sampleRate_));
  // Puffer einmal anlegen, damit der Audio-Thread nichts reserviert.
  const int maxIn = static_cast<int>(std::ceil(kChunk * kMaxRate)) + 2;
  const int seekLen = st.s.outputSeekLength(static_cast<float>(kMaxRate)) + 2;
  inPlanar_.assign(static_cast<size_t>(channels_) * maxIn, 0.0f);
  outPlanar_.assign(static_cast<size_t>(channels_) * kChunk, 0.0f);
  st.seekBuf.assign(static_cast<size_t>(channels_) * seekLen, 0.0f);
  st.in.assign(channels_, nullptr);
  st.out.assign(channels_, nullptr);
  stretching_ = false;
}

void Engine::setSource(std::vector<float> interleaved, int channels, int sampleRate) {
  configure(channels, sampleRate);
  auto *s = new Source;
  s->frames = static_cast<long long>(interleaved.size()) / channels_;
  s->data = std::move(interleaved);
  installSource(s);
  collectGarbage();
}

bool Engine::submitSource(std::unique_ptr<Source> source) {
  if (!source)
    return false;
  const long long frames = source->frames;
  Command c;
  c.type = Command::SetSource;
  c.source = source.get();
  if (!send(c))
    return false;
  source.release(); // gehört jetzt der Queue bzw. dem Audio-Thread
  // Sofort sichtbar, auch bevor der Audio-Thread den Titel übernimmt.
  publishedFrames_.store(frames);
  publishedPosition_.store(0.0);
  publishedPlaying_.store(false);
  return true;
}

void Engine::collectGarbage() {
  Source *s = nullptr;
  while (retired_.pop(s))
    delete s;
}

bool Engine::send(const Command &c) { return commands_.push(c); }

bool Engine::play() { return send({Command::Play}); }

bool Engine::pause() { return send({Command::Pause}); }

bool Engine::seek(double seconds) { return send({Command::Seek, std::max(0.0, seconds)}); }

bool Engine::setRate(double rate) {
  const double r = std::clamp(rate, kMinRate, kMaxRate);
  requestedRate_.store(r);
  return send({Command::Rate, r});
}

bool Engine::setLoop(double a, double b) { return send({Command::Loop, a, b}); }

bool Engine::setVolume(float v) { return send({Command::Volume, static_cast<double>(v)}); }

double Engine::position() const { return publishedPosition_.load(); }

double Engine::duration() const {
  return static_cast<double>(publishedFrames_.load()) / sampleRate_;
}

void Engine::applyCommands() {
  // Seeks werden pro Block zusammengefasst: nur das letzte Ziel zählt. Ein Seek im gedehnten Pfad
  // ist teuer (outputSeek); viele davon in einem Block (z. B. schnelles Ziehen) würden den Block
  // sprengen.
  double seekTarget = -1.0;
  bool changed = false;
  Command c;
  while (commands_.pop(c)) {
    apply(c, seekTarget);
    changed = true;
  }
  if (seekTarget >= 0)
    seekTo(seekTarget);
  if (changed)
    publish();
}

void Engine::apply(const Command &c, double &seekTarget) {
  switch (c.type) {
  case Command::Play: {
    if (frames_ == 0)
      break;
    const double at = seekTarget >= 0 ? seekTarget * sampleRate_ : playhead_;
    if (loopB_ == 0 && at >= static_cast<double>(frames_))
      seekTarget = 0.0; // am Dateiende: von vorn
    playing_ = true;
    break;
  }
  case Command::Pause:
    playing_ = false;
    break;
  case Command::Seek:
    seekTarget = c.a;
    break;
  case Command::Rate:
    rate_ = c.a;
    break;
  case Command::Volume:
    volume_ = static_cast<float>(c.a);
    break;
  case Command::Loop: {
    const double a = c.a, b = c.b;
    long long fa = 0, fb = 0;
    if (b >= a + kMinLoopSeconds && a >= 0) {
      fa = static_cast<long long>(std::llround(a * sampleRate_));
      fb = std::min(static_cast<long long>(std::llround(b * sampleRate_)), frames_);
      if (fb - fa < static_cast<long long>(kMinLoopSeconds * sampleRate_))
        fa = fb = 0;
    }
    loopA_ = fa;
    loopB_ = fb;
    break;
  }
  case Command::SetSource:
    installSource(c.source);
    seekTarget = -1.0; // ein Seek davor galt dem alten Titel
    break;
  }
}

void Engine::installSource(Source *s) {
  // Den alten Titel nicht hier freigeben (Audio-Thread), sondern über collectGarbage().
  // Ist die Rückgabe-Queue voll, bleibt er lieber liegen, als hier Speicher freizugeben.
  if (source_)
    retired_.push(source_);
  source_ = s;
  data_ = s ? s->data.data() : nullptr;
  frames_ = s ? s->frames : 0;
  readPos_ = 0;
  playhead_ = 0;
  inAccum_ = 0;
  stretching_ = false;
  activeRate_ = 1.0;
  loopA_ = loopB_ = 0;
  playing_ = false;
  publishedFrames_.store(frames_);
  publish();
}

void Engine::seekTo(double seconds) {
  const long long f =
      std::min(static_cast<long long>(std::llround(seconds * sampleRate_)), frames_);
  readPos_ = f;
  playhead_ = static_cast<double>(f);
  if (stretching_)
    primeStretch(activeRate_);
}

void Engine::publish() {
  publishedPosition_.store(playhead_ / sampleRate_);
  publishedPlaying_.store(playing_);
  publishedLoopPasses_.store(loopPasses_);
}

bool Engine::readNext(float *frame) {
  if (loopB_ > 0 && readPos_ >= loopB_)
    readPos_ = loopA_;
  if (readPos_ >= frames_) {
    std::fill(frame, frame + channels_, 0.0f);
    return false;
  }
  const float *src = data_ + readPos_ * channels_;
  std::copy(src, src + channels_, frame);
  ++readPos_;
  if (loopB_ > 0 && readPos_ >= loopB_)
    readPos_ = loopA_;
  return true;
}

void Engine::advancePlayhead(double inputFrames) {
  const bool beforeLoopEnd = playhead_ < static_cast<double>(loopB_);
  playhead_ += inputFrames;
  if (loopB_ > 0 && playhead_ >= static_cast<double>(loopB_)) {
    // Nur ein Überschreiten des Loop-Endes ist ein Durchgang, nicht ein Seek hinter das Ende.
    if (beforeLoopEnd)
      loopPasses_ +=
          1 + static_cast<long long>((playhead_ - loopB_) / static_cast<double>(loopB_ - loopA_));
    playhead_ = loopA_ + std::fmod(playhead_ - loopB_, static_cast<double>(loopB_ - loopA_));
  }
  playhead_ = std::min(playhead_, static_cast<double>(frames_));
}

void Engine::primeStretch(double rate) {
  auto &st = *stretch_;
  readPos_ = static_cast<long long>(std::llround(playhead_));
  const int len = st.s.outputSeekLength(static_cast<float>(rate));
  float frame[16];
  const int ch = std::min(channels_, 16);
  for (int c = 0; c < ch; ++c)
    st.in[c] = st.seekBuf.data() + static_cast<size_t>(c) * len;
  for (int i = 0; i < len; ++i) {
    readNext(frame);
    for (int c = 0; c < ch; ++c)
      st.in[c][i] = frame[c];
  }
  st.s.outputSeek(st.in.data(), len);
  inAccum_ = 0;
  stretching_ = true;
  activeRate_ = rate;
}

void Engine::render(float *out, int frames) {
  applyCommands();
  const int ch = channels_;
  int done = 0;
  while (done < frames) {
    const int n = std::min(frames - done, kChunk);
    float *dst = out + static_cast<size_t>(done) * ch;
    done += n;

    if (!playing_ || frames_ == 0) {
      std::fill(dst, dst + static_cast<size_t>(n) * ch, 0.0f);
      continue;
    }
    const float vol = volume_;
    const double r = rate_;
    const bool wantStretch = std::fabs(r - 1.0) > 1e-6;

    if (wantStretch && !stretching_) {
      primeStretch(r);
    } else if (!wantStretch && stretching_) {
      // Zurück zur direkten Wiedergabe an der hörbaren Stelle.
      readPos_ = static_cast<long long>(std::llround(playhead_));
      stretching_ = false;
    }
    activeRate_ = r;

    if (!stretching_) {
      // Direkte Wiedergabe: sample-genau, Loop-Sprung ohne Lücke.
      float frame[16];
      for (int i = 0; i < n; ++i) {
        const long long before = readPos_;
        const bool ok = readNext(frame);
        // Sprung zurück aus dem Loop heraus ist ein Durchgang; liegt der Lesekopf nach einem Seek
        // hinter dem Loop-Ende, ist der Sprung zum Anfang keiner.
        if (loopB_ > 0 && before < loopB_ && readPos_ < before)
          ++loopPasses_;
        if (!ok) {
          std::fill(dst + static_cast<size_t>(i) * ch, dst + static_cast<size_t>(n) * ch, 0.0f);
          playing_ = false;
          break;
        }
        for (int c = 0; c < ch; ++c)
          dst[i * ch + c] = frame[c] * vol;
      }
      playhead_ = static_cast<double>(readPos_);
      continue;
    }

    // Tempo ohne Tonhöhenänderung: Eingabe als Strom inklusive Loop-Sprung in den Stretcher.
    auto &st = *stretch_;
    inAccum_ += n * r;
    const int nIn = static_cast<int>(inAccum_);
    inAccum_ -= nIn;
    const size_t inStride = inPlanar_.size() / ch;
    for (int c = 0; c < ch; ++c) {
      st.in[c] = inPlanar_.data() + c * inStride;
      st.out[c] = outPlanar_.data() + static_cast<size_t>(c) * kChunk;
    }
    float frame[16];
    for (int i = 0; i < nIn; ++i) {
      readNext(frame);
      for (int c = 0; c < ch; ++c)
        st.in[c][i] = frame[c];
    }
    st.s.process(st.in.data(), nIn, st.out.data(), n);
    for (int i = 0; i < n; ++i)
      for (int c = 0; c < ch; ++c)
        dst[i * ch + c] = st.out[c][i] * vol;
    advancePlayhead(n * r);
    if (loopB_ == 0 && playhead_ >= static_cast<double>(frames_))
      playing_ = false;
  }
  publish();
}

} // namespace wp
