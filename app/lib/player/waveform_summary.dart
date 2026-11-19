// Wellenform im Browser (#34): Das AudioWorklet liefert sie nur als Nachricht, also asynchron. Darum holt
// die Web-Anbindung nach dem Laden einmal eine feine Wellenform des ganzen Titels und beantwortet jede
// Abfrage (Übersicht, Ausschnitt, Loop) daraus sofort.
import 'dart:math';
import 'dart:typed_data';

import 'package:wp_core/wp_types.dart';

class WaveformSummary {
  WaveformSummary(this.duration, this.mins, this.maxs)
    : assert(mins.length == maxs.length);

  /// Abschnitte pro Sekunde (5 ms, feiner als jeder Ausschnitt der Zeitleiste) und Obergrenze.
  static const binsPerSecond = 200;
  static const maxBins = 400000;

  /// Wie viele Abschnitte für einen Titel von [duration] Sekunden geholt werden.
  static int binsFor(double duration) =>
      (duration * binsPerSecond).ceil().clamp(1, maxBins);

  final double duration;
  final Float32List mins, maxs;

  int get length => mins.length;

  /// Wie `wp_waveform`: [count] Abschnitte von [start] bis [end] Sekunden, je Minimum und Maximum der
  /// darin liegenden feinen Abschnitte. Null bei ungültigen Grenzen.
  WpWaveform? query(double start, double end, int count) {
    final n = length;
    if (n == 0 || count <= 0 || duration <= 0) return null;
    final a = start.clamp(0.0, duration), b = end.clamp(0.0, duration);
    if (b <= a) return null;
    final perSecond = n / duration;
    final outMin = Float32List(count), outMax = Float32List(count);
    final step = (b - a) / count;
    for (var i = 0; i < count; i++) {
      final from = ((a + step * i) * perSecond).floor().clamp(0, n - 1);
      final to = max(
        from + 1,
        ((a + step * (i + 1)) * perSecond).ceil().clamp(0, n),
      );
      var lo = mins[from], hi = maxs[from];
      for (var j = from + 1; j < to; j++) {
        if (mins[j] < lo) lo = mins[j];
        if (maxs[j] > hi) hi = maxs[j];
      }
      outMin[i] = lo;
      outMax[i] = hi;
    }
    return WpWaveform(outMin, outMax);
  }
}
