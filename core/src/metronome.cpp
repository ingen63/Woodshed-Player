#include "metronome.hpp"

#include <algorithm>
#include <cmath>

namespace wp {

namespace {
constexpr double kPi = 3.14159265358979323846;
constexpr double kClickSeconds = 0.05;   // Hüllkurve ca. 50 ms
constexpr double kAttackSeconds = 0.001;
constexpr double kDecaySeconds = 0.012;
constexpr double kGainSmoothSeconds = 0.005;  // Lautstärke ohne Knacken

struct Sound {
    double freq;
    float level;
};
// Klangstufen wie im Metronom-Projekt: Betonung, Nebenakzent, Schlag, Unterteilung (leiser).
constexpr Sound kSounds[4] = {{1600, 1.0f}, {1250, 0.85f}, {1000, 0.7f}, {700, 0.4f}};

bool validMeter(int m) { return m == 2 || m == 3 || m == 4 || m == 6; }
}  // namespace

Metronome::Metronome(int sampleRate) { setSampleRate(sampleRate); }

void Metronome::setSampleRate(int sampleRate) {
    sampleRate_ = std::max(1, sampleRate);
    gainCoef_ = static_cast<float>(1.0 - std::exp(-1.0 / (kGainSmoothSeconds * sampleRate_)));
}

int Metronome::clampBpm(int bpm) { return std::clamp(bpm, kMinBpm, kMaxBpm); }

void Metronome::start() {
    running_.store(true);
    command_.store(1);
}

void Metronome::stop() {
    running_.store(false);
    command_.store(2);
}

void Metronome::setBpm(int bpm) { bpm_.store(clampBpm(bpm)); }

void Metronome::setMeter(int beatsPerBar) {
    if (validMeter(beatsPerBar)) meter_.store(beatsPerBar);
}

void Metronome::setSubdivision(int clicksPerBeat) { subdivision_.store(std::clamp(clicksPerBeat, 1, 4)); }

void Metronome::setVolume(float volume) { volume_.store(std::clamp(volume, 0.0f, 1.0f)); }

void Metronome::setRamp(bool enabled, int startBpm, int targetBpm, int stepBpm, int everyBars) {
    const bool changed = rampTimed_.exchange(false);
    rampStart_.store(clampBpm(startBpm));
    rampTarget_.store(clampBpm(targetBpm));
    rampStep_.store(std::clamp(stepBpm, 1, 280));
    rampEvery_.store(std::clamp(everyBars, 1, 20));
    enableRamp(enabled, changed);
}

void Metronome::setTimedRamp(bool enabled, int startBpm, int targetBpm, int durationSeconds) {
    const int start = clampBpm(startBpm), target = clampBpm(targetBpm);
    const int seconds = std::clamp(durationSeconds, 1, 3600);
    bool changed = !rampTimed_.exchange(true);
    changed |= rampStart_.exchange(start) != start;
    changed |= rampTarget_.exchange(target) != target;
    changed |= rampSeconds_.exchange(seconds) != seconds;
    enableRamp(enabled, changed);
}

// Einschalten im Stand: Start-BPM. Einschalten oder Wechsel der Art: Steigerung neu beginnen. Bei Zeit
// auch nach geänderten Werten, damit die Runde zur neuen Dauer passt (vom laufenden Tempo aus).
void Metronome::enableRamp(bool enabled, bool changed) {
    const bool was = rampOn_.exchange(enabled);
    if (enabled && !was && !running_.load()) bpm_.store(rampStart_.load());
    if (enabled && (!was || changed)) rampRestart_.store(true);
}

double Metronome::framesPerTimedStep() const {
    const int steps = std::abs(rampTarget_.load() - rampStart_.load());
    return steps == 0 ? 0 : static_cast<double>(rampSeconds_.load()) * sampleRate_ / steps;
}

// Stufe (0 = Start-BPM … |Ziel − Start| = Ziel) zur Position `frame`; eine Runde hat |Ziel − Start| + 1
// Stufen, die letzte (Ziel halten) endet mit dem Rücksprung auf Start.
int Metronome::timedStep(double frame) {
    const double perStep = framesPerTimedStep();
    if (perStep <= 0) return 0;
    const int steps = std::abs(rampTarget_.load() - rampStart_.load());
    const double round = perStep * (steps + 1);
    if (frame - cycleStart_ >= round) cycleStart_ += std::floor((frame - cycleStart_) / round) * round;
    const double k = std::floor((frame - cycleStart_) / perStep + 1e-9);
    return std::clamp(static_cast<int>(k), 0, steps);
}

double Metronome::framesPerTick() const {
    return 60.0 * sampleRate_ / (static_cast<double>(bpm_.load()) * subdivision_.load());
}

void Metronome::applyCommands() {
    const int cmd = command_.exchange(0);
    if (cmd == 1) {
        // Start: immer Takt 1, Schlag 1; mit Steigerung auf Start-BPM.
        if (rampOn_.load()) bpm_.store(rampStart_.load());
        active_ = true;
        now_ = 0;
        nextTick_ = 0;
        beatStart_ = 0;
        activeSub_ = subdivision_.load();
        beat_ = sub_ = 0;
        bar_ = 1;
        barsSinceChange_ = 0;
        cycleStart_ = 0;
        firstTick_ = true;
        rampRestart_.store(false);
    } else if (cmd == 2) {
        active_ = false;  // laufende Klicks klingen aus
    }
    if (rampRestart_.exchange(false)) {
        barsSinceChange_ = 0;
        // Zeit: Runde so legen, dass das laufende Tempo als erreichte Stufe gilt (sonst ab Start).
        const int start = rampStart_.load(), target = rampTarget_.load(), cur = bpm_.load();
        const bool inside = (cur - start) * (target - cur) >= 0;
        const int k = inside ? std::abs(cur - start) : 0;
        cycleStart_ = static_cast<double>(now_) - k * framesPerTimedStep();
    }

    // Unterteilung mitten im Schlag gewechselt: nächsten Klick ab Beginn des laufenden Schlags neu planen.
    const int subdiv = subdivision_.load();
    if (active_ && !firstTick_ && subdiv != activeSub_) {
        activeSub_ = subdiv;
        const double interval = framesPerTick();
        const long long k = static_cast<long long>(std::floor((now_ - beatStart_) / interval)) + 1;
        if (k >= subdiv) {
            sub_ = subdiv;  // nächster Klick ist der nächste Schlag
            nextTick_ = beatStart_ + interval * subdiv;
        } else {
            sub_ = static_cast<int>(k);
            nextTick_ = beatStart_ + interval * static_cast<double>(k);
        }
    }
}

void Metronome::onBarBoundary(double frame) {
    ++bar_;
    ++barsSinceChange_;
    if (!rampOn_.load()) return;
    if (rampTimed_.load()) {
        const int start = rampStart_.load(), target = rampTarget_.load();
        const int k = timedStep(frame);
        bpm_.store(target >= start ? start + k : start - k);
        return;
    }
    if (barsSinceChange_ < rampEvery_.load()) return;
    barsSinceChange_ = 0;
    const int start = rampStart_.load(), target = rampTarget_.load(), step = rampStep_.load();
    const int cur = bpm_.load();
    int next;
    if (cur == target) {
        next = start;  // Ziel gehalten: zurück auf Start (Endlosschleife)
    } else if (target > start) {
        next = std::min(cur + step, target);
    } else {
        next = std::max(cur - step, target);
    }
    bpm_.store(next);
}

void Metronome::scheduleTick() {
    // Wechsel der Taktart oder Unterteilung wirkt sofort.
    const int meter = meter_.load();
    const int subdiv = subdivision_.load();
    if (sub_ >= subdiv) {
        sub_ = 0;
        ++beat_;
    }
    if (beat_ >= meter) {
        beat_ = 0;
    }
    if (beat_ == 0 && sub_ == 0) {
        if (!firstTick_) onBarBoundary(nextTick_);
        firstTick_ = false;
    }
    if (sub_ == 0) beatStart_ = nextTick_;
    activeSub_ = subdiv;

    int kind;
    if (sub_ > 0) {
        kind = Sub;
    } else if (beat_ == 0) {
        kind = Accent;
    } else if (meter == 6 && beat_ == 3) {
        kind = SecondaryAccent;
    } else {
        kind = Beat;
    }
    if (tickLog) tickLog->push_back({now_, kind, bar_, beat_, sub_, bpm_.load()});

    // Freie (oder älteste) Stimme nehmen.
    Voice* v = &voices_[0];
    for (auto& cand : voices_) {
        if (cand.age < 0) {
            v = &cand;
            break;
        }
        if (cand.age > v->age) v = &cand;
    }
    v->freq = kSounds[kind].freq;
    v->amp = kSounds[kind].level;
    v->age = 0;

    // Nächste Position: Abstand aus dem jetzt gültigen Tempo, als Gleitkommasumme ohne Drift.
    nextTick_ += framesPerTick();
    advanceStep();
}

void Metronome::advanceStep() {
    ++sub_;
    if (sub_ >= subdivision_.load()) {
        sub_ = 0;
        ++beat_;
        if (beat_ >= meter_.load()) beat_ = 0;
    }
}

float Metronome::renderVoices() {
    const int clickLen = static_cast<int>(kClickSeconds * sampleRate_);
    const double attack = kAttackSeconds * sampleRate_;
    const double decay = kDecaySeconds * sampleRate_;
    float s = 0;
    for (auto& v : voices_) {
        if (v.age < 0) continue;
        const double env = std::min(1.0, (v.age + 1) / attack) * std::exp(-v.age / decay);
        s += static_cast<float>(v.amp * env * std::sin(2 * kPi * v.freq * v.age / sampleRate_));
        if (++v.age >= clickLen) v.age = -1;
    }
    return s;
}

void Metronome::renderAdd(float* out, int frames, int channels) {
    applyCommands();
    const float target = volume_.load();
    for (int i = 0; i < frames; ++i) {
        if (active_) {
            while (now_ >= static_cast<long long>(std::llround(nextTick_))) scheduleTick();
            ++now_;
        }
        gain_ += (target - gain_) * gainCoef_;
        if (std::fabs(target - gain_) < 1e-5f) gain_ = target;
        const float s = renderVoices() * gain_;
        for (int c = 0; c < channels; ++c) out[i * channels + c] += s;
    }
}

}  // namespace wp
