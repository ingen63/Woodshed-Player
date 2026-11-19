// Dienste der App auf Desktop und Handy (#34 trennt sie vom Web): Bibliothek im App-Ordner, Audio-Kern
// über FFI mit eigenem Audiogerät, Aufnahme auf macOS. Gegenstück im Browser: platform_web.dart.
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:wp_core/wp_core.dart';

import '../library/library.dart';
import '../metronome/metronome_controller.dart';
import '../player/audio_core_ffi.dart';
import '../player/player_service.dart';
import '../ui/recording_button.dart';
import 'app_controller.dart';
import 'file_platform.dart';
import 'file_store_io.dart';

/// Dienste der App. [baseDir] ersetzt den App-Ordner (Bibliothek, Metronom-Einstellungen), z. B. im
/// Rauchtest, damit nie die echte Bibliothek berührt wird.
Future<AppController> createAppController({Directory? baseDir}) async {
  final files = ChannelFilePlatform();
  final support =
      baseDir?.path ?? await files.supportDir() ?? Directory.systemTemp.path;
  final player = WpPlayer();
  final library = Library(
    IoFileStore(Directory('$support/WoodshedPlayer')),
    probe: wpFileDuration,
    readSource: readLocalFile,
  );
  await library.load();
  final metronome = MetronomeController(
    _PlayerMetronome(player),
    store: FileSettingsStore(File('$support/metronome.json')),
    onRunningChanged: files.keepAwake,
  );
  await metronome.restore();
  return AppController(
    library: library,
    player: PlayerService(WpAudioCore(player)),
    metronome: metronome,
    files: files,
  );
}

/// Aufnahme-Knopf, wenn der Kern Aufnahme kann (macOS 14.2+).
Widget? recordingButtonFor(AppController controller) =>
    WpRecorder.available ? RecordingButton(controller: controller) : null;

/// Verbindet den MetronomeController mit dem Audio-Kern.
class _PlayerMetronome implements MetronomeBackend {
  _PlayerMetronome(this._p);
  final WpPlayer _p;

  @override
  void start() => _p.metronomeStart();
  @override
  void stop() => _p.metronomeStop();
  @override
  bool get running => _p.metronomeRunning;
  @override
  int get bpm => _p.metronomeBpm;
  @override
  set bpm(int v) => _p.metronomeBpm = v;
  @override
  set meter(int v) => _p.metronomeMeter = v;
  @override
  set subdivision(int v) => _p.metronomeSubdivision = v;
  @override
  set volume(double v) => _p.metronomeVolume = v;
  @override
  void ramp({
    required bool enabled,
    required int start,
    required int target,
    required int step,
    required int everyBars,
  }) => _p.metronomeRamp(
    enabled: enabled,
    start: start,
    target: target,
    step: step,
    everyBars: everyBars,
  );
  @override
  void timedRamp({
    required bool enabled,
    required int start,
    required int target,
    required int seconds,
  }) => _p.metronomeTimedRamp(
    enabled: enabled,
    start: start,
    target: target,
    seconds: seconds,
  );
}
