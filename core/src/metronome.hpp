// Metronom (FEA-3): sample-genau geplante Klicks, Taktarten, Unterteilungen, automatische Tempo-Steigerung.
// Steuerung von jedem Thread aus (atomare Werte), renderAdd() läuft im Audio-Thread und mischt die Klicks dazu.
#pragma once

#include <atomic>
#include <vector>

namespace wp {

class Metronome {
public:
    static constexpr int kMinBpm = 20;
    static constexpr int kMaxBpm = 300;

    enum Kind { Accent = 0, SecondaryAccent = 1, Beat = 2, Sub = 3 };

    // Für Tests: jeder geplante Klick mit Position (Frames seit Start), Art, Takt (ab 1), Schlag und Unterteilung (ab 0).
    struct Tick {
        long long frame;
        int kind;
        int bar;
        int beat;
        int sub;
        int bpm;
    };

    explicit Metronome(int sampleRate = 48000);

    void setSampleRate(int sampleRate);  // nur bei gestopptem Audio-Thread
    int sampleRate() const { return sampleRate_; }

    void start();
    void stop();
    bool running() const { return running_.load(); }

    static int clampBpm(int bpm);
    void setBpm(int bpm);
    int bpm() const { return bpm_.load(); }

    // Schläge pro Takt: 4 (4/4), 3 (3/4), 2 (2/4), 6 (6/8, Nebenakzent auf Schlag 4).
    void setMeter(int beatsPerBar);
    int meter() const { return meter_.load(); }

    // Klicks pro Schlag: 1 Viertel, 2 Achtel, 3 Triolen, 4 Sechzehntel.
    void setSubdivision(int clicksPerBeat);
    int subdivision() const { return subdivision_.load(); }

    void setVolume(float volume);  // 0–1
    float volume() const { return volume_.load(); }

    // Automatische Steigerung. Bei gestopptem Metronom setzt Einschalten das Tempo auf startBpm.
    void setRamp(bool enabled, int startBpm, int targetBpm, int stepBpm, int everyBars);
    bool rampEnabled() const { return rampOn_.load(); }

    // Audio-Thread: Klicks zu `out` (interleaved, `channels` Kanäle) addieren.
    void renderAdd(float* out, int frames, int channels);

    // Nur für Tests (nicht thread-sicher): Protokoll der geplanten Klicks.
    std::vector<Tick>* tickLog = nullptr;

private:
    struct Voice {
        double freq = 0;
        float amp = 0;
        int age = -1;  // -1 = frei
    };

    void applyCommands();
    void scheduleTick();
    void advanceStep();
    void onBarBoundary();
    double framesPerTick() const;
    float renderVoices();

    int sampleRate_;

    // Einstellungen (jeder Thread)
    std::atomic<bool> running_{false};
    std::atomic<int> command_{0};  // 1 = Start, 2 = Stopp
    std::atomic<int> bpm_{120};
    std::atomic<int> meter_{4};
    std::atomic<int> subdivision_{1};
    std::atomic<float> volume_{0.7f};
    std::atomic<bool> rampOn_{false};
    std::atomic<int> rampStart_{100}, rampTarget_{150}, rampStep_{5}, rampEvery_{4};
    std::atomic<bool> rampRestart_{false};

    // Zustand des Audio-Threads
    bool active_ = false;
    long long now_ = 0;      // Frames seit Start
    double nextTick_ = 0;    // Position des nächsten Klicks (Frames seit Start)
    double beatStart_ = 0;   // Position des laufenden Schlags
    int activeSub_ = 1;      // Unterteilung, mit der nextTick_ geplant wurde
    int beat_ = 0, sub_ = 0, bar_ = 1;
    int barsSinceChange_ = 0;
    bool firstTick_ = true;
    float gain_ = 0.7f;
    float gainCoef_ = 0;
    Voice voices_[4];
};

}  // namespace wp
