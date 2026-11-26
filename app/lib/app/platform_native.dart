// Dienste der App auf Desktop und Handy (#34 trennt sie vom Web): Bibliothek im App-Ordner, Audio-Kern
// über FFI mit eigenem Audiogerät, Aufnahme auf macOS. Gegenstück im Browser: platform_web.dart.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show PlatformDispatcher;

import 'package:material_ui/material_ui.dart';
import 'package:wp_core/wp_core.dart';

import '../l10n/app_localizations.dart';
import '../library/library.dart';
import '../metronome/metronome_controller.dart';
import '../metronome/tap_tempo.dart';
import '../player/audio_core_ffi.dart';
import '../player/player_service.dart';
import '../sync/cloud_account.dart';
// #54/AK6: the provider module is loaded only once Google Drive is chosen
import '../sync/providers/google_platform_io.dart' deferred as google;
import '../ui/armed_switch.dart';
import '../ui/recording_button.dart';
import 'app_controller.dart';
import 'app_start.dart';
import 'command_line.dart';
import 'command_server.dart';
import 'file_platform.dart';
import 'file_store_io.dart';
import 'keychain_store.dart';
import 'library_settings_store.dart';
import 'practice_arming.dart';
import 'core_recorder.dart';
import 'practice_recording.dart';
import 'recording_controller.dart';
import 'smoke.dart';
import 'web_auth_channel.dart';
import 'test_host.dart';

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
  // #141/AK3: in the background, once per device
  unawaited(library.fillYears());
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
  final playerService = PlayerService(WpAudioCore(player));
  // #54: Google Drive on the desktop; on iPhone and iPad only in the web app. Without a choice NoSync.
  final cloud = CloudAccount(
    library: library,
    chooseFolders: true,
    loadGoogle: Platform.isIOS || baseDir != null
        ? null
        : () async {
            await google.loadLibrary();
            return google.openGoogle(
              library: library,
              secrets: KeychainStore(),
              openUrl: files.openUrl,
              systemSignIn: Platform.isMacOS ? WebAuthChannel() : null,
              playing: () => playerService.isPlaying,
            );
          },
  );
  final controller = AppController(
    library: library,
    player: playerService,
    cloud: cloud,
    metronome: metronome,
    files: files,
    // #116: FLAC is encoded again, so the cut runs off the UI isolate
    trimmer: (bytes, start, end) =>
        Isolate.run(() => wpTrim(bytes, start, end)),
    // #141: MP3 export on the Mac; LAME lies in the app's Frameworks folder (tools/build-lame.sh)
    mp3: Platform.isMacOS
        ? (input, output, {cancel, onProgress}) => WpMp3.export(
            bundledLamePath(),
            input,
            output,
            cancel: cancel,
            onProgress: onProgress,
          )
        : null,
  );
  // #54/AK1: the first frame never waits on keychain, network or sync
  startInBackground(controller);
  // #140: the command line of the desktop app; not in the smoke test (own folder)
  if (Platform.isMacOS && baseDir == null) {
    unawaited(startCommandLine(controller));
  }
  return controller;
}

/// #141: LAME inside the app: `Woodshed Player.app/Contents/Frameworks/libmp3lame.dylib`.
String bundledLamePath() =>
    '${File(Platform.resolvedExecutable).parent.parent.path}/Frameworks/libmp3lame.dylib';

/// The recording of [controller], shared by the record button and the command line (#140).
final _recordings = Expando<RecordingController>();
RecordingController? recordingFor(AppController controller) =>
    WpRecorder.available
    ? _recordings[controller] ??= RecordingController(
        app: controller,
        recorder: const CoreRecorder(),
      )
    : null;

/// #147: the armed practice recording of [controller], where the microphone records (macOS).
final _practice = Expando<PracticeRecording>();
PracticeRecording? practiceRecordingFor(AppController controller) {
  final recording = recordingFor(controller);
  if (recording == null ||
      !WpRecorder.sourceAvailable(WpRecSource.microphone)) {
    return null;
  }
  return _practice[controller] ??= PracticeRecording(
    app: controller,
    recording: recording,
  );
}

/// #147: the switch «Armed» for the main window, where the microphone records.
ArmedSwitchSlot? armedSwitchFor(AppController controller) {
  final practice = practiceRecordingFor(controller);
  return practice == null
      ? null
      : (arming: practice, widget: ArmedSwitch(practice: practice));
}

/// Aufnahme-Knopf, wenn der Kern Aufnahme kann (macOS 14.2+).
Widget? recordingButtonFor(AppController controller) => WpRecorder.available
    ? RecordingButton(
        controller: controller,
        recording: recordingFor(controller),
      )
    : null;

/// #140: listens for the command line on the socket file the platform names; none, no listening.
Future<CommandServer?> startCommandLine(AppController controller) async {
  final path = await controller.files.commandSocket();
  if (path == null) return null;
  return CommandServer.start(
    path,
    CommandHandler(
      app: controller,
      recording: recordingFor(controller),
      texts: systemTexts,
    ),
  );
}

/// Texts in the first system language the app has, otherwise English (as the app, #43/AK3).
AppLocalizations systemTexts() {
  for (final p in PlatformDispatcher.instance.locales) {
    for (final s in AppLocalizations.supportedLocales) {
      if (s.languageCode == p.languageCode) return lookupAppLocalizations(s);
    }
  }
  return lookupAppLocalizations(const Locale('en'));
}

/// The page language exists only in the browser (#144/AK3); macOS and iOS take the system language.
void showDocumentLanguage(Locale locale) {}

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

/// #151: the app is only the host of the Swift tests; the Dart app does not start.
bool get swiftTestHost => isSwiftTestHost(Platform.environment);

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
