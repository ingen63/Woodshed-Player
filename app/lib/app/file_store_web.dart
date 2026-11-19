// FileStore im Browser (#35): Origin Private File System (OPFS, `navigator.storage.getDirectory()`).
// Die Bibliothek bleibt über Neuladen und Neustart des Browsers erhalten. `createWritable()` schreibt in
// eine Zwischendatei und ersetzt erst beim Schliessen, deshalb ist jedes Schreiben atomar.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:web/web.dart' as web;

import 'file_platform.dart';

class OpfsFileStore extends FileStore {
  OpfsFileStore._(this._root);

  /// Ordner [dir] im OPFS der Seite (wird angelegt), z. B. «WoodshedPlayer».
  static Future<OpfsFileStore> open(String dir) async {
    final origin = await web.window.navigator.storage.getDirectory().toDart;
    return OpfsFileStore._(await _subdir(origin, dir, create: true));
  }

  /// Löscht den Ordner [dir] samt Inhalt (für Prüfseiten, die mit leerer Bibliothek beginnen).
  static Future<void> clear(String dir) async {
    final origin = await web.window.navigator.storage.getDirectory().toDart;
    try {
      await origin
          .removeEntry(dir, web.FileSystemRemoveOptions(recursive: true))
          .toDart;
    } catch (_) {} // gibt es noch nicht
  }

  final web.FileSystemDirectoryHandle _root;

  /// Schreiben, Umbenennen und Löschen nacheinander, in Aufrufreihenfolge.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _queue.then((_) => op());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<web.FileSystemDirectoryHandle> _subdir(
    web.FileSystemDirectoryHandle dir,
    String name, {
    required bool create,
  }) => dir
      .getDirectoryHandle(
        name,
        web.FileSystemGetDirectoryOptions(create: create),
      )
      .toDart;

  /// Ordner und Dateiname zu «a/b/c.mp3»; null, wenn ein Ordner fehlt und [create] falsch ist.
  Future<(web.FileSystemDirectoryHandle, String)?> _parent(
    String name, {
    bool create = false,
  }) async {
    final parts = name.split('/');
    var dir = _root;
    try {
      for (final p in parts.sublist(0, parts.length - 1)) {
        dir = await _subdir(dir, p, create: create);
      }
    } catch (_) {
      return null;
    }
    return (dir, parts.last);
  }

  Future<web.FileSystemFileHandle?> _handle(String name) async {
    final parent = await _parent(name);
    if (parent == null) return null;
    try {
      return await parent.$1
          .getFileHandle(parent.$2, web.FileSystemGetFileOptions(create: false))
          .toDart;
    } catch (_) {
      return null; // NotFoundError
    }
  }

  Future<Uint8List?> _read(String name) async {
    final h = await _handle(name);
    if (h == null) return null;
    final file = await h.getFile().toDart;
    return (await file.arrayBuffer().toDart).toDart.asUint8List();
  }

  Future<void> _write(String name, Uint8List bytes) async {
    final (dir, file) = (await _parent(name, create: true))!;
    final h = await dir
        .getFileHandle(file, web.FileSystemGetFileOptions(create: true))
        .toDart;
    final w = await h.createWritable().toDart;
    await w.write(bytes.toJS).toDart;
    await w.close().toDart;
  }

  Future<void> _delete(String name) async {
    final parent = await _parent(name);
    if (parent == null) return;
    try {
      await parent.$1.removeEntry(parent.$2).toDart;
    } catch (_) {} // fehlt schon
  }

  // Lesen wartet auf ausstehendes Schreiben, damit es den neuesten Stand sieht.
  @override
  Future<Uint8List?> read(String name) => _serial(() => _read(name));

  @override
  Future<void> write(String name, Uint8List bytes) =>
      _serial(() => _write(name, bytes));

  @override
  Future<bool> exists(String name) =>
      _serial(() async => await _handle(name) != null);

  @override
  Future<void> delete(String name) => _serial(() => _delete(name));

  /// OPFS kennt kein allgemeines Umbenennen: kopieren und das Original löschen.
  @override
  Future<void> rename(String from, String to) => _serial(() async {
    final bytes = await _read(from);
    if (bytes == null) throw StateError('$from fehlt');
    await _write(to, bytes);
    await _delete(from);
  });

  @override
  Future<String?> sha256(String name) async {
    final bytes = await read(name);
    return bytes == null ? null : crypto.sha256.convert(bytes).toString();
  }

  @override
  String locate(String name) => name;

  @override
  String? localPath(String name) => null;

  @override
  Future<StorageInfo> storageInfo() async {
    final storage = web.window.navigator.storage;
    final estimate = await storage.estimate().toDart;
    final persisted = (await storage.persisted().toDart).toDart;
    return StorageInfo(
      used: estimate.usage,
      quota: estimate.quota,
      persisted: persisted,
    );
  }

  @override
  Future<bool?> requestPersistence() async {
    final storage = web.window.navigator.storage;
    try {
      if ((await storage.persisted().toDart).toDart) return true;
      return (await storage.persist().toDart).toDart;
    } catch (_) {
      return false;
    }
  }
}
