// Dateiauswahl, Ordner und Drag & Drop vom nativen Teil (Kanal «woodshed/files»), austauschbar für Tests.
// Dazu die Speicher-Schicht (#35): [FileStore] legt Bibliothek und Audiodateien ab, auf Desktop und Handy
// im Dateisystem (file_store_io.dart), im Browser im Origin Private File System (file_store_web.dart).
import 'package:flutter/services.dart';

/// Speicherplatz der Bibliothek für die Anzeige im Fuss der Bibliothek.
class StorageInfo {
  const StorageInfo({required this.used, this.quota, this.persisted});

  /// Belegte Bytes (Desktop: Ordner der Bibliothek; Web: alles, was die Seite speichert).
  final int used;

  /// Obergrenze in Bytes, die der Browser der Seite zugesteht; null auf Desktop und Handy.
  final int? quota;

  /// Dauerhafter Speicher gewährt (Browser löscht nicht von sich aus); null auf Desktop und Handy.
  final bool? persisted;

  /// Kleine Zeile, z. B. «1,2 GB belegt» oder «1,2 GB belegt · 58 GB frei · dauerhaft gespeichert».
  String get label {
    final parts = ['${formatBytes(used)} belegt'];
    if (quota case final q?) parts.add('${formatBytes(max0(q - used))} frei');
    if (persisted case final p?) {
      parts.add(p ? 'dauerhaft gespeichert' : 'nicht dauerhaft gespeichert');
    }
    return parts.join(' · ');
  }

  static int max0(int v) => v < 0 ? 0 : v;
}

/// Bytes deutsch mit Komma und einer Nachkommastelle ab KB: «512 B», «1,2 GB».
String formatBytes(int bytes) {
  const units = ['KB', 'MB', 'GB', 'TB'];
  if (bytes < 1000) return '$bytes B';
  var v = bytes / 1000;
  var i = 0;
  while (v >= 999.95 && i < units.length - 1) {
    v /= 1000;
    i++;
  }
  return '${v.toStringAsFixed(1).replaceAll('.', ',')} ${units[i]}';
}

/// Ablage der Bibliothek. Namen sind relativ und mit «/» getrennt («library.json», «Tracks/‹id›.mp3»).
/// Schreiben ersetzt eine Datei als Ganzes; Schreib- und Löschvorgänge laufen in Aufrufreihenfolge.
abstract class FileStore {
  /// Inhalt oder null, wenn die Datei fehlt.
  Future<Uint8List?> read(String name);

  /// Legt die Datei an oder ersetzt sie (fehlende Ordner werden angelegt).
  Future<void> write(String name, Uint8List bytes);

  Future<bool> exists(String name);

  /// Löscht die Datei, falls es sie gibt.
  Future<void> delete(String name);

  Future<void> rename(String from, String to);

  /// SHA-256 des Inhalts (64 Hex-Zeichen) oder null, wenn die Datei fehlt.
  Future<String?> sha256(String name);

  /// Ort der Datei für den Audio-Kern: auf Desktop und Handy der gerätelokale Pfad, im Browser der Name.
  String locate(String name);

  /// Gerätelokaler Pfad (Desktop und Handy); null im Browser, wo es keine Pfade gibt.
  String? localPath(String name);

  /// Belegter (und im Browser verfügbarer) Speicher.
  Future<StorageInfo> storageInfo();

  /// Dauerhaften Speicher anfragen (nur im Browser, `navigator.storage.persist()`); sonst null.
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
}

class ChannelFilePlatform implements FilePlatform {
  ChannelFilePlatform() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'dropFiles' && call.arguments is List) {
        _onDrop?.call((call.arguments as List).cast<String>());
      }
    });
  }

  static const _channel = MethodChannel('woodshed/files');
  void Function(List<String>)? _onDrop;

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
}
