// Data model for merging changes from several devices (#36, plan W4): every shared field carries a hybrid
// logical clock stamp (time, counter, device ID); per field the higher stamp wins. Deleted tracks and folders
// stay as tombstones for 90 days; after that the newest removed deletion is kept as the purge horizon, so a
// device offline for longer cannot bring them back (#98). Pure Dart without I/O, so the sync engine (#37) can
// merge with it.
import 'dart:convert';

/// Hybrid logical clock stamp: wall time in milliseconds, a counter for events within the same millisecond
/// (or while the clock lags behind a stamp already seen), and the ID of the device that made the change.
/// Ordered by time, then counter, then device ID, so two stamps are never equal across devices.
class Hlc implements Comparable<Hlc> {
  const Hlc(this.millis, this.counter, this.device);

  final int millis;
  final int counter;
  final String device;

  DateTime get time => DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);

  @override
  int compareTo(Hlc o) {
    if (millis != o.millis) return millis.compareTo(o.millis);
    if (counter != o.counter) return counter.compareTo(o.counter);
    return device.compareTo(o.device);
  }

  bool operator >(Hlc o) => compareTo(o) > 0;
  bool operator <(Hlc o) => compareTo(o) < 0;

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.millis == millis &&
      other.counter == counter &&
      other.device == device;

  @override
  int get hashCode => Object.hash(millis, counter, device);

  /// «millis-counter-device», e.g. `1763560000000-0-3f2a9c1e5b7d4a60`.
  @override
  String toString() => '$millis-$counter-$device';

  static Hlc parse(String s) {
    final a = s.indexOf('-');
    final b = s.indexOf('-', a + 1);
    if (a <= 0 || b <= a + 1 || b == s.length - 1) {
      throw FormatException('Invalid stamp', s);
    }
    final millis = int.parse(s.substring(0, a));
    final counter = int.parse(s.substring(a + 1, b));
    // #10/AK7: only times a DateTime can hold and counters exact in JavaScript (web app).
    if (millis > maxMillis || counter > maxCounter) {
      throw FormatException('Stamp out of range', s);
    }
    return Hlc(millis, counter, s.substring(b + 1));
  }

  /// Largest time of a stamp (that of DateTime), largest counter.
  static const maxMillis = 8640000000000000;
  static const maxCounter = 0x7fffffff;

  static Hlc? maxOf(Iterable<Hlc?> stamps) {
    Hlc? m;
    for (final s in stamps) {
      if (s != null && (m == null || s > m)) m = s;
    }
    return m;
  }
}

/// Issues stamps for this device. Every new stamp is higher than all stamps issued or [observe]d before,
/// even if the wall clock goes backwards.
class HlcClock {
  HlcClock(this.device, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final String device;
  final DateTime Function() _now;
  Hlc? _last;

  Hlc tick() {
    final wall = _now().millisecondsSinceEpoch;
    final last = _last;
    return _last = last == null || wall > last.millis
        ? Hlc(wall, 0, device)
        : Hlc(last.millis, last.counter + 1, device);
  }

  /// Takes note of a stamp from the file or another device.
  void observe(Hlc? h) {
    if (h == null) return;
    final last = _last;
    if (last == null ||
        h.millis > last.millis ||
        (h.millis == last.millis && h.counter > last.counter)) {
      _last = Hlc(h.millis, h.counter, device);
    }
  }
}

/// Deep equality of JSON values; 47 and 47.0 are the same number.
bool sameJson(Object? a, Object? b) {
  if (a is num && b is num) return a == b;
  if (a is Map && b is Map) {
    return a.length == b.length &&
        a.keys.every((k) => b.containsKey(k) && sameJson(a[k], b[k]));
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!sameJson(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

/// #10 (found by the random tests): JSON allows numbers beyond the range of a double (`1e400`), which
/// Dart reads as infinity; such a value could be read but never written again. A file containing one is
/// damaged.
bool isFiniteJson(Object? v) => switch (v) {
  double d => d.isFinite,
  Map<Object?, Object?> m => m.values.every(isFiniteJson),
  List<Object?> l => l.every(isFiniteJson),
  _ => true,
};

/// JSON with sorted keys, used only to break ties deterministically.
String _canonical(Object? v) => switch (v) {
  Map<Object?, Object?> m =>
    '{${(m.keys.map((k) => '$k').toList()..sort()).map((k) => '${jsonEncode(k)}:${_canonical(m[k])}').join(',')}}',
  List<Object?> l => '[${l.map(_canonical).join(',')}]',
  num n => jsonEncode(n.toDouble()),
  _ => jsonEncode(v),
};

/// One track, folder or the shared settings: field values, a stamp per field and, once deleted, the
/// stamp of the deletion. A record is alive if it was never deleted or a field changed after the deletion.
class StampedRecord {
  const StampedRecord(this.values, this.stamps, [this.deleted]);

  /// New record whose fields all carry [stamp].
  factory StampedRecord.create(Map<String, Object?> values, Hlc stamp) =>
      StampedRecord(Map.unmodifiable(values), {
        for (final k in values.keys) k: stamp,
      });

  final Map<String, Object?> values;
  final Map<String, Hlc> stamps;
  final Hlc? deleted;

  /// Highest field stamp.
  Hlc? get latest => Hlc.maxOf(stamps.values);

  bool get alive {
    final d = deleted;
    if (d == null) return true;
    final l = latest;
    return l != null && l > d;
  }

  /// Stamps every field whose value differs from [current] with [stamp]. A deleted record is revived
  /// with all fields stamped. Returns this record if nothing changed.
  StampedRecord update(Map<String, Object?> current, Hlc stamp) {
    if (!alive) {
      return StampedRecord(Map.unmodifiable(current), {
        for (final k in current.keys) k: stamp,
      }, deleted);
    }
    final changed = [
      for (final k in current.keys)
        if (!values.containsKey(k) || !sameJson(values[k], current[k])) k,
    ];
    if (changed.isEmpty) return this;
    return StampedRecord(
      Map.unmodifiable({...values, for (final k in changed) k: current[k]}),
      {...stamps, for (final k in changed) k: stamp},
      deleted,
    );
  }

  /// Every field stamped anew with [stamp], values and deletion unchanged (#104).
  StampedRecord restamp(Hlc stamp) =>
      StampedRecord(values, {for (final k in stamps.keys) k: stamp}, deleted);

  /// Marks the record deleted; its values stay so that a newer change elsewhere can revive it.
  StampedRecord delete(Hlc stamp) => StampedRecord(values, stamps, stamp);

  /// Field by field the value with the higher stamp; the later deletion. Commutative, associative and
  /// idempotent.
  StampedRecord merge(StampedRecord o) {
    final values = <String, Object?>{};
    final stamps = <String, Hlc>{};
    for (final k in {...this.stamps.keys, ...o.stamps.keys}) {
      final a = this.stamps[k];
      final b = o.stamps[k];
      final bool takeOther;
      if (a == null) {
        takeOther = true;
      } else if (b == null) {
        takeOther = false;
      } else if (a != b) {
        takeOther = b > a;
      } else {
        // Same stamp, so normally the same value; otherwise choose deterministically.
        takeOther =
            _canonical(o.values[k]).compareTo(_canonical(this.values[k])) > 0;
      }
      values[k] = takeOther ? o.values[k] : this.values[k];
      stamps[k] = takeOther ? b! : a!;
    }
    return StampedRecord(
      Map.unmodifiable(values),
      stamps,
      Hlc.maxOf([deleted, o.deleted]),
    );
  }

  Map<String, Object?> toJson() => {
    'values': values,
    'stamps': {for (final e in stamps.entries) e.key: '${e.value}'},
    if (deleted != null) 'deleted': '$deleted',
  };

  factory StampedRecord.fromJson(Map<String, Object?> j) {
    final values = (j['values'] as Map? ?? const {}).cast<String, Object?>();
    final stamps = {
      for (final e in (j['stamps'] as Map? ?? const {}).entries)
        e.key as String: Hlc.parse(e.value as String),
    };
    if (!stamps.keys.toSet().containsAll(values.keys)) {
      throw const FormatException('Field without stamp');
    }
    final d = j['deleted'];
    return StampedRecord(
      Map.unmodifiable(values),
      stamps,
      d is String ? Hlc.parse(d) : null,
    );
  }
}

/// Contents of `library.json` from format version 2 on: tracks (key = SHA-256 of the audio file), folders,
/// playlists (#114, optional, so older apps of format 2 read the file and ignore them) and the shared
/// settings, each with stamps. Device-local data never goes in here (see DeviceSettings).
class SharedState {
  const SharedState({
    this.tracks = const {},
    this.folders = const {},
    this.playlists = const {},
    this.settings = const StampedRecord({}, {}),
    this.purged,
  });

  static const empty = SharedState();

  /// Version of the file format written by this app; 1 is the former Swift-compatible `library.json`.
  static const formatVersion = 2;

  /// Tombstones are removed after this time.
  static const tombstoneLifetime = Duration(days: 90);

  final Map<String, StampedRecord> tracks;
  final Map<String, StampedRecord> folders;

  /// #114: playlists by ID (UUID); merged like folders.
  final Map<String, StampedRecord> playlists;
  final StampedRecord settings;

  /// Purge horizon (#98): the newest deletion whose tombstone [purge] removed; null if none was removed
  /// yet. A record deleted and purged here was last changed before this stamp. So a record the other side
  /// of a [merge] does not know may be one deleted here: it is deleted at this stamp, which kills it if it
  /// was last changed before (a device offline for longer than the tombstones). Records changed later (a
  /// new import) stay alive.
  final Hlc? purged;

  Hlc? get latest => Hlc.maxOf([
    for (final r in [
      ...tracks.values,
      ...folders.values,
      ...playlists.values,
      settings,
    ]) ...[r.latest, r.deleted],
  ]);

  SharedState copyWith({
    Map<String, StampedRecord>? tracks,
    Map<String, StampedRecord>? folders,
    Map<String, StampedRecord>? playlists,
    StampedRecord? settings,
    Hlc? purged,
  }) => SharedState(
    tracks: tracks ?? this.tracks,
    folders: folders ?? this.folders,
    playlists: playlists ?? this.playlists,
    settings: settings ?? this.settings,
    purged: purged ?? this.purged,
  );

  /// Merges record by record. A record only one side knows is merged with a tombstone at the other side's
  /// purge horizon (#98): a record last changed before the horizon may have been deleted there and is dead
  /// afterwards, a later one stays alive. The result keeps the higher horizon. Being a merge of records
  /// throughout, it is commutative, associative and idempotent.
  SharedState merge(SharedState o) {
    StampedRecord against(StampedRecord r, Hlc? horizon) {
      final d = Hlc.maxOf([r.deleted, horizon]);
      return d == r.deleted ? r : StampedRecord(r.values, r.stamps, d);
    }

    Map<String, StampedRecord> both(
      Map<String, StampedRecord> a,
      Map<String, StampedRecord> b,
    ) => {
      for (final k in {...a.keys, ...b.keys})
        k: switch ((a[k], b[k])) {
          (final x?, final y?) => x.merge(y),
          (final x?, null) => against(x, o.purged),
          (null, final y?) => against(y, purged),
          _ => throw StateError('unreachable'),
        },
    };
    return SharedState(
      tracks: both(tracks, o.tracks),
      folders: both(folders, o.folders),
      playlists: both(playlists, o.playlists),
      settings: settings.merge(o.settings),
      purged: Hlc.maxOf([purged, o.purged]),
    );
  }

  /// #104: prepares the state of a device that has never synced for its first merge with [remote]; the
  /// purge horizon applies only between devices that have synced before. This device's own horizon only
  /// concerns records it never shared, so it is dropped. Its alive records that [remote] does not know and
  /// whose horizon would kill are stamped anew with [stamp], which must be higher than every stamp and the
  /// horizon of [remote]. Records [remote] knows, even as tombstones, are left as they are. [merge] itself
  /// stays unchanged (commutative, associative, idempotent).
  SharedState beforeFirstSync(SharedState remote, Hlc stamp) {
    final lost = lostTo(remote);
    return SharedState(
      tracks: _restamped(tracks, lost.tracks, stamp),
      folders: _restamped(folders, lost.folders, stamp),
      playlists: _restamped(playlists, lost.playlists, stamp),
      settings: settings,
    );
  }

  /// #104, #107: keys of the alive tracks, folders and playlists (#114) of this state that a [merge] with
  /// [remote] would kill by the purge horizon of [remote]: [remote] does not know them and they were last
  /// changed before the horizon.
  ({Set<String> tracks, Set<String> folders, Set<String> playlists}) lostTo(
    SharedState remote,
  ) {
    final h = remote.purged;
    Set<String> lost(
      Map<String, StampedRecord> mine,
      Map<String, StampedRecord> theirs,
    ) => {
      if (h != null)
        for (final e in mine.entries)
          if (e.value.latest case final l?
              when e.value.alive && !theirs.containsKey(e.key) && !(l > h))
            e.key,
    };
    return (
      tracks: lost(tracks, remote.tracks),
      folders: lost(folders, remote.folders),
      playlists: lost(playlists, remote.playlists),
    );
  }

  /// #107 «Keep»: the tracks [tracks], folders [folders] and playlists [playlists] stamped anew with
  /// [stamp], so the purge horizon no longer applies to them and they reach the other devices.
  SharedState restamp(
    Set<String> tracks,
    Set<String> folders,
    Hlc stamp, {
    Set<String> playlists = const {},
  }) => copyWith(
    tracks: _restamped(this.tracks, tracks, stamp),
    folders: _restamped(this.folders, folders, stamp),
    playlists: _restamped(this.playlists, playlists, stamp),
  );

  static Map<String, StampedRecord> _restamped(
    Map<String, StampedRecord> records,
    Set<String> keys,
    Hlc stamp,
  ) => {
    for (final e in records.entries)
      e.key: keys.contains(e.key) ? e.value.restamp(stamp) : e.value,
  };

  /// Some stamp, deletion or the horizon comes from a device other than [device]: this state has been
  /// merged with another one (#104, for `device.json` files written before the flag existed).
  bool stampedByOthers(String device) => [
    purged,
    for (final r in [
      ...tracks.values,
      ...folders.values,
      ...playlists.values,
      settings,
    ]) ...[...r.stamps.values, r.deleted],
  ].any((h) => h != null && h.device != device);

  /// Removes tombstones whose deletion is older than [tombstoneLifetime] and moves the purge horizon up to
  /// the newest deletion removed (#98).
  SharedState purge(DateTime now) {
    final limit = now.millisecondsSinceEpoch - tombstoneLifetime.inMilliseconds;
    bool keep(StampedRecord r) => r.alive || r.deleted!.millis >= limit;
    return SharedState(
      tracks: {
        for (final e in tracks.entries)
          if (keep(e.value)) e.key: e.value,
      },
      folders: {
        for (final e in folders.entries)
          if (keep(e.value)) e.key: e.value,
      },
      playlists: {
        for (final e in playlists.entries)
          if (keep(e.value)) e.key: e.value,
      },
      settings: settings,
      purged: Hlc.maxOf([
        purged,
        for (final r in [
          ...tracks.values,
          ...folders.values,
          ...playlists.values,
        ])
          if (!keep(r)) r.deleted,
      ]),
    );
  }

  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    if (purged != null) 'purged': '$purged',
    'settings': settings.toJson(),
    'folders': {for (final e in folders.entries) e.key: e.value.toJson()},
    if (playlists.isNotEmpty)
      'playlists': {for (final e in playlists.entries) e.key: e.value.toJson()},
    'tracks': {for (final e in tracks.entries) e.key: e.value.toJson()},
  };

  /// Reads format version 2; throws [FormatException] if the contents are invalid.
  factory SharedState.fromJson(Map<String, Object?> j) {
    Map<String, StampedRecord> records(Object? m) => {
      for (final e in (m as Map? ?? const {}).entries)
        e.key as String: StampedRecord.fromJson(
          (e.value as Map).cast<String, Object?>(),
        ),
    };
    return SharedState(
      tracks: records(j['tracks']),
      folders: records(j['folders']),
      playlists: records(j['playlists']),
      settings: j['settings'] is Map
          ? StampedRecord.fromJson((j['settings'] as Map).cast())
          : const StampedRecord({}, {}),
      purged: j['purged'] is String ? Hlc.parse(j['purged'] as String) : null,
    );
  }
}
