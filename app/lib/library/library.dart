// Bibliothek (#16), wie Library.swift der Swift-App: Dateien werden in den App-Ordner kopiert,
// Metadaten und Einstellungen liegen in `library.json` im gleichen Format `{folders, tracks}`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'metadata.dart';
import 'natural_compare.dart';
import 'swift_json.dart';
import 'track.dart';

export 'track.dart';

/// Dauer einer Datei in Sekunden, < 0 = Fehler. In der App `wpFileDuration` aus dem Audio-Kern.
typedef DurationProbe = double Function(String path);

class ImportResult {
  const ImportResult(this.imported, this.failed);
  final List<Track> imported;

  /// Ursprüngliche Dateinamen, die nicht übernommen werden konnten.
  final List<String> failed;
}

class Library extends ChangeNotifier {
  /// [base] enthält `library.json`, `preferences.json` und den Ordner `Tracks/`.
  Library(
    this.base, {
    required this.probe,
    DateTime Function()? now,
    this.saveDelay = const Duration(milliseconds: 400),
    Random? random,
  }) : _now = now ?? DateTime.now,
       _random = random; // ignore: prefer_initializing_formals

  final Directory base;
  final DurationProbe probe;
  final Duration saveDelay;
  final DateTime Function() _now;
  final Random? _random;

  Directory get tracksDir => Directory('${base.path}/Tracks');
  File get indexFile => File('${base.path}/library.json');
  File get _prefsFile => File('${base.path}/preferences.json');

  List<Track> _tracks = [];
  List<TrackFolder> _folders = [];
  TrackSortOrder _sortOrder = TrackSortOrder.dateAdded;
  bool _importing = false;
  int _droppedMissing = 0;
  String? lastError;
  Timer? _pendingSave;

  List<Track> get tracks => List.unmodifiable(_tracks);
  List<TrackFolder> get folders => List.unmodifiable(_folders);
  bool get isImporting => _importing;

  /// Beim letzten Laden entfernte Einträge, deren Datei fehlte.
  int get droppedMissing => _droppedMissing;

  TrackSortOrder get sortOrder => _sortOrder;
  set sortOrder(TrackSortOrder o) {
    if (o == _sortOrder) return;
    _sortOrder = o;
    _savePrefs();
    notifyListeners();
  }

  // ---- Laden und Speichern ----

  Future<void> load() async {
    tracksDir.createSync(recursive: true);
    _readPrefs();
    _droppedMissing = 0;
    if (!indexFile.existsSync()) return notifyListeners();
    final (folders, tracks) = _readIndex(indexFile);
    if (tracks == null) {
      // Unlesbar: Datei aufheben statt beim nächsten Speichern zu überschreiben.
      final stamp = _now().toIso8601String().replaceAll(':', '-');
      indexFile.renameSync('${indexFile.path}.defekt-$stamp');
      lastError =
          'Die Bibliothek war beschädigt und wurde als «library.json.defekt-$stamp» aufgehoben.';
      return notifyListeners();
    }
    _folders = folders;
    _tracks = tracks.where((t) => File(filePath(t)).existsSync()).toList();
    _droppedMissing = tracks.length - _tracks.length;
    notifyListeners();
  }

  /// Liest `{folders, tracks}` oder das alte Format `[Track]`. tracks == null: unlesbar.
  static (List<TrackFolder>, List<Track>?) _readIndex(File f) {
    try {
      final json = jsonDecode(f.readAsStringSync());
      if (json is List) {
        return (
          <TrackFolder>[],
          json
              .map((e) => Track.fromJson((e as Map).cast<String, Object?>()))
              .toList(),
        );
      }
      final map = (json as Map).cast<String, Object?>();
      final folders = (map['folders'] as List? ?? [])
          .map((e) => TrackFolder.fromJson((e as Map).cast<String, Object?>()))
          .toList();
      final tracks = (map['tracks'] as List? ?? [])
          .map((e) => Track.fromJson((e as Map).cast<String, Object?>()))
          .toList();
      return (folders, tracks);
    } catch (_) {
      return (<TrackFolder>[], null);
    }
  }

  /// Schreibt `library.json` sofort (atomar über eine Zwischendatei).
  void save() {
    _pendingSave?.cancel();
    _pendingSave = null;
    try {
      base.createSync(recursive: true);
      final tmp = File('${indexFile.path}.tmp');
      tmp.writeAsStringSync(swiftPrettyJson(indexJson()));
      tmp.renameSync(indexFile.path);
    } catch (e) {
      lastError = 'Bibliothek konnte nicht gespeichert werden: $e';
      notifyListeners();
    }
  }

  /// Inhalt von library.json.
  Map<String, Object?> indexJson() => {
    'folders': _folders.map((f) => f.toJson()).toList(),
    'tracks': _tracks.map((t) => t.toJson()).toList(),
  };

  /// Fasst häufige Änderungen zusammen (z. B. beim Ziehen des Tempo-Reglers).
  void _scheduleSave() {
    if (saveDelay == Duration.zero) return save();
    _pendingSave?.cancel();
    _pendingSave = Timer(saveDelay, save);
  }

  /// Ausstehendes Speichern sofort erledigen.
  void flush() {
    if (_pendingSave != null) save();
  }

  void _readPrefs() {
    try {
      final p = jsonDecode(_prefsFile.readAsStringSync()) as Map;
      _sortOrder = TrackSortOrder.parse(p['sortOrder'] as String?);
    } catch (_) {
      // keine oder unlesbare Einstellungen: Standardwerte
    }
  }

  void _savePrefs() {
    try {
      base.createSync(recursive: true);
      _prefsFile.writeAsStringSync(jsonEncode({'sortOrder': _sortOrder.name}));
    } catch (_) {}
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
        list.sort((a, b) => naturalCompare(a.title, b.title));
      case TrackSortOrder.dateAdded:
        list.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
      case TrackSortOrder.custom:
        list.sort((a, b) => a.customOrder.compareTo(b.customOrder));
    }
    return list;
  }

  List<TrackFolder> get sortedFolders =>
      [..._folders]..sort((a, b) => naturalCompare(a.name, b.name));

  /// Titel eines Ordners (null = ohne Ordner) in der aktuellen Sortierung.
  List<Track> sortedTracksIn(String? folderId) =>
      sortedTracks.where((t) => t.folderId == folderId).toList();

  Track? track(String id) => _tracks.where((t) => t.id == id).firstOrNull;

  String filePath(Track t) => '${tracksDir.path}/${t.fileName}';

  String? artworkPath(Track t) =>
      t.hasArtwork ? '${tracksDir.path}/${t.id}.artwork' : null;

  int get _nextOrder => _tracks.fold(-1, (m, t) => max(m, t.customOrder)) + 1;

  // ---- Import und Löschen ----

  /// Kopiert die Dateien in die Bibliothek und liest Titel, Künstler, Album, Cover und Dauer.
  Future<ImportResult> importFiles(
    List<String> paths, {
    String? folderId,
  }) async {
    _importing = true;
    notifyListeners();
    final imported = <Track>[];
    final failed = <String>[];
    tracksDir.createSync(recursive: true);
    for (final path in paths) {
      final t = await _importFile(path, folderId);
      if (t == null) {
        failed.add(_baseName(path));
      } else {
        _tracks.add(t);
        imported.add(t);
      }
    }
    _importing = false;
    if (failed.isNotEmpty) {
      lastError =
          'Folgende Dateien konnten nicht importiert werden:\n${failed.join('\n')}';
    }
    save();
    notifyListeners();
    return ImportResult(imported, failed);
  }

  Future<Track?> _importFile(String source, String? folderId) async {
    final id = newUuid(_random);
    final name = _baseName(source);
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : 'mp3';
    final fileName = '$id.$ext';
    final dest = File('${tracksDir.path}/$fileName');
    try {
      await File(source).copy(dest.path);
      final duration = probe(dest.path);
      if (duration <= 0) throw const FormatException('kein lesbares Audio');
      final meta = readMetadata(await dest.readAsBytes());
      var hasArtwork = false;
      if (meta.artwork != null && meta.artwork!.isNotEmpty) {
        try {
          File('${tracksDir.path}/$id.artwork').writeAsBytesSync(meta.artwork!);
          hasArtwork = true;
        } catch (_) {}
      }
      return Track(
        id: id,
        fileName: fileName,
        originalFileName: name,
        title: meta.title ?? (dot > 0 ? name.substring(0, dot) : name),
        artist: meta.artist,
        album: meta.album,
        duration: duration,
        hasArtwork: hasArtwork,
        dateAdded: _now().toUtc(),
        customOrder: _nextOrder,
        folderId: folderId,
      );
    } catch (_) {
      if (dest.existsSync()) dest.deleteSync();
      return null;
    }
  }

  static String _baseName(String path) => path.split(RegExp(r'[/\\]')).last;

  void delete(Set<String> ids) {
    for (final t in _tracks.where((t) => ids.contains(t.id))) {
      _tryDelete(File(filePath(t)));
      _tryDelete(File('${tracksDir.path}/${t.id}.artwork'));
    }
    _tracks.removeWhere((t) => ids.contains(t.id));
    save();
    notifyListeners();
  }

  static void _tryDelete(File f) {
    try {
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
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
    _savePrefs();
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

  TrackFolder createFolder(String name) {
    final f = TrackFolder(id: newUuid(_random), name: _cleanName(name));
    _folders.add(f);
    save();
    notifyListeners();
    return f;
  }

  void renameFolder(String id, String name) {
    final i = _folders.indexWhere((f) => f.id == id);
    if (i < 0) return;
    _folders[i] = TrackFolder(id: id, name: _cleanName(name));
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
      final insertAt = at < slots.length
          ? slots[at]
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

  static String _cleanName(String name) {
    final t = name.trim();
    return t.isEmpty ? 'Neuer Ordner' : t;
  }

  // ---- Einstellungen pro Titel ----

  void updateSettings(String id, PlaybackSettings settings) {
    final i = _tracks.indexWhere((t) => t.id == id);
    if (i < 0 || _tracks[i].settings == settings) return;
    _tracks[i] = _tracks[i].copyWith(settings: settings);
    _scheduleSave();
    notifyListeners();
  }
}
