import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'metronome_settings.dart';
import 'tap_tempo.dart';

/// Was das Metronom vom Audio-Kern braucht. In Tests durch eine Attrappe ersetzt.
abstract class MetronomeBackend {
  void start();
  void stop();
  bool get running;
  int get bpm;
  set bpm(int value);
  set meter(int value);
  set subdivision(int value);
  set volume(double value);
  void ramp({
    required bool enabled,
    required int start,
    required int target,
    required int step,
    required int everyBars,
  });
}

/// Speichert die Einstellungen.
abstract class SettingsStore {
  Future<Object?> load();
  Future<void> save(Object json);
}

/// JSON-Datei im App-Ordner.
class FileSettingsStore implements SettingsStore {
  FileSettingsStore(this.file);
  final File file;

  @override
  Future<Object?> load() async {
    try {
      return jsonDecode(await file.readAsString());
    } catch (_) {
      return null; // fehlt oder ist beschädigt: Standardwerte
    }
  }

  @override
  Future<void> save(Object json) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(json));
  }
}

/// Zustand und Bedienung des Metronoms. Der Audio-Kern ist die Quelle für das laufende Tempo
/// (die automatische Steigerung ändert es); [sync] holt es ab.
class MetronomeController extends ChangeNotifier {
  MetronomeController(
    this._backend, {
    this._store,
    TapTempo? tapTempo,
    this.onRunningChanged,
  }) : _tap = tapTempo ?? TapTempo();

  final MetronomeBackend _backend;
  final SettingsStore? _store;
  final TapTempo _tap;

  /// Z. B. Bildschirm wach halten, solange das Metronom läuft (iPhone/iPad).
  final void Function(bool running)? onRunningChanged;

  MetronomeSettings _settings = const MetronomeSettings();
  MetronomeSettings get settings => _settings;
  bool get running => _backend.running;

  /// Gespeicherte Einstellungen laden und an den Kern geben. Das Metronom bleibt gestoppt.
  Future<void> restore() async {
    _settings = MetronomeSettings.fromJson(await _store?.load());
    _applyAll();
    notifyListeners();
  }

  void _applyAll() {
    final s = _settings;
    _backend
      ..meter = s.meter
      ..subdivision = s.subdivision
      ..volume = s.volume;
    _backend.ramp(
      enabled: s.rampEnabled,
      start: s.rampStart,
      target: s.rampTarget,
      step: s.rampStep,
      everyBars: s.rampEveryBars,
    );
    _backend.bpm = s.rampEnabled ? s.rampStart : s.bpm;
    _settings = s.copyWith(bpm: _backend.bpm);
  }

  void _update(MetronomeSettings next) {
    if (next == _settings) return;
    _settings = next;
    notifyListeners();
    _store?.save(next.toJson());
  }

  /// Übernimmt das Tempo aus dem Kern (automatische Steigerung). Aufruf regelmässig aus der Oberfläche.
  void sync() {
    final bpm = _backend.bpm;
    if (bpm != _settings.bpm) _update(_settings.copyWith(bpm: bpm));
  }

  void toggle() => running ? stop() : start();

  /// Wird vor jedem Start aufgerufen (z. B. Titel pausieren, siehe PracticeSession).
  void Function()? beforeStart;

  void start() {
    beforeStart?.call();
    _backend.start();
    if (_settings.rampEnabled) {
      _settings = _settings.copyWith(bpm: _settings.rampStart);
    }
    notifyListeners();
    onRunningChanged?.call(true);
  }

  void stop() {
    _backend.stop();
    notifyListeners();
    onRunningChanged?.call(false);
  }

  void setBpm(int bpm) {
    final v = MetronomeSettings.clampBpm(bpm);
    _backend.bpm = v;
    _update(_settings.copyWith(bpm: v));
  }

  void changeBpm(int delta) => setBpm(_backend.bpm + delta);

  void tap() {
    final bpm = _tap.tap();
    if (bpm != null) setBpm(bpm);
  }

  void setMeter(int meter) {
    _backend.meter = meter;
    _update(_settings.copyWith(meter: meter));
  }

  void setSubdivision(int clicks) {
    _backend.subdivision = clicks;
    _update(_settings.copyWith(subdivision: clicks));
  }

  void setVolume(double volume) {
    _backend.volume = volume;
    _update(_settings.copyWith(volume: volume));
  }

  void setRamp({
    bool? enabled,
    int? start,
    int? target,
    int? step,
    int? everyBars,
  }) {
    final next = _settings.copyWith(
      rampEnabled: enabled,
      rampStart: start,
      rampTarget: target,
      rampStep: step,
      rampEveryBars: everyBars,
    );
    _backend.ramp(
      enabled: next.rampEnabled,
      start: next.rampStart,
      target: next.rampTarget,
      step: next.rampStep,
      everyBars: next.rampEveryBars,
    );
    // Einschalten im Stand setzt der Kern auf Start-BPM; das hier übernehmen.
    _update(next.copyWith(bpm: _backend.bpm));
  }
}
