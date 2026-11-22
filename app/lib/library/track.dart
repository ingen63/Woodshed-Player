// Data model of the library (#16). Since #36 a track is identified by the SHA-256 of its audio file and is
// stored as shared fields with stamps (stamps.dart). [Track.fromLegacyJson] reads the former Swift-compatible
// `library.json` (format 1: UUIDs in capitals, dates as seconds since 2001-01-01) for the migration only.
import 'dart:math';

import 'playback_settings.dart';

export 'playback_settings.dart';

/// Neue UUID (Version 4) in Grossbuchstaben, wie `UUID().uuidString`.
String newUuid([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final hex = b
      .map((x) => x.toRadixString(16).padLeft(2, '0'))
      .join()
      .toUpperCase();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
      '${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Sekunden zwischen 1970-01-01 und 2001-01-01 (Bezugsdatum von Foundation).
const _referenceEpochSeconds = 978307200;

// In ganzen Mikrosekunden rechnen, damit 784123456.789 genau so zurückkommt.
double dateToSwift(DateTime d) =>
    (d.microsecondsSinceEpoch - _referenceEpochSeconds * 1000000) / 1e6;

DateTime dateFromSwift(num seconds) => DateTime.fromMicrosecondsSinceEpoch(
  (seconds * 1e6).round() + _referenceEpochSeconds * 1000000,
  isUtc: true,
);

class Track {
  const Track({
    required this.id,
    required this.fileName,
    required this.originalFileName,
    required this.title,
    this.artist,
    this.album,
    required this.duration,
    required this.hasArtwork,
    required this.dateAdded,
    required this.customOrder,
    this.settings = const PlaybackSettings(),
    this.folderId,
    this.loopId,
    this.loops = const {},
    this.noUpload = false,
  });

  /// SHA-256 of the audio file (64 lowercase hex digits, #36): identifies the track on every device; the same
  /// file is stored only once.
  final String id;

  /// SHA-256 of the contents; the same as [id].
  String get contentHash => id;

  /// File name in the library's `Tracks/` folder: `<id>.<ext>`.
  final String fileName;

  /// Ursprünglicher Dateiname beim Import.
  final String originalFileName;
  final String title;
  final String? artist;
  final String? album;
  final double duration;
  final bool hasArtwork;
  final DateTime dateAdded;
  final int customOrder;
  final PlaybackSettings settings;

  /// Ordner; null = «Ohne Ordner».
  final String? folderId;

  /// ID of the loop shown in the player (its range is [settings].loopStart/loopEnd); null = no loop (#37).
  final String? loopId;

  /// All loops of the track by ID, null for a deleted one (#37/AK4). Each loop is a shared field of its
  /// own, so loops from several devices are merged element by element. The active one is taken from
  /// [settings] when saving.
  final Map<String, LoopRange?> loops;

  /// «Don't upload» (#37/AK5): the audio file stays on this device, the metadata are synced anyway.
  final bool noUpload;

  Track copyWith({
    String? title,
    String? Function()? artist,
    double? duration,
    bool? hasArtwork,
    int? customOrder,
    PlaybackSettings? settings,
    String? Function()? folderId,
    String? id,
    String? fileName,
    String? Function()? loopId,
    Map<String, LoopRange?>? loops,
    bool? noUpload,
  }) => Track(
    id: id ?? this.id,
    fileName: fileName ?? this.fileName,
    originalFileName: originalFileName,
    title: title ?? this.title,
    artist: artist != null ? artist() : this.artist,
    album: album,
    duration: duration ?? this.duration,
    hasArtwork: hasArtwork ?? this.hasArtwork,
    dateAdded: dateAdded,
    customOrder: customOrder ?? this.customOrder,
    settings: settings ?? this.settings,
    folderId: folderId != null ? folderId() : this.folderId,
    loopId: loopId != null ? loopId() : this.loopId,
    loops: loops ?? this.loops,
    noUpload: noUpload ?? this.noUpload,
  );

  /// New playback settings from the player. Setting a loop where there was none creates a loop with a
  /// new ID from [newLoopId]; clearing it deletes the active loop (#37/AK4).
  Track withSettings(PlaybackSettings s, String Function() newLoopId) {
    final hasLoop = s.loopEnd > 0;
    if (hasLoop && loopId == null) {
      final id = newLoopId();
      return copyWith(
        settings: s,
        loopId: () => id,
        loops: {...loops, id: LoopRange(s.loopStart, s.loopEnd)},
      );
    }
    if (!hasLoop && loopId != null) {
      return copyWith(
        settings: s,
        loopId: () => null,
        loops: {...loops, loopId!: null},
      );
    }
    return copyWith(settings: s);
  }

  /// #116/AK5, AK6: the same track after its file was trimmed to [start] … [start] + [duration] seconds and
  /// stored as [fileName] under the new [id]. Title, artist, folder, order, tempo and the other settings stay;
  /// every loop moves by [start] so it marks the same passage, is clamped to the new length if it reaches
  /// outside it and is dropped if it lies outside entirely. A dropped active loop switches the loop off.
  Track trimmed({
    required String id,
    required String fileName,
    required double start,
    required double duration,
    required bool hasArtwork,
  }) {
    final moved = <String, LoopRange?>{
      for (final e in loops.entries) e.key: ?e.value?.trimmed(start, duration),
    };
    var s = settings;
    String? active = loopId;
    if (active != null) {
      final r = LoopRange(
        settings.loopStart,
        settings.loopEnd,
      ).trimmed(start, duration);
      if (r == null) {
        moved.remove(active);
        active = null;
        s = s.copyWith(loopEnabled: false, loopStart: 0, loopEnd: 0);
      } else {
        moved[active] = r;
        s = s.copyWith(loopStart: r.start, loopEnd: r.end);
      }
    } else {
      s = s.copyWith(loopStart: 0, loopEnd: 0);
    }
    return Track(
      id: id,
      fileName: fileName,
      originalFileName: originalFileName,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      hasArtwork: hasArtwork,
      dateAdded: dateAdded,
      customOrder: customOrder,
      settings: s,
      folderId: folderId,
      loopId: active,
      loops: Map.unmodifiable(moved),
      noUpload: noUpload,
    );
  }

  /// Entry of the former `library.json` (format 1, Swift app); `id` is still the UUID there. Its loop gets
  /// the fixed ID «0».
  factory Track.fromLegacyJson(Map<String, Object?> j) {
    final t = Track._fromLegacyJson(j);
    final s = t.settings;
    return s.loopEnd > 0
        ? t.copyWith(
            loopId: () => '0',
            loops: {'0': LoopRange(s.loopStart, s.loopEnd)},
          )
        : t;
  }

  factory Track._fromLegacyJson(Map<String, Object?> j) => Track(
    id: (j['id'] as String).toUpperCase(),
    fileName: j['fileName'] as String,
    originalFileName:
        j['originalFileName'] as String? ?? j['fileName'] as String,
    title: j['title'] as String,
    artist: j['artist'] as String?,
    album: j['album'] as String?,
    duration: (j['duration'] as num?)?.toDouble() ?? 0,
    hasArtwork: j['hasArtwork'] as bool? ?? false,
    dateAdded: dateFromSwift(j['dateAdded'] as num? ?? 0),
    customOrder: (j['customOrder'] as num?)?.toInt() ?? 0,
    settings: j['settings'] is Map
        ? PlaybackSettings.fromJson(
            (j['settings'] as Map).cast<String, Object?>(),
          )
        : const PlaybackSettings(),
    folderId: (j['folderID'] as String?)?.toUpperCase(),
  );

  /// Prefix of the loop fields: `loops.<id>` = `{start, end}` or null (deleted).
  static const loopPrefix = 'loops.';

  /// Shared fields (#36/AK5), each stamped on its own. Every loop is one field `loops.<id>` with start and
  /// end, so merging never mixes the boundaries of two devices but keeps loops from both (#37/AK4).
  Map<String, Object?> toShared() => {
    'fileName': fileName,
    'originalFileName': originalFileName,
    'title': title,
    'artist': artist,
    'album': album,
    'duration': duration,
    'hasArtwork': hasArtwork,
    'dateAdded': dateAdded.toUtc().toIso8601String(),
    'customOrder': customOrder,
    'folderId': folderId,
    'speedEnabled': settings.speedEnabled,
    'speed': settings.speed,
    'loopEnabled': settings.loopEnabled,
    'activeLoop': loopId,
    for (final e in loops.entries) '$loopPrefix${e.key}': e.value?.toJson(),
    if (loopId case final id?)
      '$loopPrefix$id': LoopRange(
        settings.loopStart,
        settings.loopEnd,
      ).toJson(),
    'noUpload': noUpload,
    'rampEnabled': settings.rampEnabled,
    'rampStart': settings.rampStart,
    'rampTarget': settings.rampTarget,
    'rampStep': settings.rampStep,
    'rampPasses': settings.rampPasses,
  };

  factory Track.fromShared(String id, Map<String, Object?> v) {
    double d(Object? x, double fallback) => x is num ? x.toDouble() : fallback;
    int? i(Object? x) => x is num ? x.round() : null;
    final loops = <String, LoopRange?>{
      for (final e in v.entries)
        if (e.key.startsWith(loopPrefix))
          e.key.substring(loopPrefix.length): LoopRange.fromJson(e.value),
    };
    String? loopId = v['activeLoop'] as String?;
    var loopEnabled = v['loopEnabled'] as bool? ?? false;
    if (!v.containsKey('activeLoop') && v['loop'] is Map) {
      // Format 2 before #37: one loop {enabled, start, end}; it gets the fixed ID «0» on every device.
      final old = v['loop'] as Map;
      loopEnabled = old['enabled'] as bool? ?? false;
      final r = LoopRange.fromJson(old);
      if (r != null) {
        loopId = '0';
        loops['0'] = r;
      }
    }
    final active = loopId == null ? null : loops[loopId];
    if (active == null) loopId = null; // deleted on another device
    final fileName = v['fileName'] as String;
    return Track(
      id: id,
      fileName: fileName,
      originalFileName: v['originalFileName'] as String? ?? fileName,
      title: v['title'] as String? ?? '',
      artist: v['artist'] as String?,
      album: v['album'] as String?,
      duration: d(v['duration'], 0),
      hasArtwork: v['hasArtwork'] as bool? ?? false,
      dateAdded:
          DateTime.tryParse(v['dateAdded'] as String? ?? '')?.toUtc() ??
          DateTime.utc(2001),
      customOrder: i(v['customOrder']) ?? 0,
      folderId: v['folderId'] as String?,
      loopId: loopId,
      loops: Map.unmodifiable(loops),
      noUpload: v['noUpload'] as bool? ?? false,
      settings:
          PlaybackSettings(
            speedEnabled: v['speedEnabled'] as bool? ?? false,
            speed: d(v['speed'], 1),
            loopEnabled: loopEnabled,
            loopStart: active?.start ?? 0,
            loopEnd: active?.end ?? 0,
          ).copyWith(
            rampEnabled: v['rampEnabled'] as bool?,
            rampStart: i(v['rampStart']),
            rampTarget: i(v['rampTarget']),
            rampStep: i(v['rampStep']),
            rampPasses: i(v['rampPasses']),
          ),
    );
  }
}

/// Start and end of a loop in seconds (#37/AK4).
class LoopRange {
  const LoopRange(this.start, this.end);
  final double start;
  final double end;

  Map<String, Object?> toJson() => {'start': start, 'end': end};

  /// #116/AK6: this loop in a file trimmed to [cut] … [cut] + [length] seconds: moved by [cut], clamped to
  /// 0 … [length]; null if it lies entirely outside (touching a bound counts as outside).
  LoopRange? trimmed(double cut, double length) {
    final s = start - cut, e = end - cut;
    if (e <= 0 || s >= length) return null;
    return LoopRange(max(0.0, s), min(length, e));
  }

  /// null for a deleted loop or invalid contents.
  static LoopRange? fromJson(Object? j) {
    if (j is! Map) return null;
    final s = j['start'];
    final e = j['end'];
    return s is num && e is num ? LoopRange(s.toDouble(), e.toDouble()) : null;
  }

  @override
  bool operator ==(Object other) =>
      other is LoopRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// Ordner der Bibliothek (`TrackFolder` in Swift).
class TrackFolder {
  const TrackFolder({required this.id, required this.name, this.sync = true});
  final String id;
  final String name;

  /// «Sync» (#37/AK5): the audio files of its tracks go to the cloud; off keeps them on this device, the
  /// metadata are synced anyway.
  final bool sync;

  TrackFolder copyWith({String? name, bool? sync}) =>
      TrackFolder(id: id, name: name ?? this.name, sync: sync ?? this.sync);

  /// Entry of the former `library.json` (format 1).
  factory TrackFolder.fromLegacyJson(Map<String, Object?> j) => TrackFolder(
    id: (j['id'] as String).toUpperCase(),
    name: j['name'] as String? ?? '',
  );

  /// Shared fields (#36/AK5).
  Map<String, Object?> toShared() => {'name': name, 'sync': sync};

  factory TrackFolder.fromShared(String id, Map<String, Object?> v) =>
      TrackFolder(
        id: id,
        name: v['name'] as String? ?? '',
        sync: v['sync'] as bool? ?? true,
      );
}

/// Playlist (#114): a named list of tracks in its own order. A track may stand in several playlists and
/// several times in one; [entries] hold track IDs, the audio file exists once. Shared playlists are synced
/// like folders; one «only on this device» ([shared] false) stays on the device that chose it.
class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    this.shared = true,
    this.entries = const [],
  });

  final String id;
  final String name;

  /// «On all devices» (#114/AK9); new playlists are shared.
  final bool shared;

  /// Track IDs in playing order, possibly repeated; may name tracks deleted on another device, which the
  /// library leaves out ([Library.playlistTracks]).
  final List<String> entries;

  Playlist copyWith({String? name, bool? shared, List<String>? entries}) =>
      Playlist(
        id: id,
        name: name ?? this.name,
        shared: shared ?? this.shared,
        entries: entries ?? this.entries,
      );

  /// Shared fields; [entries] is one field, so a sync takes the newer order as a whole.
  Map<String, Object?> toShared() => {
    'name': name,
    'shared': shared,
    'entries': List<String>.unmodifiable(entries),
  };

  /// Throws on values of the wrong type (a damaged file), like the other records.
  factory Playlist.fromShared(String id, Map<String, Object?> v) => Playlist(
    id: id,
    name: v['name'] as String? ?? '',
    shared: v['shared'] as bool? ?? true,
    entries: List.unmodifiable(
      (v['entries'] as List? ?? const []).cast<String>().toList(),
    ),
  );
}

/// Sort order of the library; the UI names it in the user's language (#43).
enum TrackSortOrder {
  alphabetical,
  dateAdded,
  custom;

  static TrackSortOrder parse(String? s) => values.firstWhere(
    (v) => v.name == s,
    orElse: () => TrackSortOrder.dateAdded,
  );
}

/// Light or dark appearance of the app (#31); [system] follows the platform setting.
enum Appearance {
  system,
  light,
  dark;

  /// #31/AK5: missing or unknown values mean [system].
  static Appearance parse(Object? s) =>
      values.firstWhere((v) => v.name == s, orElse: () => Appearance.system);
}
