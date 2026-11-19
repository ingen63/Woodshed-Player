// Migration of the former `library.json` (format 1, compatible with the Swift app) to format 2 (#36/AK3).
// The track ID becomes the SHA-256 of the audio file, and the files in `Tracks/` (audio and artwork) are
// renamed to `<hash>.<ext>`. Runs on every FileStore, so file system and browser (OPFS) share it.
//
// Safe to repeat after an interruption: the old file is kept as `library.v1.json` and the mapping
// old ID → hash is written to `library.v1-ids.json` before any file is renamed. Both stay as the backup.
// Only the final write of `library.json` in format 2 completes the migration.
import 'dart:convert';
import 'dart:typed_data';

import '../app/file_platform.dart';
import 'track.dart';

class LegacyLibrary {
  const LegacyLibrary(this.folders, this.tracks, this.missing);
  final List<TrackFolder> folders;

  /// Tracks with their new ID and file name.
  final List<Track> tracks;

  /// Entries whose audio file was missing (dropped, as before when opening).
  final int missing;
}

const legacyBackupName = 'library.v1.json';
const legacyIdsName = 'library.v1-ids.json';

final _hex64 = RegExp(r'^[0-9a-f]{64}$');

/// Reads `{folders, tracks}` or the oldest format `[Track]`; throws on unreadable contents.
(List<TrackFolder>, List<Track>) readLegacyIndex(Object? json) {
  List<Map<String, Object?>> maps(Object? l) => [
    for (final e in (l as List? ?? const []))
      (e as Map).cast<String, Object?>(),
  ];
  if (json is List) {
    return (<TrackFolder>[], maps(json).map(Track.fromLegacyJson).toList());
  }
  final map = (json as Map).cast<String, Object?>();
  return (
    maps(map['folders']).map(TrackFolder.fromLegacyJson).toList(),
    maps(map['tracks']).map(Track.fromLegacyJson).toList(),
  );
}

/// Legacy `contentHash` (#35) of each entry, by old ID.
Map<String, String> _storedHashes(Object? json) {
  final list = json is List
      ? json
      : (json as Map)['tracks'] as List? ?? const [];
  return {
    for (final e in list.cast<Map>())
      if (e['contentHash'] case final String h
          when _hex64.hasMatch(h.toLowerCase()))
        (e['id'] as String).toUpperCase(): h.toLowerCase(),
  };
}

String _ext(String fileName) {
  final dot = fileName.lastIndexOf('.');
  return dot > 0 ? fileName.substring(dot + 1) : 'mp3';
}

Future<void> _move(FileStore store, String from, String to) async {
  if (from == to || !await store.exists(from) || await store.exists(to)) return;
  await store.rename(from, to);
}

/// Converts the format 1 index [raw] in [store]: backup, ID mapping, renamed files. The caller writes the
/// new `library.json`.
Future<LegacyLibrary> migrateLegacyLibrary(
  FileStore store,
  Uint8List raw,
) async {
  final json = jsonDecode(utf8.decode(raw));
  final (folders, oldTracks) = readLegacyIndex(json);
  if (!await store.exists(legacyBackupName)) {
    await store.write(legacyBackupName, raw);
  }

  // Mapping old ID → hash; from an interrupted run if there is one.
  var ids = <String, String>{};
  try {
    final j = await store.read(legacyIdsName);
    if (j != null) {
      ids = (jsonDecode(utf8.decode(j)) as Map).cast<String, String>();
    }
  } catch (_) {}
  final stored = _storedHashes(json);
  var added = false;
  for (final t in oldTracks) {
    if (ids.containsKey(t.id)) continue;
    final h =
        stored[t.id] ?? await store.sha256(LibraryFiles.trackName(t.fileName));
    if (h == null) continue; // audio missing
    ids[t.id] = h;
    added = true;
  }
  if (added) {
    await store.write(
      legacyIdsName,
      Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(ids)),
      ),
    );
  }

  final tracks = <Track>[];
  final seen = <String>{};
  var missing = 0;
  for (final t in oldTracks) {
    final h = ids[t.id];
    if (h == null || !seen.add(h)) {
      // Missing audio, or a second entry with the same contents: its file stays under the old name.
      if (h == null) missing++;
      continue;
    }
    final fileName = '$h.${_ext(t.fileName)}';
    await _move(
      store,
      LibraryFiles.trackName(t.fileName),
      LibraryFiles.trackName(fileName),
    );
    await _move(
      store,
      LibraryFiles.artworkName(t.id),
      LibraryFiles.artworkName(h),
    );
    if (!await store.exists(LibraryFiles.trackName(fileName))) {
      missing++;
      continue;
    }
    tracks.add(t.copyWith(id: h, fileName: fileName));
  }
  return LegacyLibrary(folders, tracks, missing);
}

/// File names in the library folder.
abstract final class LibraryFiles {
  static String trackName(String fileName) => 'Tracks/$fileName';
  static String artworkName(String id) => 'Tracks/$id.artwork';
}
