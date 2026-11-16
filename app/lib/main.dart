// Woodshed Player (Flutter): Wiedergabe mit Tempo und Loop über den C++-Kern, Metronom (#3),
// Aufnahme des Systemtons (macOS, #4). Erscheinungsbild wie die alte App (#19).
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
import 'ui/player_view.dart';
import 'ui/style.dart';

void main() => runApp(const WoodshedApp());

class WoodshedApp extends StatelessWidget {
  const WoodshedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Woodshed Player',
      theme: woodshedTheme(Brightness.light),
      darkTheme: woodshedTheme(Brightness.dark),
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
  double _volume = 1.0;
  bool _speedOn = false;
  double _rate = 1.0;
  double _loopStart = 0;
  double _loopEnd = 0;
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
      _player.rate = _speedOn ? _rate : 1.0;
      _player.volume = _volume;
      setState(() {
        _title = title;
        _duration = _player.duration;
        _error = null;
        _loopStart = 0;
        _loopEnd = _duration;
        _loopOn = false;
      });
      _session.playTitle();
    } on WpException catch (e) {
      setState(() => _error = e.message);
    }
  }

  void _setRate(double r) {
    final rounded = ((r * 20).round() / 20).clamp(0.1, 2.0); // 0,05er-Schritte
    setState(() => _rate = rounded);
    _player.rate = _speedOn ? rounded : 1.0;
  }

  void _setSpeedOn(bool on) {
    setState(() => _speedOn = on);
    _player.rate = on ? _rate : 1.0;
  }

  void _setVolume(double v) {
    setState(() => _volume = v);
    _player.volume = v;
  }

  void _setLoop({bool? on, double? start, double? end}) {
    setState(() {
      _loopOn = on ?? _loopOn;
      _loopStart = (start ?? _loopStart).clamp(0, _duration);
      _loopEnd = (end ?? _loopEnd).clamp(0, _duration);
    });
    if (_loopOn && _loopEnd >= _loopStart + 1) {
      _player.setLoop(_loopStart, _loopEnd);
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
    return PracticeShortcuts(
      metronome: _metronome,
      onPlayPause: () {
        if (_duration > 0) _session.toggleTitle();
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Text(_title ?? 'Woodshed Player'),
            bottom: const TabBar(
              tabs: [
                Tab(icon: Icon(WsIcons.musicNote), text: 'Player'),
                Tab(icon: Icon(WsIcons.metronome), text: 'Metronom'),
              ],
            ),
            actions: [
              ExcludeFocus(
                child: IconButton(
                  onPressed: _open,
                  icon: const Icon(WsIcons.folder),
                  tooltip: 'Datei öffnen',
                ),
              ),
            ],
          ),
          body: TabBarView(
            children: [
              PlayerView(
                state: PlayerViewState(
                  title: _title,
                  position: _position,
                  duration: _duration,
                  playing: _playing,
                  volume: _volume,
                  speedOn: _speedOn,
                  speed: _rate,
                  loopOn: _loopOn,
                  loopStart: _loopStart,
                  loopEnd: _loopEnd,
                  error: _error,
                ),
                actions: PlayerViewActions(
                  open: _open,
                  playPause: _session.toggleTitle,
                  seek: _player.seek,
                  volume: _setVolume,
                  speedOn: _setSpeedOn,
                  speed: _setRate,
                  loopOn: (v) => _setLoop(on: v),
                  loopStart: (v) => _setLoop(start: v),
                  loopEnd: (v) => _setLoop(end: v),
                ),
                extraCards: [if (WpRecorder.available) _recordingCard()],
              ),
              // Keine Textfelder: Knöpfe und Regler nehmen keinen Tastaturfokus.
              ExcludeFocus(
                child: AccentBackground(
                  child: CardColumn(
                    children: [MetronomePanel(controller: _metronome)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _recordingCard() {
    final theme = Theme.of(context);
    return ExcludeFocus(
      child: WsCard(
        key: const Key('card:recording'),
        children: [
          CardHeader(
            icon: WsIcons.record,
            title: 'Aufnahme',
            trailing: FilledButton.icon(
              onPressed: _toggleRecording,
              style: FilledButton.styleFrom(
                backgroundColor: _recording ? Colors.red : null,
              ),
              icon: Icon(_recording ? WsIcons.stop : WsIcons.record, size: 14),
              label: Text(_recording ? 'Stopp' : 'Aufnahme starten'),
            ),
          ),
          if (_recording)
            Row(
              children: [
                Text(
                  formatTime(_recSeconds),
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: LinearProgressIndicator(value: _recLevel.clamp(0, 1)),
                ),
              ],
            ),
          if (_recSilent)
            Text(
              'Es kommt nur Stille an. Läuft gerade Musik? Sonst die Berechtigung erteilen: '
              'Systemeinstellungen › Datenschutz & Sicherheit › Bildschirm- & Systemaudioaufnahme.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          const HintText(
            'Nimmt den Systemton auf (ohne Mikrofon). Die Aufnahme wird nur lokal gespeichert '
            'und danach im Player geöffnet.',
          ),
        ],
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
