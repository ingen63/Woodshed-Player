import 'dart:math';

import '../library/playback_settings.dart';

/// #29: Steigerung der Titel-Geschwindigkeit nach Loop-Durchgängen. Zählt die Durchgänge auf der
/// aktuellen Stufe; die Einstellungen (Start, Ziel, Schritt, Durchgänge pro Stufe) stehen in
/// [PlaybackSettings] und werden pro Titel gespeichert, der Zähler nicht.
class LoopRamp {
  /// Durchgänge auf der aktuellen Stufe.
  int get passes => _passes;
  int _passes = 0;

  /// #29/AK5: Loop-Grenzen oder Geschwindigkeit von Hand geändert.
  void reset() => _passes = 0;

  /// Ist die Zielstufe erreicht (oder die Geschwindigkeit von Hand darüber gesetzt)?
  static bool atTarget(PlaybackSettings s) => s.speedPercent >= s.rampTarget;

  /// [count] neue Durchgänge. Gibt die neue Geschwindigkeit zurück, wenn eine Stufe erreicht ist, sonst null.
  /// #29/AK3: nach [PlaybackSettings.rampPasses] Durchgängen eine Stufe höher, der Zähler beginnt bei 0.
  /// #29/AK4: an der Zielstufe bleibt die Geschwindigkeit, der Zähler läuft weiter.
  double? addPasses(int count, PlaybackSettings s) {
    var percent = s.speedPercent;
    var changed = false;
    for (var i = 0; i < count; i++) {
      _passes++;
      if (percent >= s.rampTarget || _passes < s.rampPasses) continue;
      percent = min(percent + s.rampStep, s.rampTarget);
      _passes = 0;
      changed = true;
    }
    return changed ? percent / 100 : null;
  }

  /// #29/AK8: «75 % · 7 von 10», an der Zielstufe «100 % · Ziel erreicht · 14 Durchgänge».
  String label(PlaybackSettings s) {
    final p = s.speedPercent;
    if (atTarget(s)) {
      return '$p % · Ziel erreicht · $_passes ${_passes == 1 ? 'Durchgang' : 'Durchgänge'}';
    }
    return '$p % · $_passes von ${s.rampPasses}';
  }
}
