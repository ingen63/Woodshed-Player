// Austauschbare Schnittstelle zum Audio-Kern (#15): in der App der C++-Kern über FFI, in Tests eine Attrappe.
import 'package:wp_core/wp_core.dart';

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
}

/// Der echte Kern.
class WpAudioCore implements AudioCore {
  WpAudioCore(this.player);
  final WpPlayer player;

  @override
  int loadAsync(String path) => player.loadAsync(path);
  @override
  int get loadState => player.loadState;
  @override
  double get loadProgress => player.loadProgress;
  @override
  void play() => player.play();
  @override
  void pause() => player.pause();
  @override
  bool get isPlaying => player.isPlaying;
  @override
  void seek(double seconds) => player.seek(seconds);
  @override
  set rate(double rate) => player.rate = rate;
  @override
  void setLoop(double a, double b) => player.setLoop(a, b);
  @override
  void clearLoop() => player.clearLoop();
  @override
  set volume(double volume) => player.volume = volume;
  @override
  double get position => player.position;
  @override
  double get duration => player.duration;
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
