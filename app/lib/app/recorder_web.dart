// Recording in the browser (#157): the microphone through `getUserMedia` (without echo cancellation, noise
// suppression and automatic gain, AK2) into the AudioWorklet processor «wp-mic» of the core's AudioContext,
// from there over a MessagePort to the recording worker (core/web/wp_recorder.js). The worker runs its own
// instance of the WASM core: the same sound gate as natively (armed) and FLAC with 24 bits, stored piece by
// piece in the OPFS (folder WoodshedPlayerRecordings). After the stop the library takes the file over like a
// picked file ([take]) and it is removed there.
// The microphone is open only while recording, or between two takes of «Armed» (AK9): [releaseAfter] after
// the stop it is closed unless the next take starts. While it is open the page's audio session is
// 'play-and-record' (Safari on iPhone records only then), otherwise 'playback' (#158).
// The getters of [Recorder] are synchronous and read the state the worker last sent (about every 50 ms).
// AK7: when the page is hidden (another app, locked screen) a running recording ends ([interruption]
// background; the controller saves it) and the microphone closes; Safari would stop it there anyway.
// AK8: when the storage is full the worker ends the file with what was stored ([interruption]
// storageFull).
import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import 'package:wp_core/wp_types.dart';

import '../player/audio_core_web.dart';
import '../player/audio_session_web.dart';
import 'recording_controller.dart';

/// Opens the microphone with [constraints] (`navigator.mediaDevices.getUserMedia`); tests pass another
/// source.
typedef MicrophoneOpener = JSPromise<web.MediaStream> Function(
  JSObject constraints,
);

/// Why the microphone did not open.
enum MicrophoneProblem {
  /// The browser or the user refused the permission (AK6).
  denied,

  /// No microphone, or it could not be opened.
  noInput,
}

class WebRecorder with ChangeNotifier implements Recorder {
  WebRecorder._(
    this._core,
    this._worker,
    this._open, {
    required this.releaseAfter,
    required this.setSession,
    this.storageLimit,
  }) {
    _worker.onmessage = ((web.MessageEvent e) => _onMessage(e.data)).toJS;
  }

  /// Tests: the worker reports a full storage once the file would grow beyond this many bytes.
  final int? storageLimit;

  /// Folder of the recordings in the page's OPFS, until the library takes them over.
  static const folder = 'WoodshedPlayerRecordings';

  /// Prefix of the paths this recorder hands out (`recordings/<name>.flac`).
  static const dir = 'recordings';

  /// Channels of the file: stereo like every native recording; a mono microphone fills both.
  static const channels = 2;

  /// AK2: the microphone as it is, without the processing of a call.
  static JSObject constraints() =>
      {
            'audio': {
              'echoCancellation': false,
              'noiseSuppression': false,
              'autoGainControl': false,
            },
            'video': false,
          }.jsify()!
          as JSObject;

  /// AK1: the page can record: `getUserMedia` (only in a secure context, i.e. HTTPS or localhost) and
  /// AudioWorklet. Synchronous OPFS access exists only in Workers; the worker checks it ([create]).
  static bool get supported {
    final nav = web.window.navigator as JSObject;
    final devices = nav['mediaDevices'];
    if (devices == null || !devices.isA<JSObject>()) return false;
    if (!(devices as JSObject).has('getUserMedia')) return false;
    return globalContext.has('AudioWorkletNode');
  }

  /// The recorder for [core], or null if the browser cannot record. [open] replaces `getUserMedia`
  /// (tests); [setSession] the audio session switch.
  static Future<WebRecorder?> create(
    WebAudioCore core, {
    MicrophoneOpener? open,
    Duration releaseAfter = const Duration(milliseconds: 1500),
    bool Function(AudioSessionType type) setSession = setAudioSessionType,
    int? storageLimit,
    bool watchPage = true,
  }) async {
    if (!supported) return null;
    final worker = web.Worker(
      // network-free: own origin, the core's recording worker next to the app (#157)
      '${core.base}wp_recorder.js'.toJS,
      web.WorkerOptions(type: 'module'),
    );
    final r = WebRecorder._(
      core,
      worker,
      open ?? _getUserMedia,
      releaseAfter: releaseAfter,
      setSession: setSession,
      storageLimit: storageLimit,
    );
    final ready = await r._ask('init', [core.wasmModule]);
    if ((ready as JSBoolean?)?.toDart != true) {
      worker.terminate();
      return null;
    }
    if (watchPage) {
      web.document.addEventListener(
        'visibilitychange',
        ((web.Event _) {
          if (web.document.visibilityState == 'hidden') r.pageHidden();
        }).toJS,
      );
      web.window.addEventListener(
        'pagehide',
        ((web.Event _) => r.pageHidden()).toJS,
      );
    }
    return r;
  }

  static JSPromise<web.MediaStream> _getUserMedia(JSObject constraints) {
    final devices =
        (web.window.navigator as JSObject)['mediaDevices']! as JSObject;
    return devices.callMethod<JSPromise<web.MediaStream>>(
      'getUserMedia'.toJS,
      constraints,
    );
  }

  /// The stream, or the `name` of the error the promise was rejected with.
  static Future<(web.MediaStream?, String?)> _settle(
    JSPromise<web.MediaStream> promise,
  ) {
    final done = Completer<(web.MediaStream?, String?)>();
    promise.callMethod<JSAny?>(
      'then'.toJS,
      ((web.MediaStream s) => done.complete((s, null))).toJS,
      ((JSAny? err) {
        final name = err != null && err.isA<JSObject>()
            ? ((err as JSObject)['name'] as JSString?)?.toDart
            : null;
        done.complete((null, name ?? 'Error'));
      }).toJS,
    );
    return done.future;
  }

  final WebAudioCore _core;
  final web.Worker _worker;
  final MicrophoneOpener _open;

  /// How long the microphone stays open after a stop (the next take of «Armed» starts at once).
  final Duration releaseAfter;
  final bool Function(AudioSessionType type) setSession;

  web.MediaStream? _stream;
  web.MediaStreamAudioSourceNode? _source;
  web.AudioWorkletNode? _mic;
  MicrophoneProblem? _problem;
  Timer? _release;

  /// Why the microphone did not open at the last [acquire].
  MicrophoneProblem? get problem => _problem;

  /// The microphone is open (AK9: only while recording or armed).
  bool get microphoneOpen => _stream != null;

  // ---- Worker ----

  int _lastId = 0;
  final _replies = <int, Completer<JSAny?>>{};

  Future<JSAny?> _ask(
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
      ..['args'] = plainArray(args);
    _worker.postMessage(msg, plainArray(transfer));
    return reply.future;
  }

  void _onMessage(JSAny? data) {
    if (data == null || !data.isA<JSObject>()) return;
    final m = data as JSObject;
    final status = m['status'];
    if (status != null && status.isA<JSObject>()) {
      _applyStatus(status as JSObject);
      return;
    }
    final reply = _replies.remove((m['id'] as JSNumber?)?.toDartInt);
    if (reply == null) return;
    final error = m['error'];
    if (error != null) {
      reply.completeError(StateError((error as JSString).toDart));
    } else {
      reply.complete(m['result']);
    }
  }

  void _applyStatus(JSObject s) {
    // A late status of the previous take does not count for the next one.
    if ((s['name'] as JSString?)?.toDart != _name) return;
    _gate = WpRecGate.of((s['gate'] as JSNumber).toDartInt);
    _seconds = (s['seconds'] as JSNumber).toDartDouble;
    _kept = (s['keptSeconds'] as JSNumber).toDartDouble;
    final level = (s['level'] as JSNumber).toDartDouble;
    if (level > _level) _level = level;
    _silent = (s['silent'] as JSBoolean).toDart;
    final interrupted = (s['interrupted'] as JSString?)?.toDart;
    if (interrupted != null) _interrupted = interrupted;
    notifyListeners();
  }

  // ---- Microphone ----

  /// Opens the microphone (the browser asks the first time). False if the permission was refused
  /// ([problem] is then [MicrophoneProblem.denied]); without a microphone true, and the start fails
  /// with [WpRecCode.noInput].
  Future<bool> acquire() async {
    _release?.cancel();
    _release = null;
    if (_stream != null) return true;
    _problem = null;
    setSession(AudioSessionType.playAndRecord);
    _core.wake(); // within the click, so the AudioContext runs
    final (opened, error) = await _settle(_open(constraints()));
    if (opened == null) {
      final denied = error == 'NotAllowedError' || error == 'SecurityError';
      _problem = denied ? MicrophoneProblem.denied : MicrophoneProblem.noInput;
      setSession(AudioSessionType.playback);
      return !denied;
    }
    final stream = opened;
    final ctx = _core.context;
    final source = ctx.createMediaStreamSource(stream);
    final mic = web.AudioWorkletNode(
      ctx,
      'wp-mic',
      web.AudioWorkletNodeOptions(
        numberOfInputs: 1,
        numberOfOutputs: 1,
        outputChannelCount: [1.toJS].toJS,
        channelCount: channels,
        channelCountMode: 'explicit',
        processorOptions: {'channels': channels}.jsify()! as JSObject,
      ),
    );
    source.connect(mic);
    mic.connect(
      ctx.destination,
    ); // silent; keeps process() running in every browser
    _stream = stream;
    _source = source;
    _mic = mic;
    return true;
  }

  /// Closes the microphone and gives the audio session back to playback.
  void releaseMicrophone() {
    _release?.cancel();
    _release = null;
    final stream = _stream;
    if (stream == null) return;
    for (final track in stream.getTracks().toDart) {
      track.stop();
    }
    _source?.disconnect();
    _mic?.disconnect();
    _stream = null;
    _source = null;
    _mic = null;
    setSession(AudioSessionType.playback);
    notifyListeners();
  }

  // ---- Recorder ----

  int _count = 0;
  String? _name, _path;
  final _names = <String, String>{};
  final _finished = <String, Future<void>>{};
  bool _recording = false;
  WpRecGate _gate = WpRecGate.off;
  double _seconds = 0, _kept = 0, _level = 0;
  bool _silent = true;
  String? _interrupted;

  /// AK7: the page went to the background: a running recording ends (the controller saves it), the
  /// microphone closes.
  void pageHidden() {
    if (_recording) {
      _interrupted ??= 'background';
      notifyListeners();
    } else {
      releaseMicrophone();
    }
  }

  @override
  RecordingInterruption? get interruption => !_recording
      ? null
      : switch (_interrupted) {
          'background' => RecordingInterruption.background,
          'storage' => RecordingInterruption.storageFull,
          'error' => RecordingInterruption.failed,
          _ => null,
        };

  @override
  bool sourceAvailable(WpRecSource source) => source == WpRecSource.microphone;

  @override
  void start(String path, WpRecSource source) => _start(path, null);

  @override
  void startArmed(
    String path,
    WpRecSource source, {
    required double thresholdDb,
    required double silenceSeconds,
    double? tailSeconds,
  }) => _start(path, (
    thresholdDb: thresholdDb,
    silenceSeconds: silenceSeconds,
    tailSeconds: tailSeconds ?? WpRecArming.defaultTailSeconds,
  ));

  void _start(
    String path,
    ({double thresholdDb, double silenceSeconds, double tailSeconds})? arming,
  ) {
    final mic = _mic;
    if (mic == null) {
      throw const WpRecordingException(
        WpRecCode.noInput,
        0,
        'No microphone or it could not be opened',
      );
    }
    _release?.cancel();
    _release = null;
    final name =
        'take-${DateTime.now().millisecondsSinceEpoch}-${++_count}.flac';
    _names[path] = name;
    _name = name;
    _path = path;
    _recording = true;
    _gate = arming == null ? WpRecGate.off : WpRecGate.armed;
    _seconds = 0;
    _kept = 0;
    _level = 0;
    _silent = true;
    _interrupted = null;
    _core.wake();
    final channel = web.MessageChannel();
    mic.port.postMessage({'port': channel.port1}.jsify(), [channel.port1].toJS);
    final options =
        {
              'name': name,
              'sampleRate': _core.context.sampleRate,
              'channels': channels,
              'armed': arming != null,
              'thresholdDb': arming?.thresholdDb ?? 0,
              'silenceSeconds': arming?.silenceSeconds ?? 0,
              'tailSeconds': arming?.tailSeconds ?? 0,
              'storageLimit': ?storageLimit,
            }.jsify()!
            as JSObject;
    final started = _ask('start', [options, channel.port2], [channel.port2]);
    _finished[path] = started.then((code) {
      if ((code as JSNumber?)?.toDartInt != WpCode.ok && _name == name) {
        _interrupted = 'error';
      }
    });
  }

  @override
  void stop() {
    if (!_recording) return;
    _recording = false;
    final path = _path!;
    _mic?.port.postMessage({'stop': true}.jsify());
    final before = _finished[path] ?? Future.value();
    _finished[path] = before.then((_) => _ask('stop')).then((result) {
      final r = result as JSObject?;
      final interrupted = (r?['interrupted'] as JSString?)?.toDart;
      if (interrupted != null) _interrupted = interrupted;
    });
    _release = Timer(releaseAfter, releaseMicrophone);
  }

  @override
  bool get isRecording => _recording;
  @override
  double get seconds => _seconds;
  @override
  WpRecGate get gate => _recording ? _gate : WpRecGate.off;
  @override
  double get keptSeconds => _kept;

  /// Peak since the last query.
  @override
  double get level {
    final l = _level;
    _level = 0;
    return l;
  }

  @override
  bool get onlySilence => _silent;

  @override
  bool exists(String path) => _names.containsKey(path);

  @override
  void delete(String path) {
    final name = _names.remove(path);
    if (name == null) return;
    unawaited(_finished.remove(path)!.then((_) => _remove(name)));
  }

  /// The finished file at [path] as bytes, removed from the recorder's folder; null if there is none.
  /// Waits until the worker has finished it.
  Future<Uint8List?> take(String path) async {
    final name = _names[path];
    if (name == null) return null;
    await _finished[path];
    _names.remove(path);
    _finished.remove(path);
    try {
      final dir = await _folder();
      final handle = await dir.getFileHandle(name).toDart;
      final file = await handle.getFile().toDart;
      final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
      await _remove(name);
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<web.FileSystemDirectoryHandle> _folder() async {
    final root = await web.window.navigator.storage.getDirectory().toDart;
    return root
        .getDirectoryHandle(
          folder,
          web.FileSystemGetDirectoryOptions(create: true),
        )
        .toDart;
  }

  static Future<void> _remove(String name) async {
    try {
      await (await _folder()).removeEntry(name).toDart;
    } catch (_) {} // already gone
  }
}
