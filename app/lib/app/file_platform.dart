// Dateiauswahl, Ordner und Drag & Drop vom nativen Teil (Kanal «woodshed/files»), austauschbar für Tests.
// Plus the storage layer (#35): [FileStore] holds the library and audio files, in the file system on desktop
// and mobile (file_store_io.dart), in the browser's Origin Private File System (file_store_web.dart).
import 'package:flutter/services.dart';

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

  /// Requests persistent storage (browser only, `navigator.storage.persist()`); null elsewhere.
  Future<bool?> requestPersistence() async => null;
}

abstract class FilePlatform {
  /// Audiodateien wählen (mehrere). Leer bei Abbruch.
  Future<List<String>> pickAudioFiles();

  /// *Application Support* der App.
  Future<String?> supportDir();

  /// Ablage für Aufnahmen (nur macOS).
  Future<String?> recordingsDir();

  /// Bildschirm wach halten (iPhone/iPad, solange das Metronom läuft).
  void keepAwake(bool on);

  /// Dateien wurden ins Fenster gezogen (macOS).
  set onDropFiles(void Function(List<String> paths)? handler);

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
      if (call.method == 'dropFiles' && call.arguments is List) {
        _onDrop?.call((call.arguments as List).cast<String>());
      } else if (call.method == 'showAbout') {
        _onShowAbout?.call();
      }
    });
  }

  static const _channel = MethodChannel('woodshed/files');
  void Function(List<String>)? _onDrop;
  void Function()? _onShowAbout;

  @override
  set onDropFiles(void Function(List<String> paths)? handler) =>
      _onDrop = handler;

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
}
