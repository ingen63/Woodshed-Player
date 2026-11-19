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

/// #15/AK3: verständliche deutsche Meldung zu einem Fehlercode des Kerns.
String loadErrorMessage(int code, {String? file}) {
  final name = file == null ? 'Die Datei' : 'Die Datei «$file»';
  return switch (code) {
    WpCode.fileNotFound =>
      '$name wurde nicht gefunden. Wurde sie verschoben oder gelöscht?',
    WpCode.unsupportedFormat =>
      '$name ist kein unterstütztes Audioformat (MP3, WAV, FLAC) oder beschädigt.',
    WpCode.fileUnreadable =>
      '$name kann nicht gelesen werden. Fehlen die Zugriffsrechte?',
    WpCode.deviceUnavailable => 'Kein Audiogerät verfügbar. Bitte Kopfhörer oder Lautsprecher prüfen und erneut versuchen.',
    WpCode.outOfMemory => '$name ist zu gross für den freien Arbeitsspeicher.',
    WpCode.cancelled => 'Das Laden wurde abgebrochen.',
    WpCode.busy =>
      'Der Audio-Kern ist gerade ausgelastet. Bitte erneut versuchen.',
    WpCode.invalidArgument => 'Ungültige Datei-Angabe.',
    _ => 'Unbekannter Fehler beim Laden (Code $code).',
  };
}
