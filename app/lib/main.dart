// Woodshed Player (Flutter): Bibliothek (#16), Wiedergabe mit Tempo und Loop über den C++-Kern (#15),
// Metronom (#3), Aufnahme des Systemtons (macOS, #4). Oberfläche im Design «Studio» (#30).
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:wp_core/wp_core.dart';

import 'app/app_controller.dart';
import 'app/file_platform.dart';
import 'library/library.dart';
import 'metronome/metronome_controller.dart';
import 'player/audio_core.dart';
import 'player/player_service.dart';
import 'ui/font_licenses.dart';
import 'ui/home_page.dart';
import 'ui/recording_button.dart';
import 'ui/style.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  final controller = await createAppController();
  runApp(WoodshedApp(controller: controller, recording: WpRecorder.available));
}

/// Dienste der App. [baseDir] ersetzt den App-Ordner (Bibliothek, Metronom-Einstellungen), z. B. im
/// Rauchtest, damit nie die echte Bibliothek berührt wird.
Future<AppController> createAppController({Directory? baseDir}) async {
  final files = ChannelFilePlatform();
  final support =
      baseDir?.path ?? await files.supportDir() ?? Directory.systemTemp.path;
  final player = WpPlayer();
  final library = Library(
    Directory('$support/WoodshedPlayer'),
    probe: wpFileDuration,
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

class WoodshedApp extends StatelessWidget {
  const WoodshedApp({
    super.key,
    required this.controller,
    this.recording = false,
  });
  final AppController controller;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Woodshed Player',
      theme: woodshedTheme(Brightness.light),
      darkTheme: woodshedTheme(Brightness.dark),
      home: HomePage(
        controller: controller,
        recordingButton: recording
            ? RecordingButton(controller: controller)
            : null,
      ),
    );
  }
}

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
