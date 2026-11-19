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
  );

  /// Entry of the former `library.json` (format 1, Swift app); `id` is still the UUID there.
  factory Track.fromLegacyJson(Map<String, Object?> j) => Track(
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

  /// Shared fields (#36/AK5), each stamped on its own. Loop start, end and switch form one field so that
  /// merging never mixes the boundaries of two devices.
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
    'loop': {
      'enabled': settings.loopEnabled,
      'start': settings.loopStart,
      'end': settings.loopEnd,
    },
    'rampEnabled': settings.rampEnabled,
    'rampStart': settings.rampStart,
    'rampTarget': settings.rampTarget,
    'rampStep': settings.rampStep,
    'rampPasses': settings.rampPasses,
  };

  factory Track.fromShared(String id, Map<String, Object?> v) {
    double d(Object? x, double fallback) => x is num ? x.toDouble() : fallback;
    int? i(Object? x) => x is num ? x.round() : null;
    final loop = v['loop'] is Map ? v['loop'] as Map : const {};
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
      settings:
          PlaybackSettings(
            speedEnabled: v['speedEnabled'] as bool? ?? false,
            speed: d(v['speed'], 1),
            loopEnabled: loop['enabled'] as bool? ?? false,
            loopStart: d(loop['start'], 0),
            loopEnd: d(loop['end'], 0),
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

/// Ordner der Bibliothek (`TrackFolder` in Swift).
class TrackFolder {
  const TrackFolder({required this.id, required this.name});
  final String id;
  final String name;

  /// Entry of the former `library.json` (format 1).
  factory TrackFolder.fromLegacyJson(Map<String, Object?> j) => TrackFolder(
    id: (j['id'] as String).toUpperCase(),
    name: j['name'] as String? ?? '',
  );

  /// Shared fields (#36/AK5).
  Map<String, Object?> toShared() => {'name': name};

  factory TrackFolder.fromShared(String id, Map<String, Object?> v) =>
      TrackFolder(id: id, name: v['name'] as String? ?? '');
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
