// Sync engine (#37, #53, plan W5): merges the library with the state of every other device and moves the
// audio files. Pure Dart on top of one or more CloudProviders, the same on desktop and in the browser.
//
// Layout at every source (docs/KONZEPT-SYNC.md):
//   format.json                         format version and library ID
//   devices/<device-id>.json            state of that device; only that device writes the file
//   backup/<device-id>/state-<n>.json   the last 5 own states
//   audio/<hash>.<ext>                  audio files, named after the SHA-256 of their contents
//
// One sync: (1) at every source check `format.json`, read every `devices/*.json` (conflict copies too)
// and merge all of them into the library (stamps per field, stamps.dart; the merge is commutative and
// idempotent, so the order of files and sources does not matter). (2) Write the merged state to the own
// device file at every source; the previous contents go to a backup slot first. No write is conditional:
// no device writes the file of another one. Conflict copies and files of devices gone for
// [CloudSync.staleAfter] are deleted once their contents are in the own file. (3) Per source, list `audio/`
// and plan the tasks: upload what is missing, delete what was deleted or excluded, download (desktop)
// what is missing here. Tasks that fail are retried with growing delays and given up after a few
// attempts; a source without connection waits and is retried later.
//
// Several sources make a bridge (#53/AK4): a device syncing with the cloud and with a paired device
// carries the changes of each to the other, because its own file holds everything it merged. Google
// Drive (#54) and a paired device (#56) are just further CloudProviders.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../library/library.dart';
import '../library/stamps.dart' show isFiniteJson, sameJson;
import 'cloud_provider.dart';
import 'sync_service.dart';

/// A source holds the library in a newer format.
class SyncTooNew implements Exception {
  const SyncTooNew(this.version);
  final int version;
}

/// A task of the queue of one source: `state`, `up:<hash>`, `down:<hash>` or `rm:<hash>`.
class SyncTask {
  SyncTask(this.key);
  final String key;
  int attempts = 0;
  DateTime? notBefore;

  /// Failed [CloudSync.maxAttempts] times: not retried until [CloudSync.syncNow] or the next start.
  bool parked = false;
  Object? lastError;
}

/// A device file as read from a source.
class DeviceFile {
  const DeviceFile({
    required this.name,
    required this.deviceId,
    required this.copy,
    required this.bytes,
    required this.state,
    required this.generation,
    this.written,
  });

  final String name;
  final String deviceId;

  /// A conflict copy made by the storage, not the file the device writes.
  final bool copy;
  final Uint8List bytes;
  final SharedState state;

  /// Counts the writes of the device; picks the backup slot.
  final int generation;

  /// When the device wrote the file (its clock); null if unknown.
  final DateTime? written;
}

/// Contents of `format.json`; both null if it is missing or damaged.
class _Format {
  const _Format({this.version, this.id});

  factory _Format.parse(Uint8List bytes) {
    try {
      final j = jsonDecode(utf8.decode(bytes));
      if (j is Map) {
        return _Format(
          version: j['formatVersion'] is int ? j['formatVersion'] as int : null,
          id: switch (j['libraryId']) {
            final String v when v.isNotEmpty => v,
            _ => null,
          },
        );
      }
    } on FormatException {
      // damaged: written again with the library ID of this device
    }
    return const _Format();
  }

  final int? version;
  final String? id;
}

/// What one sync read from one source.
class _Read {
  final files = <DeviceFile>[];
  DeviceFile? own;
  Uint8List? ownBytes;
}

/// One storage the device syncs with, with its own queue.
class _Source {
  _Source(this.provider);
  final CloudProvider provider;
  final queue = <String, SyncTask>{};
  Set<String> audio = {};

  /// The last sync could not reach it.
  bool offline = false;

  /// It holds another library (`format.json`): nothing is merged or written.
  bool foreign = false;
}

class CloudSync extends SyncService {
  CloudSync(
    CloudProvider provider,
    this.library, {
    List<CloudProvider> more = const [],
    this.eagerDownload = true,
    this.changeDelay = const Duration(seconds: 5),
    this.backoffBase = const Duration(seconds: 2),
    this.backoffMax = const Duration(minutes: 5),
    this.maxAttempts = 5,
    this.maxOfflineRetries = 8,
    DateTime Function()? now,
    Random? random,
  }) : _now = now ?? DateTime.now,
       _random = random ?? Random.secure() {
    for (final p in [provider, ...more]) {
      _sources.add(_Source(p));
    }
  }

  static const formatName = 'format.json';
  static const devicesPrefix = 'devices/';
  static String deviceName(String deviceId) => '$devicesPrefix$deviceId.json';
  static const backupCount = 5;
  static String backupName(String deviceId, int n) =>
      'backup/$deviceId/state-$n.json';

  /// #53/AK8: a device file not written for so long is merged and removed.
  static const staleAfter = Duration(days: 180);

  /// The own file is written again after this time even without changes, so it never looks stale.
  static const refreshAfter = Duration(days: 30);

  final Library library;

  /// Download missing audio files right away (desktop); otherwise only when played ([fetchAudio]).
  final bool eagerDownload;
  final Duration changeDelay;
  final Duration backoffBase;
  final Duration backoffMax;

  /// Attempts per file before it is given up (protection against endless loops).
  final int maxAttempts;

  /// Automatic retries without a connection; after that only start, foreground and changes trigger one.
  final int maxOfflineRetries;
  final DateTime Function() _now;
  final Random _random;

  final _sources = <_Source>[];
  SyncStatus _status = SyncStatus.idle;
  Future<void>? _running;
  bool _again = false;
  int _offline = 0;
  Timer? _changeTimer;
  Timer? _retryTimer;
  bool _disposed = false;

  /// Format version already reported as too new: one message per version.
  int? _reportedTooNew;

  /// Time of the last sync that got through.
  DateTime? lastSync;

  final _devices = <String, DateTime?>{};

  /// #54/AK8: every device whose file a sync read, with the time it last wrote it (its clock); the own
  /// device with the time of its last write.
  Map<String, DateTime?> get devices => Map.unmodifiable(_devices);

  /// The sources in sync order; the first one is the cloud if there is one.
  List<CloudProvider> get sources => [for (final s in _sources) s.provider];

  /// The first source.
  CloudProvider get provider => _sources.first.provider;

  /// Adds a source, e.g. a paired device that connected (#56). It takes part from the next sync on.
  void addSource(CloudProvider p) {
    if (_sources.any((s) => identical(s.provider, p))) return;
    _sources.add(_Source(p));
  }

  /// Removes a source with its queue (e.g. a paired device that went away).
  void removeSource(CloudProvider p) =>
      _sources.removeWhere((s) => identical(s.provider, p));

  @override
  SyncStatus get status => _status;

  /// Tasks still waiting or given up, of every source (for tests and the status in #40).
  List<SyncTask> get pending =>
      List.unmodifiable([for (final s in _sources) ...s.queue.values]);

  /// Tasks given up after [maxAttempts].
  List<SyncTask> get failed => [
    for (final t in pending)
      if (t.parked) t,
  ];

  /// When the next automatic retry is due; null if none is planned.
  Duration? nextRetry;

  @override
  bool inCloud(String trackId) =>
      _sources.any((s) => s.audio.contains(trackId));

  @override
  Future<void> start() => sync();

  @override
  void resumed() => sync();

  @override
  void localChanged() {
    // A new change gives the state another chance even if it gave up before.
    for (final s in _sources) {
      if (s.queue['state'] case final t? when t.parked) s.queue.remove('state');
    }
    _changeTimer?.cancel();
    _changeTimer = Timer(changeDelay, sync);
  }

  @override
  Future<void> syncNow() {
    for (final t in pending) {
      t.parked = false;
      t.attempts = 0;
      t.notBefore = null;
    }
    _offline = 0;
    return sync();
  }

  /// Runs one sync; if one is running, another follows right after it.
  Future<void> sync() {
    if (_disposed) return Future.value();
    _changeTimer?.cancel();
    if (_running case final r?) {
      _again = true;
      return r;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _once();
    } while (_again &&
        _status != SyncStatus.offline &&
        _status != SyncStatus.tooNew &&
        _status != SyncStatus.foreignLibrary);
  }

  Future<void> _once() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    nextRetry = null;
    if (library.readOnly) {
      _setStatus(SyncStatus.tooNew);
      return;
    }
    _setStatus(SyncStatus.syncing);
    try {
      library.flush();
      final active = [..._sources];
      for (final s in active) {
        s.offline = false;
        s.queue.putIfAbsent('state', () => SyncTask('state'));
      }
      // (0) format.json everywhere first: a library ID found at any source is taken over before a new
      // one is made for a source that has none yet
      final formats = <_Source, _Format>{};
      for (final s in active) {
        if (!_due(s.queue['state']!)) continue;
        await _guard(s, s.queue['state']!, () async {
          formats[s] = await _readFormat(s);
        });
      }
      if (library.device.libraryId == null) {
        final found = formats.values.map((f) => f.id).nonNulls.firstOrNull;
        if (found != null) await library.setLibraryId(found);
      }
      // (1) read every source, then merge everything at once
      final reads = <_Source, _Read>{};
      for (final e in formats.entries) {
        final s = e.key;
        await _guard(s, s.queue['state']!, () async {
          final r = await _read(s, e.value);
          if (r != null) reads[s] = r;
        });
      }
      final merged = [
        for (final r in reads.values)
          for (final f in r.files) f.state,
      ];
      if (merged.isNotEmpty) {
        await library.mergeRemote(merged.reduce((a, b) => a.merge(b)));
      }
      // (2) write the own file at every source that was read
      for (final e in reads.entries) {
        final s = e.key;
        if (await _guard(s, s.queue['state']!, () => _write(s, e.value))) {
          s.queue.remove('state');
        }
      }
      // (3) audio at every source whose state got through: first download from all of them, then
      // upload and delete, so a file that arrived from one source goes on to the others at once (AK4)
      final ready = [
        for (final s in active)
          if (!s.offline && !s.foreign && !s.queue.containsKey('state')) s,
      ];
      for (final downloads in [true, false]) {
        for (final s in ready) {
          if (s.offline) continue;
          try {
            if (downloads) {
              _plan(s, {
                for (final e in await s.provider.list('audio/'))
                  _hashOf(e.name),
              });
            } else {
              _plan(s, s.audio);
            }
            await _runTasks(s, downloads: downloads);
          } on CloudOffline {
            s.offline = true;
          }
        }
      }
      await _trimCache();
      final reached = active.where((s) => !s.offline).length;
      if (active.isNotEmpty && reached == 0) throw const CloudOffline();
      if (reached < active.length) {
        _offline++;
        if (_offline <= maxOfflineRetries) _retryIn(_backoff(_offline));
      } else {
        _offline = 0;
        _scheduleRetry();
      }
      lastSync = _now();
      _setStatus(
        active.any((s) => s.foreign)
            ? SyncStatus.foreignLibrary
            : failed.isEmpty
            ? SyncStatus.idle
            : SyncStatus.failed,
      );
    } on CloudOffline {
      _offline++;
      if (_offline <= maxOfflineRetries) _retryIn(_backoff(_offline));
      _setStatus(SyncStatus.offline);
    } on SyncTooNew {
      _setStatus(SyncStatus.tooNew);
    }
  }

  bool _due(SyncTask t) =>
      !t.parked && !(t.notBefore?.isAfter(_now()) ?? false);

  /// Runs [step] for source [s]; a failure counts against [task]. False if it did not get through.
  /// [CloudOffline] marks the source as offline; [SyncTooNew] stops the whole sync.
  Future<bool> _guard(
    _Source s,
    SyncTask task,
    Future<void> Function() step,
  ) async {
    try {
      await step();
      return true;
    } on CloudOffline {
      s.offline = true;
    } on SyncTooNew {
      rethrow;
    } catch (e) {
      _fail(task, e);
    }
    return false;
  }

  void _fail(SyncTask task, Object e) {
    task.lastError = e;
    task.attempts++;
    if (task.attempts >= maxAttempts) {
      task.parked = true;
    } else {
      task.notBefore = _now().add(_backoff(task.attempts));
    }
  }

  void _setStatus(SyncStatus s) {
    _status = s;
    if (!_disposed) notifyListeners();
  }

  // ---- State: format.json and device files (#53) ----

  /// Settles `format.json` and reads every device file of [s]. Null if [s] holds another library.
  Future<_Read?> _read(_Source s, _Format format) async {
    if (!await _settleFormat(s, format)) return null;
    final me = library.device.deviceId;
    final read = _Read();
    for (final e in await s.provider.list(devicesPrefix)) {
      final kind = parseDeviceName(e.name);
      if (kind == null) continue; // not a device file: left alone
      final f = await s.provider.get(e.name);
      if (f == null) continue; // gone in the meantime
      final DeviceFile file;
      try {
        file = decodeDevice(e.name, f.bytes);
      } on SyncTooNew catch (t) {
        _reportTooNew(t.version);
        rethrow;
      } on FormatException {
        // #53/AK5: no error; the file stays and is tried again on the next sync
        if (e.name == deviceName(me)) read.ownBytes = f.bytes;
        continue;
      }
      read.files.add(file);
      if (!file.copy) _seen(file.deviceId, file.written);
      if (e.name == deviceName(me)) {
        read.own = file;
        read.ownBytes = f.bytes;
      }
    }
    return read;
  }

  /// Reads `format.json` of [s] (#53/AK9): a newer format stops the sync without writing.
  Future<_Format> _readFormat(_Source s) async {
    s.foreign = false;
    final f = await s.provider.get(formatName);
    final format = f == null ? const _Format() : _Format.parse(f.bytes);
    if (format.version case final v? when v > SharedState.formatVersion) {
      _reportTooNew(v);
      throw SyncTooNew(v);
    }
    return format;
  }

  /// #53/AK9: another library ID is not merged. Writes `format.json` if it is missing, damaged or older,
  /// with the library ID of this device (a new one if it has none yet).
  Future<bool> _settleFormat(_Source s, _Format format) async {
    final mine = library.device.libraryId;
    final id = format.id;
    if (mine != null && id != null && id != mine) {
      s.foreign = true;
      return false;
    }
    if (id != null && format.version == SharedState.formatVersion) return true;
    final useId = id ?? mine ?? _newLibraryId();
    await s.provider.put(formatName, encodeFormat(useId));
    // two devices may create it at the same moment: the one stored wins, before anything is merged
    final stored = await s.provider.get(formatName);
    final adopt =
        (stored == null ? null : _Format.parse(stored.bytes).id) ?? useId;
    if (mine != null && adopt != mine) {
      s.foreign = true;
      return false;
    }
    if (mine == null) await library.setLibraryId(adopt);
    return true;
  }

  String _newLibraryId() => List.generate(
    16,
    (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  void _reportTooNew(int version) {
    if (_reportedTooNew != version) library.report(CloudStateTooNew(version));
    _reportedTooNew = version;
  }

  /// Writes the merged state to the own device file of [s] if it differs (#53/AK1), after keeping the
  /// previous contents as a backup (#53/AK7). Then removes conflict copies and stale files whose contents
  /// are in it (#53/AK6, AK8).
  Future<void> _write(_Source s, _Read read) async {
    final me = library.device.deviceId;
    final mine = library.state;
    final own = read.own;
    final now = _now();
    final fresh =
        own != null &&
        own.written != null &&
        now.difference(own.written!) < refreshAfter;
    if (own == null || !fresh || !sameJson(own.state.toJson(), mine.toJson())) {
      final generation = own?.generation ?? 0;
      if (read.ownBytes case final previous?) {
        // the slot follows the generation, so the last 5 remain
        await s.provider.put(
          backupName(me, generation % backupCount + 1),
          previous,
        );
      }
      await s.provider.put(
        deviceName(me),
        encodeDevice(mine, me, generation + 1, now),
      );
      _seen(me, now);
    }
    await library.markSynced(); // #104
    for (final f in read.files) {
      final stale =
          f.deviceId != me &&
          !f.copy &&
          f.written != null &&
          now.difference(f.written!) >= staleAfter;
      if (!f.copy && !stale) continue;
      // merged above and written into the own file; delete only what was read (no data loss)
      final again = await s.provider.get(f.name);
      if (again != null && _same(again.bytes, f.bytes)) {
        await s.provider.delete(f.name);
        if (stale) _devices.remove(f.deviceId);
      }
    }
  }

  void _seen(String device, DateTime? written) {
    final known = _devices[device];
    if (!_devices.containsKey(device) ||
        (written != null && (known == null || written.isAfter(known)))) {
      _devices[device] = written;
    }
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// The device ID of a file under `devices/` and whether it is a conflict copy; null for other files.
  ///
  /// Storages keep both versions of a file written twice at once under a new name (#53/AK6): Google Drive
  /// for desktop `<id> (1).json`, the OneDrive API (`conflictBehavior=rename`) `<id> 1.json`, the OneDrive
  /// client `<id>-<device name>.json`, iCloud `<id> 2.json`, others
  /// `<id> (<name>'s conflicted copy <date>).json`, Syncthing `<id>.sync-conflict-<date>-<time>-<id>.json`.
  /// Device IDs are 16 hex digits, so whatever follows them up to `.json` (starting with another
  /// character) marks a copy.
  static ({String deviceId, bool copy})? parseDeviceName(String name) {
    final m = RegExp(r'^devices/([0-9a-f]{16})([^0-9a-f/][^/]*)?\.json$')
        .firstMatch(name);
    if (m == null) return null;
    return (deviceId: m.group(1)!, copy: m.group(2) != null);
  }

  /// Decodes and checks a device file: not JSON, other types, missing stamps, numbers beyond a double,
  /// stamps out of range or records the app cannot show give a [FormatException] (#10/AK7); a newer
  /// format version gives [SyncTooNew].
  static DeviceFile decodeDevice(String name, Uint8List bytes) {
    final kind = parseDeviceName(name);
    if (kind == null) throw FormatException('not a device file: $name');
    try {
      final j = jsonDecode(utf8.decode(bytes));
      if (j is! Map) throw const FormatException('not an object');
      final v = j['formatVersion'];
      if (v is int && v > SharedState.formatVersion) throw SyncTooNew(v);
      if (v != SharedState.formatVersion || !isFiniteJson(j)) {
        throw const FormatException('format version or numbers');
      }
      final state = SharedState.fromJson(j.cast());
      // every record must be one the app can show (as when loading library.json)
      for (final e in state.tracks.entries) {
        Track.fromShared(e.key, e.value.values);
      }
      for (final e in state.folders.entries) {
        TrackFolder.fromShared(e.key, e.value.values);
      }
      for (final e in state.playlists.entries) {
        Playlist.fromShared(e.key, e.value.values);
      }
      TrackSortOrder.parse(state.settings.values['sortOrder'] as String?);
      final g = j['generation'];
      final w = j['written'];
      return DeviceFile(
        name: name,
        deviceId: kind.deviceId,
        copy: kind.copy,
        bytes: bytes,
        state: state,
        generation: g is int && g >= 0 && g <= Hlc.maxCounter ? g : 0,
        written: w is int && w >= 0
            ? DateTime.fromMillisecondsSinceEpoch(w, isUtc: true)
            : null,
      );
    } on SyncTooNew {
      rethrow;
    } on FormatException {
      rethrow;
    } catch (e) {
      throw FormatException('$name unreadable: $e');
    }
  }

  /// A device file: the shared state, the writing device, a generation counter for the backup slots and
  /// the time of writing (for [staleAfter]).
  static Uint8List encodeDevice(
    SharedState s,
    String deviceId,
    int generation,
    DateTime written,
  ) => Uint8List.fromList(
    utf8.encode(
      const JsonEncoder.withIndent('  ').convert({
        ...s.toJson(),
        'deviceId': deviceId,
        'generation': generation,
        'written': written.millisecondsSinceEpoch,
      }),
    ),
  );

  static Uint8List encodeFormat(String libraryId) => Uint8List.fromList(
    utf8.encode(
      const JsonEncoder.withIndent('  ').convert({
        'formatVersion': SharedState.formatVersion,
        'libraryId': libraryId,
      }),
    ),
  );

  // ---- Audio ----

  /// Hash from `audio/<hash>.<ext>`.
  static String _hashOf(String name) {
    final base = name.substring(name.lastIndexOf('/') + 1);
    final dot = base.indexOf('.');
    return dot < 0 ? base : base.substring(0, dot);
  }

  void _plan(_Source s, Set<String> hashes) {
    s.audio = {...hashes};
    void add(String key) => s.queue.putIfAbsent(key, () => SyncTask(key));
    final tracks = {for (final t in library.tracks) t.id: t};
    for (final t in tracks.values) {
      final here = library.hasFile(t.id);
      final there = s.audio.contains(t.id);
      if (here && !there && library.uploadable(t)) add('up:${t.id}');
      if (!here && there && eagerDownload) add('down:${t.id}');
    }
    // Only hashes the state knows: a file of a track this device has not seen yet stays.
    for (final h in s.audio) {
      final rec = library.state.tracks[h];
      if (rec == null) continue;
      final t = tracks[h];
      if (!rec.alive || (t != null && !library.uploadable(t))) add('rm:$h');
    }
    notifyListeners();
  }

  /// Runs the due downloads of [s], or its other audio tasks. [CloudOffline] stops all of them.
  Future<void> _runTasks(_Source s, {required bool downloads}) async {
    for (final task in s.queue.values.toList()) {
      if (task.key == 'state' || !_due(task)) continue;
      if (task.key.startsWith('down:') != downloads) continue;
      try {
        await _execute(s, task.key);
        s.queue.remove(task.key);
      } on CloudOffline {
        rethrow;
      } catch (e) {
        _fail(task, e);
      }
    }
  }

  Future<void> _execute(_Source s, String key) async {
    final hash = key.substring(key.indexOf(':') + 1);
    final t = library.track(hash);
    switch (key.substring(0, key.indexOf(':'))) {
      case 'up':
        if (t == null || !library.uploadable(t) || !library.hasFile(hash)) {
          return;
        }
        final bytes = await library.readAudio(t);
        if (bytes == null) return;
        // Content-addressed: writing the same file again changes nothing, so this is idempotent.
        await s.provider.put(Library.cloudAudioName(t), bytes);
        s.audio.add(hash);
      case 'down':
        if (t == null || library.hasFile(hash)) return;
        // #53/AK5: a file with the wrong hash is not stored; the task is tried again later
        if (!await _download(s.provider, t)) {
          throw CloudError('download of $hash failed');
        }
      case 'rm':
        final rec = library.state.tracks[hash];
        if (rec == null) return;
        if (rec.alive && t != null && library.uploadable(t)) return;
        for (final e in await s.provider.list('audio/$hash')) {
          await s.provider.delete(e.name);
        }
        s.audio.remove(hash);
    }
  }

  Future<bool> _download(CloudProvider p, Track t) async {
    final f = await p.get(Library.cloudAudioName(t));
    if (f == null) return false;
    return library.addAudio(t.id, f.bytes);
  }

  @override
  Future<bool> fetchAudio(Track track) async {
    if (library.hasFile(track.id)) return true;
    var ok = false;
    for (final s in [..._sources]) {
      try {
        if (await _download(s.provider, track)) {
          ok = true;
          break;
        }
      } catch (_) {
        // try the next source
      }
    }
    if (!ok) return false;
    await _trimCache(
      keep: {track.id},
    ); // the file just loaded is about to be played
    return true;
  }

  /// #39/AK3: without eager downloads (browser) the device is a cache of the cloud: above its limit the
  /// files used longest ago go, as far as they are in the cloud. Desktop keeps every file.
  Future<void> _trimCache({Set<String> keep = const {}}) async {
    if (eagerDownload) return;
    try {
      await library.trimCache(inCloud: inCloud, keep: keep);
    } catch (_) {} // a failed delete leaves the file; the next sync tries again
  }

  Duration _backoff(int attempt) {
    final ms = backoffBase.inMilliseconds * pow(2, attempt - 1);
    return Duration(milliseconds: min(ms, backoffMax.inMilliseconds).round());
  }

  /// Plans a retry when the earliest waiting task is due.
  void _scheduleRetry() {
    DateTime? next;
    for (final t in pending) {
      if (t.parked) continue;
      final at = t.notBefore ?? _now();
      if (next == null || at.isBefore(next)) next = at;
    }
    if (next != null) {
      final d = next.difference(_now());
      _retryIn(d.isNegative ? Duration.zero : d);
    }
  }

  void _retryIn(Duration d) {
    _retryTimer?.cancel();
    nextRetry = d;
    _retryTimer = Timer(d, sync);
  }

  @override
  void dispose() {
    _disposed = true;
    _changeTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }
}
