// Verbindet Bibliothek, Player und Metronom (#17): Titel wählen, importieren, löschen.
// Ohne Widgets, damit es sich in Tests prüfen lässt.
import 'package:flutter/foundation.dart';

import '../library/library.dart';
import '../metronome/metronome_controller.dart';
import '../metronome/practice_session.dart';
import '../player/player_service.dart';
import '../sync/sync_service.dart';
import 'file_platform.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.library,
    required this.player,
    required this.metronome,
    required this.files,
    SyncService? sync,
  }) : session = PracticeSession(player, metronome),
       sync = sync ?? NoSync() {
    player.onSettingsChanged = library.updateSettings;
    library.onLocalChange = this.sync.localChanged;
    files.onDropFiles = (paths) => importFiles(paths);
    library.addListener(_libraryChanged);
  }

  final Library library;
  final PlayerService player;
  final MetronomeController metronome;
  final FilePlatform files;
  final PracticeSession session;

  /// Cloud sync (#37); [NoSync] without an account.
  final SyncService sync;

  /// After loading: first sync (trigger «start», #37).
  Future<void> start() => sync.start();

  /// App back in the foreground (trigger «resume», #37).
  void resumed() => sync.resumed();

  /// #65: repairs a damaged `state.json` in the cloud as the user chose and shows the outcome.
  Future<void> repairCloudState(CloudStateRepair how) async {
    final result = await sync.repairCloudState(how);
    _show(switch (result) {
      CloudRepairResult.restored => const CloudStateRestored(),
      CloudRepairResult.overwritten => const CloudStateOverwritten(),
      CloudRepairResult.notDamaged => const CloudStateReadableAgain(),
      CloudRepairResult.noBackup => const CloudStateNoBackup(),
      CloudRepairResult.failed => const CloudStateRepairFailed(),
    });
  }

  /// Message for a dialog (error or result); the UI words and shows it, then calls [clearMessage].
  LibraryMessage? message;

  void clearMessage() {
    message = null;
    notifyListeners();
  }

  void _show(LibraryMessage m) {
    message = m;
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

  /// Title of the loaded track as the library has it now (edited titles show at once, #24).
  String? get currentTitle => currentTrack?.title ?? player.title;

  String? get currentArtwork {
    final t = currentTrack;
    return t == null ? null : library.artworkPath(t);
  }

  /// Titel in den Player laden (ohne abzuspielen, wie in der Swift-App). A track without a known
  /// duration (imported in the browser) gets the one the core found (#42/AK5).
  Future<bool> select(Track t) async {
    // #37: a file synced from another device is loaded from the cloud when played.
    if (!library.hasFile(t.id) && !await sync.fetchAudio(t)) {
      _show(TrackNotOnDevice(t.title));
      return false;
    }
    final ok = await player.load(
      library.filePath(t),
      title: t.title,
      trackId: t.id,
      settings: t.settings,
    );
    if (ok && player.trackId == t.id) {
      library.fillDuration(t.id, player.duration);
    }
    return ok;
  }

  Future<void> pickAndImport({String? folderId}) async {
    final paths = await files.pickAudioFiles();
    if (paths.isNotEmpty) await importFiles(paths, folderId: folderId);
  }

  /// Imports and loads the first new (or already present) track if none is loaded yet.
  Future<ImportResult> importFiles(
    List<String> paths, {
    String? folderId,
  }) async {
    final r = await library.importFiles(paths, folderId: folderId);
    final first = [...r.imported, ...r.duplicates].firstOrNull;
    if (!player.hasTrack && first != null) await select(first);
    return r;
  }

  void deleteTracks(Set<String> ids) {
    if (ids.contains(player.trackId)) player.unload();
    library.delete(ids);
  }

  /// Adds a finished recording to the library and plays it (#4). [title] replaces the name taken from
  /// the file, e.g. the date and time in the user's locale; it stays editable like any title (#24).
  Future<void> addRecording(String path, {String? title}) async {
    final r = await library.importFiles([path]);
    if (r.imported.isEmpty) return;
    var track = r.imported.first;
    if (title != null &&
        library.editMetadata(track.id, title: title, artist: track.artist)) {
      track = library.track(track.id) ?? track;
    }
    if (await select(track)) session.playTitle();
  }

  @override
  void dispose() {
    library.removeListener(_libraryChanged);
    library.onLocalChange = null;
    files.onDropFiles = null;
    sync.dispose();
    super.dispose();
  }
}
