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

  /// #120: trimming an MP4 with several audio tracks.
  static const multipleTracks = -10;

  /// #120: trimming a fragmented MP4.
  static const fragmented = -11;

  /// #141: MP3 export without its encoder library (LAME).
  static const encoderUnavailable = -12;

  /// #141: the exported file cannot be written.
  static const fileUnwritable = -13;

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

  /// #140: threshold or pause of an armed recording out of range.
  static const invalidArgument = -12;

  /// #162: the system refuses access to the microphone (the privacy setting of Windows).
  static const accessDenied = -13;

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
    noInput,
    invalidArgument,
    accessDenied, //
  ];
}

/// States of an armed recording (#140), the values of `WP_REC_GATE_*` in wp_core.h.
enum WpRecGate {
  /// No recording, or one started without arming.
  off(0),

  /// Recording the source, nothing written until the first sound.
  armed(1),

  /// Sound came: written from 1 s before the first sound.
  recording(2),

  /// Silence long enough: the file ends 2 s after the last sound; stop the recording.
  done(3);

  const WpRecGate(this.code);
  final int code;

  /// The state of [code]; [off] for an unknown one.
  static WpRecGate of(int code) =>
      values.firstWhere((g) => g.code == code, orElse: () => off);
}

/// Settings of an armed recording (#140) and their range, as in sound_gate.hpp.
abstract final class WpRecArming {
  static const defaultThresholdDb = -50.0;
  static const defaultSilenceSeconds = 5.0;
  static const minThresholdDb = -120.0;
  static const maxThresholdDb = 0.0;
  static const minSilenceSeconds = 0.1;
  static const maxSilenceSeconds = 60.0;

  /// #147: kept after the last sound unless another tail is given (the command line).
  static const defaultTailSeconds = 2.0;
  static const minTailSeconds = 0.0;
  static const maxTailSeconds = 10.0;
}

/// Source of a recording (#113), the values of `WP_REC_SOURCE_*` in wp_core.h.
enum WpRecSource {
  /// System audio without Woodshed Player's own sound, recorded as FLAC (#4, #118).
  system(0, 'flac'),

  /// Default input device of the system, recorded as FLAC (#113).
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

/// #162: what the microphone source reads, the values of `WP_REC_INPUT_*` in wp_core.h. Besides the
/// device, artificial inputs for tests and the smoke tests on machines without a microphone.
enum WpRecInput {
  /// The default input device of the system (the normal case).
  device(0),

  /// Artificial: silence at 48 kHz in real time.
  silence(1),

  /// Artificial: a 440 Hz sine at about -12 dBFS.
  tone(2),

  /// A device that refuses access ([WpRecCode.accessDenied]).
  denied(3),

  /// No input device: the microphone is not available.
  none(4);

  const WpRecInput(this.code);
  final int code;
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

/// #116: a file trimmed by the core: its bytes and where it starts and ends in the old file (seconds), or
/// the error code ([WpCode], < 0) with no bytes.
class WpTrimmed {
  const WpTrimmed(Uint8List this.bytes, this.start, this.end)
    : code = WpCode.ok;
  const WpTrimmed.failed(this.code) : bytes = null, start = 0, end = 0;

  final int code;
  final Uint8List? bytes;
  final double start;
  final double end;

  /// Shortest part that may remain (WP_TRIM_MIN_SECONDS).
  static const minSeconds = 1.0;
}
