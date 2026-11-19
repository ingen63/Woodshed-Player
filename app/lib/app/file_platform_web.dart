// Vorläufige Dateiauswahl im Browser (#34, bis #35 mit OPFS): `<input type=file>` liest die Dateien in den
// Speicher. Sie gelten nur für diese Sitzung, nichts wird gespeichert. Jede Datei bekommt einen Pfad
// «web:<n>/<Dateiname>», über den Bibliothek und Audio-Kern sie finden.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:wp_core/wp_types.dart';

import 'file_platform.dart';

class WebFilePlatform implements FilePlatform {
  final _files = <String, Uint8List>{};
  int _count = 0;

  /// Bytes zu einem Pfad dieser Sitzung; null, wenn unbekannt.
  Uint8List? bytesOf(String path) => _files[path];

  /// Dauer für die Bibliothek: 0 (erst der Kern kennt sie), Fehlercode für unbekannte Pfade.
  double probe(String path) =>
      _files.containsKey(path) ? 0 : WpCode.fileNotFound.toDouble();

  /// Legt Bytes für die Sitzung ab und gibt ihren Pfad zurück.
  String register(String name, Uint8List bytes) {
    final path = 'web:${++_count}/$name';
    _files[path] = bytes;
    return path;
  }

  @override
  Future<List<String>> pickAudioFiles() async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..multiple = true
      ..accept = 'audio/*,.mp3,.wav,.flac,.m4a,.aac'
      ..style.display = 'none';
    final picked = Completer<List<web.File>>();
    input.onchange = ((web.Event _) {
      final list = input.files;
      picked.complete([
        for (var i = 0; i < (list?.length ?? 0); i++) list!.item(i)!,
      ]);
    }).toJS;
    input.addEventListener(
      'cancel',
      ((web.Event _) {
        if (!picked.isCompleted) picked.complete(const []);
      }).toJS,
    );
    web.document.body?.append(input);
    input.click();
    try {
      final files = await picked.future;
      return [
        for (final f in files)
          register(f.name, (await f.arrayBuffer().toDart).toDart.asUint8List()),
      ];
    } finally {
      input.remove();
    }
  }

  @override
  Future<String?> supportDir() async => null;

  @override
  Future<String?> recordingsDir() async => null;

  @override
  void keepAwake(bool on) {} // im Browser erst mit W7 (#39)

  @override
  set onDropFiles(void Function(List<String> paths)? handler) {}
}
