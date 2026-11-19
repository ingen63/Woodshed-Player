// Sync engine (#37, plan W5): merges the library with `state.json` in the cloud and moves the audio files.
// Pure Dart on top of a CloudProvider, the same on desktop and in the browser.
//
// One sync: (1) read `state.json`, merge it into the library (stamps per field, stamps.dart), write the
// result conditionally on the version read; on a conflict read, merge and try again. Before each write
// the previous contents go to `backup/state-<n>.json` (5 slots in turn). (2) List `audio/` and plan the
// tasks: upload what is missing, delete what was deleted or excluded, download (desktop) what is missing
// here. Tasks that fail are retried with growing delays and given up after a few attempts; without a
// connection the whole sync waits and is retried later. The queue is derived again from the library on
// every sync, so changes made offline are sent as soon as a sync gets through.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../library/library.dart';
import '../library/stamps.dart' show isFiniteJson, sameJson;
import 'cloud_provider.dart';
import 'sync_service.dart';

/// The cloud holds `state.json` in a newer format.
class SyncTooNew implements Exception {
  const SyncTooNew(this.version);
  final int version;
}

/// A task of the queue: `state`, `up:<hash>`, `down:<hash>` or `rm:<hash>`.
class SyncTask {
  SyncTask(this.key);
  final String key;
  int attempts = 0;
  DateTime? notBefore;

  /// Failed [CloudSync.maxAttempts] times: not retried until [CloudSync.syncNow] or the next start.
  bool parked = false;
  Object? lastError;
}

class CloudSync extends SyncService {
  CloudSync(
    this.provider,
    this.library, {
    this.eagerDownload = true,
    this.changeDelay = const Duration(seconds: 5),
    this.backoffBase = const Duration(seconds: 2),
    this.backoffMax = const Duration(minutes: 5),
    this.maxAttempts = 5,
    this.maxConflicts = 5,
    this.maxOfflineRetries = 8,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  static const stateName = 'state.json';
  static const backupCount = 5;
  static String backupName(int n) => 'backup/state-$n.json';

  final CloudProvider provider;
  final Library library;

  /// Download missing audio files right away (desktop); otherwise only when played ([fetchAudio]).
  final bool eagerDownload;
  final Duration changeDelay;
  final Duration backoffBase;
  final Duration backoffMax;

  /// Attempts per file before it is given up (protection against endless loops).
  final int maxAttempts;

  /// Conditional writes of `state.json` per sync before the sync counts as failed.
  final int maxConflicts;

  /// Automatic retries without a connection; after that only start, foreground and changes trigger one.
  final int maxOfflineRetries;
  final DateTime Function() _now;

  SyncStatus _status = SyncStatus.idle;
  final _queue = <String, SyncTask>{};
  Set<String> _cloudAudio = {};
  Future<void>? _running;
  bool _again = false;
  int _offline = 0;
  Timer? _changeTimer;
  Timer? _retryTimer;
  bool _disposed = false;

  /// Time of the last sync that got through.
  DateTime? lastSync;

  @override
  SyncStatus get status => _status;

  /// Tasks still waiting or given up (for tests and the status in #40).
  List<SyncTask> get pending => List.unmodifiable(_queue.values);

  /// Tasks given up after [maxAttempts].
  List<SyncTask> get failed => [
    for (final t in _queue.values)
      if (t.parked) t,
  ];

  /// When the next automatic retry is due; null if none is planned.
  Duration? nextRetry;

  @override
  bool inCloud(String trackId) => _cloudAudio.contains(trackId);

  @override
  Future<void> start() => sync();

  @override
  void resumed() => sync();

  @override
  void localChanged() {
    // A new change gives the state another chance even if it gave up before.
    if (_queue['state'] case final t? when t.parked) _queue.remove('state');
    _changeTimer?.cancel();
    _changeTimer = Timer(changeDelay, sync);
  }

  @override
  Future<void> syncNow() {
    for (final t in _queue.values) {
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
        _status != SyncStatus.tooNew);
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
      _queue.putIfAbsent('state', () => SyncTask('state'));
      await _runTasks(only: 'state');
      if (!_queue.containsKey('state')) {
        _plan(await provider.list('audio/'));
        await _runTasks();
      }
      _offline = 0;
      lastSync = _now();
      _scheduleRetry();
      _setStatus(failed.isEmpty ? SyncStatus.idle : SyncStatus.failed);
    } on CloudOffline {
      _offline++;
      if (_offline <= maxOfflineRetries) _retryIn(_backoff(_offline));
      _setStatus(SyncStatus.offline);
    } on SyncTooNew {
      _setStatus(SyncStatus.tooNew);
    }
  }

  void _setStatus(SyncStatus s) {
    _status = s;
    if (!_disposed) notifyListeners();
  }

  /// Hash from `audio/<hash>.<ext>`.
  static String _hashOf(String name) {
    final base = name.substring(name.lastIndexOf('/') + 1);
    final dot = base.indexOf('.');
    return dot < 0 ? base : base.substring(0, dot);
  }

  void _plan(List<CloudEntry> listing) {
    _cloudAudio = {for (final e in listing) _hashOf(e.name)};
    void add(String key) => _queue.putIfAbsent(key, () => SyncTask(key));
    final tracks = {for (final t in library.tracks) t.id: t};
    for (final t in tracks.values) {
      final here = library.hasFile(t.id);
      final there = _cloudAudio.contains(t.id);
      if (here && !there && library.uploadable(t)) add('up:${t.id}');
      if (!here && there && eagerDownload) add('down:${t.id}');
    }
    // Only hashes the state knows: a file of a track this device has not seen yet stays.
    for (final h in _cloudAudio) {
      final rec = library.state.tracks[h];
      if (rec == null) continue;
      final t = tracks[h];
      if (!rec.alive || (t != null && !library.uploadable(t))) add('rm:$h');
    }
    notifyListeners();
  }

  /// Runs the due tasks ([only] one key). [CloudOffline] stops all of them.
  Future<void> _runTasks({String? only}) async {
    final now = _now();
    for (final task in _queue.values.toList()) {
      if (only != null && task.key != only) continue;
      if (task.parked) continue;
      if (task.notBefore case final t? when t.isAfter(now)) continue;
      try {
        await _execute(task.key);
        _queue.remove(task.key);
      } on CloudOffline {
        rethrow;
      } on SyncTooNew {
        rethrow;
      } catch (e) {
        task.lastError = e;
        task.attempts++;
        if (task.attempts >= maxAttempts) {
          task.parked = true;
        } else {
          task.notBefore = _now().add(_backoff(task.attempts));
        }
      }
    }
  }

  Future<void> _execute(String key) async {
    if (key == 'state') return _syncState();
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
        await provider.put(Library.cloudAudioName(t), bytes);
        _cloudAudio.add(hash);
      case 'down':
        if (t == null || library.hasFile(hash)) return;
        if (!await _download(t)) throw CloudError('download of $hash failed');
      case 'rm':
        final rec = library.state.tracks[hash];
        if (rec == null) return;
        if (rec.alive && t != null && library.uploadable(t)) return;
        for (final e in await provider.list('audio/$hash')) {
          await provider.delete(e.name);
        }
        _cloudAudio.remove(hash);
    }
  }

  Future<bool> _download(Track t) async {
    final f = await provider.get(Library.cloudAudioName(t));
    if (f == null) return false;
    return library.addAudio(t.id, f.bytes);
  }

  @override
  Future<bool> fetchAudio(Track track) async {
    if (library.hasFile(track.id)) return true;
    try {
      return await _download(track);
    } catch (_) {
      return false;
    }
  }

  /// Merges `state.json` into the library and writes the result back conditionally (#37/AK1, AK6).
  Future<void> _syncState() async {
    for (var i = 0; i < maxConflicts; i++) {
      final remote = await provider.get(stateName);
      SharedState? theirs;
      var generation = 0;
      if (remote != null) {
        final (state, gen) = _readState(remote);
        theirs = state;
        generation = gen;
        await library.mergeRemote(theirs);
      }
      final mine = library.state;
      if (theirs != null && sameJson(mine.toJson(), theirs.toJson())) return;
      if (remote != null) {
        // #37/AK6: the previous contents first; the slot follows the generation, so the last 5 remain.
        await provider.put(
          backupName(generation % backupCount + 1),
          remote.bytes,
        );
      }
      try {
        await provider.put(
          stateName,
          encodeState(mine, generation + 1),
          ifVersion: remote?.version,
          ifAbsent: remote == null,
        );
        return;
      } on VersionConflict {
        continue; // someone else wrote in between: read, merge, try again
      }
    }
    throw CloudError('state.json: $maxConflicts conflicts in a row');
  }

  /// Reads `state.json` and checks it before anything is merged (#10/AK7): a damaged file (not JSON, other
  /// types, missing stamps, numbers beyond a double, stamps out of range, records the app cannot show)
  /// leaves the library untouched. The user gets one message per damaged version, the sync stops with an
  /// error and is retried. A newer format version stops the sync ([SyncTooNew]).
  (SharedState, int) _readState(CloudFile remote) {
    try {
      final j = jsonDecode(utf8.decode(remote.bytes));
      if (j is! Map) throw const FormatException('not an object');
      final v = j['formatVersion'];
      if (v is int && v > SharedState.formatVersion) {
        if (_reported != remote.version) library.report(CloudStateTooNew(v));
        _reported = remote.version;
        throw SyncTooNew(v);
      }
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
      TrackSortOrder.parse(state.settings.values['sortOrder'] as String?);
      final g = j['generation'];
      return (state, g is int && g >= 0 && g <= Hlc.maxCounter ? g : 0);
    } on SyncTooNew {
      rethrow;
    } catch (e) {
      if (_reported != remote.version) {
        library.report(const CloudStateUnreadable());
      }
      _reported = remote.version;
      throw CloudError('state.json unreadable: $e');
    }
  }

  /// Version of `state.json` already reported as damaged or too new: one message per version.
  String? _reported;

  /// `state.json`: the shared state plus a generation counter for the backup slots.
  static Uint8List encodeState(SharedState s, int generation) =>
      Uint8List.fromList(
        utf8.encode(
          const JsonEncoder.withIndent('  ')
              .convert({...s.toJson(), 'generation': generation}),
        ),
      );

  Duration _backoff(int attempt) {
    final ms = backoffBase.inMilliseconds * pow(2, attempt - 1);
    return Duration(milliseconds: min(ms, backoffMax.inMilliseconds).round());
  }

  /// Plans a retry when the earliest waiting task is due.
  void _scheduleRetry() {
    DateTime? next;
    for (final t in _queue.values) {
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
