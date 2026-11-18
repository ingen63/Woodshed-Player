// Verbindet Bibliothek, Player und Metronom (#17): Titel wählen, importieren, löschen.
// Ohne Widgets, damit es sich in Tests prüfen lässt.
import 'package:flutter/foundation.dart';

import '../library/library.dart';
import '../metronome/metronome_controller.dart';
import '../metronome/practice_session.dart';
import '../player/player_service.dart';
import 'file_platform.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.library,
    required this.player,
    required this.metronome,
    required this.files,
  }) : session = PracticeSession(player, metronome) {
    player.onSettingsChanged = library.updateSettings;
    files.onDropFiles = (paths) => importFiles(paths);
    library.addListener(_libraryChanged);
  }

  final Library library;
  final PlayerService player;
  final MetronomeController metronome;
  final FilePlatform files;
  final PracticeSession session;

  /// Meldung für einen Dialog (Fehler oder Ergebnis); die Oberfläche zeigt sie und ruft [clearMessage].
  String? message;

  void clearMessage() {
    message = null;
    notifyListeners();
  }

  void _show(String text) {
    message = text;
    notifyListeners();
  }

  void _libraryChanged() {
    final err = library.lastError;
    if (err != null) {
      library.lastError = null;
      _show(err);
    }
  }

  /// Der geladene Titel aus der Bibliothek (für Cover und Künstler).
  Track? get currentTrack {
    final id = player.trackId;
    return id == null ? null : library.track(id);
  }

  String? get currentArtwork {
    final t = currentTrack;
    return t == null ? null : library.artworkPath(t);
  }

  /// Titel in den Player laden (ohne abzuspielen, wie in der Swift-App).
  Future<bool> select(Track t) => player.load(
    library.filePath(t),
    title: t.title,
    trackId: t.id,
    settings: t.settings,
  );

  Future<void> pickAndImport({String? folderId}) async {
    final paths = await files.pickAudioFiles();
    if (paths.isNotEmpty) await importFiles(paths, folderId: folderId);
  }

  /// Importiert und lädt den ersten neuen Titel, falls noch keiner geladen ist.
  Future<ImportResult> importFiles(
    List<String> paths, {
    String? folderId,
  }) async {
    final r = await library.importFiles(paths, folderId: folderId);
    if (!player.hasTrack && r.imported.isNotEmpty) {
      await select(r.imported.first);
    }
    return r;
  }

  void deleteTracks(Set<String> ids) {
    if (ids.contains(player.trackId)) player.unload();
    library.delete(ids);
  }

  /// Fertige Aufnahme in die Bibliothek und abspielen.
  Future<void> addRecording(String path) async {
    final r = await library.importFiles([path]);
    if (r.imported.isEmpty) return;
    if (await select(r.imported.first)) session.playTitle();
  }

  @override
  void dispose() {
    library.removeListener(_libraryChanged);
    files.onDropFiles = null;
    super.dispose();
  }
}
