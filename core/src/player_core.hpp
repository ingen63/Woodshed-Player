// Player ohne Audiogerät (#14): Engine und Metronom, Laden im Hintergrund, Fehlercodes, Verhalten
// bei Gerätewechsel. player.cpp verbindet ihn mit dem Audiogerät (miniaudio); Tests treiben
// render() selbst.
#pragma once

#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <thread>

#include "engine.hpp"
#include "metronome.hpp"
#include "waveform.hpp"

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
const char *errorMessage(int code);

// Dauer einer Audiodatei in Sekunden ohne vollständiges Dekodieren (Bibliothek, #16).
// < 0 = Fehlercode. MP3 ohne Längenangabe wird dafür einmal durchgelesen.
double fileDuration(const std::string &path);

// Dekodiert MP3, WAV oder FLAC aus dem Speicher nach `out` (Stereo, f32, `sampleRate`), z. B. im
// Browser, wo es keine Dateipfade gibt (#33). kOk, kErrInvalidArgument, kErrUnsupportedFormat oder
// kErrOutOfMemory.
int decodeMemory(const void *data, size_t size, int sampleRate, Source &out);

// Wandelt bereits dekodiertes PCM (interleaved, `channels` Kanäle, `srcRate`) nach `out` (Stereo,
// `dstRate`), z. B. AAC/M4A, das der Browser dekodiert hat (#33). Mono wird auf beide Kanäle
// gelegt.
int convertPcm(const float *interleaved, int channels, long long frames, int srcRate, int dstRate,
               Source &out);

// Ladezustand, gleich wie WP_LOAD_* in wp_core.h; Werte < 0 sind Fehlercodes des letzten
// Ladevorgangs.
enum LoadState { kLoadIdle = 0, kLoadRunning = 1, kLoadReady = 2 };

// Ereignisse des Audiogeräts (aus miniaudio übersetzt).
enum class DeviceEvent { Started, Stopped, Rerouted, InterruptionBegan, InterruptionEnded };

// Festgelegtes Verhalten: Ausgabe gewechselt (z. B. Kopfhörer ab), Unterbrechung (Anruf) oder Gerät
// unerwartet gestoppt pausieren Wiedergabe und Metronom; die Position bleibt. Weiter geht es nur
// auf Play.
bool pausesPlayback(DeviceEvent e);

class Player {
public:
  static constexpr int kChannels = 2;

  explicit Player(int sampleRate);
  ~Player(); // bricht ein laufendes Laden ab

  Player(const Player &) = delete;
  Player &operator=(const Player &) = delete;

  Engine &engine() { return engine_; }
  Metronome &metronome() { return metronome_; }
  int sampleRate() const { return sampleRate_; }

  // Audio-Thread: Titel und Metronom nach `out` (interleaved, kChannels). Sperrt nicht, reserviert
  // nichts.
  void render(float *out, int frames);

  // Ob ein Audiogerät läuft. Ohne Gerät meldet das Laden kErrDeviceUnavailable.
  void setDeviceAvailable(bool available) { deviceAvailable_.store(available); }
  bool deviceAvailable() const { return deviceAvailable_.load(); }

  // Startet das Dekodieren im Hintergrund und kehrt sofort zurück. Ein noch laufendes Laden wird
  // abgebrochen. 0 = gestartet, < 0 = Fehler sofort (ungültiges Argument, kein Gerät). Ein Fehler
  // lässt den bisherigen Titel unverändert spielbar.
  int loadAsync(const std::string &path);
  // Wartet auf das Ende des laufenden Ladens. 0 = geladen, < 0 = Fehlercode.
  int waitForLoad();
  // loadAsync() und waitForLoad().
  int load(const std::string &path);

  // Setzt einen bereits dekodierten Titel (Stereo, Samplerate des Players) ein und berechnet die
  // Wellenform, ohne Datei und ohne Lade-Thread (Web, #33). Nicht im Audio-Thread aufrufen. Wie
  // beim Laden steht der Titel danach am Anfang, pausiert, ohne Loop. kOk, kErrInvalidArgument,
  // kErrBusy oder kErrOutOfMemory. withPeaks = false skips the waveform (#42: in the browser a
  // worker computes it, the AudioWorklet must not spend the time); waveform() then reports
  // kErrInvalidArgument until the next title with peaks.
  int setSource(std::unique_ptr<Source> source, bool withPeaks = true);

  int loadState() const { return loadState_.load(); }
  double loadProgress() const {
    return loadProgress_.load();
  } // 0–1 des laufenden bzw. letzten Ladens

  // Wellenform des zuletzt erfolgreich geladenen Titels (#28): `count` Abschnitte über [start, end]
  // Sekunden, Minimum und Maximum je Abschnitt (−1…1). Nicht im Audio-Thread aufrufen. kOk oder
  // kErrInvalidArgument (kein Titel, count < 1, start >= end, Bereich ausserhalb des Titels).
  int waveform(double start, double end, int count, float *mins, float *maxs) const;

  // Von jedem Thread aus, auch aus Callbacks des Audiogeräts.
  void onDeviceEvent(DeviceEvent e);

private:
  void cancelLoad();
  void runLoad(const std::string &path);

  const int sampleRate_;
  Engine engine_;
  Metronome metronome_;
  std::atomic<bool> deviceAvailable_{true};

  std::mutex loadMutex_; // nur Steuer-Threads, nie der Audio-Thread
  std::thread loader_;
  std::atomic<bool> cancel_{false};
  std::atomic<int> loadState_{kLoadIdle};
  std::atomic<double> loadProgress_{0.0};

  mutable std::mutex peaksMutex_;      // nur Steuer- und Lade-Threads
  std::shared_ptr<const Peaks> peaks_; // beim Laden berechnet, ersetzt mit dem Titel
};

} // namespace wp
