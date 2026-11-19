// Datenmodell der Bibliothek (#16), wie Track.swift der Swift-App. JSON wie der Swift-JSONEncoder:
// UUIDs gross geschrieben, Datum als Sekunden seit 2001-01-01, leere optionale Felder fehlen.
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
    this.contentHash,
  });

  /// Internal ID (UUID) and file name in `Tracks/`, as in the Swift app.
  final String id;

  /// Dateiname im Ordner `Tracks/` der Bibliothek.
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

  /// SHA-256 of the contents (64 hex digits, #35): identifies the track across devices; the same file is
  /// stored only once. Extra field the Swift app ignores; missing in old libraries and computed on open.
  final String? contentHash;

  Track copyWith({
    String? title,
    String? Function()? artist,
    double? duration,
    bool? hasArtwork,
    int? customOrder,
    PlaybackSettings? settings,
    String? Function()? folderId,
    String? contentHash,
  }) => Track(
    id: id,
    fileName: fileName,
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
    contentHash: contentHash ?? this.contentHash,
  );

  factory Track.fromJson(Map<String, Object?> j) => Track(
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
    contentHash: (j['contentHash'] as String?)?.toLowerCase(),
  );

  Map<String, Object?> toJson() => {
    if (album != null) 'album': album,
    if (artist != null) 'artist': artist,
    if (contentHash != null) 'contentHash': contentHash,
    'customOrder': customOrder,
    'dateAdded': dateToSwift(dateAdded),
    'duration': duration,
    'fileName': fileName,
    if (folderId != null) 'folderID': folderId,
    'hasArtwork': hasArtwork,
    'id': id,
    'originalFileName': originalFileName,
    'settings': settings.toJson(),
    'title': title,
  };
}

/// Ordner der Bibliothek (`TrackFolder` in Swift).
class TrackFolder {
  const TrackFolder({required this.id, required this.name});
  final String id;
  final String name;

  factory TrackFolder.fromJson(Map<String, Object?> j) => TrackFolder(
    id: (j['id'] as String).toUpperCase(),
    name: j['name'] as String? ?? '',
  );

  Map<String, Object?> toJson() => {'id': id, 'name': name};
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
