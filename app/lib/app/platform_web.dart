// Dienste der App im Browser (#34): WASM-Kern im AudioWorklet, vorläufige Dateiauswahl und eine
// Bibliothek nur für die Sitzung (gespeichert wird erst mit #35). Keine Aufnahme.
// Gegenstück auf Desktop und Handy: platform_native.dart.
import 'package:material_ui/material_ui.dart';

import '../library/library.dart';
import '../metronome/metronome_controller.dart';
import '../player/audio_core_web.dart';
import '../player/player_service.dart';
import 'app_controller.dart';
import 'file_platform_web.dart';

/// [baseDir] gibt es nur auf Desktop und Handy; im Browser wird nichts gespeichert.
Future<AppController> createAppController({Object? baseDir}) async {
  final files = WebFilePlatform();
  final core = await WebAudioCore.create(bytesOf: files.bytesOf);
  final library = Library.session(probe: files.probe);
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
