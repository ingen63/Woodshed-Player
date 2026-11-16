import 'metronome_settings.dart';

/// Tap-Tempo (#3): ab 2 Taps Tempo aus dem Mittel der Abstände der letzten bis zu 5 Taps;
/// nach mehr als 2 s Pause beginnt die Messung neu.
class TapTempo {
  TapTempo({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const maxTaps = 5;
  static const resetAfter = Duration(seconds: 2);

  final DateTime Function() _clock;
  final List<DateTime> _taps = [];

  /// Registriert einen Tap. Gibt das neue Tempo zurück oder `null`, solange es nur einen Tap gibt.
  int? tap() {
    final now = _clock();
    if (_taps.isNotEmpty && now.difference(_taps.last) > resetAfter) {
      _taps.clear();
    }
    _taps.add(now);
    if (_taps.length > maxTaps) _taps.removeAt(0);
    if (_taps.length < 2) return null;
    final spanMs = _taps.last.difference(_taps.first).inMicroseconds / 1000.0;
    final avgMs = spanMs / (_taps.length - 1);
    if (avgMs <= 0) return null;
    return MetronomeSettings.clampBpm((60000 / avgMs).round());
  }
}
