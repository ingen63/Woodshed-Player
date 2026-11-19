// FileStore im Dateisystem (#35): Desktop und Handy. Die Bibliothek liegt wie bei der Swift-App im
// App-Ordner (`library.json`, `Tracks/`). Die Pfade bleiben gerätelokale Zusatzinfo.
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'file_platform.dart';

class IoFileStore extends FileStore {
  IoFileStore(this.base);

  /// Ordner der Bibliothek.
  final Directory base;

  File _file(String name) => File('${base.path}/$name');

  // Die Methoden arbeiten synchron im async-Rumpf: Schreiben und Löschen sind erledigt, wenn der Aufruf
  // zurückkehrt, damit bleibt die Reihenfolge erhalten.

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

  /// Rechnet in einem eigenen Isolate und liest die Datei in Stücken (grosse Dateien blockieren nichts).
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

/// Liest eine gewählte oder hereingezogene Datei (Quelle des Imports); null, wenn sie fehlt.
Future<Uint8List?> readLocalFile(String path) async {
  final f = File(path);
  return f.existsSync() ? f.readAsBytes() : null;
}
