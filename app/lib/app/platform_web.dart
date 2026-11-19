// Dienste der App im Browser: WASM-Kern im AudioWorklet (#34), Bibliothek im Origin Private File System
// (#35), Import über die Dateiauswahl. Keine Aufnahme. Gegenstück auf Desktop und Handy: platform_native.dart.
import 'package:material_ui/material_ui.dart';

import '../library/library.dart';
import '../metronome/metronome_controller.dart';
import '../player/audio_core_web.dart';
import '../player/player_service.dart';
import 'app_controller.dart';
import 'file_platform_web.dart';
import 'file_store_web.dart';

/// Ordner der Bibliothek im OPFS der Seite.
const libraryDir = 'WoodshedPlayer';

/// [baseDir] gibt es nur auf Desktop und Handy; im Browser liegt die Bibliothek im OPFS.
Future<AppController> createAppController({Object? baseDir}) async {
  final files = WebFilePlatform();
  final store = await OpfsFileStore.open(libraryDir);
  final core = await WebAudioCore.create(bytesOf: store.read);
  // Dauer kennt im Browser erst der Kern beim Laden.
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
