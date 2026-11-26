// File picker in the browser (#34, #35): `<input type=file>` reads the files into memory. Each file gets a
// key «web:<n>/<file name>»; the library fetches it once with that key ([take]) and stores it
// persistently in the OPFS (file_store_web.dart).
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:web/web.dart' as web;

import 'file_platform.dart';

class WebFilePlatform implements FilePlatform {
  final _files = <String, Uint8List>{};
  int _count = 0;

  /// #157: opens the microphone for a recording (WebRecorder.acquire); null where the browser cannot
  /// record.
  Future<bool> Function()? microphone;

  /// #157: the bytes of a finished recording (WebRecorder.take), for paths under [recordingsDir].
  Future<Uint8List?> Function(String path)? recording;

  /// #157: the folder name of recordings; their paths are names of the recorder, not files.
  static const recordings = 'recordings';

  /// Takes the picked bytes for [key] (for the import); afterwards they are dropped here. #157: a
  /// recording comes from the recorder.
  Future<Uint8List?> take(String key) async {
    final rec = recording;
    if (rec != null && key.startsWith('$recordings/')) return rec(key);
    return _files.remove(key);
  }

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

  /// #157: recordings exist only where the browser can record.
  @override
  Future<String?> recordingsDir() async =>
      microphone == null ? null : recordings;

  /// #141: no export in the browser.
  @override
  Future<String?> pickFolder(String prompt) async => null;

  /// #157: opens the microphone (the browser asks the first time); false if refused or the browser
  /// cannot record.
  @override
  Future<bool> microphoneAccess() async => await microphone?.call() ?? false;

  /// #140: no command line in the browser.
  @override
  Future<String?> commandSocket() async => null;

  @override
  void keepAwake(bool on) {} // im Browser erst mit W7 (#39)

  /// #121: files dragged from the file explorer over the page, reported with their position.
  @override
  set onFileDrag(void Function(FileDragEvent event)? handler) {
    _onDrag = handler;
    if (handler != null && _listeners == null) _listen();
  }

  void Function(FileDragEvent)? _onDrag;
  List<(String, JSFunction)>? _listeners;

  /// Nested elements report enter and leave in pairs; at zero the drag has left the page.
  int _depth = 0;

  static bool _hasFiles(web.DragEvent e) =>
      e.dataTransfer?.types.toDart.any((t) => t.toDart == 'Files') ?? false;

  static Offset _at(web.DragEvent e) =>
      Offset(e.clientX.toDouble(), e.clientY.toDouble());

  void _listen() {
    void on(String type, void Function(web.DragEvent e) f) {
      final js = ((web.DragEvent e) {
        if (_hasFiles(e)) f(e);
      }).toJS;
      web.window.addEventListener(type, js);
      _listeners!.add((type, js));
    }

    _listeners = [];
    on('dragenter', (e) {
      e.preventDefault();
      _depth++;
    });
    on('dragover', (e) {
      // without this the browser opens the file instead of handing it to the page
      e.preventDefault();
      e.dataTransfer?.dropEffect = 'copy';
      _onDrag?.call(FileDragOver(_at(e)));
    });
    on('dragleave', (e) {
      if (--_depth > 0) return;
      _depth = 0;
      _onDrag?.call(const FileDragLeave());
    });
    on('drop', (e) async {
      e.preventDefault();
      _depth = 0;
      final at = _at(e);
      final list = e.dataTransfer?.files;
      final files = [
        for (var i = 0; i < (list?.length ?? 0); i++) list!.item(i)!,
      ];
      final paths = [
        for (final f in files)
          register(f.name, (await f.arrayBuffer().toDart).toDart.asUint8List()),
      ];
      _onDrag?.call(FileDragDrop(paths, at));
    });
  }

  /// Removes the page listeners (tests).
  void dispose() {
    for (final (type, js) in _listeners ?? const <(String, JSFunction)>[]) {
      web.window.removeEventListener(type, js);
    }
    _listeners = null;
    _onDrag = null;
  }

  @override
  Future<void> openUrl(String url) async {
    web.window.open(url, '_blank', 'noopener');
  }

  @override
  bool get hasMenuBar => false;

  @override
  void localizeMenuBar(Map<String, String> titles) {}

  /// In the browser from `--dart-define=WP_GIT_TAG=… --dart-define=WP_BUILD_DATE=YYYY-MM-DD` (#50/AK6).
  @override
  Future<BuildInfo> buildInfo() async => BuildInfo.parse(
    const String.fromEnvironment('WP_GIT_TAG'),
    const String.fromEnvironment('WP_BUILD_DATE'),
  );
}
