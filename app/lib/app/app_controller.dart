// Verbindet Bibliothek, Player und Metronom (#17): Titel wählen, importieren, löschen.
// Ohne Widgets, damit es sich in Tests prüfen lässt.
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../library/library.dart';
import '../metronome/metronome_controller.dart';
import '../metronome/practice_session.dart';
import '../player/play_queue.dart';
import '../player/player_service.dart';
import '../sync/sync_service.dart';
import 'file_platform.dart';

/// #115: the three areas of the app, in the order of their tabs (⌘1, ⌘2, ⌘3).
enum AppArea {
  player,
  practice,
  metronome;

  /// The area stored under [name] (DeviceSettings); Player if none or unknown.
  static AppArea named(String? name) =>
      values.firstWhere((a) => a.name == name, orElse: () => player);
}

class AppController extends ChangeNotifier {
  AppController({
    required this.library,
    required this.player,
    required this.metronome,
    required this.files,
    SyncService? sync,
    Random? random,
  }) : session = PracticeSession(player, metronome),
       sync = sync ?? NoSync(),
       _random = random ?? Random() {
    player.onSettingsChanged = library.updateSettings;
    player.onEnded = _trackEnded;
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

  final Random _random;

  /// #115/AK7: the area shown, the one last chosen on this device.
  AppArea get area => AppArea.named(library.area);

  /// The area (Player or Practice) a playing track shows its dot at: the one of the two shown last.
  AppArea get trackArea => _trackArea;
  AppArea _trackArea = AppArea.player;

  /// #115/AK1, AK3: switching the area changes nothing in playback, the metronome, position, loop or tempo.
  void setArea(AppArea a) {
    if (a == area) return;
    if (a != AppArea.metronome) _trackArea = a;
    unawaited(library.setArea(a.name));
    notifyListeners();
  }

  /// After loading: first sync (trigger «start», #37).
  Future<void> start() => sync.start();

  /// App back in the foreground (trigger «resume», #37).
  void resumed() => sync.resumed();

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

  /// Track whose file is being loaded from the cloud (#39/AK4); null otherwise.
  String? fetching;

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

  /// #114: the playlist being played and the row loaded; #115: or the folder a track was chosen from. Null
  /// when a track was chosen on its own.
  PlayQueue? get queue => _queue;
  PlayQueue? _queue;

  /// #115/AK8: repeat off, the list or the track.
  Repeat get repeat => _repeat;
  Repeat _repeat = Repeat.off;

  /// #115/AK10: the list plays in a random order, each track once per pass.
  bool get shuffle => _shuffle;
  bool _shuffle = false;

  /// The tracks of the list [q] is playing.
  List<Track> _tracksOf(PlayQueue q) => q.isPlaylist
      ? library.playlistTracks(q.playlistId!)
      : library.sortedTracksIn(q.folderId);

  /// The queue at the row of the loaded track: a folder may be sorted anew or a row moved meanwhile.
  PlayQueue? _current() {
    final q = _queue;
    if (q == null) return null;
    final tracks = _tracksOf(q);
    final id = player.trackId;
    if (q.index < tracks.length && tracks[q.index].id == id) return q;
    final i = tracks.indexWhere((t) => t.id == id);
    return i < 0 ? q : q.at(i, order: q.order);
  }

  /// Loads row [index] of playlist [playlistId]; at the end of each track the next row follows (#114/AK5).
  /// With [play] it starts at once («Play»); a tap on a row only loads, like a tap on a track.
  Future<bool> playPlaylist(
    String playlistId, {
    int index = 0,
    bool play = true,
  }) => _start(PlayQueue(playlistId, index), play: play);

  /// #115/AK9: a track chosen in the library plays within its folder: «Next» and the end of the track go
  /// on with the folder's next track.
  Future<bool> selectInFolder(Track track) {
    final t = library.track(track.id) ?? track; // the folder as it is now
    final i = library
        .sortedTracksIn(t.folderId)
        .indexWhere((x) => x.id == t.id);
    return i < 0
        ? select(t)
        : _start(PlayQueue.folder(t.folderId, i), play: false);
  }

  /// A new list from row [q.index]; with shuffle on, a new random order that begins with that row.
  Future<bool> _start(PlayQueue q, {required bool play}) {
    final length = _tracksOf(q).length;
    return _playAt(_shuffle ? q.shuffle(length, _random) : q, play: play);
  }

  Future<bool> _playAt(PlayQueue q, {required bool play}) async {
    final tracks = _tracksOf(q);
    if (q.index < 0 || q.index >= tracks.length) return false;
    _queue = q;
    notifyListeners();
    final ok = await _load(tracks[q.index]);
    if (ok && play && _queue == q) session.playTitle();
    return ok;
  }

  /// #114/AK5: the next row of the list follows; after the last one playback ends unless the list repeats
  /// (#115/AK8). An active loop never ends a track, so it repeats instead (#114/AK6, [PlayerService.onEnded]).
  void _trackEnded() {
    final q = _current();
    if (q == null) {
      if (_repeat == Repeat.track) _again();
      return;
    }
    final next = q.next(_tracksOf(q).length, repeat: _repeat, random: _random);
    if (next == null) return;
    if (next == q) return _again();
    unawaited(_playAt(next, play: true));
  }

  /// #115/AK8: repeat «track»: the same track from its start.
  void _again() {
    player.seek(0);
    session.playTitle();
  }

  /// #115/AK9: «Next»: the next track of the list, playing if one played. After the last track (repeat off)
  /// or without a list, playback stops at the end of the track.
  Future<void> next() async {
    if (!player.hasTrack) return;
    final q = _current();
    final next = q?.next(
      _tracksOf(q).length,
      repeat: _repeat,
      manual: true,
      random: _random,
    );
    if (next == null) {
      player.pause();
      player.seek(player.duration);
      return;
    }
    await _playAt(next, play: player.isPlaying);
  }

  /// #115/AK9: within the first seconds of a track «Previous» goes to the track before it in the list.
  static const previousWithin = 3.0;

  /// #115/AK9: «Previous»: to the start of the track; within its first 3 s to the previous track of the list.
  Future<void> previous() async {
    if (!player.hasTrack) return;
    final q = _current();
    final prev = player.position < previousWithin
        ? q?.previous(_tracksOf(q).length, repeat: _repeat, random: _random)
        : null;
    if (prev == null) return player.seek(0);
    await _playAt(prev, play: player.isPlaying);
  }

  /// #115/AK10: shuffle on or off; on, the list goes on in a new random order after the loaded track.
  void toggleShuffle() {
    _shuffle = !_shuffle;
    final q = _current();
    if (q != null) {
      _queue = _shuffle
          ? q.shuffle(_tracksOf(q).length, _random)
          : q.unshuffle();
    }
    notifyListeners();
  }

  /// #115/AK8: off → list → track → off.
  void cycleRepeat() {
    _repeat = _repeat.following;
    notifyListeners();
  }

  /// «On all devices» or «Only on this device» (#114/AK9); a playlist being played goes on under the new ID
  /// the library gives a playlist kept on this device. Returns that ID.
  String setPlaylistShared(String id, bool shared) {
    final next = library.setPlaylistShared(id, shared);
    final q = _queue;
    if (next != id && q != null && q.playlistId == id) {
      _queue = PlayQueue(next, q.index, order: q.order);
      notifyListeners();
    }
    return next;
  }

  /// Titel in den Player laden (ohne abzuspielen, wie in der Swift-App). A track chosen on its own ends
  /// playing a playlist (#114).
  Future<bool> select(Track t) {
    if (_queue != null) {
      _queue = null;
      notifyListeners();
    }
    return _load(t);
  }

  /// A track without a known duration (imported in the browser) gets the one the core found (#42/AK5).
  Future<bool> _load(Track t) async {
    // #39/AK3: the loaded track is the newest in the cache and never removed while loaded.
    library.inUse = t.id;
    unawaited(library.markUsed(t.id));
    // #37, #39/AK4: a file only in the cloud is loaded from there when played.
    if (!library.hasFile(t.id)) {
      fetching = t.id;
      notifyListeners();
      final ok = await sync.fetchAudio(t);
      fetching = null;
      notifyListeners();
      if (!ok) {
        library.inUse = player.trackId;
        _show(TrackNotOnDevice(t.title));
        return false;
      }
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
    if (ids.contains(player.trackId)) {
      player.unload();
      library.inUse = null;
      _queue = null;
    }
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
