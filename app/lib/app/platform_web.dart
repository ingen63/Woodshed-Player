// App services in the browser: WASM core in the AudioWorklet (#34), library in the Origin Private File
// System (#35), import through the file picker. Recording through the microphone where the browser can
// (#157, recorder_web.dart). Media Session for the lock screen and headphone buttons (#39/AK2). The screen
// stays on while a track plays (#109). Desktop and mobile: platform_native.dart.
import 'dart:async';

import 'dart:js_interop';

import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' as web;

import '../library/library.dart';
import '../metronome/metronome_controller.dart';
import '../metronome/tap_tempo.dart';
import '../player/audio_core_web.dart';
import '../player/player_service.dart';
import '../sync/cloud_account.dart';
// #54/AK6: the provider module is loaded only once Google Drive is chosen
import '../sync/providers/google_platform_web.dart' deferred as google;
import '../sync/oauth_return_web.dart';
import 'app_controller.dart';
import 'app_start.dart';
import 'file_platform_web.dart';
import 'file_store_web.dart';
import 'install_hint.dart';
import 'library_settings_store.dart';
import 'practice_arming.dart';
import 'media_session.dart';
import 'practice_recording.dart';
import 'recorder_web.dart';
import 'recording_controller.dart';
import '../ui/armed_switch.dart';
import '../ui/recording_button.dart';
import 'media_session_web.dart';
import 'wake_lock.dart';
import 'wake_lock_web.dart';

/// Library folder in the page's OPFS.
const libraryDir = 'WoodshedPlayer';

/// [baseDir] exists only on desktop and mobile; in the browser the library lives in the OPFS.
/// [tapTempo] lets tests set the tap clock (#13).
Future<AppController> createAppController({
  Object? baseDir,
  TapTempo? tapTempo,
}) async {
  // #131: Google's answer before anything is awaited; the first frame replaces the address
  final signInAnswer = takeStartAnswer();
  final files = WebFilePlatform();
  final store = await OpfsFileStore.open(libraryDir);
  final core = await WebAudioCore.create(bytesOf: store.read);
  // #157: the microphone, where the browser can record (getUserMedia, i.e. HTTPS)
  final recorder = await WebRecorder.create(core);
  if (recorder != null) {
    files
      ..microphone = recorder.acquire
      ..recording = recorder.take;
  }
  // In the browser only the core knows the duration, once it loads the file.
  final library = Library(store, probe: (_) => null, readSource: files.take);
  await library.load();
  // #141/AK3: in the background, once per device
  unawaited(library.fillYears());
  final metronome = MetronomeController(
    core.metronome,
    tapTempo: tapTempo,
    store: LibrarySettingsStore(library),
    onRunningChanged: files.keepAwake,
  );
  await metronome.restore();
  final player = PlayerService(core);
  // #54: Google Drive (also on iPhone and iPad); without a choice NoSync.
  final cloud = CloudAccount(
    library: library,
    loadGoogle: () async {
      await google.loadLibrary();
      return google.openGoogle(
        library: library,
        secrets: null,
        openUrl: files.openUrl,
        playing: () => player.isPlaying,
        fragment: signInAnswer,
      );
    },
  );
  final controller = AppController(
    library: library,
    player: player,
    cloud: cloud,
    metronome: metronome,
    files: files,
    trimmer: core.trim, // #116: in the core's loader worker
  );
  RecordingController? recording;
  PracticeRecording? practice;
  if (recorder != null) {
    recording = _recordings[controller] = RecordingController(
      app: controller,
      recorder: recorder,
    );
    practice = _practice[controller] = PracticeRecording(
      app: controller,
      recording: recording,
    );
  }
  if (WebMediaSession.create() case final api?) {
    MediaSessionLink(api, controller); // lives as long as the page
  }
  if (WebWakeLock.create() case final api?) {
    // #157/AK7: also while a recording runs or «Armed» is on
    WakeLockLink(
      api,
      controller.player,
      recording: recording == null
          ? null
          : Listenable.merge([recording, practice]),
      recordingActive: () =>
          (recording?.busy ?? false) || (practice?.on ?? false),
    ); // lives as long as the page
  }
  // #54/AK1: the first frame never waits on keychain, network or sync
  startInBackground(controller);
  return controller;
}

final _recordings = Expando<RecordingController>();

/// #157: the recording of [controller]; null where the browser cannot record.
RecordingController? recordingFor(AppController controller) =>
    _recordings[controller];

/// #157/AK1: the record button with the microphone as its only source; none without getUserMedia.
Widget? recordingButtonFor(AppController controller) {
  final recording = recordingFor(controller);
  return recording == null
      ? null
      : RecordingButton(controller: controller, recording: recording);
}

final _practice = Expando<PracticeRecording>();

/// #157/AK4: the switch «Armed» where the browser can record.
ArmedSwitchSlot? armedSwitchFor(AppController controller) {
  final practice = _practice[controller];
  return practice == null
      ? null
      : (arming: practice, widget: ArmedSwitch(practice: practice));
}

@JS('navigator.standalone')
external bool? get _iosStandalone;

/// #39/AK6: iPhone or iPad in the browser, not started from the home screen.
bool get installHintWanted => wantsInstallHint(
  userAgent: web.window.navigator.userAgent,
  maxTouchPoints: web.window.navigator.maxTouchPoints,
  standalone:
      (_iosStandalone ?? false) ||
      web.window.matchMedia('(display-mode: standalone)').matches,
);

/// #144/AK3: the language the app shows, as `<html lang>` of the page (screen readers, hyphenation,
/// translation offers of the browser).
void showDocumentLanguage(Locale locale) =>
    web.document.documentElement?.setAttribute('lang', locale.toLanguageTag());

/// #151: the Swift tests exist only on macOS.
bool get swiftTestHost => false;

/// The smoke test of the built app (#13/AK5) exists only on desktop.
bool get smokeRequested => false;

Future<Never> runSmokeApp(Widget Function(AppController c) app) =>
    throw UnsupportedError('smoke test on desktop only');
