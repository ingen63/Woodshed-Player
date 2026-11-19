// Austauschbare Schnittstelle zum Audio-Kern (#15): auf Desktop und Handy der C++-Kern über FFI
// (audio_core_ffi.dart), im Browser der WASM-Kern im AudioWorklet (audio_core_web.dart, #34), in Tests
// eine Attrappe. Welche Implementierung die App nimmt, entscheidet der bedingte Import in main.dart.
import 'package:wp_core/wp_types.dart';

/// Was der [PlayerService] vom Audio-Kern braucht. Zeiten in Sekunden der Originaldatei.
abstract class AudioCore {
  /// Startet das Laden im Hintergrund. [WpCode.ok] oder Fehlercode (< 0).
  int loadAsync(String path);

  /// `WpCode.load*` oder Fehlercode (< 0) des letzten Ladens.
  int get loadState;

  /// Fortschritt 0–1 des laufenden Ladens.
  double get loadProgress;

  void play();
  void pause();
  bool get isPlaying;
  void seek(double seconds);
  set rate(double rate);
  void setLoop(double a, double b);
  void clearLoop();
  set volume(double volume);
  double get position;
  double get duration;

  /// Loop-Durchgänge seit dem Start (#29): Sprünge vom Loop-Ende zum Anfang, ohne Seek. Zählt nur hoch.
  int get loopPasses;

  /// Wellenform (#28) von [start] bis [end] Sekunden in [count] Abschnitten; null, solange keine da ist.
  WpWaveform? waveform(double start, double end, int count);
}

/// #15/AK3: load error of the core; the UI turns it into a message in the user's language (#43).
class LoadError {
  const LoadError(this.code, this.file);

  /// Error code of the core (`WpCode`, < 0).
  final int code;

  /// Title or file name of the track that failed to load.
  final String file;

  @override
  bool operator ==(Object other) =>
      other is LoadError && other.code == code && other.file == file;

  @override
  int get hashCode => Object.hash(code, file);

  @override
  String toString() => 'LoadError($code, $file)';
}
