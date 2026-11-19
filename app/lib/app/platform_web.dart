// App services in the browser: WASM core in the AudioWorklet (#34), library in the Origin Private File
// System (#35), import through the file picker. No recording. Desktop and mobile: platform_native.dart.
import 'package:material_ui/material_ui.dart';

import '../library/library.dart';
import '../metronome/metronome_controller.dart';
import '../metronome/tap_tempo.dart';
import '../player/audio_core_web.dart';
import '../player/player_service.dart';
import 'app_controller.dart';
import 'file_platform_web.dart';
import 'file_store_web.dart';
import 'library_settings_store.dart';

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
  await controller.start();
  return controller;
}

/// Aufnahme gibt es im Browser nicht.
Widget? recordingButtonFor(AppController controller) => null;

/// The smoke test of the built app (#13/AK5) exists only on desktop.
bool get smokeRequested => false;

Future<Never> runSmokeApp(Widget Function(AppController c) app) =>
    throw UnsupportedError('smoke test on desktop only');
