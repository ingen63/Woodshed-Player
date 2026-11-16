/// Zeit als `mm:ss` (unter einer Stunde) bzw. `h:mm:ss`, wie in der alten App.
String formatTime(double seconds) {
  if (!seconds.isFinite || seconds < 0) seconds = 0;
  final total = seconds.floor();
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  return h > 0 ? '$h:${_two(m)}:${_two(s)}' : '${_two(m)}:${_two(s)}';
}

/// Wie [formatTime], mit Zehntelsekunden: `01:23.4`.
String formatTimePrecise(double seconds) {
  if (!seconds.isFinite || seconds < 0) seconds = 0;
  final tenths = (seconds * 10).round();
  return '${formatTime(tenths ~/ 10 * 1.0)}.${tenths % 10}';
}

/// Zeitfeld: ganze Sekunden ohne, sonst mit Zehntel.
String formatTimeField(double seconds) =>
    (seconds - seconds.roundToDouble()).abs() < 0.05
    ? formatTime(seconds.roundToDouble())
    : formatTimePrecise(seconds);

/// Liest `83`, `1:23`, `01:23.5`, `01:23,5` oder `1:02:05`; `null` bei ungültiger Eingabe.
double? parseTime(String text) {
  final cleaned = text.trim().replaceAll(',', '.');
  if (cleaned.isEmpty) return null;
  final parts = cleaned.split(':');
  if (parts.length > 3) return null;
  var result = 0.0;
  for (var i = 0; i < parts.length; i++) {
    final v = double.tryParse(parts[i]);
    if (v == null || v < 0 || !v.isFinite) return null;
    // Nur die erste Stelle darf über 59 liegen.
    if (i > 0 && v >= 60) return null;
    result = result * 60 + v;
  }
  return result;
}

/// Geschwindigkeit mit zwei Nachkommastellen und Dezimalkomma: `0,75×`.
String formatRate(double rate) =>
    '${rate.toStringAsFixed(2).replaceAll('.', ',')}×';

/// Zeitstempel für Dateinamen, z. B. `2026-11-16 14.05.09` (ohne Doppelpunkte).
String fileStamp(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}.${_two(t.minute)}.${_two(t.second)}';

String _two(int v) => v.toString().padLeft(2, '0');
