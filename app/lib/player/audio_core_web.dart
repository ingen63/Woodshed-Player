// AudioCore im Browser (#34): der WASM-Kern (core/web, #33) läuft im AudioWorklet «wp-core». Steuerung geht
// als Nachricht ans Worklet, Zustand (Position, Pegel, Loop-Durchgänge, Metronom) kommt etwa alle 10 ms als
// Nachricht zurück. Die Getter der Schnittstelle sind synchron und lesen deshalb den zuletzt gemeldeten
// Zustand. Die Wellenform holt die Anbindung einmal nach dem Laden (siehe WaveformSummary).
// Loading (#42): a Worker with a second instance of the core (wp_loader.js) decodes MP3, WAV and FLAC and
// computes the waveform; AAC/M4A the browser decodes (decodeAudioData) and the Worker converts it. Only the
// finished PCM goes to the worklet, which takes it over between render blocks, so playback and metronome
// go on while a file loads.
// Die Dateien liefert app/tool/build_web_core.sh nach web/wp_core/.
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;
import 'package:wp_core/wp_types.dart';

import '../metronome/metronome_controller.dart';
import 'audio_core.dart';
import 'waveform_summary.dart';

@JS('WebAssembly.compile')
external JSPromise<JSObject> _wasmCompile(JSArrayBuffer bytes);

/// Bytes of a library file (name in the OPFS, #35); null if it is missing.
typedef WebFileBytes = Future<Uint8List?> Function(String path);

class WebAudioCore implements AudioCore {
  WebAudioCore._(this._ctx, this._node, this._loader, this._bytesOf) {
    _node.port.onmessage = ((web.MessageEvent e) => _onMessage(e.data)).toJS;
    _loader.onmessage = ((web.MessageEvent e) => _onLoaderMessage(e.data)).toJS;
  }

  /// #97/AK6: [ctx] if it runs at a rate the core accepts, otherwise (an output faster than
  /// WpSampleRate.max, e.g. 384 kHz) [ctx] is closed and a new context at WpSampleRate.max is
  /// returned; the browser converts to the output's rate.
  static Future<web.AudioContext> supportedContext(web.AudioContext ctx) async {
    final own = ctx.sampleRate.round();
    final rate = WpSampleRate.output(own);
    if (rate == own) return ctx;
    await ctx.close().toDart;
    return web.AudioContext(web.AudioContextOptions(sampleRate: rate));
  }

  /// Ordner mit wp_core_web.wasm, wp_core_web.mjs und wp_worklet.js, relativ zur Seite.
  static const assetDir = 'wp_core/';

  /// Zustand etwa alle 10 ms (Position flüssig, Klicks des Metronoms messbar).
  static const stateEvery = 0.01;

  /// Lädt den Kern und hängt das Worklet an die Lautsprecher. Der AudioContext startet erst mit der
  /// ersten Bedienung (Play, Laden, Metronom), wie es die Browser verlangen.
  static Future<WebAudioCore> create({
    required WebFileBytes bytesOf,
    String base = assetDir,
  }) async {
    // network-free: own origin, the core's WASM file next to the app (#58)
    final response = await web.window
        .fetch('${base}wp_core_web.wasm'.toJS)
        .toDart;
    if (!response.ok) {
      throw StateError(
        'Audio core missing (${base}wp_core_web.wasm). Run app/tool/build_web_core.sh first.',
      );
    }
    final module = await _wasmCompile(await response.arrayBuffer().toDart)
        .toDart;
    final ctx = await supportedContext(web.AudioContext());
    await ctx.audioWorklet.addModule('${base}wp_worklet.js').toDart;
    final options = JSObject()
      ..['module'] = module
      ..['stateEvery'] = stateEvery.toJS;
    final node = web.AudioWorkletNode(
      ctx,
      'wp-core',
      web.AudioWorkletNodeOptions(
        numberOfInputs: 0,
        numberOfOutputs: 1,
        outputChannelCount: [2.toJS].toJS,
        processorOptions: options,
      ),
    );
    node.connect(ctx.destination);
    final loader = web.Worker(
      '${base}wp_loader.js'.toJS,
      web.WorkerOptions(type: 'module'),
    );
    final core = WebAudioCore._(ctx, node, loader, bytesOf);
    await core._ask('init', [module]);
    return core;
  }

  final web.AudioContext _ctx;
  final web.AudioWorkletNode _node;
  final web.Worker _loader;
  final WebFileBytes _bytesOf;

  // ---- Nachrichten ----

  int _lastId = 0;
  final _replies = <int, Completer<JSAny?>>{};
  final _states = StreamController<WebCoreState>.broadcast();

  /// Jeder Zustand, den das Worklet meldet (für Messungen, z. B. Pegel und Klicks des Metronoms).
  Stream<WebCoreState> get states => _states.stream;

  /// Spitzenpegel der Ausgabe (0–1) im zuletzt gemeldeten Abschnitt von etwa 10 ms.
  double get outputLevel => _peak;

  /// Läuft der AudioContext (nach der ersten Bedienung)?
  bool get audioRunning => _ctx.state == 'running';

  Future<JSAny?> _call(
    String cmd, [
    List<JSAny?> args = const [],
    List<JSObject> transfer = const [],
  ]) {
    final id = ++_lastId;
    final reply = Completer<JSAny?>();
    _replies[id] = reply;
    final msg = JSObject()
      ..['id'] = id.toJS
      ..['cmd'] = cmd.toJS
      ..['args'] = _plain(args);
    if (transfer.isEmpty) {
      _node.port.postMessage(msg);
    } else {
      _node.port.postMessage(msg, _plain(transfer));
    }
    return reply.future;
  }

  void _send(String cmd, [List<JSAny?> args = const []]) =>
      _call(cmd, args).ignore();

  // ---- Messages to the loader worker (#42) ----

  int _lastLoaderId = 0;
  final _loaderReplies = <int, Completer<JSAny?>>{};

  Future<JSAny?> _ask(
    String cmd, [
    List<JSAny?> args = const [],
    List<JSObject> transfer = const [],
  ]) {
    final id = ++_lastLoaderId;
    final reply = Completer<JSAny?>();
    _loaderReplies[id] = reply;
    final msg = JSObject()
      ..['id'] = id.toJS
      ..['cmd'] = cmd.toJS
      ..['args'] = _plain(args);
    _loader.postMessage(msg, _plain(transfer));
    return reply.future;
  }

  void _onLoaderMessage(JSAny? data) {
    if (data == null || !data.isA<JSObject>()) return;
    final m = data as JSObject;
    final reply = _loaderReplies.remove((m['id'] as JSNumber?)?.toDartInt);
    if (reply == null) return;
    final error = m['error'];
    if (error != null) {
      reply.completeError(StateError((error as JSString).toDart));
    } else {
      reply.complete(m['result']);
    }
  }

  void _onMessage(JSAny? data) {
    if (data == null || !data.isA<JSObject>()) return;
    final m = data as JSObject;
    final state = m['state'];
    if (state != null && state.isA<JSObject>()) {
      _applyState(state as JSObject);
      return;
    }
    final id = (m['id'] as JSNumber?)?.toDartInt;
    final reply = _replies.remove(id);
    if (reply == null) return;
    final error = m['error'];
    if (error != null) {
      reply.completeError(StateError((error as JSString).toDart));
    } else {
      reply.complete(m['result']);
    }
  }

  void _applyState(JSObject s, {bool force = false}) {
    final peak = (s['peak'] as JSNumber?)?.toDartDouble;
    if (peak != null) _peak = peak;
    final time = (s['time'] as JSNumber?)?.toDartDouble ?? 0;
    final wall = (s['wall'] as JSNumber?)?.toDartDouble ?? 0;
    final busy = (s['busy'] as JSNumber?)?.toDartDouble ?? 0;
    final ack = (s['ack'] as JSNumber?)?.toDartInt ?? 0;
    // Älter als der letzte Befehl (z. B. Position vor einem Seek): nur den Pegel übernehmen.
    if (force || ack >= _lastId) {
      _playing = (s['playing'] as JSBoolean).toDart;
      _position = (s['position'] as JSNumber).toDartDouble;
      _duration = (s['duration'] as JSNumber).toDartDouble;
      _loopPasses = (s['loopPasses'] as JSNumber).toDartInt;
      _metroRunning = (s['metroRunning'] as JSBoolean).toDart;
      _metroBpm = (s['metroBpm'] as JSNumber).toDartInt;
    }
    if (_states.hasListener) {
      _states.add(
        WebCoreState(
          time: time,
          wall: wall / 1000,
          busy: busy / 1000,
          peak: _peak,
          position: _position,
          playing: _playing,
          loopPasses: _loopPasses,
          metroRunning: _metroRunning,
        ),
      );
    }
  }

  /// Startet den AudioContext; muss in einer Bedienung des Nutzers liegen. Play, Laden und Metronom
  /// rufen es selbst.
  void wake() {
    if (_ctx.state != 'running') _ctx.resume().toDart.ignore();
  }

  // ---- Zustand ----

  bool _playing = false, _metroRunning = false;
  double _position = 0, _duration = 0, _peak = 0, _loadProgress = 0;
  int _loopPasses = 0, _metroBpm = 120, _loadState = WpCode.loadIdle;
  int _loadGeneration = 0;
  WaveformSummary? _summary;

  // ---- Laden ----

  @override
  int loadAsync(String path) {
    wake();
    _loadState = WpCode.loadRunning;
    _loadProgress = 0;
    _load(path, ++_loadGeneration);
    return WpCode.ok;
  }

  /// Sections of the waveform per second and at most, as WaveformSummary.binsFor.
  static final _bins = JSObject()
    ..['perSecond'] = WaveformSummary.binsPerSecond.toJS
    ..['max'] = WaveformSummary.maxBins.toJS;

  Future<void> _load(String path, int generation) async {
    try {
      final bytes = await _bytesOf(path);
      if (generation != _loadGeneration) return;
      if (bytes == null) {
        _loadState = WpCode.fileNotFound;
        return;
      }
      final rate = _ctx.sampleRate.toJS;
      // Own copy whose buffer is transferred to the worker; the bytes stay for the browser decoder.
      final copy = Uint8List.fromList(bytes).buffer.toJS;
      var track =
          (await _ask('decode', [copy, rate, _bins], [copy])) as JSObject;
      if (_code(track) == WpCode.unsupportedFormat) {
        track = await _decodeInBrowser(bytes) ?? track;
      }
      if (generation != _loadGeneration) return;
      if (_code(track) != WpCode.ok) {
        _loadState = _code(
          track,
        ); // the previous title stays loaded and keeps playing
        return;
      }
      _loadProgress = 0.5;
      final pcm = track['pcm'] as JSFloat32Array;
      final code = ((await _call(
        'beginPcm',
        [pcm],
        [pcm['buffer'] as JSObject],
      )) as JSNumber).toDartInt;
      if (generation != _loadGeneration) return;
      if (code != WpCode.ok) {
        _loadState = code;
        return;
      }
      _applyState((await _call('state')) as JSObject, force: true);
      _summary = WaveformSummary(
        _duration,
        (track['mins'] as JSFloat32Array).toDart,
        (track['maxs'] as JSFloat32Array).toDart,
      );
      _loadProgress = 1;
      _loadState = WpCode.loadReady;
    } catch (_) {
      if (generation == _loadGeneration) _loadState = WpCode.unsupportedFormat;
    }
  }

  static int _code(JSObject track) => (track['code'] as JSNumber).toDartInt;

  /// #116: cuts the file [bytes] to [start] … [end] seconds in the loader worker, with the same core code as
  /// natively (MP3, WAV, FLAC, AAC in ADTS and, #120, M4A/MP4; the browser only decodes AAC, it does not cut
  /// it).
  Future<WpTrimmed> trim(Uint8List bytes, double start, double end) async {
    final copy = Uint8List.fromList(bytes).buffer.toJS;
    final r =
        (await _ask('trim', [copy, start.toJS, end.toJS], [copy])) as JSObject;
    final code = (r['code'] as JSNumber).toDartInt;
    final out = r['bytes'];
    if (code != WpCode.ok || out == null) return WpTrimmed.failed(code);
    return WpTrimmed(
      (out as JSUint8Array).toDart,
      (r['start'] as JSNumber).toDartDouble,
      (r['end'] as JSNumber).toDartDouble,
    );
  }

  /// AAC/M4A u. a.: the browser decodes, the worker converts to stereo at the context's rate. null if the
  /// browser cannot decode it either.
  Future<JSObject?> _decodeInBrowser(Uint8List bytes) async {
    final web.AudioBuffer buffer;
    try {
      buffer = await _ctx
          .decodeAudioData(Uint8List.fromList(bytes).buffer.toJS)
          .toDart;
    } catch (_) {
      return null;
    }
    final channels = <JSAny?>[
      for (var c = 0; c < buffer.numberOfChannels; c++)
        buffer.getChannelData(c),
    ];
    return (await _ask('convert', [
      channels.toJS,
      buffer.sampleRate.toJS,
      _ctx.sampleRate.toJS,
      _bins,
    ])) as JSObject;
  }

  /// The way before #42: the worklet decodes the file itself and blocks meanwhile. Only for the control
  /// measurement in tool/web_core_check.dart; WP_OK or error code.
  Future<int> loadInWorklet(Uint8List bytes) async {
    wake();
    _loadGeneration++;
    final copy = Uint8List.fromList(bytes).buffer.toJS;
    return ((await _call('loadEncoded', [copy], [copy])) as JSNumber).toDartInt;
  }

  @override
  int get loadState => _loadState;
  @override
  double get loadProgress => _loadProgress;

  // ---- Wiedergabe ----

  @override
  void play() {
    wake();
    _playing = true;
    _send('play');
  }

  @override
  void pause() {
    _playing = false;
    _send('pause');
  }

  @override
  bool get isPlaying => _playing;

  @override
  void seek(double seconds) {
    _position = seconds;
    _send('seek', [seconds.toJS]);
  }

  @override
  set rate(double rate) => _send('setRate', [rate.toJS]);

  @override
  void setLoop(double a, double b) => _send('setLoop', [a.toJS, b.toJS]);

  @override
  void clearLoop() => setLoop(0, 0);

  @override
  set volume(double volume) => _send('setVolume', [volume.toJS]);

  @override
  double get position => _position;
  @override
  double get duration => _duration;
  @override
  int get loopPasses => _loopPasses;

  @override
  WpWaveform? waveform(double start, double end, int count) =>
      _summary?.query(start, end, count);

  /// Das Metronom desselben Kerns (rendert im selben Worklet).
  late final MetronomeBackend metronome = _WebMetronome(this);
}

/// Metronom im Worklet, wie _PlayerMetronome auf dem Desktop.
class _WebMetronome implements MetronomeBackend {
  _WebMetronome(this._core);
  final WebAudioCore _core;

  @override
  void start() {
    _core.wake();
    _core._metroRunning = true;
    _core._send('metroStart');
  }

  @override
  void stop() {
    _core._metroRunning = false;
    _core._send('metroStop');
  }

  @override
  bool get running => _core._metroRunning;

  @override
  int get bpm => _core._metroBpm;

  @override
  set bpm(int value) {
    _core._metroBpm = value;
    _core._send('metroSetBpm', [value.toJS]);
  }

  @override
  set meter(int value) => _core._send('metroSetMeter', [value.toJS]);

  @override
  set subdivision(int value) =>
      _core._send('metroSetSubdivision', [value.toJS]);

  @override
  set volume(double value) => _core._send('metroSetVolume', [value.toJS]);

  @override
  void ramp({
    required bool enabled,
    required int start,
    required int target,
    required int step,
    required int everyBars,
  }) => _core._send('metroSetRamp', [
    enabled.toJS,
    start.toJS,
    target.toJS,
    step.toJS,
    everyBars.toJS,
  ]);

  @override
  void timedRamp({
    required bool enabled,
    required int start,
    required int target,
    required int seconds,
  }) => _core._send('metroSetTimedRamp', [
    enabled.toJS,
    start.toJS,
    target.toJS,
    seconds.toJS,
  ]);
}

/// [items] as a new, plain JS array for postMessage. In debug builds (DDC) `toJS` hands over the Dart
/// list itself, and a constant list (e.g. the default `const []`) carries Dart data that postMessage
/// cannot clone (DataCloneError). Found by the web tests in Chrome (#13/AK4).
JSArray<T> _plain<T extends JSAny?>(List<T> items) {
  final a = JSArray<T>.withLength(items.length);
  for (var i = 0; i < items.length; i++) {
    a[i] = items[i];
  }
  return a;
}

/// Ein vom Worklet gemeldeter Zustand.
class WebCoreState {
  const WebCoreState({
    required this.time,
    required this.wall,
    required this.busy,
    required this.peak,
    required this.position,
    required this.playing,
    required this.loopPasses,
    required this.metroRunning,
  });

  /// Audiozeit am Ende des gemeldeten Blocks (Sekunden) und Spitzenpegel seit der letzten Meldung.
  final double time, peak;

  /// Wall clock when the worklet sent it (seconds, Date.now()); shows gaps the audio time hides, e.g. a
  /// blocked worklet (#42/AK1).
  final double wall;

  /// Longest single command or render block in the worklet since the previous state (seconds).
  final double busy;
  final double position;
  final bool playing, metroRunning;
  final int loopPasses;
}
