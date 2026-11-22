// Library (#16): files are copied into the library, metadata and settings live in `library.json`.
// Since #35 through a storage layer ([FileStore]): file system on desktop and mobile, OPFS in the browser.
// Since #36 a track is identified by the SHA-256 of its contents (the same file is stored only once), and
// `library.json` holds the shared state with stamps and tombstones in format 2 (stamps.dart). The former
// Swift-compatible format 1 is migrated on the first start (migration.dart); device-local settings live
// in `device.json` (device_settings.dart).
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

import '../app/file_platform.dart';
import 'device_settings.dart';
import 'metadata.dart';
import 'migration.dart';
import 'natural_compare.dart';
import 'stamps.dart';
import 'track.dart';

export '../app/file_platform.dart' show FileStore, StorageInfo;
export 'device_settings.dart' show DeviceSettings;
export 'stamps.dart' show Hlc, SharedState, StampedRecord;
export 'track.dart';

/// Dauer einer Datei in Sekunden, < 0 = Fehler. In der App `wpFileDuration` aus dem Audio-Kern.
/// null = known only when loading (browser, where the core decodes in the worklet).
typedef DurationProbe = double? Function(String path);

/// Contents of a picked or dropped file (import source); null if it is missing.
typedef SourceReader = Future<Uint8List?> Function(String source);

/// Problem the library reports to the UI (#43: data, worded by the UI in the user's language).
sealed class LibraryMessage {
  const LibraryMessage();
}

/// `library.json` was unreadable and was kept under [backupName].
class LibraryCorrupt extends LibraryMessage {
  const LibraryCorrupt(this.backupName);
  final String backupName;
}

/// `library.json` was written by a newer app ([version] > [SharedState.formatVersion]). The library stays
/// read-only and is not overwritten; the user should update the app (#36/AK4).
class LibraryTooNew extends LibraryMessage {
  const LibraryTooNew(this.version);
  final int version;
}

/// Saving `library.json` failed.
class LibrarySaveFailed extends LibraryMessage {
  const LibrarySaveFailed(this.detail);
  final String detail;
}

/// The audio file of this track (title) is on another device only and not in the cloud (#37/AK5).
class TrackNotOnDevice extends LibraryMessage {
  const TrackNotOnDevice(this.title);
  final String title;
}

/// `state.json` in the cloud was written by a newer app ([version]); nothing is synced (#10/AK7).
class CloudStateTooNew extends LibraryMessage {
  const CloudStateTooNew(this.version);
  final int version;
}

/// These files (names) could not be imported.
class ImportFailed extends LibraryMessage {
  const ImportFailed(this.files);
  final List<String> files;
}

class ImportResult {
  const ImportResult(this.imported, this.failed, [this.duplicates = const []]);
  final List<Track> imported;

  /// Ursprüngliche Dateinamen, die nicht übernommen werden konnten.
  final List<String> failed;

  /// Tracks whose contents were already in the library (no second file).
  final List<Track> duplicates;
}

String _sha256Hex(Uint8List bytes) => crypto.sha256.convert(bytes).toString();

/// Up to this size (bytes) the hash is computed inline; that takes only milliseconds.
const _hashInline = 1 << 20;

class Library extends ChangeNotifier {
  /// [store] holds `library.json`, `device.json` and the `Tracks/` folder. [readSource] reads the
  /// files being imported (path on desktop, file picker key in the browser).
  Library(
    this.store, {
    required this.probe,
    required this.readSource,
    DateTime Function()? now,
    this.saveDelay = const Duration(milliseconds: 400),
    Random? random,
  }) : _now = now ?? DateTime.now,
       _random = random; // ignore: prefer_initializing_formals

  final FileStore store;
  final DurationProbe probe;
  final SourceReader readSource;
  final Duration saveDelay;
  final DateTime Function() _now;
  final Random? _random;

  static const indexName = 'library.json';

  /// Settings of the Flutter app before #36; read once and then kept as a backup.
  static const legacyPrefsName = 'preferences.json';
  static String trackName(String fileName) => LibraryFiles.trackName(fileName);
  static String _artworkName(String id) => LibraryFiles.artworkName(id);

  List<Track> _tracks = [];
  List<TrackFolder> _folders = [];
  TrackSortOrder _sortOrder = TrackSortOrder.dateAdded;
  Appearance _appearance = Appearance.system;
  Map<String, Object?>? _metronome;
  bool _importing = false;
  int _droppedMissing = 0;

  /// Persisted shared state with stamps; the lists above are its live view. [save] stamps the differences.
  SharedState _state = SharedState.empty;
  DeviceSettings _device = const DeviceSettings(deviceId: '0000000000000000');
  late HlcClock _clock = HlcClock(_device.deviceId, now: _now);
  bool _readOnly = false;
  int _newerVersion = 0;

  /// Tracks whose audio file is not on this device (synced from another one, #37).
  final _absent = <String>{};

  /// Called after the library saved a change made on this device (not after [mergeRemote]); the sync
  /// engine schedules a sync (#37).
  void Function()? onLocalChange;

  /// Problem for the UI (#43: as data, the UI words it); the UI clears it after showing it.
  LibraryMessage? lastError;
  Timer? _pendingSave;
  StorageInfo? _storage;
  bool _persistAsked = false;

  List<Track> get tracks => List.unmodifiable(_tracks);
  List<TrackFolder> get folders => List.unmodifiable(_folders);
  bool get isImporting => _importing;

  /// Beim letzten Laden entfernte Einträge, deren Datei fehlte.
  int get droppedMissing => _droppedMissing;

  /// Shared state as last saved (with stamps and tombstones), for the sync engine (#37). Tracks and folders
  /// held back ([heldNames], #107) are left out: they stay on this device until the user decides.
  SharedState get state {
    final d = _device;
    if (d.heldTracks.isEmpty && d.heldFolders.isEmpty) return _state;
    final cached = _shared;
    if (cached != null && identical(cached.$1, _state)) return cached.$2;
    final shared = _state.copyWith(
      tracks: {
        for (final e in _state.tracks.entries)
          if (!d.heldTracks.contains(e.key)) e.key: e.value,
      },
      folders: {
        for (final e in _state.folders.entries)
          if (!d.heldFolders.contains(e.key)) e.key: e.value,
      },
    );
    _shared = (_state, shared);
    return shared;
  }

  /// [state] computed for this [_state]; cleared whenever the held records change.
  (SharedState, SharedState)? _shared;

  /// #107: names of the own tracks and folders held back from the sync, folders first, each sorted; empty
  /// if there is nothing to decide.
  List<String> get heldNames {
    final d = _device;
    return [
      ...[
        for (final f in _folders)
          if (d.heldFolders.contains(f.id)) f.name,
      ]..sort(naturalCompare),
      ...[
        for (final t in _tracks)
          if (d.heldTracks.contains(t.id)) t.title,
      ]..sort(naturalCompare),
    ];
  }

  /// Device-local settings (#36/AK5).
  DeviceSettings get device => _device;

  /// The file is from a newer app: nothing is written (#36/AK4).
  bool get readOnly => _readOnly;

  /// Used storage (in the browser also available space and persistence); null until measured.
  StorageInfo? get storage => _storage;

  TrackSortOrder get sortOrder => _sortOrder;
  set sortOrder(TrackSortOrder o) {
    if (o == _sortOrder) return;
    _sortOrder = o;
    save();
    notifyListeners();
  }

  /// Light, dark or system appearance (#31), a shared setting next to the sort order.
  Appearance get appearance => _appearance;
  set appearance(Appearance a) {
    if (a == _appearance) return;
    _appearance = a;
    save();
    notifyListeners();
  }

  /// Metronome and ramp presets (shared, #36/AK5) as MetronomeSettings JSON; null until first set.
  Map<String, Object?>? get metronomePreset =>
      _metronome == null ? null : Map.unmodifiable(_metronome!);
  set metronomePreset(Map<String, Object?>? m) {
    if (m == null || sameJson(m, _metronome)) return;
    _metronome = Map.of(m);
    _scheduleSave();
  }

  // ---- Laden und Speichern ----

  Future<void> load() async {
    _device = await DeviceSettings.load(store, random: _random);
    _clock = HlcClock(_device.deviceId, now: _now);
    _droppedMissing = 0;
    _readOnly = false;
    _absent.clear();
    final raw = await store.read(indexName);
    if (raw == null) {
      await _setHeld(const {}, const {});
      await _readLegacyPrefs();
      notifyListeners();
      return _afterLoad();
    }
    Object? json;
    try {
      json = jsonDecode(utf8.decode(raw));
    } catch (_) {}
    final version = json is Map ? json['formatVersion'] : 1;
    if (json != null && version is int && version > SharedState.formatVersion) {
      // #36/AK4: never overwrite a newer format.
      _readOnly = true;
      _newerVersion = version;
      lastError = LibraryTooNew(version);
      notifyListeners();
      return _afterLoad();
    }
    try {
      if (json == null || !isFiniteJson(json)) throw const FormatException();
      if (version == SharedState.formatVersion) {
        _state = SharedState.fromJson((json as Map).cast());
        _clock.observe(_state.latest);
        _clock.observe(_state.purged);
        // #104: a `device.json` from before the flag; foreign stamps show that this device has synced
        if (!_device.synced && _state.stampedByOthers(_device.deviceId)) {
          await markSynced();
        }
        _state = _state.purge(_now());
        _materialize();
      } else {
        await _migrate(raw);
      }
    } catch (_) {
      // Unlesbar: Datei aufheben statt beim nächsten Speichern zu überschreiben.
      final stamp = _now().toIso8601String().replaceAll(':', '-');
      try {
        await store.rename(indexName, '$indexName.defekt-$stamp');
      } catch (_) {}
      lastError = LibraryCorrupt('$indexName.defekt-$stamp');
      _state = SharedState.empty;
      await _setHeld(const {}, const {});
      _tracks = [];
      _folders = [];
      notifyListeners();
      return _afterLoad();
    }
    final present = <Track>[];
    _absent.clear();
    for (final t in _tracks) {
      if (await store.exists(trackName(t.fileName))) {
        present.add(t);
      } else if (_device.evicted.contains(t.id) ||
          _state.tracks[t.id]?.stamps['fileName']?.device != _device.deviceId) {
        // Imported on another device (#37) or removed from the cache (#39/AK3): stays visible without a
        // file here.
        present.add(t);
        _absent.add(t.id);
      }
    }
    if (present.length < _tracks.length) {
      // A file imported here and now missing drops out as before; its record goes too (no tombstone).
      final gone = {for (final t in _tracks) t.id}
        ..removeAll(present.map((t) => t.id));
      _droppedMissing += gone.length;
      _tracks = present;
      _state = _state.copyWith(
        tracks: {
          for (final e in _state.tracks.entries)
            if (!gone.contains(e.key)) e.key: e.value,
        },
      );
    }
    // #107/AK5: the held records survive a restart, as far as they are still there and alive
    await _setHeld(
      _device.heldTracks.where((id) => _state.tracks[id]?.alive ?? false),
      _device.heldFolders.where((id) => _state.folders[id]?.alive ?? false),
    );
    notifyListeners();
    return _afterLoad();
  }

  /// Format 1 → 2 (#36/AK3): IDs and files renamed, everything stamped now, written at once.
  Future<void> _migrate(Uint8List raw) async {
    final legacy = await migrateLegacyLibrary(store, raw);
    _folders = legacy.folders;
    // #10 (found with the golden files): `[Track]` of the Swift app has no folders, but its entries may
    // still name one. Such a track showed in no folder until the next start; now it shows without one,
    // like a track whose folder was deleted on another device.
    final folderIds = {for (final f in _folders) f.id};
    _tracks = [
      for (final t in legacy.tracks)
        t.folderId == null || folderIds.contains(t.folderId)
            ? t
            : t.copyWith(folderId: () => null),
    ];
    _droppedMissing = legacy.missing;
    await _readLegacyPrefs();
    _state = SharedState.empty;
    await _write();
  }

  /// Builds the live lists from the alive records. A track in a deleted folder shows without folder.
  void _materialize() {
    _folders = [
      for (final e in _state.folders.entries)
        if (e.value.alive) TrackFolder.fromShared(e.key, e.value.values),
    ];
    final folderIds = {for (final f in _folders) f.id};
    _tracks = [
      for (final e in _state.tracks.entries)
        if (e.value.alive)
          switch (Track.fromShared(e.key, e.value.values)) {
            final t
                when t.folderId != null && !folderIds.contains(t.folderId) =>
              t.copyWith(folderId: () => null),
            final t => t,
          },
    ];
    final s = _state.settings.values;
    _sortOrder = TrackSortOrder.parse(s['sortOrder'] as String?);
    _appearance = Appearance.parse(s['appearance']);
    final m = {
      for (final e in s.entries)
        if (e.key.startsWith(_metronomePrefix))
          e.key.substring(_metronomePrefix.length): e.value,
    };
    _metronome = m.isEmpty ? null : m;
  }

  static const _metronomePrefix = 'metronome.';

  /// Shared settings (#36/AK5), each stamped on its own.
  Map<String, Object?> _settingsValues() => {
    'sortOrder': _sortOrder.name,
    'appearance': _appearance.name,
    if (_metronome case final m?)
      for (final e in m.entries) '$_metronomePrefix${e.key}': e.value,
  };

  /// Stamps everything that changed since the last save; removed tracks and folders become tombstones.
  void _commit() {
    final stamp = _clock.tick();
    Map<String, StampedRecord> records(
      Map<String, StampedRecord> old,
      Map<String, Map<String, Object?>> live,
    ) => {
      for (final e in old.entries)
        if (!live.containsKey(e.key))
          e.key: e.value.alive ? e.value.delete(stamp) : e.value,
      for (final e in live.entries)
        e.key:
            old[e.key]?.update(e.value, stamp) ??
            StampedRecord.create(e.value, stamp),
    };
    _state = SharedState(
      tracks: records(_state.tracks, {
        for (final t in _tracks) t.id: t.toShared(),
      }),
      folders: records(_state.folders, {
        for (final f in _folders) f.id: f.toShared(),
      }),
      settings: _state.settings.update(_chosenSettings(), stamp),
      purged: _state.purged,
    );
  }

  /// #10 (found by the random sync tests): shared settings without a stamp that are still at their default
  /// (sort order «date added», appearance «system») were never chosen on this device and are not stamped.
  /// Before, the first save of a new device stamped its defaults as the newest change, and its first sync
  /// reset the sort order and appearance chosen on all other devices.
  Map<String, Object?> _chosenSettings() {
    final stamped = _state.settings.stamps;
    return {
      for (final e in _settingsValues().entries)
        if (stamped.containsKey(e.key) || !_isDefault(e.key, e.value))
          e.key: e.value,
    };
  }

  static bool _isDefault(String key, Object? value) =>
      (key == 'sortOrder' && value == TrackSortOrder.dateAdded.name) ||
      (key == 'appearance' && value == Appearance.system.name);

  Future<void> _afterLoad() async {
    if (_tracks.isNotEmpty) await _askPersistence();
    await refreshStorage();
  }

  /// Requests persistent storage once there is something to keep (only has an effect in the browser).
  Future<void> _askPersistence() async {
    if (_persistAsked) return;
    _persistAsked = true;
    try {
      await store.requestPersistence();
    } catch (_) {}
  }

  /// Measures used storage again (after load, import and delete).
  Future<void> refreshStorage() async {
    try {
      _storage = await store.storageInfo();
      notifyListeners();
    } catch (_) {}
  }

  /// Writes `library.json` atomically. In the file system the file is written when the call returns; in
  /// the browser shortly after, in call order.
  /// Never when the file is from a newer app (#36/AK4).
  Future<void> save() {
    _pendingSave?.cancel();
    _pendingSave = null;
    if (_readOnly) return Future.value();
    final before = _state.latest;
    final done = _write().catchError((Object e) {
      lastError = LibrarySaveFailed('$e');
      notifyListeners();
    });
    if (_state.latest != before) onLocalChange?.call();
    return done;
  }

  // ---- Sync (#37) ----

  /// Merges the shared state of another device or the cloud into the library and saves the result. Local
  /// changes not yet saved are stamped first, so nothing is lost. Tracks deleted elsewhere lose their
  /// local files; tracks new here are marked as without a file until it arrives ([addAudio]).
  Future<void> mergeRemote(SharedState remote) async {
    if (_readOnly) return;
    _pendingSave?.cancel();
    _pendingSave = null;
    _commit();
    _clock.observe(remote.latest);
    _clock.observe(remote.purged);
    if (!_device.synced) {
      // #104: the purge horizon applies only between devices that have synced before
      _state = _state.beforeFirstSync(remote, _clock.tick());
    }
    final before = {for (final t in _tracks) t.id: t};
    // #107: own records the horizon of [remote] would kill are held back as they are until the user keeps
    // or removes them; everything else is merged
    final lost = _state.lostTo(remote);
    final mine = _state;
    final merged = _state.merge(remote).purge(_now());
    _state = merged.copyWith(
      tracks: {
        ...merged.tracks,
        for (final id in lost.tracks) id: mine.tracks[id]!,
      },
      folders: {
        ...merged.folders,
        for (final id in lost.folders) id: mine.folders[id]!,
      },
    );
    await _setHeld(lost.tracks, lost.folders);
    _materialize();
    final alive = {for (final t in _tracks) t.id};
    for (final t in before.values) {
      if (!alive.contains(t.id)) {
        await store.delete(trackName(t.fileName)).catchError((_) {});
        await store.delete(_artworkName(t.id)).catchError((_) {});
      }
    }
    _absent.removeWhere((id) => !alive.contains(id));
    for (final t in _tracks) {
      if (!before.containsKey(t.id) || _absent.contains(t.id)) {
        if (await store.exists(trackName(t.fileName))) {
          _absent.remove(t.id);
        } else {
          _absent.add(t.id);
        }
      }
    }
    try {
      await _write();
      await markSynced();
    } catch (e) {
      lastError = LibrarySaveFailed('$e');
    }
    notifyListeners();
  }

  /// #107 «Keep»: the held tracks and folders are stamped anew, so the purge horizon no longer applies to
  /// them, and go to the other devices with the next sync.
  Future<void> keepHeld() async {
    final d = _device;
    if (_readOnly || (d.heldTracks.isEmpty && d.heldFolders.isEmpty)) return;
    // changes not yet saved are stamped by _write afterwards, with a higher stamp
    final (tracks, folders) = _aliveHeld();
    _state = _state.restamp(tracks, folders, _clock.tick());
    await _setHeld(const {}, const {});
    try {
      await _write();
    } catch (e) {
      lastError = LibrarySaveFailed('$e');
    }
    onLocalChange?.call();
    notifyListeners();
  }

  /// #107 «Remove»: the held tracks (with their audio files) and folders are removed from this device, as
  /// the merge would have done; tracks in a removed folder stay, without a folder.
  Future<void> removeHeld() async {
    final d = _device;
    if (_readOnly || (d.heldTracks.isEmpty && d.heldFolders.isEmpty)) return;
    _commit();
    final (tracks, folders) = _aliveHeld();
    for (final t in _tracks.where((t) => tracks.contains(t.id))) {
      await store.delete(trackName(t.fileName)).catchError((_) {});
      await store.delete(_artworkName(t.id)).catchError((_) {});
    }
    // gone without a tombstone, as after the merge and purge: no other device knows them
    _state = _state.copyWith(
      tracks: {
        for (final e in _state.tracks.entries)
          if (!tracks.contains(e.key)) e.key: e.value,
      },
      folders: {
        for (final e in _state.folders.entries)
          if (!folders.contains(e.key)) e.key: e.value,
      },
    );
    _materialize();
    _absent.removeAll(tracks);
    await _setHeld(const {}, const {});
    _forgetOnDevice(tracks);
    try {
      await _write();
    } catch (e) {
      lastError = LibrarySaveFailed('$e');
    }
    notifyListeners();
    await refreshStorage();
  }

  /// The held tracks and folders still alive: one deleted here meanwhile stays deleted (a tombstone like any
  /// other) and is neither revived by «Keep» nor removed without its tombstone by «Remove».
  (Set<String>, Set<String>) _aliveHeld() => (
    {
      for (final id in _device.heldTracks)
        if (_state.tracks[id]?.alive ?? false) id,
    },
    {
      for (final id in _device.heldFolders)
        if (_state.folders[id]?.alive ?? false) id,
    },
  );

  /// Remembers the held records in `device.json`, so the question survives a restart (#107/AK5).
  Future<void> _setHeld(Iterable<String> tracks, Iterable<String> folders) {
    final t = {...tracks};
    final f = {...folders};
    final d = _device;
    if (t.length == d.heldTracks.length &&
        d.heldTracks.containsAll(t) &&
        f.length == d.heldFolders.length &&
        d.heldFolders.containsAll(f)) {
      return Future.value();
    }
    _shared = null;
    return _updateDevice(d.copyWith(heldTracks: t, heldFolders: f));
  }

  /// This device has shared its state (#104): from now on the purge horizon applies to its records. Called
  /// after a merge is saved and by the sync engine after it wrote `state.json`.
  Future<void> markSynced() async {
    if (_device.synced) return;
    _device = _device.copyWith(synced: true);
    try {
      await _device.save(store);
    } catch (_) {
      // only this run knows it; after a restart foreign stamps in the state show it ([load])
    }
  }

  /// Remembers the library ID of the storage this device syncs with (#53, `format.json`).
  Future<void> setLibraryId(String id) =>
      _updateDevice(_device.copyWith(libraryId: id));

  /// Shows [m] to the user, e.g. a problem of the sync (#10/AK7).
  void report(LibraryMessage m) {
    lastError = m;
    notifyListeners();
  }

  /// The audio file of [t] is on this device.
  bool hasFile(String id) => !_absent.contains(id);

  /// Name of the audio file in the cloud: `audio/<hash>.<ext>` (plan, cloud layout).
  static String cloudAudioName(Track t) {
    final dot = t.fileName.lastIndexOf('.');
    return 'audio/${t.id}${dot > 0 ? t.fileName.substring(dot) : ''}';
  }

  /// The audio file of [t] may go to the cloud: not «don't upload» and its folder is synced (#37/AK5).
  bool uploadable(Track t) {
    if (t.noUpload || _device.heldTracks.contains(t.id)) return false;
    final f = t.folderId;
    if (f == null) return true;
    return _folders.where((x) => x.id == f).firstOrNull?.sync ?? true;
  }

  /// Contents of the audio file of [t]; null if it is not on this device.
  Future<Uint8List?> readAudio(Track t) => store.read(trackName(t.fileName));

  /// Stores the audio file of track [id] that came from the cloud. Returns false if [bytes] do not match
  /// the track's hash (damaged download).
  Future<bool> addAudio(String id, Uint8List bytes) async {
    final t = track(id);
    if (t == null) return false;
    final hash = bytes.length > _hashInline
        ? await compute(_sha256Hex, bytes)
        : _sha256Hex(bytes);
    if (hash != id) return false;
    await store.write(trackName(t.fileName), bytes);
    if (_device.evicted.contains(id)) {
      await _updateDevice(
        _device.copyWith(evicted: {..._device.evicted}..remove(id)),
      );
    }
    if (t.hasArtwork) {
      final art = readMetadata(bytes).artwork;
      if (art != null && art.isNotEmpty) {
        await store.write(_artworkName(id), art).catchError((_) {});
      }
    }
    _absent.remove(id);
    notifyListeners();
    await refreshStorage();
    return true;
  }

  // ---- Audio cache of this device (#39/AK3) ----

  /// Track loaded in the player (set by the app); [trimCache] never removes its file.
  String? inUse;

  /// Bytes of audio files this device keeps; above it [trimCache] removes the oldest.
  int get cacheLimit => _device.cacheLimit;

  /// Sets the limit (device-local, never synced); values below 1 are ignored.
  Future<void> setCacheLimit(int bytes) async {
    if (bytes < 1 || bytes == _device.cacheLimit) return;
    final saving = _updateDevice(_device.copyWith(cacheLimit: bytes));
    notifyListeners();
    await saving;
  }

  /// The hint «Add to Home Screen» was closed on this device (#110, device-local, never synced).
  bool get installHintClosed => _device.installHintClosed;

  /// Remembers that the hint was closed; a failed write keeps it closed for this run only (#110/AK4).
  Future<void> closeInstallHint() async {
    if (_device.installHintClosed) return;
    final saving = _updateDevice(_device.copyWith(installHintClosed: true));
    notifyListeners();
    await saving;
  }

  /// The file of track [id] is never removed to keep the limit («Keep offline»).
  bool keptOffline(String id) => _device.keepOffline.contains(id);

  /// Switches «Keep offline» for these tracks (device-local).
  Future<void> setKeepOffline(Set<String> ids, bool on) async {
    final next = {..._device.keepOffline};
    on ? next.addAll(ids) : next.removeAll(ids);
    if (next.length == _device.keepOffline.length &&
        next.containsAll(_device.keepOffline)) {
      return;
    }
    final saving = _updateDevice(_device.copyWith(keepOffline: next));
    notifyListeners();
    await saving;
  }

  /// Track [id] was played on this device now: it is the last one [trimCache] removes.
  Future<void> markUsed(String id) => _updateDevice(
    _device.copyWith(
      lastUsed: {..._device.lastUsed, id: _now().millisecondsSinceEpoch},
    ),
  );

  /// Sum of the audio files on this device (bytes).
  Future<int> cacheSize() async {
    var total = 0;
    for (final t in _tracks) {
      if (hasFile(t.id)) total += await store.size(trackName(t.fileName)) ?? 0;
    }
    return total;
  }

  /// Keeps the audio files on this device at or below [cacheLimit]: removes the files of the tracks used
  /// longest ago (last played here, else added) until the rest fits. Only files that are in the cloud
  /// ([inCloud]) are removed; never a track kept offline, the loaded track ([inUse]) or one in [keep]. The track
  /// stays in the library and is loaded again when played. Returns the IDs whose file was removed.
  Future<List<String>> trimCache({
    required bool Function(String id) inCloud,
    Set<String> keep = const {},
  }) async {
    final sizes = <Track, int>{
      for (final t in _tracks)
        if (hasFile(t.id)) t: await store.size(trackName(t.fileName)) ?? 0,
    };
    var total = sizes.values.fold(0, (a, b) => a + b);
    if (total <= cacheLimit) return const [];
    int age(Track t) =>
        _device.lastUsed[t.id] ?? t.dateAdded.millisecondsSinceEpoch;
    final candidates = [
      for (final t in sizes.keys)
        if (inCloud(t.id) &&
            !keptOffline(t.id) &&
            t.id != inUse &&
            !keep.contains(t.id))
          t,
    ]..sort((a, b) => age(a).compareTo(age(b)));
    final removed = <String>[];
    for (final t in candidates) {
      if (total <= cacheLimit) break;
      await store.delete(trackName(t.fileName)).catchError((_) {});
      _absent.add(t.id);
      removed.add(t.id);
      total -= sizes[t]!;
    }
    if (removed.isEmpty) return removed;
    await _updateDevice(
      _device.copyWith(evicted: {..._device.evicted, ...removed}),
    );
    notifyListeners();
    await refreshStorage();
    return removed;
  }

  /// Removes deleted tracks from the device-local cache lists.
  void _forgetOnDevice(Set<String> ids) {
    final d = _device;
    if (!ids.any(
      (id) =>
          d.keepOffline.contains(id) ||
          d.evicted.contains(id) ||
          d.lastUsed.containsKey(id),
    )) {
      return;
    }
    _updateDevice(
      d.copyWith(
        keepOffline: {...d.keepOffline}..removeAll(ids),
        evicted: {...d.evicted}..removeAll(ids),
        lastUsed: {...d.lastUsed}..removeWhere((k, _) => ids.contains(k)),
      ),
    );
  }

  /// A failed write keeps the settings for this run; the next change writes them again.
  Future<void> _updateDevice(DeviceSettings d) async {
    _device = d;
    try {
      await d.save(store);
    } catch (_) {}
  }

  /// Switches «don't upload» for these tracks (#37/AK5).
  void setNoUpload(Set<String> ids, bool on) {
    _tracks = [
      for (final t in _tracks)
        ids.contains(t.id) ? t.copyWith(noUpload: on) : t,
    ];
    save();
    notifyListeners();
  }

  /// Switches «sync» for the folder (#37/AK5).
  void setFolderSync(String id, bool on) {
    final i = _folders.indexWhere((f) => f.id == id);
    if (i < 0 || _folders[i].sync == on) return;
    _folders[i] = _folders[i].copyWith(sync: on);
    save();
    notifyListeners();
  }

  /// Async so that an encoding error, too, reaches the caller as a failed future ([save] reports it as
  /// [LibrarySaveFailed]) instead of being thrown into the UI (#10). The commit still happens at once.
  Future<void> _write() async {
    _commit();
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(_state.toJson())),
    );
    await store.write(indexName, bytes);
  }

  /// Fasst häufige Änderungen zusammen (z. B. beim Ziehen des Tempo-Reglers).
  void _scheduleSave() {
    if (saveDelay == Duration.zero) {
      save();
      return;
    }
    _pendingSave?.cancel();
    _pendingSave = Timer(saveDelay, save);
  }

  /// Ausstehendes Speichern sofort erledigen.
  void flush() {
    if (_pendingSave != null) save();
  }

  /// Sort order and appearance from `preferences.json` (before #36); the file stays as it is.
  Future<void> _readLegacyPrefs() async {
    try {
      final raw = await store.read(legacyPrefsName);
      if (raw == null) return;
      final p = jsonDecode(utf8.decode(raw)) as Map;
      _sortOrder = TrackSortOrder.parse(p['sortOrder'] as String?);
      _appearance = Appearance.parse(p['appearance']);
    } catch (_) {
      // unlesbare Einstellungen: Standardwerte
    }
  }

  @override
  void dispose() {
    flush();
    super.dispose();
  }

  // ---- Abfragen ----

  List<Track> get sortedTracks {
    final list = [..._tracks];
    switch (_sortOrder) {
      case TrackSortOrder.alphabetical:
        return sortedNaturally(_tracks, (t) => t.title);
      case TrackSortOrder.dateAdded:
        list.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
      case TrackSortOrder.custom:
        list.sort((a, b) => a.customOrder.compareTo(b.customOrder));
    }
    return list;
  }

  List<TrackFolder> get sortedFolders =>
      sortedNaturally(_folders, (f) => f.name);

  /// Titel eines Ordners (null = ohne Ordner) in der aktuellen Sortierung.
  List<Track> sortedTracksIn(String? folderId) =>
      sortedTracks.where((t) => t.folderId == folderId).toList();

  Track? track(String id) => _tracks.where((t) => t.id == id).firstOrNull;

  /// Track with these contents (SHA-256), if already in the library.
  Track? trackWithHash(String hash) => track(hash);

  /// File location for the audio core: device-local path on desktop and mobile, name in the browser.
  String filePath(Track t) => store.locate(trackName(t.fileName));

  /// Device-local path of the file (desktop and mobile); null in the browser.
  String? localPath(Track t) => store.localPath(trackName(t.fileName));

  /// Artwork as a device-local path; none in the browser (yet).
  String? artworkPath(Track t) =>
      t.hasArtwork ? store.localPath(_artworkName(t.id)) : null;

  int get _nextOrder => _tracks.fold(-1, (m, t) => max(m, t.customOrder)) + 1;

  // ---- Import und Löschen ----

  /// Adds the files to the library and reads title, artist, album, artwork and duration. Files whose
  /// contents are already present end up in [ImportResult.duplicates] and are not stored again.
  Future<ImportResult> importFiles(
    List<String> paths, {
    String? folderId,
  }) async {
    if (_readOnly) {
      lastError = LibraryTooNew(_newerVersion);
      notifyListeners();
      return ImportResult(const [], [for (final p in paths) _baseName(p)]);
    }
    _importing = true;
    notifyListeners();
    final imported = <Track>[];
    final failed = <String>[];
    final duplicates = <Track>[];
    for (final path in paths) {
      final r = await _importFile(path, folderId);
      switch (r) {
        case (final Track t, false):
          _tracks.add(t);
          imported.add(t);
        case (final Track t, true):
          duplicates.add(t);
        case _:
          failed.add(_baseName(path));
      }
    }
    _importing = false;
    if (failed.isNotEmpty) {
      lastError = ImportFailed(List.unmodifiable(failed));
    }
    save();
    notifyListeners();
    if (imported.isNotEmpty) await _askPersistence();
    await refreshStorage();
    return ImportResult(imported, failed, duplicates);
  }

  /// (track, already present) or null on failure.
  Future<(Track, bool)?> _importFile(String source, String? folderId) async {
    final name = _baseName(source);
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : 'mp3';
    String? dest;
    var written = false;
    try {
      final bytes = await readSource(source);
      if (bytes == null) return null;
      // Large files in a separate isolate (in the browser compute runs on the same thread).
      final id = bytes.length > _hashInline
          ? await compute(_sha256Hex, bytes)
          : _sha256Hex(bytes);
      final existing = this.track(id);
      if (existing != null) return (existing, true);
      final fileName = '$id.$ext';
      dest = trackName(fileName);
      await store.write(dest, bytes);
      written = true;
      final duration = probe(store.locate(dest));
      if (duration != null && duration <= 0) {
        throw const FormatException('no readable audio');
      }
      final meta = readMetadata(bytes);
      var hasArtwork = false;
      if (meta.artwork != null && meta.artwork!.isNotEmpty) {
        try {
          await store.write(_artworkName(id), meta.artwork!);
          hasArtwork = true;
        } catch (_) {}
      }
      final track = Track(
        id: id,
        fileName: fileName,
        originalFileName: name,
        title: meta.title ?? (dot > 0 ? name.substring(0, dot) : name),
        artist: meta.artist,
        album: meta.album,
        duration: duration ?? 0,
        hasArtwork: hasArtwork,
        dateAdded: _now().toUtc(),
        customOrder: _nextOrder,
        folderId: folderId,
      );
      return (track, false);
    } catch (_) {
      if (written) await store.delete(dest!).catchError((_) {});
      return null;
    }
  }

  static String _baseName(String path) => path.split(RegExp(r'[/\\]')).last;

  void delete(Set<String> ids) {
    if (_readOnly) return;
    for (final t in _tracks.where((t) => ids.contains(t.id))) {
      store.delete(trackName(t.fileName)).catchError((_) {});
      store.delete(_artworkName(t.id)).catchError((_) {});
    }
    _tracks.removeWhere((t) => ids.contains(t.id));
    _absent.removeAll(ids);
    _forgetOnDevice(ids);
    save();
    notifyListeners();
    refreshStorage();
  }

  // ---- Reihenfolge ----

  /// Verschiebt eine Zeile innerhalb eines Ordners; [to] wie bei SwiftUI/Flutter vor dem Entfernen gezählt.
  /// Schaltet auf eigene Reihenfolge um, ausgehend von der gerade angezeigten.
  void move(String? folderId, int from, int to) {
    final ordered = sortedTracks;
    final slots = [
      for (var i = 0; i < ordered.length; i++)
        if (ordered[i].folderId == folderId) i,
    ];
    if (from < 0 || from >= slots.length) return;
    final section = [for (final s in slots) ordered[s]];
    final moving = section.removeAt(from);
    section.insert((to > from ? to - 1 : to).clamp(0, section.length), moving);
    for (var i = 0; i < slots.length; i++) {
      ordered[slots[i]] = section[i];
    }
    _renumber(ordered);
    _sortOrder = TrackSortOrder.custom;
    save();
    notifyListeners();
  }

  void _renumber(List<Track> ordered) {
    final pos = {
      for (var i = 0; i < ordered.length; i++)
        ordered[i].id: (i, ordered[i].folderId),
    };
    _tracks = [
      for (final t in _tracks)
        if (pos[t.id] case final p?)
          t.copyWith(customOrder: p.$1, folderId: () => p.$2)
        else
          t,
    ];
  }

  // ---- Ordner ----

  /// New folder; a blank [name] becomes [fallback] (the UI passes the localized «New folder»).
  TrackFolder createFolder(String name, {String fallback = ''}) {
    final t = name.trim();
    final f = TrackFolder(id: newUuid(_random), name: t.isEmpty ? fallback : t);
    _folders.add(f);
    save();
    notifyListeners();
    return f;
  }

  /// Renames the folder; a blank [name] keeps the old one.
  void renameFolder(String id, String name) {
    final i = _folders.indexWhere((f) => f.id == id);
    final t = name.trim();
    if (i < 0 || t.isEmpty) return;
    _folders[i] = _folders[i].copyWith(name: t);
    save();
    notifyListeners();
  }

  /// Entfernt den Ordner; seine Titel bleiben ohne Ordner in der Bibliothek.
  void deleteFolder(String id) {
    _folders.removeWhere((f) => f.id == id);
    _tracks = [
      for (final t in _tracks)
        t.folderId == id ? t.copyWith(folderId: () => null) : t,
    ];
    save();
    notifyListeners();
  }

  /// Legt Titel in einen Ordner. Mit [at] an diese Zeile der Ordnerliste (eigene Reihenfolge),
  /// sonst bleibt ihre Position.
  void moveTracks(Set<String> ids, String? folderId, {int? at}) {
    if (at == null) {
      _tracks = [
        for (final t in _tracks)
          ids.contains(t.id) ? t.copyWith(folderId: () => folderId) : t,
      ];
    } else {
      final ordered = sortedTracks;
      final moving = [
        for (final t in ordered)
          if (ids.contains(t.id)) t.copyWith(folderId: () => folderId),
      ];
      ordered.removeWhere((t) => ids.contains(t.id));
      final slots = [
        for (var i = 0; i < ordered.length; i++)
          if (ordered[i].folderId == folderId) i,
      ];
      // #10 (random tests): a negative row counts as the first one instead of throwing a RangeError.
      final row = max(0, at);
      final insertAt = row < slots.length
          ? slots[row]
          : (slots.isEmpty ? ordered.length : slots.last + 1);
      ordered.insertAll(insertAt, moving);
      _renumber(ordered);
    }
    save();
    notifyListeners();
  }

  /// Ziehen und Ablegen in der Liste: vor [beforeId] (eigene Reihenfolge) oder ohne [beforeId]
  /// ans Ende des Ordners [folderId] (Position bleibt, wie beim Ablegen auf einen Ordner in Swift).
  void placeTrack(String id, String? folderId, {String? beforeId}) {
    if (beforeId == id) return;
    if (beforeId == null) {
      moveTracks({id}, folderId);
      return;
    }
    final others = sortedTracksIn(folderId).where((t) => t.id != id).toList();
    final at = others.indexWhere((t) => t.id == beforeId);
    moveTracks({id}, folderId, at: at < 0 ? others.length : at);
    sortOrder = TrackSortOrder.custom;
  }

  // ---- Title and artist (#24) ----

  /// Changes title and artist in `library.json` only; the audio file and its tags stay untouched. Both are
  /// trimmed; a blank [title] is rejected (returns false), a blank [artist] removes it.
  bool editMetadata(String id, {required String title, String? artist}) {
    final i = _tracks.indexWhere((t) => t.id == id);
    final newTitle = title.trim();
    if (i < 0 || newTitle.isEmpty) return false;
    final a = artist?.trim();
    final newArtist = a == null || a.isEmpty ? null : a;
    final t = _tracks[i];
    if (t.title == newTitle && t.artist == newArtist) return true;
    _tracks[i] = t.copyWith(title: newTitle, artist: () => newArtist);
    save();
    notifyListeners();
    return true;
  }

  /// Stores the duration the audio core found on loading, for tracks imported without one (in the
  /// browser only the core knows it, #42/AK5). Known durations stay as they are.
  void fillDuration(String id, double seconds) {
    final i = _tracks.indexWhere((t) => t.id == id);
    if (i < 0 || seconds <= 0 || _tracks[i].duration > 0) return;
    _tracks[i] = _tracks[i].copyWith(duration: seconds);
    save(); // at once: the page may be reloaded right after loading
    notifyListeners();
  }

  // ---- Einstellungen pro Titel ----

  /// Random loop ID (8 hex digits), unique per track in practice (#37/AK4).
  String _newLoopId() {
    final r = _random ?? Random.secure();
    return List.generate(
      4,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void updateSettings(String id, PlaybackSettings settings) {
    final i = _tracks.indexWhere((t) => t.id == id);
    if (i < 0 || _tracks[i].settings == settings) return;
    _tracks[i] = _tracks[i].withSettings(settings, _newLoopId);
    _scheduleSave();
    notifyListeners();
  }
}
