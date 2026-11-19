/// Plattformunabhängige Typen des Audio-Kerns (#34): gelten für die FFI-Anbindung (wp_core.dart) und die
/// Web-Anbindung der App (WASM-Kern im AudioWorklet). Ohne dart:ffi, darum auch im Browser nutzbar.
library;

import 'dart:typed_data';

/// Fehlercodes und Ladezustände wie in wp_core.h (`WP_ERR_*`, `WP_LOAD_*`).
abstract final class WpCode {
  static const ok = 0;
  static const invalidArgument = -1;
  static const fileNotFound = -2;
  static const unsupportedFormat = -3;
  static const deviceUnavailable = -4;
  static const outOfMemory = -5;
  static const fileUnreadable = -6;
  static const cancelled = -7;
  static const busy = -8;

  static const loadIdle = 0;
  static const loadRunning = 1;
  static const loadReady = 2;
}

/// Minimum und Maximum je Abschnitt einer Wellenform, gleich lang, Werte −1…1.
class WpWaveform {
  WpWaveform(this.min, this.max);
  final Float32List min;
  final Float32List max;
  int get length => min.length;
}

class WpException implements Exception {
  WpException(this.message);
  final String message;
  @override
  String toString() => message;
}
