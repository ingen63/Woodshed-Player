// Wiedergabe-Logik ohne Audiogerät: Tempo, Loop, Seek. Wird vom Audio-Thread über render() abgefragt
// und ist dadurch auch offline (in Tests) sample-genau prüfbar.
//
// Steuerbefehle (Play, Pause, Seek, Tempo, Loop, Lautstärke, neuer Titel) kommen von beliebigen Threads
// über eine Lock-free-Queue in den Audio-Thread (#14). render() reserviert und gibt keinen Speicher frei
// und sperrt nicht; ersetzte Titel gibt collectGarbage() ausserhalb des Audio-Threads frei.
#pragma once

#include <atomic>
#include <memory>
#include <vector>

#include "command_queue.hpp"

namespace wp {

// Dekodierter Titel, interleaved mit den Kanälen und der Samplerate der Engine.
struct Source {
    std::vector<float> data;
    long long frames = 0;
};

class Engine {
public:
    static constexpr double kMinRate = 0.1;
    static constexpr double kMaxRate = 2.0;
    static constexpr double kMinLoopSeconds = 1.0;
    static constexpr size_t kQueueCapacity = 1024;

    Engine();
    ~Engine();

    // Kanäle und Samplerate festlegen, Puffer anlegen. Nur aufrufen, während render() nicht läuft.
    void configure(int channels, int sampleRate);

    // Für Tests und Werkzeuge: configure() und Titel sofort einsetzen. Nur, während render() nicht läuft.
    void setSource(std::vector<float> interleaved, int channels, int sampleRate);

    // Neuen Titel (gleiche Kanäle und Samplerate wie configure) über die Queue einsetzen, von jedem Thread aus.
    // Der Titel ersetzt den bisherigen beim nächsten render(); Wiedergabe steht dann am Anfang, pausiert,
    // ohne Loop. false = Queue voll, der Titel wurde nicht übernommen.
    bool submitSource(std::unique_ptr<Source> source);

    // Gibt ersetzte Titel frei. Nicht im Audio-Thread aufrufen.
    void collectGarbage();

    // Steuerung, von jedem Thread aus. false = Queue voll, Befehl verworfen.
    bool play();
    bool pause();
    bool seek(double seconds);
    bool setRate(double rate);
    bool setLoop(double a, double b);
    bool setVolume(float v);

    bool playing() const { return publishedPlaying_.load(); }
    double rate() const { return requestedRate_.load(); }  // zuletzt gesetztes Tempo
    double position() const;  // hörbare Position in Sekunden
    double duration() const;
    int channels() const { return channels_; }
    int sampleRate() const { return sampleRate_; }
    long long frames() const { return publishedFrames_.load(); }

    // Audio-Thread: schreibt `frames` Frames interleaved nach `out`.
    void render(float* out, int frames);

    // Für Tests: aktueller Lesekopf in Frames (nur aus dem Audio-Thread bzw. offline).
    long long readFrame() const { return readPos_; }

private:
    struct Stretch;

    struct Command {
        enum Type : unsigned char { Play, Pause, Seek, Rate, Loop, Volume, SetSource } type = Play;
        double a = 0, b = 0;
        Source* source = nullptr;
    };

    bool send(const Command& c);
    void applyCommands();
    void apply(const Command& c);
    void installSource(Source* s);
    void seekTo(double seconds);
    void publish();
    void primeStretch(double rate);
    // Liest einen Frame ab readPos_ und rückt vor (Loop-Sprung, Dateiende).
    bool readNext(float* frame);
    void advancePlayhead(double inputFrames);

    int channels_ = 2;
    int sampleRate_ = 44100;

    CommandQueue<Command> commands_{kQueueCapacity};
    CommandQueue<Source*> retired_{kQueueCapacity};

    // Zustand des Audio-Threads
    Source* source_ = nullptr;
    const float* data_ = nullptr;
    long long frames_ = 0;
    bool playing_ = false;
    double rate_ = 1.0;
    float volume_ = 1.0f;
    long long readPos_ = 0;
    double playhead_ = 0;  // hörbare Position in Frames
    double inAccum_ = 0;
    bool stretching_ = false;
    double activeRate_ = 1.0;
    long long loopA_ = 0, loopB_ = 0;  // B == 0: kein Loop
    std::unique_ptr<Stretch> stretch_;
    std::vector<float> inPlanar_, outPlanar_;

    // Für andere Threads veröffentlicht
    std::atomic<bool> publishedPlaying_{false};
    std::atomic<double> publishedPosition_{0.0};
    std::atomic<long long> publishedFrames_{0};
    std::atomic<double> requestedRate_{1.0};
};

}  // namespace wp
