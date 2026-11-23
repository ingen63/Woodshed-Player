// Dateiauswahl, Ordner und Drag & Drop vom nativen Teil (Kanal «woodshed/files»), austauschbar für Tests.
// Plus the storage layer (#35): [FileStore] holds the library and audio files, in the file system on desktop
// and mobile (file_store_io.dart), in the browser's Origin Private File System (file_store_web.dart).
import 'package:flutter/services.dart';

/// #121: files dragged from outside the app (Finder, file explorer) over the window.
sealed class FileDragEvent {
  const FileDragEvent();
}

/// The files are over the window at [position] (logical pixels of the view).
final class FileDragOver extends FileDragEvent {
  const FileDragOver(this.position);
  final Offset position;
}

/// The drag left the window or was cancelled.
final class FileDragLeave extends FileDragEvent {
  const FileDragLeave();
}

/// The files were dropped at [position]; null if the platform did not say where.
final class FileDragDrop extends FileDragEvent {
  const FileDragDrop(this.paths, [this.position]);
  final List<String> paths;
  final Offset? position;
}

/// Position `{x, y}` in a message of the native part; null if missing or not numbers.
Offset? _position(Object? args) {
  if (args is! Map) return null;
  final (x, y) = (args['x'], args['y']);
  return x is num && y is num ? Offset(x.toDouble(), y.toDouble()) : null;
}

/// The event for a message of the native part, null for anything else: «dragFiles» `{x, y}`,
/// «dragExit», «dropFiles» with the paths (#22) or `{paths, x, y}` (#121).
FileDragEvent? fileDragEvent(MethodCall call) => switch (call.method) {
  'dragFiles' => switch (_position(call.arguments)) {
    final Offset p => FileDragOver(p),
    null => null,
  },
  'dragExit' => const FileDragLeave(),
  'dropFiles' => switch (call.arguments) {
    final List<Object?> paths => FileDragDrop(
      paths.whereType<String>().toList(),
    ),
    {'paths': final List<Object?> paths} => FileDragDrop(
      paths.whereType<String>().toList(),
      _position(call.arguments),
    ),
    _ => null,
  },
  _ => null,
};

/// Storage used by the library, shown in the library footer.
class StorageInfo {
  const StorageInfo({required this.used, this.quota, this.persisted});

  /// Bytes used (desktop: the library folder; web: everything the page stores).
  final int used;

  /// Quota in bytes the browser grants the page; null on desktop and mobile.
  final int? quota;

  /// Persistent storage granted (the browser won't evict it on its own); null on desktop and mobile.
  final bool? persisted;
}

/// Library storage. Names are relative and separated by «/» («library.json», «Tracks/‹id›.mp3»).
/// A write replaces the whole file; writes and deletes run in call order.
abstract class FileStore {
  /// Contents, or null if the file is missing.
  Future<Uint8List?> read(String name);

  /// Creates or replaces the file (missing folders are created).
  Future<void> write(String name, Uint8List bytes);

  Future<bool> exists(String name);

  /// Deletes the file if it exists.
  Future<void> delete(String name);

  Future<void> rename(String from, String to);

  /// SHA-256 of the contents (64 hex digits), or null if the file is missing.
  Future<String?> sha256(String name);

  /// Location for the audio core: the device-local path on desktop and mobile, the name in the browser.
  String locate(String name);

  /// Device-local path (desktop and mobile); null in the browser, which has no paths.
  String? localPath(String name);

  /// Used (and, in the browser, available) storage.
  Future<StorageInfo> storageInfo();

  /// Size of the file in bytes, or null if it is missing (#39/AK3: size of the audio cache).
  Future<int?> size(String name) async => (await read(name))?.length;

  /// Requests persistent storage (browser only, `navigator.storage.persist()`); null elsewhere.
  Future<bool?> requestPersistence() async => null;
}

/// Git tag and build date of this build (#50/AK6), stamped in at build time.
class BuildInfo {
  const BuildInfo({this.tag, this.date});

  /// Latest Git tag; null if the build had none.
  final String? tag;

  /// Build date (UTC day); null if unknown.
  final DateTime? date;

  /// From the strings the build wrote (empty means unknown); the date as YYYY-MM-DD.
  factory BuildInfo.parse(String? tag, String? date) => BuildInfo(
    tag: (tag ?? '').trim().isEmpty ? null : tag!.trim(),
    date: DateTime.tryParse((date ?? '').trim()),
  );
}

abstract class FilePlatform {
  /// Audiodateien wählen (mehrere). Leer bei Abbruch.
  Future<List<String>> pickAudioFiles();

  /// *Application Support* der App.
  Future<String?> supportDir();

  /// Ablage für Aufnahmen (nur macOS).
  Future<String?> recordingsDir();

  /// #113/AK4: whether the app may use the microphone. Asks the user the first time (system dialog);
  /// false if access was refused before or there is no microphone recording here.
  Future<bool> microphoneAccess();

  /// Bildschirm wach halten (iPhone/iPad, solange das Metronom läuft).
  void keepAwake(bool on);

  /// Files are dragged over the window or dropped on it (macOS, web; #22, #121).
  set onFileDrag(void Function(FileDragEvent event)? handler);

  /// Git tag and build date of this build (#50/AK6).
  Future<BuildInfo> buildInfo();

  /// Opens [url] in the system browser (#50/AK6); the app itself loads nothing from the network.
  Future<void> openUrl(String url);

  /// The macOS app menu item «About …» was chosen (#50/AK6).
  set onShowAbout(void Function()? handler);

  /// Title of the macOS app menu item «About …» in the UI language (#50/AK6); no-op elsewhere.
  void setAboutMenuTitle(String title);
}

class ChannelFilePlatform implements FilePlatform {
  ChannelFilePlatform() {
    _channel.setMethodCallHandler((call) async {
      if (fileDragEvent(call) case final e?) {
        _onDrag?.call(e);
      } else if (call.method == 'showAbout') {
        _onShowAbout?.call();
      }
    });
  }

  static const _channel = MethodChannel('woodshed/files');
  void Function(FileDragEvent)? _onDrag;
  void Function()? _onShowAbout;

  @override
  set onFileDrag(void Function(FileDragEvent event)? handler) =>
      _onDrag = handler;

  @override
  Future<List<String>> pickAudioFiles() async =>
      (await _channel.invokeMethod<List<Object?>>('pickAudioFiles'))
          ?.cast<String>() ??
      const [];

  @override
  Future<String?> supportDir() => _channel.invokeMethod<String>('supportDir');

  @override
  Future<String?> recordingsDir() =>
      _channel.invokeMethod<String>('recordingsDir');

  @override
  Future<bool> microphoneAccess() async {
    try {
      return await _channel.invokeMethod<bool>('microphoneAccess') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  void keepAwake(bool on) =>
      _channel.invokeMethod('keepAwake', on).catchError((_) => null);

  @override
  Future<void> openUrl(String url) =>
      _channel.invokeMethod<void>('openUrl', url).catchError((_) {});

  @override
  set onShowAbout(void Function()? handler) => _onShowAbout = handler;

  @override
  void setAboutMenuTitle(String title) => _channel
      .invokeMethod<void>('setAboutMenuTitle', title)
      .catchError((_) {});

  @override
  Future<BuildInfo> buildInfo() async {
    try {
      final m = await _channel.invokeMapMethod<String, Object?>('buildInfo');
      return BuildInfo.parse(m?['tag'] as String?, m?['date'] as String?);
    } catch (_) {
      return const BuildInfo();
    }
  }
}
