// Player ohne Audiogerät (#14): Engine und Metronom, Laden im Hintergrund, Fehlercodes, Verhalten bei
// Gerätewechsel. player.cpp verbindet ihn mit dem Audiogerät (miniaudio); Tests treiben render() selbst.
#pragma once

#include <atomic>
#include <mutex>
#include <string>
#include <thread>

#include "engine.hpp"
#include "metronome.hpp"

namespace wp {

// Fehlercodes, gleich wie WP_ERR_* in wp_core.h.
enum ErrorCode {
    kOk = 0,
    kErrInvalidArgument = -1,
    kErrFileNotFound = -2,
    kErrUnsupportedFormat = -3,
    kErrDeviceUnavailable = -4,
    kErrOutOfMemory = -5,
    kErrFileUnreadable = -6,
    kErrCancelled = -7,
    kErrBusy = -8,
};

// Deutscher Text zu einem Fehlercode (statisch, nie nullptr).
const char* errorMessage(int code);

// Dauer einer Audiodatei in Sekunden ohne vollständiges Dekodieren (Bibliothek, #16).
// < 0 = Fehlercode. MP3 ohne Längenangabe wird dafür einmal durchgelesen.
double fileDuration(const std::string& path);

// Ladezustand, gleich wie WP_LOAD_* in wp_core.h; Werte < 0 sind Fehlercodes des letzten Ladevorgangs.
enum LoadState { kLoadIdle = 0, kLoadRunning = 1, kLoadReady = 2 };

// Ereignisse des Audiogeräts (aus miniaudio übersetzt).
enum class DeviceEvent { Started, Stopped, Rerouted, InterruptionBegan, InterruptionEnded };

// Festgelegtes Verhalten: Ausgabe gewechselt (z. B. Kopfhörer ab), Unterbrechung (Anruf) oder Gerät
// unerwartet gestoppt pausieren Wiedergabe und Metronom; die Position bleibt. Weiter geht es nur auf Play.
bool pausesPlayback(DeviceEvent e);

class Player {
public:
    static constexpr int kChannels = 2;

    explicit Player(int sampleRate);
    ~Player();  // bricht ein laufendes Laden ab

    Player(const Player&) = delete;
    Player& operator=(const Player&) = delete;

    Engine& engine() { return engine_; }
    Metronome& metronome() { return metronome_; }
    int sampleRate() const { return sampleRate_; }

    // Audio-Thread: Titel und Metronom nach `out` (interleaved, kChannels). Sperrt nicht, reserviert nichts.
    void render(float* out, int frames);

    // Ob ein Audiogerät läuft. Ohne Gerät meldet das Laden kErrDeviceUnavailable.
    void setDeviceAvailable(bool available) { deviceAvailable_.store(available); }
    bool deviceAvailable() const { return deviceAvailable_.load(); }

    // Startet das Dekodieren im Hintergrund und kehrt sofort zurück. Ein noch laufendes Laden wird abgebrochen.
    // 0 = gestartet, < 0 = Fehler sofort (ungültiges Argument, kein Gerät). Ein Fehler lässt den
    // bisherigen Titel unverändert spielbar.
    int loadAsync(const std::string& path);
    // Wartet auf das Ende des laufenden Ladens. 0 = geladen, < 0 = Fehlercode.
    int waitForLoad();
    // loadAsync() und waitForLoad().
    int load(const std::string& path);

    int loadState() const { return loadState_.load(); }
    double loadProgress() const { return loadProgress_.load(); }  // 0–1 des laufenden bzw. letzten Ladens

    // Von jedem Thread aus, auch aus Callbacks des Audiogeräts.
    void onDeviceEvent(DeviceEvent e);

private:
    void cancelLoad();
    void runLoad(std::string path);

    const int sampleRate_;
    Engine engine_;
    Metronome metronome_;
    std::atomic<bool> deviceAvailable_{true};

    std::mutex loadMutex_;  // nur Steuer-Threads, nie der Audio-Thread
    std::thread loader_;
    std::atomic<bool> cancel_{false};
    std::atomic<int> loadState_{kLoadIdle};
    std::atomic<double> loadProgress_{0.0};
};

}  // namespace wp
