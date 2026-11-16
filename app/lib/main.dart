// Prototyp GEN-5 / FEA-4: Wiedergabe mit Tempo und Loop über den C++-Kern, Aufnahme des Systemtons (macOS).
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wp_core/wp_core.dart';

import 'metronome/metronome_controller.dart';
import 'metronome/metronome_panel.dart';
import 'metronome/practice_session.dart';
import 'metronome/practice_shortcuts.dart';
import 'time_format.dart';

void main() => runApp(const WoodshedApp());

class WoodshedApp extends StatelessWidget {
  const WoodshedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Woodshed Player',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.brown),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.brown,
          brightness: Brightness.dark,
        ),
      ),
      home: const PlayerPage(),
    );
  }
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  static const _files = MethodChannel('woodshed/files');
  static const _quickRates = [0.25, 0.5, 0.7, 0.8, 0.9, 1.0];

  final WpPlayer _player = WpPlayer();
  late final MetronomeController _metronome = MetronomeController(
    _PlayerMetronome(_player),
    onRunningChanged: (on) =>
        _files.invokeMethod('keepAwake', on).catchError((_) => null),
    store: _SupportDirStore(_files),
  );
  late final PracticeSession _session = PracticeSession(
    _PlayerTitle(_player),
    _metronome,
  );
  Timer? _ticker;
  String? _title;
  String? _error;
  double _position = 0;
  double _duration = 0;
  bool _playing = false;
  double _rate = 1.0;
  double? _loopA;
  double? _loopB;
  bool _loopOn = false;

  // Aufnahme
  bool _recording = false;
  double _recSeconds = 0;
  double _recLevel = 0;
  bool _recSilent = false;
  String? _recPath;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) => _tick());
    _metronome.restore();
    // Datei per Drag & Drop ins Fenster (macOS).
    _files.setMethodCallHandler((call) async {
      if (call.method == 'openFile' && call.arguments is String) {
        final path = call.arguments as String;
        _load(path, path.split(Platform.pathSeparator).last);
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (WpRecorder.isRecording) WpRecorder.stop();
    _metronome.dispose();
    _player.dispose();
    super.dispose();
  }

  void _tick() {
    setState(() {
      _position = _player.position;
      _playing = _player.isPlaying;
      if (_metronome.running) {
        _metronome.sync(); // Tempo der automatischen Steigerung
      }
      if (_recording) {
        _recSeconds = WpRecorder.seconds;
        _recLevel = WpRecorder.level;
        _recSilent = _recSeconds > 3 && WpRecorder.onlySilence;
      }
    });
  }

  Future<void> _open() async {
    try {
      final path = await _files.invokeMethod<String>('pickAudio');
      if (path != null) _load(path, path.split(Platform.pathSeparator).last);
    } on PlatformException catch (e) {
      setState(() => _error = 'Datei-Dialog: ${e.message}');
    }
  }

  void _load(String path, String title) {
    try {
      _player.load(path);
      _player.rate = _rate;
      setState(() {
        _title = title;
        _duration = _player.duration;
        _error = null;
        _loopA = _loopB = null;
        _loopOn = false;
      });
      _session.playTitle();
    } on WpException catch (e) {
      setState(() => _error = e.message);
    }
  }

  void _setRate(double r) {
    final rounded = (r * 20).round() / 20; // 0,05er-Schritte
    _player.rate = rounded;
    setState(() => _rate = rounded);
  }

  void _applyLoop() {
    final a = _loopA, b = _loopB;
    if (_loopOn && a != null && b != null && b >= a + 1) {
      _player.setLoop(a, b);
    } else {
      _player.clearLoop();
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      WpRecorder.stop();
      setState(() => _recording = false);
      final path = _recPath;
      if (path != null && File(path).existsSync()) {
        _load(path, _recordingTitle(DateTime.now()));
      }
      return;
    }
    final dir = await _files.invokeMethod<String>('recordingsDir');
    if (dir == null) return;
    final now = DateTime.now();
    final path = '$dir/Aufnahme ${fileStamp(now)}.wav';
    try {
      WpRecorder.start(path);
      setState(() {
        _recording = true;
        _recPath = path;
        _recSeconds = 0;
        _recSilent = false;
        _error = null;
      });
    } on WpException catch (e) {
      setState(() => _error = 'Aufnahme nicht möglich: ${e.message}');
    }
  }

  String _recordingTitle(DateTime t) => 'Aufnahme ${fileStamp(t)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = _duration > 0;
    return PracticeShortcuts(
      metronome: _metronome,
      onPlayPause: () {
        if (_duration > 0) _session.toggleTitle();
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Woodshed Player · Prototyp'),
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(Icons.music_note), text: 'Player'),
                Tab(icon: Icon(Icons.av_timer), text: 'Metronom'),
              ],
            ),
            actions: [
              IconButton(
                onPressed: _open,
                icon: const Icon(Icons.folder_open),
                tooltip: 'Datei öffnen',
              ),
            ],
          ),
          // Knöpfe und Regler nehmen keinen Tastaturfokus, damit Leertaste und Pfeile immer die Kürzel auslösen.
          body: ExcludeFocus(
            child: TabBarView(
              children: [
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _title ?? 'Keine Datei geladen',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        FilledButton.icon(
                          onPressed: _open,
                          icon: const Icon(Icons.audio_file),
                          label: Text(loaded ? 'Andere Datei' : 'MP3 öffnen'),
                        ),
                      ],
                    ),
                    if (!loaded)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          Platform.isMacOS
                              ? 'MP3, WAV oder FLAC wählen oder einfach ins Fenster ziehen.'
                              : 'MP3, WAV oder FLAC aus «Dateien» wählen.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Slider(
                      value: _position.clamp(0, loaded ? _duration : 1),
                      max: loaded ? _duration : 1,
                      onChanged: loaded ? (v) => _player.seek(v) : null,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(formatTime(_position)),
                        Text(formatTime(_duration)),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          onPressed: loaded
                              ? () => _player.seek(
                                  (_position - 15).clamp(0, _duration),
                                )
                              : null,
                          icon: const Icon(Icons.replay_10),
                          tooltip: '15 s zurück',
                        ),
                        IconButton.filled(
                          iconSize: 40,
                          onPressed: loaded ? _session.toggleTitle : null,
                          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                        ),
                        IconButton(
                          onPressed: loaded
                              ? () => _player.seek(
                                  (_position + 15).clamp(0, _duration),
                                )
                              : null,
                          icon: const Icon(Icons.forward_10),
                          tooltip: '15 s vor',
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    Text(
                      'Tempo ${_rate.toStringAsFixed(2)}×',
                      style: theme.textTheme.titleMedium,
                    ),
                    Slider(
                      value: _rate,
                      min: 0.1,
                      max: 2.0,
                      divisions: 38,
                      onChanged: _setRate,
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final r in _quickRates)
                          ChoiceChip(
                            label: Text('$r×'),
                            selected: _rate == r,
                            onSelected: (_) => _setRate(r),
                          ),
                      ],
                    ),
                    const Divider(height: 32),
                    Row(
                      children: [
                        Text('Loop', style: theme.textTheme.titleMedium),
                        const Spacer(),
                        Switch(
                          value: _loopOn,
                          onChanged: loaded
                              ? (v) {
                                  setState(() => _loopOn = v);
                                  _applyLoop();
                                }
                              : null,
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: loaded
                              ? () {
                                  setState(() => _loopA = _position);
                                  _applyLoop();
                                }
                              : null,
                          child: Text(
                            'A ${_loopA == null ? '–' : formatTime(_loopA!)}',
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: loaded
                              ? () {
                                  setState(() => _loopB = _position);
                                  _applyLoop();
                                }
                              : null,
                          child: Text(
                            'B ${_loopB == null ? '–' : formatTime(_loopB!)}',
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (_loopA != null &&
                            _loopB != null &&
                            _loopB! < _loopA! + 1)
                          const Expanded(
                            child: Text('B muss mindestens 1 s nach A liegen'),
                          ),
                      ],
                    ),
                    if (WpRecorder.available) ...[
                      const Divider(height: 32),
                      Text(
                        'Aufnahme (Systemton, ohne Mikrofon)',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: _toggleRecording,
                            icon: Icon(
                              _recording
                                  ? Icons.stop
                                  : Icons.fiber_manual_record,
                            ),
                            label: Text(
                              _recording ? 'Stopp' : 'Aufnahme starten',
                            ),
                          ),
                          const SizedBox(width: 16),
                          if (_recording) Text(formatTime(_recSeconds)),
                        ],
                      ),
                      if (_recording) ...[
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: _recLevel.clamp(0, 1)),
                      ],
                      if (_recSilent)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'Es kommt nur Stille an. Läuft gerade Musik? Sonst die Berechtigung erteilen: '
                            'Systemeinstellungen › Datenschutz & Sicherheit › Bildschirm- & Systemaudioaufnahme.',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                        ),
                    ],
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [MetronomePanel(controller: _metronome)],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Titel-Wiedergabe für die PracticeSession.
class _PlayerTitle implements TitleTransport {
  _PlayerTitle(this._p);
  final WpPlayer _p;

  @override
  bool get isPlaying => _p.isPlaying;
  @override
  void play() => _p.play();
  @override
  void pause() => _p.pause();
}

/// Verbindet den MetronomeController mit dem Audio-Kern.
class _PlayerMetronome implements MetronomeBackend {
  _PlayerMetronome(this._p);
  final WpPlayer _p;

  @override
  void start() => _p.metronomeStart();
  @override
  void stop() => _p.metronomeStop();
  @override
  bool get running => _p.metronomeRunning;
  @override
  int get bpm => _p.metronomeBpm;
  @override
  set bpm(int v) => _p.metronomeBpm = v;
  @override
  set meter(int v) => _p.metronomeMeter = v;
  @override
  set subdivision(int v) => _p.metronomeSubdivision = v;
  @override
  set volume(double v) => _p.metronomeVolume = v;
  @override
  void ramp({
    required bool enabled,
    required int start,
    required int target,
    required int step,
    required int everyBars,
  }) => _p.metronomeRamp(
    enabled: enabled,
    start: start,
    target: target,
    step: step,
    everyBars: everyBars,
  );
}

/// Einstellungen als `metronome.json` im App-Ordner (Pfad vom nativen Teil).
class _SupportDirStore implements SettingsStore {
  _SupportDirStore(this._channel);
  final MethodChannel _channel;
  FileSettingsStore? _file;

  Future<FileSettingsStore?> _store() async {
    if (_file != null) return _file;
    final dir = await _channel.invokeMethod<String>('supportDir');
    if (dir == null) return null;
    return _file = FileSettingsStore(File('$dir/metronome.json'));
  }

  @override
  Future<Object?> load() async => (await _store())?.load();

  @override
  Future<void> save(Object json) async => (await _store())?.save(json);
}
