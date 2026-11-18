// Player-Service (#15): Zustand der Wiedergabe für die Oberfläche. Spricht den Audio-Kern nur über
// [AudioCore] an und lässt sich deshalb in Tests ohne Audiogerät prüfen.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:wp_core/wp_core.dart';

import '../library/playback_settings.dart';
import '../metronome/loop_ramp.dart';
import '../metronome/practice_session.dart';
import 'audio_core.dart';

/// Erzeugt einen periodischen Timer; Tests geben eine Attrappe mit, die sie selbst auslösen.
typedef PeriodicTimerFactory = Timer Function(
  Duration interval,
  void Function(Timer timer) onTick,
);

/// Wiedergabe-Zustand eines Titels. Benachrichtigt bei jeder Änderung.
class PlayerService extends ChangeNotifier implements TitleTransport {
  PlayerService(
    this.core, {
    PeriodicTimerFactory? timerFactory,
    this.tickInterval = defaultTick,
  }) : _timerFactory = timerFactory ?? Timer.periodic;

  /// #15/AK2: etwa 30 Aktualisierungen pro Sekunde.
  static const defaultTick = Duration(milliseconds: 33);

  /// Kürzester Loop in Sekunden, wie im Kern.
  static const minLoopSeconds = 1.0;

  final AudioCore core;
  final Duration tickInterval;
  final PeriodicTimerFactory _timerFactory;

  /// Wird bei jeder Änderung der Einstellungen des geladenen Titels gerufen (zum Speichern in der Bibliothek).
  void Function(String trackId, PlaybackSettings settings)? onSettingsChanged;

  // ---- Zustand ----
  String? _title, _path, _trackId;
  double _position = 0, _duration = 0, _volume = 1.0, _loadProgress = 0;
  bool _playing = false, _loading = false;
  PlaybackSettings _settings = const PlaybackSettings();
  String? _error;

  String? get title => _title;
  String? get path => _path;
  String? get trackId => _trackId;
  double get position => _position;
  double get duration => _duration;
  double get volume => _volume;
  @override
  bool get isPlaying => _playing;
  bool get isLoading => _loading;
  double get loadProgress => _loadProgress;
  bool get hasTrack => _path != null;
  PlaybackSettings get settings => _settings;
  String? get error => _error;

  /// Wellenform des geladenen Titels (#28, #30); null ohne Titel oder solange sie fehlt.
  WpWaveform? waveform(double start, double end, int count) =>
      hasTrack && _duration > 0 ? core.waveform(start, end, count) : null;

  /// Aktiver Loop (start, ende) oder null, wenn aus bzw. Grenzen ungültig.
  (double, double)? get activeLoop =>
      _settings.loopEnabled &&
          _settings.loopEnd - _settings.loopStart >= minLoopSeconds
      ? (_settings.loopStart, _settings.loopEnd)
      : null;

  // ---- Steigerung nach Loop-Durchgängen (#29) ----
  final _ramp = LoopRamp();
  int _lastLoopPasses = 0;

  /// Läuft die Steigerung? Nur mit eingeschalteter Geschwindigkeit und aktivem Loop.
  bool get rampActive =>
      _settings.rampEnabled && _settings.speedEnabled && activeLoop != null;

  /// Durchgänge auf der aktuellen Stufe.
  int get rampPasses => _ramp.passes;

  /// #29/AK8: «75 % · 7 von 10».
  String get rampLabel => _ramp.label(_settings);

  void _countLoopPasses() {
    final total = core.loopPasses;
    final added = total - _lastLoopPasses;
    _lastLoopPasses = total;
    if (added <= 0 || !rampActive) return;
    final next = _ramp.addPasses(added, _settings);
    if (next != null) _commit(_settings.copyWith(speed: next));
  }

  // ---- Positionsabfrage ----
  Timer? _timer;
  int _playGrace = 0; // Ticks, in denen «spielt» gilt, bis der Audio-Thread den Befehl übernommen hat
  _PendingLoad? _pending;

  /// #15/AK2: Timer läuft nur, solange gespielt oder geladen wird (plus ein Tick danach).
  bool get isPolling => _timer != null;

  void _ensurePolling() {
    _timer ??= _timerFactory(tickInterval, (_) => tick());
  }

  /// Ein Takt der Positionsabfrage. Öffentlich für Tests.
  @visibleForTesting
  void tick() {
    if (_pending != null) _pollLoad();
    if (hasTrack) {
      final corePlaying = core.isPlaying;
      if (corePlaying || _playGrace <= 0) _playing = corePlaying;
      if (_playGrace > 0) _playGrace--;
      _position = core.position.clamp(0, _duration).toDouble();
      _countLoopPasses();
    }
    if (!_playing && _pending == null) {
      _timer?.cancel();
      _timer = null;
    }
    notifyListeners();
  }

  // ---- Laden ----

  /// Lädt eine Datei im Hintergrund. Ergebnis `true`, sobald sie bereit ist; bei Fehlern `false` mit
  /// [error], der bisherige Titel bleibt dann geladen und spielt weiter.
  Future<bool> load(
    String path, {
    String? title,
    String? trackId,
    PlaybackSettings settings = const PlaybackSettings(),
  }) {
    _pending?.completer.complete(false); // überholt
    _pending = null;
    final file = title ?? _fileName(path);
    final code = core.loadAsync(path);
    if (code != WpCode.ok) {
      _loading = false;
      _error = loadErrorMessage(code, file: file);
      notifyListeners();
      return Future.value(false);
    }
    final pending = _PendingLoad(path, file, trackId, settings);
    _pending = pending;
    _loading = true;
    _loadProgress = 0;
    _ensurePolling();
    notifyListeners();
    return pending.completer.future;
  }

  void _pollLoad() {
    final p = _pending!;
    final state = core.loadState;
    _loadProgress = core.loadProgress;
    if (state == WpCode.loadRunning) return;
    _pending = null;
    _loading = false;
    if (state == WpCode.loadReady) {
      _path = p.path;
      _title = p.title;
      _trackId = p.trackId;
      _duration = core.duration;
      _position = 0;
      _playing = false;
      _playGrace = 0;
      _error = null;
      _settings = _normalized(p.settings, _duration);
      _lastLoopPasses = core.loopPasses;
      _ramp.reset();
      _applySettings();
      core.volume = _volume;
      p.completer.complete(true);
    } else {
      _error = loadErrorMessage(
        state < 0 ? state : WpCode.invalidArgument,
        file: p.title,
      );
      p.completer.complete(false);
    }
  }

  static String _fileName(String path) {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? path : parts.last;
  }

  /// Titel entladen (z. B. gelöscht). Der Kern behält die Daten, spielt aber nicht mehr.
  void unload() {
    if (_playing) core.pause();
    _path = _title = _trackId = null;
    _playing = false;
    _position = _duration = 0;
    _settings = const PlaybackSettings();
    notifyListeners();
  }

  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  // ---- Wiedergabe ----

  @override
  void play() {
    if (!hasTrack || _playing) return;
    core.play();
    _playing = true;
    _playGrace = 3;
    _ensurePolling();
    notifyListeners();
  }

  @override
  void pause() {
    if (!hasTrack) return;
    core.pause();
    _playing = false;
    _playGrace = 0;
    _ensurePolling(); // ein Tick holt die endgültige Position
    notifyListeners();
  }

  void togglePlayPause() => _playing ? pause() : play();

  /// Leertaste: wie Play/Pause, Stoppen in einem aktiven Loop springt aber zum Loop-Anfang zurück.
  void togglePlayPauseReturningToLoop() {
    if (!_playing) return play();
    pause();
    final loop = activeLoop;
    if (loop != null) seek(loop.$1);
  }

  void seek(double seconds) {
    if (!hasTrack) return;
    final t = seconds.clamp(0, _duration).toDouble();
    core.seek(t);
    _position = t;
    _ensurePolling();
    notifyListeners();
  }

  void skip(double delta) => seek(_position + delta);

  void setVolume(double v) {
    _volume = v.clamp(0, 1).toDouble();
    core.volume = _volume;
    notifyListeners();
  }

  // ---- Einstellungen (Tempo, Loop) ----

  /// Ändert die Einstellungen und hält Loop-Grenzen gültig (wie `updateSettings` der Swift-App).
  void updateSettings(PlaybackSettings Function(PlaybackSettings s) change) {
    var next = change(_settings);
    next = next.copyWith(
      speed: next.speed
          .clamp(PlaybackSettings.minSpeed, PlaybackSettings.maxSpeed)
          .toDouble(),
      loopStart: next.loopStart.clamp(0, _duration).toDouble(),
      loopEnd: next.loopEnd.clamp(0, _duration).toDouble(),
    );
    final old = _settings;
    if (next.loopEnd - next.loopStart < minLoopSeconds &&
        _duration >= minLoopSeconds) {
      if (next.loopStart != old.loopStart) {
        // Anfang hinter das Ende gesetzt: bis zum Titelende, bis ein neues Ende gesetzt wird.
        next = next.copyWith(
          loopStart: next.loopStart
              .clamp(0, _duration - minLoopSeconds)
              .toDouble(),
          loopEnd: _duration,
        );
      } else if (next.loopEnd != old.loopEnd) {
        final end = (next.loopStart + minLoopSeconds)
            .clamp(0, _duration)
            .toDouble();
        next = next.copyWith(
          loopEnd: end,
          loopStart: next.loopStart.clamp(0, end - minLoopSeconds).toDouble(),
        );
      } else if (next.loopEnabled && !old.loopEnabled) {
        next = next.copyWith(
          loopStart: 0,
          loopEnd: _duration,
        ); // Loop ohne Grenzen: ganzer Titel
      }
    }
    if (next.rampEnabled && !old.rampEnabled) {
      // #29: Einschalten beginnt bei der Startstufe.
      next = next.copyWith(speedEnabled: true, speed: next.rampStart / 100);
    }
    if (next == old) return;
    // #29/AK5: Loop-Grenzen oder Geschwindigkeit von Hand geändert: Zähler auf 0, die Steigerung läuft
    // ab der neuen Geschwindigkeit weiter.
    if (next.loopEnabled != old.loopEnabled ||
        next.loopStart != old.loopStart ||
        next.loopEnd != old.loopEnd ||
        next.speedEnabled != old.speedEnabled ||
        next.speed != old.speed ||
        next.rampEnabled != old.rampEnabled) {
      _ramp.reset();
    }
    _commit(next);
  }

  void _commit(PlaybackSettings next) {
    _settings = next;
    _applySettings();
    final id = _trackId;
    if (id != null) onSettingsChanged?.call(id, next);
    notifyListeners();
  }

  /// Einstellungen der Steigerung nach Loop-Durchgängen (#29). Das Ziel liegt nie unter dem Start.
  void setRamp({
    bool? enabled,
    int? start,
    int? target,
    int? step,
    int? passes,
  }) => updateSettings((s) {
    var n = s.copyWith(
      rampEnabled: enabled,
      rampStart: start,
      rampTarget: target,
      rampStep: step,
      rampPasses: passes,
    );
    if (start != null && n.rampTarget < n.rampStart) {
      n = n.copyWith(rampTarget: n.rampStart);
    }
    if (target != null && n.rampStart > n.rampTarget) {
      n = n.copyWith(rampStart: n.rampTarget);
    }
    return n;
  });

  void setSpeedEnabled(bool on) =>
      updateSettings((s) => s.copyWith(speedEnabled: on));

  /// Tempo in 0,05er-Schritten.
  void setSpeed(double speed) =>
      updateSettings((s) => s.copyWith(speed: _roundSpeed(speed)));

  /// ± ganze Schritte (Pfeiltasten), schaltet das Tempo ein.
  void adjustSpeed(int steps) => updateSettings(
    (s) => s.copyWith(
      speedEnabled: true,
      speed: _roundSpeed(s.speed + steps * PlaybackSettings.speedStep),
    ),
  );

  void setLoopEnabled(bool on) =>
      updateSettings((s) => s.copyWith(loopEnabled: on));

  /// Setzt den Loop-Anfang (Taste S, Marker, Feld) und schaltet den Loop ein.
  void setLoopStart(double t) =>
      updateSettings((s) => s.copyWith(loopEnabled: true, loopStart: t));

  /// Setzt das Loop-Ende (Taste E, Marker, Feld) und schaltet den Loop ein.
  void setLoopEnd(double t) =>
      updateSettings((s) => s.copyWith(loopEnabled: true, loopEnd: t));

  static double _roundSpeed(double v) =>
      ((v / PlaybackSettings.speedStep).round() * PlaybackSettings.speedStep)
          .clamp(PlaybackSettings.minSpeed, PlaybackSettings.maxSpeed)
          .toDouble();

  /// Gespeicherte Einstellungen an die Dauer anpassen; «Ende nicht gesetzt» wird zum Titelende.
  static PlaybackSettings _normalized(PlaybackSettings s, double duration) {
    final end = s.loopEnd <= 0
        ? duration
        : s.loopEnd.clamp(0, duration).toDouble();
    return s.copyWith(
      speed: s.speed
          .clamp(PlaybackSettings.minSpeed, PlaybackSettings.maxSpeed)
          .toDouble(),
      loopStart: s.loopStart.clamp(0, duration).toDouble(),
      loopEnd: end,
    );
  }

  void _applySettings() {
    core.rate = _settings.effectiveRate;
    final loop = activeLoop;
    if (loop != null) {
      core.setLoop(loop.$1, loop.$2);
    } else {
      core.clearLoop();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _pending?.completer.complete(false);
    _pending = null;
    super.dispose();
  }
}

class _PendingLoad {
  _PendingLoad(this.path, this.title, this.trackId, this.settings);
  final String path, title;
  final String? trackId;
  final PlaybackSettings settings;
  final completer = Completer<bool>();
}
