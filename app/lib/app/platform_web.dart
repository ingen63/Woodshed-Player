// App services in the browser: WASM core in the AudioWorklet (#34), library in the Origin Private File
// System (#35), import through the file picker. No recording. Desktop and mobile: platform_native.dart.
import 'package:material_ui/material_ui.dart';

import '../library/library.dart';
import '../metronome/metronome_controller.dart';
import '../player/audio_core_web.dart';
import '../player/player_service.dart';
import 'app_controller.dart';
import 'file_platform_web.dart';
import 'file_store_web.dart';

/// Library folder in the page's OPFS.
const libraryDir = 'WoodshedPlayer';

/// [baseDir] exists only on desktop and mobile; in the browser the library lives in the OPFS.
Future<AppController> createAppController({Object? baseDir}) async {
  final files = WebFilePlatform();
  final store = await OpfsFileStore.open(libraryDir);
  final core = await WebAudioCore.create(bytesOf: store.read);
  // In the browser only the core knows the duration, once it loads the file.
  final library = Library(store, probe: (_) => null, readSource: files.take);
  await library.load();
  final metronome = MetronomeController(
    core.metronome,
    store: _SessionStore(),
    onRunningChanged: files.keepAwake,
  );
  await metronome.restore();
  return AppController(
    library: library,
    player: PlayerService(core),
    metronome: metronome,
    files: files,
  );
}

/// Aufnahme gibt es im Browser nicht.
Widget? recordingButtonFor(AppController controller) => null;

/// Metronom-Einstellungen nur für die Sitzung.
class _SessionStore implements SettingsStore {
  Object? _json;
  @override
  Future<Object?> load() async => _json;
  @override
  Future<void> save(Object json) async => _json = json;
}
