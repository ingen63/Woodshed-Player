// FileStore in the file system (#35): desktop and mobile. As in the Swift app, the library lives in the
// app folder (`library.json`, `Tracks/`). Paths stay device-local extra information.
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'file_platform.dart';

class IoFileStore extends FileStore {
  IoFileStore(this.base);

  /// Library folder.
  final Directory base;

  File _file(String name) => File('${base.path}/$name');

  // The methods work synchronously inside the async body: writes and deletes are done when the call
  // returns, which keeps them in order.

  @override
  Future<Uint8List?> read(String name) async {
    final f = _file(name);
    return f.existsSync() ? f.readAsBytesSync() : null;
  }

  @override
  Future<void> write(String name, Uint8List bytes) async {
    final f = _file(name);
    f.parent.createSync(recursive: true);
    final tmp = File('${f.path}.tmp');
    tmp.writeAsBytesSync(bytes, flush: true);
    tmp.renameSync(f.path);
  }

  @override
  Future<bool> exists(String name) async => _file(name).existsSync();

  @override
  Future<void> delete(String name) async {
    final f = _file(name);
    if (f.existsSync()) f.deleteSync();
  }

  @override
  Future<void> rename(String from, String to) async {
    _file(from).renameSync(_file(to).path);
  }

  /// Hashes in a separate isolate and reads the file in chunks (large files block nothing).
  @override
  Future<String?> sha256(String name) {
    final path = _file(name).path;
    return Isolate.run(() async {
      final f = File(path);
      if (!f.existsSync()) return null;
      return (await crypto.sha256.bind(f.openRead()).first).toString();
    });
  }

  @override
  String locate(String name) => _file(name).path;

  @override
  String? localPath(String name) => _file(name).path;

  @override
  Future<StorageInfo> storageInfo() async {
    var used = 0;
    if (base.existsSync()) {
      for (final e in base.listSync(recursive: true, followLinks: false)) {
        if (e is File) used += e.lengthSync();
      }
    }
    return StorageInfo(used: used);
  }
}

/// Reads a picked or dropped file (import source); null if it is missing.
Future<Uint8List?> readLocalFile(String path) async {
  final f = File(path);
  return f.existsSync() ? f.readAsBytes() : null;
}
