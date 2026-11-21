// Dienste der App auf Desktop und Handy (#34 trennt sie vom Web): Bibliothek im App-Ordner, Audio-Kern
// über FFI mit eigenem Audiogerät, Aufnahme auf macOS. Gegenstück im Browser: platform_web.dart.
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:wp_core/wp_core.dart';

import '../library/library.dart';
import '../metronome/metronome_controller.dart';
import '../metronome/tap_tempo.dart';
import '../player/audio_core_ffi.dart';
import '../player/player_service.dart';
import '../ui/recording_button.dart';
import 'app_controller.dart';
import 'file_platform.dart';
import 'file_store_io.dart';
import 'library_settings_store.dart';
import 'smoke.dart';

/// App services. [baseDir] replaces the app folder (library, metronome settings), e.g. in the smoke
/// test, so the real library is never touched. [tapTempo] lets UI tests set the tap clock (#13).
Future<AppController> createAppController({
  Directory? baseDir,
  TapTempo? tapTempo,
}) async {
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
    tapTempo: tapTempo,
    store: LibrarySettingsStore(
      library,
      legacy: FileSettingsStore(File('$support/metronome.json')),
    ),
    onRunningChanged: files.keepAwake,
  );
  await metronome.restore();
  // #37: without an account no sync (NoSync); providers and accounts follow in #38/#40.
  final controller = AppController(
    library: library,
    player: PlayerService(WpAudioCore(player)),
    metronome: metronome,
    files: files,
  );
  await controller.start();
  return controller;
}

/// Aufnahme-Knopf, wenn der Kern Aufnahme kann (macOS 14.2+).
Widget? recordingButtonFor(AppController controller) =>
    WpRecorder.available ? RecordingButton(controller: controller) : null;

/// The hint «Add to Home Screen» is for the browser only (#39/AK6).
bool get installHintWanted => false;

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

/// #13/AK5: WP_SMOKE=1 starts the smoke test of the built app (smoke.dart, tools/smoke_app.sh).
bool get smokeRequested => Platform.environment['WP_SMOKE'] == '1';

/// Runs the smoke test in a temporary folder with a generated sine file, shows the app built by [app]
/// and ends the process with 0 (passed) or 1 (failed, reason on stdout).
Future<Never> runSmokeApp(Widget Function(AppController c) app) async {
  final dir = Directory.systemTemp.createTempSync('wp_smoke');
  var failure = 'not started';
  try {
    final wav = File('${dir.path}/Smoke sine.wav')..writeAsBytesSync(sineWav());
    final c = await createAppController(baseDir: Directory('${dir.path}/app'));
    runApp(app(c));
    failure = await smokeRun(c, wav.path) ?? '';
  } catch (e) {
    failure = 'exception: $e';
  }
  stdout.writeln(failure.isEmpty ? 'smoke: ok' : 'smoke: FAILED, $failure');
  await stdout.flush();
  try {
    dir.deleteSync(recursive: true);
  } on FileSystemException {
    // left for the system to clean up
  }
  exit(failure.isEmpty ? 0 : 1);
}
