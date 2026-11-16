/// Zeit als `m:ss` (unter einer Stunde) bzw. `h:mm:ss`.
String formatTime(double seconds) {
  if (!seconds.isFinite || seconds < 0) seconds = 0;
  final total = seconds.floor();
  final h = total ~/ 3600, m = (total % 3600) ~/ 60, s = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// Zeitstempel für Dateinamen, z. B. `2026-11-16 14.05.09` (ohne Doppelpunkte).
String fileStamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}.${two(t.minute)}.${two(t.second)}';
}
