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
import 'player/audio_core.dart';
import 'player/player_service.dart';
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
  late final PlayerService _service = PlayerService(WpAudioCore(_player));
  late final MetronomeController _metronome = MetronomeController(
    _PlayerMetronome(_player),
    onRunningChanged: (on) =>
        _files.invokeMethod('keepAwake', on).catchError((_) => null),
    store: _SupportDirStore(_files),
  );
  late final PracticeSession _session = PracticeSession(_service, _metronome);
  Timer? _ticker; // nur für Metronom-Steigerung und Aufnahme
  String? _error; // Fehler ausserhalb der Wiedergabe (Datei-Dialog, Aufnahme)

  // Aufnahme
  bool _recording = false;
  double _recSeconds = 0;
  double _recLevel = 0;
  bool _recSilent = false;
  String? _recPath;

  @override
  void initState() {
    super.initState();
    _service.addListener(_changed);
    _metronome.addListener(_updateTicker);
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
    _metronome.removeListener(_updateTicker);
    _metronome.dispose();
    _service.dispose();
    _player.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  /// Der Ticker läuft nur, solange das Metronom läuft oder aufgenommen wird.
  void _updateTicker() {
    final needed = _metronome.running || _recording;
    if (needed && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(milliseconds: 33),
        (_) => _tick(),
      );
    } else if (!needed) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _tick() {
    setState(() {
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

  Future<void> _load(String path, String title) async {
    setState(() => _error = null);
    if (await _service.load(path, title: title)) _session.playTitle();
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      WpRecorder.stop();
      setState(() => _recording = false);
      _updateTicker();
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
      _updateTicker();
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
        if (_service.hasTrack) _session.toggleTitle();
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: Text(_service.title ?? 'Woodshed Player'),
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
                  title: _service.hasTrack ? _service.title : null,
                  position: _service.position,
                  duration: _service.duration,
                  playing: _service.isPlaying,
                  volume: _service.volume,
                  speedOn: _service.settings.speedEnabled,
                  speed: _service.settings.speed,
                  loopOn: _service.settings.loopEnabled,
                  loopStart: _service.settings.loopStart,
                  loopEnd: _service.settings.loopEnd,
                  error: _error ?? _service.error,
                ),
                actions: PlayerViewActions(
                  open: _open,
                  playPause: _session.toggleTitle,
                  seek: _service.seek,
                  volume: _service.setVolume,
                  speedOn: _service.setSpeedEnabled,
                  speed: _service.setSpeed,
                  loopOn: _service.setLoopEnabled,
                  loopStart: _service.setLoopStart,
                  loopEnd: _service.setLoopEnd,
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
