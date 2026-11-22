// File picker in the browser (#34, #35): `<input type=file>` reads the files into memory. Each file gets a
// key «web:<n>/<file name>»; the library fetches it once with that key ([take]) and stores it
// persistently in the OPFS (file_store_web.dart).
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_platform.dart';

class WebFilePlatform implements FilePlatform {
  final _files = <String, Uint8List>{};
  int _count = 0;

  /// Takes the picked bytes for [key] (for the import); afterwards they are dropped here.
  Future<Uint8List?> take(String key) async => _files.remove(key);

  /// Holds bytes for pickup and returns their key (file picker, check pages).
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

  /// #113/AK6: no microphone recording in the browser.
  @override
  Future<bool> microphoneAccess() async => false;

  @override
  void keepAwake(bool on) {} // im Browser erst mit W7 (#39)

  @override
  set onDropFiles(void Function(List<String> paths)? handler) {}

  @override
  Future<void> openUrl(String url) async {
    web.window.open(url, '_blank', 'noopener');
  }

  @override
  set onShowAbout(void Function()? handler) {}

  @override
  void setAboutMenuTitle(String title) {}

  /// In the browser from `--dart-define=WP_GIT_TAG=… --dart-define=WP_BUILD_DATE=YYYY-MM-DD` (#50/AK6).
  @override
  Future<BuildInfo> buildInfo() async => BuildInfo.parse(
    const String.fromEnvironment('WP_GIT_TAG'),
    const String.fromEnvironment('WP_BUILD_DATE'),
  );
}
