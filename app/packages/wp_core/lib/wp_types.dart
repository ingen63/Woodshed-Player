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
  static const unsupportedSampleRate = -9;

  static const loadIdle = 0;
  static const loadRunning = 1;
  static const loadReady = 2;
}

/// Range of sample rates the core accepts, as `WP_MIN_SAMPLE_RATE` and `WP_MAX_SAMPLE_RATE` in
/// wp_core.h (#76, #97); app/test/ffi_coverage_test.dart compares them.
abstract final class WpSampleRate {
  static const min = 8000;
  static const max = 192000;

  /// Rate to run an output at whose own rate is [deviceRate]: its own rate up to [max], [max] above
  /// it; the platform converts to the hardware rate (#97/AK6, as `wp::outputRate` in the core).
  static int output(int deviceRate) => deviceRate > max ? max : deviceRate;
}

/// Error codes of `wp_rec_start` as in wp_core.h (`WP_REC_ERR_*`, #44).
abstract final class WpRecCode {
  static const invalidPath = -1;
  static const unsupported = -2;
  static const tap = -3;
  static const tapFormat = -4;
  static const noOutput = -5;
  static const aggregate = -6;
  static const outOfMemory = -7;
  static const file = -8;
  static const ioProc = -9;
  static const start = -10;

  /// #113: no input device (microphone) or it could not be opened.
  static const noInput = -11;

  static const all = [
    invalidPath,
    unsupported,
    tap,
    tapFormat,
    noOutput,
    aggregate,
    outOfMemory,
    file,
    ioProc,
    start,
    noInput, //
  ];
}

/// Source of a recording (#113), the values of `WP_REC_SOURCE_*` in wp_core.h.
enum WpRecSource {
  /// System audio without Woodshed Player's own sound, recorded as WAV (#4).
  system(0, 'wav'),

  /// Default input device of the system, recorded as FLAC.
  microphone(1, 'flac');

  const WpRecSource(this.code, this.extension);
  final int code;

  /// File extension of the recording, without the dot.
  final String extension;

  /// The source stored under [name]; null if none or unknown.
  static WpRecSource? named(String? name) {
    for (final s in values) {
      if (s.name == name) return s;
    }
    return null;
  }
}

/// Recording could not start (#44): [code] is a [WpRecCode], [osStatus] the OSStatus or 0,
/// [message] the English text of the core for logs.
class WpRecordingException implements Exception {
  const WpRecordingException(this.code, this.osStatus, this.message);
  final int code;
  final int osStatus;
  final String message;
  @override
  String toString() => 'WpRecordingException($code): $message';
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
