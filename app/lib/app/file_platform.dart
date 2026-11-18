// Dateiauswahl, Ordner und Drag & Drop vom nativen Teil (Kanal «woodshed/files»), austauschbar für Tests.
import 'dart:io';

import 'package:flutter/services.dart';

abstract class FilePlatform {
  /// Audiodateien wählen (mehrere). Leer bei Abbruch.
  Future<List<String>> pickAudioFiles();

  /// Ordner der Swift-App wählen (nur macOS). null bei Abbruch.
  Future<String?> pickLegacyLibrary();

  /// Ob es die Übernahme der Swift-Bibliothek auf dieser Plattform gibt.
  bool get canImportLegacyLibrary;

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
  Future<String?> pickLegacyLibrary() =>
      _channel.invokeMethod<String>('pickLegacyLibrary');

  @override
  bool get canImportLegacyLibrary => Platform.isMacOS;

  @override
  Future<String?> supportDir() => _channel.invokeMethod<String>('supportDir');

  @override
  Future<String?> recordingsDir() =>
      _channel.invokeMethod<String>('recordingsDir');

  @override
  void keepAwake(bool on) =>
      _channel.invokeMethod('keepAwake', on).catchError((_) => null);
}
