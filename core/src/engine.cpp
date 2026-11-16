#include "engine.hpp"

#include <algorithm>
#include <cmath>

#include "signalsmith-stretch/signalsmith-stretch.h"

namespace wp {

namespace {
constexpr int kChunk = 4096;  // grösster Block pro process()-Aufruf
}

struct Engine::Stretch {
    // Fester Startwert: gleiche Eingabe ergibt gleiche Ausgabe (Tests, Golden-Dateien).
    signalsmith::stretch::SignalsmithStretch<float> s{42};
    std::vector<float*> in, out;
    std::vector<float> seekBuf;
};

Engine::Engine() : stretch_(std::make_unique<Stretch>()) {}
Engine::~Engine() = default;

void Engine::setSource(std::vector<float> interleaved, int channels, int sampleRate) {
    data_ = std::move(interleaved);
    channels_ = std::max(1, channels);
    sampleRate_ = std::max(1, sampleRate);
    frames_ = static_cast<long long>(data_.size()) / channels_;

    readPos_ = 0;
    playhead_ = 0;
    inAccum_ = 0;
    stretching_ = false;
    activeRate_ = 1.0;
    loopA_ = loopB_ = 0;
    pendingSeek_.store(-1.0);
    loopChanged_.store(false);
    playing_.store(false);
    publishedPosition_.store(0.0);

    auto& st = *stretch_;
    st.s.presetDefault(channels_, static_cast<float>(sampleRate_));
    // Puffer einmal anlegen, damit der Audio-Thread nichts reserviert.
    const int maxIn = static_cast<int>(std::ceil(kChunk * kMaxRate)) + 2;
    const int seekLen = st.s.outputSeekLength(static_cast<float>(kMaxRate)) + 2;
    inPlanar_.assign(static_cast<size_t>(channels_) * maxIn, 0.0f);
    outPlanar_.assign(static_cast<size_t>(channels_) * kChunk, 0.0f);
    st.seekBuf.assign(static_cast<size_t>(channels_) * seekLen, 0.0f);
    st.in.assign(channels_, nullptr);
    st.out.assign(channels_, nullptr);
}

void Engine::play() {
    if (frames_ == 0) return;
    if (loopB_ == 0 && publishedPosition_.load() >= duration() - 1e-3) {
        pendingSeek_.store(0.0);  // am Dateiende: von vorn
    }
    playing_.store(true);
}

void Engine::pause() { playing_.store(false); }

void Engine::seek(double seconds) { pendingSeek_.store(std::max(0.0, seconds)); }

void Engine::setRate(double rate) { rate_.store(std::clamp(rate, kMinRate, kMaxRate)); }

void Engine::setLoop(double a, double b) {
    long long fa = 0, fb = 0;
    if (b >= a + kMinLoopSeconds && a >= 0) {
        fa = static_cast<long long>(std::llround(a * sampleRate_));
        fb = std::min(static_cast<long long>(std::llround(b * sampleRate_)), frames_);
        if (fb - fa < static_cast<long long>(kMinLoopSeconds * sampleRate_)) fa = fb = 0;
    }
    pendingLoopA_.store(fa);
    pendingLoopB_.store(fb);
    loopChanged_.store(true);
}

double Engine::position() const { return publishedPosition_.load(); }

double Engine::duration() const { return static_cast<double>(frames_) / sampleRate_; }

void Engine::applyPending() {
    if (loopChanged_.exchange(false)) {
        loopA_ = pendingLoopA_.load();
        loopB_ = pendingLoopB_.load();
    }
    const double target = pendingSeek_.exchange(-1.0);
    if (target >= 0) {
        long long f = std::min(static_cast<long long>(std::llround(target * sampleRate_)), frames_);
        readPos_ = f;
        playhead_ = static_cast<double>(f);
        if (stretching_) primeStretch(activeRate_);
        publishedPosition_.store(playhead_ / sampleRate_);
    }
}

bool Engine::readNext(float* frame) {
    if (loopB_ > 0 && readPos_ >= loopB_) readPos_ = loopA_;
    if (readPos_ >= frames_) {
        std::fill(frame, frame + channels_, 0.0f);
        return false;
    }
    const float* src = data_.data() + readPos_ * channels_;
    std::copy(src, src + channels_, frame);
    ++readPos_;
    if (loopB_ > 0 && readPos_ >= loopB_) readPos_ = loopA_;
    return true;
}

void Engine::advancePlayhead(double inputFrames) {
    playhead_ += inputFrames;
    if (loopB_ > 0 && playhead_ >= static_cast<double>(loopB_)) {
        playhead_ = loopA_ + std::fmod(playhead_ - loopB_, static_cast<double>(loopB_ - loopA_));
    }
    playhead_ = std::min(playhead_, static_cast<double>(frames_));
}

void Engine::primeStretch(double rate) {
    auto& st = *stretch_;
    readPos_ = static_cast<long long>(std::llround(playhead_));
    const int len = st.s.outputSeekLength(static_cast<float>(rate));
    float frame[16];
    const int ch = std::min(channels_, 16);
    for (int c = 0; c < ch; ++c) st.in[c] = st.seekBuf.data() + static_cast<size_t>(c) * len;
    for (int i = 0; i < len; ++i) {
        readNext(frame);
        for (int c = 0; c < ch; ++c) st.in[c][i] = frame[c];
    }
    st.s.outputSeek(st.in.data(), len);
    inAccum_ = 0;
    stretching_ = true;
    activeRate_ = rate;
}

void Engine::render(float* out, int frames) {
    applyPending();
    const int ch = channels_;
    int done = 0;
    while (done < frames) {
        const int n = std::min(frames - done, kChunk);
        float* dst = out + static_cast<size_t>(done) * ch;
        done += n;

        if (!playing_.load() || frames_ == 0) {
            std::fill(dst, dst + static_cast<size_t>(n) * ch, 0.0f);
            continue;
        }
        const float vol = volume_.load();
        const double r = rate_.load();
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
                if (!readNext(frame)) {
                    std::fill(dst + static_cast<size_t>(i) * ch, dst + static_cast<size_t>(n) * ch, 0.0f);
                    playing_.store(false);
                    break;
                }
                for (int c = 0; c < ch; ++c) dst[i * ch + c] = frame[c] * vol;
            }
            playhead_ = static_cast<double>(readPos_);
            continue;
        }

        // Tempo ohne Tonhöhenänderung: Eingabe als Strom inklusive Loop-Sprung in den Stretcher.
        auto& st = *stretch_;
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
            for (int c = 0; c < ch; ++c) st.in[c][i] = frame[c];
        }
        st.s.process(st.in.data(), nIn, st.out.data(), n);
        for (int i = 0; i < n; ++i)
            for (int c = 0; c < ch; ++c) dst[i * ch + c] = st.out[c][i] * vol;
        advancePlayhead(n * r);
        if (loopB_ == 0 && playhead_ >= static_cast<double>(frames_)) playing_.store(false);
    }
    publishedPosition_.store(playhead_ / sampleRate_);
}

}  // namespace wp
