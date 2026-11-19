// Dateiauswahl im Browser (#34, #35): `<input type=file>` liest die Dateien in den Speicher. Jede Datei
// bekommt einen Schlüssel «web:<n>/<Dateiname>»; die Bibliothek holt sie damit einmal ab ([take]) und
// legt sie dauerhaft im OPFS ab (file_store_web.dart).
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_platform.dart';

class WebFilePlatform implements FilePlatform {
  final _files = <String, Uint8List>{};
  int _count = 0;

  /// Gewählte Bytes zum Schlüssel abholen (für den Import); danach sind sie hier vergessen.
  Future<Uint8List?> take(String key) async => _files.remove(key);

  /// Legt Bytes zum Abholen ab und gibt ihren Schlüssel zurück (Dateiauswahl, Prüfseiten).
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
