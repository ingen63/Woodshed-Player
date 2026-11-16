// Wiedergabe-Logik ohne Audiogerät: Tempo, Loop, Seek. Wird vom Audio-Thread über render() abgefragt
// und ist dadurch auch offline (in Tests) sample-genau prüfbar.
#pragma once

#include <atomic>
#include <memory>
#include <vector>

namespace wp {

class Engine {
public:
    static constexpr double kMinRate = 0.1;
    static constexpr double kMaxRate = 2.0;
    static constexpr double kMinLoopSeconds = 1.0;

    Engine();
    ~Engine();

    // Nur aufrufen, während render() nicht läuft (Gerät gestoppt).
    void setSource(std::vector<float> interleaved, int channels, int sampleRate);

    // Steuerung, von jedem Thread aus.
    void play();
    void pause();
    bool playing() const { return playing_.load(); }
    void seek(double seconds);
    void setRate(double rate);
    double rate() const { return rate_.load(); }
    void setLoop(double a, double b);
    void setVolume(float v) { volume_.store(v); }

    double position() const;  // hörbare Position in Sekunden
    double duration() const;
    int channels() const { return channels_; }
    int sampleRate() const { return sampleRate_; }
    long long frames() const { return frames_; }

    // Audio-Thread: schreibt `frames` Frames interleaved nach `out`.
    void render(float* out, int frames);

    // Für Tests: aktueller Lesekopf in Frames.
    long long readFrame() const { return readPos_; }

private:
    struct Stretch;

    void applyPending();
    void primeStretch(double rate);
    // Liest einen Frame ab readPos_ und rückt vor (Loop-Sprung, Dateiende).
    bool readNext(float* frame);
    void advancePlayhead(double inputFrames);

    std::vector<float> data_;
    int channels_ = 2;
    int sampleRate_ = 44100;
    long long frames_ = 0;

    // Zustand des Audio-Threads
    long long readPos_ = 0;
    double playhead_ = 0;  // hörbare Position in Frames
    double inAccum_ = 0;
    bool stretching_ = false;
    double activeRate_ = 1.0;
    long long loopA_ = 0, loopB_ = 0;  // B == 0: kein Loop
    std::unique_ptr<Stretch> stretch_;
    std::vector<float> inPlanar_, outPlanar_;

    // Befehle aus anderen Threads
    std::atomic<bool> playing_{false};
    std::atomic<double> rate_{1.0};
    std::atomic<float> volume_{1.0f};
    std::atomic<double> pendingSeek_{-1.0};
    std::atomic<long long> pendingLoopA_{0}, pendingLoopB_{0};
    std::atomic<bool> loopChanged_{false};
    std::atomic<double> publishedPosition_{0.0};
};

}  // namespace wp
