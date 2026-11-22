// App services in the browser: WASM core in the AudioWorklet (#34), library in the Origin Private File
// System (#35), import through the file picker. No recording. Media Session for the lock screen and
// headphone buttons (#39/AK2). The screen stays on while a track plays (#109). Desktop and mobile:
// platform_native.dart.
import 'dart:js_interop';

import 'package:material_ui/material_ui.dart';
import 'package:web/web.dart' as web;

import '../library/library.dart';
import '../metronome/metronome_controller.dart';
import '../metronome/tap_tempo.dart';
import '../player/audio_core_web.dart';
import '../player/player_service.dart';
import 'app_controller.dart';
import 'file_platform_web.dart';
import 'file_store_web.dart';
import 'install_hint.dart';
import 'library_settings_store.dart';
import 'media_session.dart';
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
  final files = WebFilePlatform();
  final store = await OpfsFileStore.open(libraryDir);
  final core = await WebAudioCore.create(bytesOf: store.read);
  // In the browser only the core knows the duration, once it loads the file.
  final library = Library(store, probe: (_) => null, readSource: files.take);
  await library.load();
  final metronome = MetronomeController(
    core.metronome,
    tapTempo: tapTempo,
    store: LibrarySettingsStore(library),
    onRunningChanged: files.keepAwake,
  );
  await metronome.restore();
  // #37: without an account no sync (NoSync); providers and accounts follow in #38/#40.
  final controller = AppController(
    library: library,
    player: PlayerService(core),
    metronome: metronome,
    files: files,
  );
  if (WebMediaSession.create() case final api?) {
    MediaSessionLink(api, controller); // lives as long as the page
  }
  if (WebWakeLock.create() case final api?) {
    WakeLockLink(api, controller.player); // lives as long as the page
  }
  await controller.start();
  return controller;
}

/// #39/AK5: there is no recording in the browser, so never a recording button.
Widget? recordingButtonFor(AppController controller) => null;

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

/// The smoke test of the built app (#13/AK5) exists only on desktop.
bool get smokeRequested => false;

Future<Never> runSmokeApp(Widget Function(AppController c) app) =>
    throw UnsupportedError('smoke test on desktop only');
