import 'metronome_controller.dart';

/// Wiedergabe des Titels, soweit die Übe-Sitzung sie braucht.
abstract class TitleTransport {
  bool get isPlaying;
  void play();
  void pause();
}

/// #3/AK20: Titel und Metronom laufen nie gleichzeitig. Startet das Metronom, pausiert der Titel;
/// startet der Titel, stoppt das Metronom.
class PracticeSession {
  PracticeSession(this.title, this.metronome) {
    metronome.beforeStart = () {
      if (title.isPlaying) title.pause();
    };
  }

  final TitleTransport title;
  final MetronomeController metronome;

  void playTitle() {
    if (metronome.running) metronome.stop();
    title.play();
  }

  void toggleTitle() => title.isPlaying ? title.pause() : playTitle();
}
