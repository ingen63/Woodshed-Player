// Metronome and ramp presets are shared settings (#36/AK5): they live in the library's shared state instead
// of a file of their own, on desktop, mobile and in the browser alike.
import '../library/library.dart';
import '../metronome/metronome_controller.dart';

class LibrarySettingsStore implements SettingsStore {
  LibrarySettingsStore(this.library, {this.legacy});

  final Library library;

  /// Former `metronome.json` (desktop and mobile before #36); taken over once while the library has none.
  final SettingsStore? legacy;

  @override
  Future<Object?> load() async {
    final shared = library.metronomePreset;
    if (shared != null) return shared;
    final old = await legacy?.load();
    if (old is Map) {
      library.metronomePreset = old.cast<String, Object?>();
      return library.metronomePreset;
    }
    return null;
  }

  @override
  Future<void> save(Object json) async {
    if (json is Map) library.metronomePreset = json.cast<String, Object?>();
  }
}
