// Bibliothek (#16), wie Library.swift der Swift-App: Dateien werden in die Bibliothek kopiert,
// Metadaten und Einstellungen liegen in `library.json` im gleichen Format `{folders, tracks}`.
// Seit #35 über eine Speicher-Schicht ([FileStore]): Dateisystem auf Desktop und Handy, OPFS im Browser.
// Jeder Titel trägt den SHA-256 seines Inhalts (`contentHash`); dieselbe Datei wird nur einmal gespeichert.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';

import '../app/file_platform.dart';
import 'metadata.dart';
import 'natural_compare.dart';
import 'swift_json.dart';
import 'track.dart';

export '../app/file_platform.dart' show FileStore, StorageInfo;
export 'track.dart';

/// Dauer einer Datei in Sekunden, < 0 = Fehler. In der App `wpFileDuration` aus dem Audio-Kern.
/// null = erst beim Laden bekannt (Browser, wo der Kern im Worklet dekodiert).
typedef DurationProbe = double? Function(String path);

/// Inhalt einer gewählten oder hereingezogenen Datei (Quelle des Imports); null, wenn sie fehlt.
typedef SourceReader = Future<Uint8List?> Function(String source);

class ImportResult {
  const ImportResult(this.imported, this.failed, [this.duplicates = const []]);
  final List<Track> imported;

  /// Ursprüngliche Dateinamen, die nicht übernommen werden konnten.
  final List<String> failed;

  /// Titel, die mit gleichem Inhalt schon in der Bibliothek waren (keine zweite Datei).
  final List<Track> duplicates;
}

String _sha256Hex(Uint8List bytes) => crypto.sha256.convert(bytes).toString();

/// Bis zu dieser Grösse (Bytes) wird der Hash direkt gerechnet, das dauert nur Millisekunden.
const _hashInline = 1 << 20;

class Library extends ChangeNotifier {
  /// [store] enthält `library.json`, `preferences.json` und den Ordner `Tracks/`. [readSource] liest die
  /// Dateien, die importiert werden (Pfad auf Desktop, Schlüssel der Dateiauswahl im Browser).
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
  static const _prefsName = 'preferences.json';
  static String trackName(String fileName) => 'Tracks/$fileName';
  static String _artworkName(String id) => 'Tracks/$id.artwork';

  List<Track> _tracks = [];
  List<TrackFolder> _folders = [];
  TrackSortOrder _sortOrder = TrackSortOrder.dateAdded;
  bool _importing = false;
  int _droppedMissing = 0;
  String? lastError;
  Timer? _pendingSave;
  Future<void>? _hashing;
  StorageInfo? _storage;
  bool _persistAsked = false;

  List<Track> get tracks => List.unmodifiable(_tracks);
  List<TrackFolder> get folders => List.unmodifiable(_folders);
  bool get isImporting => _importing;

  /// Beim letzten Laden entfernte Einträge, deren Datei fehlte.
  int get droppedMissing => _droppedMissing;

  /// Fertig, wenn die fehlenden `contentHash` alter Bibliotheken nachgerechnet sind (läuft nach [load]
  /// im Hintergrund).
  Future<void> get hashing => _hashing ?? Future.value();

  /// Belegter Speicher (im Browser auch verfügbarer und ob dauerhaft); null, bis er gemessen ist.
  StorageInfo? get storage => _storage;

  TrackSortOrder get sortOrder => _sortOrder;
  set sortOrder(TrackSortOrder o) {
    if (o == _sortOrder) return;
    _sortOrder = o;
    _savePrefs();
    notifyListeners();
  }

  // ---- Laden und Speichern ----

  Future<void> load() async {
    await _readPrefs();
    _droppedMissing = 0;
    final raw = await store.read(indexName);
    if (raw == null) {
      notifyListeners();
      return _afterLoad();
    }
    final (folders, tracks) = _readIndex(raw);
    if (tracks == null) {
      // Unlesbar: Datei aufheben statt beim nächsten Speichern zu überschreiben.
      final stamp = _now().toIso8601String().replaceAll(':', '-');
      try {
        await store.rename(indexName, '$indexName.defekt-$stamp');
      } catch (_) {}
      lastError =
          'Die Bibliothek war beschädigt und wurde als «library.json.defekt-$stamp» aufgehoben.';
      notifyListeners();
      return _afterLoad();
    }
    _folders = folders;
    _tracks = [
      for (final t in tracks)
        if (await store.exists(trackName(t.fileName))) t,
    ];
    _droppedMissing = tracks.length - _tracks.length;
    notifyListeners();
    _hashing = _backfillHashes();
    return _afterLoad();
  }

  Future<void> _afterLoad() async {
    if (_tracks.isNotEmpty) await _askPersistence();
    await refreshStorage();
  }

  /// Dauerhaften Speicher einmal anfragen, sobald es etwas zu behalten gibt (nur im Browser wirksam).
  Future<void> _askPersistence() async {
    if (_persistAsked) return;
    _persistAsked = true;
    try {
      await store.requestPersistence();
    } catch (_) {}
  }

  /// Misst den belegten Speicher neu (nach Laden, Import und Löschen).
  Future<void> refreshStorage() async {
    try {
      _storage = await store.storageInfo();
      notifyListeners();
    } catch (_) {}
  }

  /// Rechnet fehlende `contentHash` nach, Titel für Titel, ohne die Oberfläche zu blockieren
  /// (Dateisystem: eigenes Isolate). Gespeichert wird einmal am Ende.
  Future<void> _backfillHashes() async {
    final missing = [
      for (final t in _tracks)
        if (t.contentHash == null) t.id,
    ];
    var changed = false;
    for (final id in missing) {
      final t = track(id);
      if (t == null) continue; // inzwischen gelöscht
      String? hash;
      try {
        hash = await store.sha256(trackName(t.fileName));
      } catch (_) {}
      final i = _tracks.indexWhere((x) => x.id == id);
      if (hash == null || i < 0) continue;
      _tracks[i] = _tracks[i].copyWith(contentHash: hash);
      changed = true;
    }
    if (changed) {
      save();
      notifyListeners();
    }
  }

  /// Liest `{folders, tracks}` oder das alte Format `[Track]`. tracks == null: unlesbar.
  static (List<TrackFolder>, List<Track>?) _readIndex(Uint8List raw) {
    try {
      final json = jsonDecode(utf8.decode(raw));
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

  /// Schreibt `library.json` (atomar). Im Dateisystem ist die Datei geschrieben, wenn der Aufruf
  /// zurückkehrt; im Browser in Aufrufreihenfolge kurz danach.
  Future<void> save() {
    _pendingSave?.cancel();
    _pendingSave = null;
    final bytes = Uint8List.fromList(utf8.encode(swiftPrettyJson(indexJson())));
    return store.write(indexName, bytes).catchError((Object e) {
      lastError = 'Bibliothek konnte nicht gespeichert werden: $e';
      notifyListeners();
    });
  }

  /// Inhalt von library.json.
  Map<String, Object?> indexJson() => {
    'folders': _folders.map((f) => f.toJson()).toList(),
    'tracks': _tracks.map((t) => t.toJson()).toList(),
  };

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

  Future<void> _readPrefs() async {
    try {
      final raw = await store.read(_prefsName);
      if (raw == null) return;
      final p = jsonDecode(utf8.decode(raw)) as Map;
      _sortOrder = TrackSortOrder.parse(p['sortOrder'] as String?);
    } catch (_) {
      // unlesbare Einstellungen: Standardwerte
    }
  }

  void _savePrefs() {
    final bytes = Uint8List.fromList(
      utf8.encode(jsonEncode({'sortOrder': _sortOrder.name})),
    );
    store.write(_prefsName, bytes).catchError((_) {});
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

  /// Titel mit diesem Inhalt (SHA-256), falls schon in der Bibliothek.
  Track? trackWithHash(String hash) =>
      _tracks.where((t) => t.contentHash == hash).firstOrNull;

  /// Ort der Datei für den Audio-Kern: gerätelokaler Pfad auf Desktop und Handy, Name im Browser.
  String filePath(Track t) => store.locate(trackName(t.fileName));

  /// Gerätelokaler Pfad der Datei (Desktop und Handy); null im Browser.
  String? localPath(Track t) => store.localPath(trackName(t.fileName));

  /// Cover als gerätelokaler Pfad; im Browser (noch) keins.
  String? artworkPath(Track t) =>
      t.hasArtwork ? store.localPath(_artworkName(t.id)) : null;

  int get _nextOrder => _tracks.fold(-1, (m, t) => max(m, t.customOrder)) + 1;

  // ---- Import und Löschen ----

  /// Übernimmt die Dateien in die Bibliothek und liest Titel, Künstler, Album, Cover und Dauer. Dateien,
  /// deren Inhalt schon da ist, landen in [ImportResult.duplicates] und werden nicht noch einmal gespeichert.
  Future<ImportResult> importFiles(
    List<String> paths, {
    String? folderId,
  }) async {
    _importing = true;
    notifyListeners();
    if (_hashing case final h?) await h; // alte Titel brauchen ihren Hash, sonst wird ein Doppel nicht erkannt
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
      lastError =
          'Folgende Dateien konnten nicht importiert werden:\n${failed.join('\n')}';
    }
    save();
    notifyListeners();
    if (imported.isNotEmpty) await _askPersistence();
    await refreshStorage();
    return ImportResult(imported, failed, duplicates);
  }

  /// (Titel, schon vorhanden) oder null bei Fehler.
  Future<(Track, bool)?> _importFile(String source, String? folderId) async {
    final id = newUuid(_random);
    final name = _baseName(source);
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 ? name.substring(dot + 1).toLowerCase() : 'mp3';
    final fileName = '$id.$ext';
    final dest = trackName(fileName);
    var written = false;
    try {
      final bytes = await readSource(source);
      if (bytes == null) return null;
      // Grosse Dateien in einem eigenen Isolate (im Browser läuft compute im selben Thread).
      final hash = bytes.length > _hashInline
          ? await compute(_sha256Hex, bytes)
          : _sha256Hex(bytes);
      final existing = trackWithHash(hash);
      if (existing != null) return (existing, true);
      await store.write(dest, bytes);
      written = true;
      final duration = probe(store.locate(dest));
      if (duration != null && duration <= 0) {
        throw const FormatException('kein lesbares Audio');
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
        contentHash: hash,
      );
      return (track, false);
    } catch (_) {
      if (written) await store.delete(dest).catchError((_) {});
      return null;
    }
  }

  static String _baseName(String path) => path.split(RegExp(r'[/\\]')).last;

  void delete(Set<String> ids) {
    for (final t in _tracks.where((t) => ids.contains(t.id))) {
      store.delete(trackName(t.fileName)).catchError((_) {});
      store.delete(_artworkName(t.id)).catchError((_) {});
    }
    _tracks.removeWhere((t) => ids.contains(t.id));
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
