// The recorder of the native audio core (#4, #113, #140): system audio and microphone through wp_core
// (dart:ffi), so only on desktop and mobile; the browser has recorder_web.dart (#157).
import 'package:wp_core/wp_core.dart';

import 'recording_controller.dart';

/// [Recorder] of the audio core.
class CoreRecorder with RecordingFiles implements Recorder {
  const CoreRecorder();
  @override
  bool sourceAvailable(WpRecSource source) =>
      WpRecorder.sourceAvailable(source);
  @override
  void start(String path, WpRecSource source) =>
      WpRecorder.startSource(path, source);
  @override
  void startArmed(
    String path,
    WpRecSource source, {
    required double thresholdDb,
    required double silenceSeconds,
    double? tailSeconds,
  }) => WpRecorder.startArmed(
    path,
    source,
    thresholdDb: thresholdDb,
    silenceSeconds: silenceSeconds,
    tailSeconds: tailSeconds,
  );
  @override
  void stop() => WpRecorder.stop();
  @override
  bool get isRecording => WpRecorder.isRecording;
  @override
  double get seconds => WpRecorder.seconds;
  @override
  WpRecGate get gate => WpRecorder.gate;
  @override
  double get keptSeconds => WpRecorder.keptSeconds;
  @override
  double get level => WpRecorder.level;
  @override
  bool get onlySilence => WpRecorder.onlySilence;

  /// The native core records until it is stopped.
  @override
  RecordingInterruption? get interruption => null;
}
