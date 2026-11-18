// Wellenform-Daten (#28): Minimum und Maximum je Block von kBlockFrames Frames über alle Kanäle.
// Einmal beim Laden berechnet (im Lade-Thread, nicht im Audio-Thread); Abfragen für die Übersicht oder
// einen Ausschnitt fassen nur diese Blöcke zusammen und brauchen die Audiodaten nicht mehr.
#pragma once

#include <vector>

namespace wp {

class Peaks {
public:
    // 32 Frames ≈ 0,7 ms bei 48 kHz; ein 5-Minuten-Titel braucht damit rund 3,6 MB.
    static constexpr int kBlockFrames = 32;

    Peaks() = default;
    Peaks(const float* interleaved, long long frames, int channels, int sampleRate);

    long long frames() const { return frames_; }
    double duration() const { return sampleRate_ > 0 ? static_cast<double>(frames_) / sampleRate_ : 0.0; }

    // Teilt [start, end] Sekunden in genau `count` gleich lange Abschnitte und schreibt je Abschnitt Minimum
    // und Maximum (−1…1) nach mins[i] und maxs[i]. Abschnitte kürzer als ein Block zeigen den ganzen Block.
    // false (nichts geschrieben): kein Titel, count < 1, start >= end oder Bereich ausserhalb des Titels.
    bool query(double start, double end, int count, float* mins, float* maxs) const;

private:
    std::vector<float> min_, max_;
    long long frames_ = 0;
    int sampleRate_ = 0;
};

}  // namespace wp
