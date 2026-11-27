// Verbindet Bibliothek, Player und Metronom (#17): Titel wählen, importieren, löschen.
// Ohne Widgets, damit es sich in Tests prüfen lässt.
import 'dart:async';
import 'dart:math';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../library/library.dart';
import '../metronome/metronome_controller.dart';
import '../metronome/practice_session.dart';
import '../player/play_queue.dart';
import '../player/player_service.dart';
import '../sync/cloud_account.dart';
import '../sync/sync_service.dart';
import 'file_drop.dart';
import 'file_platform.dart';
import 'track_export.dart';

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
    CloudAccount? cloud,
    Random? random,
    this.trimmer,
    this.mp3,
  }) : session = PracticeSession(player, metronome),
       cloud = cloud ?? CloudAccount(library: library),
       _random = random ?? Random() {
    this.sync = sync ?? this.cloud.sync;
    player.onSettingsChanged = library.updateSettings;
    player.onEnded = _trackEnded;
    library.onLocalChange = this.sync.localChanged;
    files.onFileDrag = _fileDrag;
    library.addListener(_libraryChanged);
    player.addListener(_playerChanged);
    files.showWindowAppearance(_windowAppearance = library.appearance);
  }

  final Library library;
  final PlayerService player;
  final MetronomeController metronome;
  final FilePlatform files;
  final PracticeSession session;

  /// Cloud sync (#37); [NoSync] without an account.
  late final SyncService sync;

  /// #54: the chosen storage, sign-in and status for the settings.
  final CloudAccount cloud;

  bool _wasPlaying = false;

  /// #54/AK5: a sync that waited for playback to end (the browser renews its sign-in by a redirect) goes
  /// on once playback stops.
  void _playerChanged() {
    final playing = player.isPlaying;
    if (_wasPlaying && !playing && sync.status == SyncStatus.offline) {
      sync.resumed();
    }
    _wasPlaying = playing;
  }

  final Random _random;

  /// #116: cuts audio files (the core); null where trimming is not available (tests without a core).
  final AudioTrimmer? trimmer;

  /// #141: encodes a file as MP3 (the core with LAME); null where the export is not offered (iPhone,
  /// iPad, browser, tests without a core).
  final Mp3Encode? mp3;

  /// #141: exports tracks as MP3 files; null where [mp3] is.
  TrackExporter? get exporter => switch (mp3) {
    final encode? => TrackExporter(
      library: library,
      fetchAudio: sync.fetchAudio,
      encode: encode,
    ),
    null => null,
  };

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

  /// After loading: the chosen storage (#54, nothing without one), then the first sync (trigger «start»,
  /// #37).
  Future<void> start() async {
    await cloud.open();
    await sync.start();
  }

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

  /// #152: the appearance the window's title bar shows; sent again only when the choice changes.
  late Appearance _windowAppearance;

  void _libraryChanged() {
    if (library.appearance != _windowAppearance) {
      files.showWindowAppearance(_windowAppearance = library.appearance);
    }
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

  /// #124: sorts the playlist once (see [Library.sortPlaylist]); a track of it being played goes on, and
  /// the queue moves with its row, so the next track follows the new order (AK5).
  void sortPlaylist(String id, PlaylistSortKey key, {bool descending = false}) {
    final moved = library.sortPlaylist(id, key, descending: descending);
    final q = _queue;
    if (moved == null || q == null || q.playlistId != id) return;
    final to = List.filled(moved.length, 0);
    for (final (i, from) in moved.indexed) {
      to[from] = i;
    }
    int row(int i) => i < to.length ? to[i] : i;
    _queue = q.at(row(q.index), order: [for (final i in q.order) row(i)]);
    notifyListeners();
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

  // ---- Files dragged in from outside (#121) ----

  /// The target under files dragged in from outside, for its highlight; null over anything else.
  final fileDropHover = ValueNotifier<FileDropTarget?>(null);

  /// Finds the target at a position of the window; the window sets it (hit test of its widgets).
  FileDropTarget? Function(Offset position) dropTargetAt = _noTarget;

  static FileDropTarget? _noTarget(Offset _) => null;

  void _fileDrag(FileDragEvent e) {
    switch (e) {
      case FileDragOver(:final position):
        fileDropHover.value = dropTargetAt(position);
      case FileDragLeave():
        fileDropHover.value = null;
      case FileDragDrop(:final paths, :final position):
        fileDropHover.value = null;
        dropFiles(paths, position == null ? null : dropTargetAt(position));
    }
  }

  /// Imports dropped files into [target]: into a playlist at its place in the order of the files, the
  /// track already in the library instead of a second file (AK1, AK2); into a folder, where tracks
  /// already present move as well (AK3). Without a target they only come into the library (#22).
  Future<ImportResult> dropFiles(
    List<String> paths,
    FileDropTarget? target,
  ) async {
    final folder = target is FolderDropTarget;
    final r = await importFiles(
      paths,
      folderId: folder ? target.folderId : null,
    );
    switch (target) {
      case PlaylistDropTarget(:final playlistId, :final at):
        library.addToPlaylist(playlistId, [
          for (final t in r.tracks) t.id,
        ], at: at);
      case FolderDropTarget(:final folderId):
        library.moveTracks({for (final t in r.duplicates) t.id}, folderId);
      case null:
    }
    return r;
  }

  // ---- Trimming (#116) ----

  /// The track whose file is being trimmed; null otherwise.
  String? get trimming => _trimming;
  String? _trimming;

  /// #116/AK1: loads [t] for the trim view (waveform, listening), unless it is the loaded track already.
  Future<bool> openForTrim(Track t) async {
    if (player.trackId == t.id) return true;
    return select(t);
  }

  /// #116: cuts the file of track [id] to [start] … [end] seconds. A loaded track is loaded again with its
  /// new file, at its start. On failure the track stays as it was and the library reports why (AK9).
  /// Returns the new ID, null on failure.
  Future<String?> trimTrack(String id, double start, double end) async {
    final trim = trimmer;
    if (trim == null || _trimming != null) return null;
    final loaded = player.trackId == id;
    if (loaded) {
      player.stopPreview();
      player.pause();
    }
    _trimming = id;
    notifyListeners();
    final next = await library.trimTrack(id, start, end, trim);
    _trimming = null;
    if (next != null && next != id && loaded) {
      final t = library.track(next);
      if (t != null) await _load(t);
    }
    notifyListeners();
    return next;
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
  /// #140: [artist] is set if given. Returns the new track, null if the library did not take it.
  /// #147: the track goes into the folder path [folders] (missing folders are created); with [select]
  /// false it is neither loaded nor played.
  Future<Track?> addRecording(
    String path, {
    String? title,
    String? artist,
    int? year,
    List<String> folders = const [],
    bool select = true,
  }) async {
    final r = await library.importFiles([path]);
    if (r.imported.isEmpty) return null;
    var track = r.imported.first;
    // #140/AK12a
    if (year != null && library.editYear(track.id, year)) {
      track = library.track(track.id) ?? track;
    }
    if ((title != null || artist != null) &&
        library.editMetadata(
          track.id,
          title: title ?? track.title,
          artist: artist ?? track.artist,
        )) {
      track = library.track(track.id) ?? track;
    }
    if (folders.isNotEmpty) {
      library.moveTracks({track.id}, library.folderPath(folders));
      track = library.track(track.id) ?? track;
    }
    if (select && await this.select(track)) session.playTitle();
    return track;
  }

  @override
  void dispose() {
    library.removeListener(_libraryChanged);
    player.removeListener(_playerChanged);
    library.onLocalChange = null;
    files.onFileDrag = null;
    fileDropHover.dispose();
    sync.dispose();
    cloud.dispose();
    super.dispose();
  }
}
