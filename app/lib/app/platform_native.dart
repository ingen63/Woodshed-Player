// Services of the app on desktop and phone (#34 separates them from the web): library in the app folder,
// audio core over FFI with its own audio device, recording on macOS (#162: the microphone also on
// Windows and Linux). Counterpart in the browser: platform_web.dart.
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
// #161: the smoke test of the sign-in (WP_SMOKE=google), loaded only then
import '../sync/providers/google_smoke.dart' deferred as google_smoke;
import '../ui/armed_switch.dart';
import '../ui/recording_button.dart';
import 'app_controller.dart';
import 'app_start.dart';
import 'command_channel.dart';
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
import 'recording_smoke.dart';
import 'smoke.dart';
import 'web_auth_channel.dart';
import 'test_host.dart';

/// App services. [baseDir] replaces the app folder (library, metronome settings), e.g. in the smoke
/// test, so the real library is never touched. [tapTempo] lets UI tests set the tap clock (#13).
/// #162: [files] replaces the platform channel's services (the smoke test of the recording keeps its
/// recordings in its own folder).
Future<AppController> createAppController({
  Directory? baseDir,
  TapTempo? tapTempo,
  ChannelFilePlatform? files,
}) async {
  final platform = files ?? ChannelFilePlatform();
  final support =
      baseDir?.path ?? await platform.supportDir() ?? Directory.systemTemp.path;
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
    onRunningChanged: platform.keepAwake,
  );
  await metronome.restore();
  final playerService = PlayerService(WpAudioCore(player));
  // #54, #161: Google Drive on the Mac, Windows and Linux; on iPhone and iPad only in the web app.
  // Linux without libsecret: no sync, a hint says why (#161/AK2). Without a choice NoSync.
  final secrets = KeychainStore();
  final secretStoreMissing =
      googleOnThisPlatform &&
      baseDir == null &&
      Platform.isLinux &&
      !await secrets.available();
  final cloud = CloudAccount(
    library: library,
    chooseFolders: true,
    secretStoreMissing: secretStoreMissing,
    loadGoogle: !googleOnThisPlatform || baseDir != null || secretStoreMissing
        ? null
        : () async {
            await google.loadLibrary();
            return google.openGoogle(
              library: library,
              secrets: secrets,
              openUrl: platform.openUrl,
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
    files: platform,
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
  // #140: the command line of the desktop app (#60: also Windows and Linux); not in the smoke test
  // (own folder)
  if (commandLineOnThisPlatform && baseDir == null) {
    unawaited(startCommandLine(controller));
  }
  return controller;
}

/// #54, #161: Google Drive is offered on the Mac, on Windows and on Linux (sign-in in the system browser
/// with a receiver on 127.0.0.1 there); on iPhone and iPad only in the web app.
bool get googleOnThisPlatform =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// #140, #60: the desktop app has a command line on macOS, Windows and Linux.
bool get commandLineOnThisPlatform =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// #162: `record` of the command line stays on the Mac; Windows and Linux record in the app only.
bool get commandLineRecords => Platform.isMacOS;

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

/// #147: the armed practice recording of [controller], where the microphone records (macOS, #162:
/// Windows and Linux).
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

/// The record button where the core records (macOS; #162: Windows and Linux with an input device).
Widget? recordingButtonFor(AppController controller) => WpRecorder.available
    ? RecordingButton(
        controller: controller,
        recording: recordingFor(controller),
      )
    : null;

/// #140: listens for the command line on the socket file the platform names; none, no listening.
/// #60: on Windows the runner listens and hands the lines over a channel (command_channel.dart).
Future<Object?> startCommandLine(AppController controller) async {
  final path = await controller.files.commandSocket();
  if (path == null) return null;
  final handler = CommandHandler(
    app: controller,
    recording: commandLineRecords ? recordingFor(controller) : null,
    texts: systemTexts,
  );
  return Platform.isWindows
      ? ChannelCommandServer.start(path, handler)
      : CommandServer.start(path, handler);
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

/// #162: the smoke test of the recording: the folder the platform names for recordings must exist;
/// the takes go to the smoke test's own folder.
Future<String?> _smokeRecording(AppController c, _SmokeFiles files) async {
  final platformDir = await files.platformRecordingsDir();
  if (platformDir == null || !Directory(platformDir).existsSync()) {
    return 'no folder for recordings: $platformDir';
  }
  final recording = recordingFor(c);
  final practice = practiceRecordingFor(c);
  if (recording == null || practice == null) return 'no recording here';
  return smokeRecording(
    c,
    recording: recording,
    practice: practice,
    setInput: WpRecorder.setInput,
    l: lookupAppLocalizations(const Locale('en')),
  );
}

/// #162: the platform's services, with the recordings in the smoke test's folder [recordings].
class _SmokeFiles extends ChannelFilePlatform {
  _SmokeFiles(this.recordings);
  final Directory recordings;

  @override
  Future<String?> recordingsDir() async => recordings.path;

  /// The folder the platform itself names for recordings.
  Future<String?> platformRecordingsDir() => super.recordingsDir();
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

/// #13/AK5: WP_SMOKE=1 starts the smoke test of the built app (smoke.dart, tools/smoke_app.sh); #161:
/// WP_SMOKE=google the smoke test of the Google sign-in with the token store of the system; #162:
/// WP_SMOKE=record the smoke test of the recording with the core's artificial input
/// (recording_smoke.dart).
bool get smokeRequested =>
    const {'1', 'google', 'record'}.contains(Platform.environment['WP_SMOKE']);

/// Runs the smoke test in a temporary folder with a generated sine file, shows the app built by [app]
/// and ends the process with 0 (passed) or 1 (failed, reason on stdout).
Future<Never> runSmokeApp(Widget Function(AppController c) app) async {
  final dir = Directory.systemTemp.createTempSync('wp_smoke');
  var failure = 'not started';
  try {
    final wav = File('${dir.path}/Smoke sine.wav')..writeAsBytesSync(sineWav());
    final mode = Platform.environment['WP_SMOKE'];
    final files = mode == 'record'
        ? _SmokeFiles(Directory('${dir.path}/Recordings')..createSync())
        : null;
    // #162: the artificial input before the app asks whether the microphone records
    if (mode == 'record') WpRecorder.setInput(WpRecInput.silence);
    final c = await createAppController(
      baseDir: Directory('${dir.path}/app'),
      files: files,
    );
    runApp(app(c));
    if (mode == 'google') {
      await google_smoke.loadLibrary();
      failure = await google_smoke.smokeGoogleSignIn(KeychainStore()) ?? '';
    } else if (files != null) {
      failure = await _smokeRecording(c, files) ?? '';
    } else {
      failure = await smokeRun(c, wav.path) ?? '';
    }
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
