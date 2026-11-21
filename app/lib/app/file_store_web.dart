// FileStore in the browser (#35): Origin Private File System (OPFS, `navigator.storage.getDirectory()`).
// The library survives reloads and browser restarts. `createWritable()` writes to a swap file and only
// replaces on close, so every write is atomic.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:web/web.dart' as web;

import 'file_platform.dart';

class OpfsFileStore extends FileStore {
  OpfsFileStore._(this._root);

  /// Folder [dir] in the page's OPFS (created if needed), e.g. «WoodshedPlayer».
  static Future<OpfsFileStore> open(String dir) async {
    final origin = await web.window.navigator.storage.getDirectory().toDart;
    return OpfsFileStore._(await _subdir(origin, dir, create: true));
  }

  /// Deletes folder [dir] with its contents (for check pages that start with an empty library).
  static Future<void> clear(String dir) async {
    final origin = await web.window.navigator.storage.getDirectory().toDart;
    try {
      await origin
          .removeEntry(dir, web.FileSystemRemoveOptions(recursive: true))
          .toDart;
    } catch (_) {} // does not exist yet
  }

  final web.FileSystemDirectoryHandle _root;

  /// Writes, renames and deletes one after another, in call order.
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

  /// Folder and file name for «a/b/c.mp3»; null if a folder is missing and [create] is false.
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
    } catch (_) {} // already gone
  }

  // Reads wait for pending writes so they see the latest state.
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

  /// OPFS has no general rename: copy, then delete the original.
  @override
  Future<void> rename(String from, String to) => _serial(() async {
    final bytes = await _read(from);
    if (bytes == null) throw StateError('$from is missing');
    await _write(to, bytes);
    await _delete(from);
  });

  @override
  Future<String?> sha256(String name) async {
    final bytes = await read(name);
    return bytes == null ? null : crypto.sha256.convert(bytes).toString();
  }

  /// Size without reading the contents (#39/AK3).
  @override
  Future<int?> size(String name) => _serial(() async {
    final h = await _handle(name);
    if (h == null) return null;
    return (await h.getFile().toDart).size;
  });

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
