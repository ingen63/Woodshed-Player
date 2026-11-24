// K0 (#52): state and flow of the native test program, the same protocol as the test page (web/k0/app.mjs):
// hello / offer / answer sealed with the pairing key, the lower device id offers, non-trickle ICE, one data
// channel with JSON control messages and binary chunks (4-byte big-endian index + 64 KiB test data).
// Ways to meet: public relays (STUN optional), Bonjour + TCP in the Wi-Fi (no STUN, no internet), or the
// direct code (no relays, no STUN). State and log are JSON files in the app's container.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'net.dart';
import 'protocol.dart';

const relays = [
  'wss://relay.damus.io',
  'wss://nos.lol',
  'wss://relay.primal.net',
];
const stunServers = [
  'stun:stun.l.google.com:19302',
  'stun:stun.cloudflare.com:3478',
];
const total = 100 * 1024 * 1024;
const name = 'Mac Testprogramm';
const _staleMs = 10 * 60 * 1000;

String stamp(int t) {
  final d = DateTime.fromMillisecondsSinceEpoch(t);
  String p(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${p(d.month)}-${p(d.day)} ${p(d.hour)}:${p(d.minute)}:${p(d.second)}';
}

String mb(int bytes) => (bytes / 1048576).toStringAsFixed(1);

class Session extends ChangeNotifier {
  Session(this.dir);

  final Directory dir;
  final log = <(int, String)>[];
  late String deviceId;
  Uint8List? key;
  int? keyCreated;
  Keys? keys;
  bool stun = true;
  bool auto = false;
  RelayPool? pool;
  Lan? lan;
  Timer? _hello;
  RTCPeerConnection? pc;
  RTCDataChannel? dc;
  bool dcOpen = false;
  String connState = 'keine';
  String? sid;
  String? peerName;
  String via = '';
  Timer? _attempt;
  bool _offering = false;
  Completer<void>? _gatheredDone;
  Map<String, Object?>? rx; // id, seed, size, next, errors
  Map<String, Object?>? tx; // id, seed, size, done, sent
  int _pumpToken = 0;
  Stopwatch? _rxWatch;
  int _rxFrom = 0;
  String directOut = '';
  bool probing = false;
  List<Map<String, Object?>> checks = [];

  File get _stateFile => File('${dir.path}/state.json');
  File get _logFile => File('${dir.path}/log.txt');

  // ---- Storage and log ----

  Future<void> load() async {
    await dir.create(recursive: true);
    Map<String, Object?> s = {};
    if (_stateFile.existsSync()) {
      s = (jsonDecode(await _stateFile.readAsString()) as Map)
          .cast<String, Object?>();
    }
    deviceId = s['device'] as String? ?? hex(randomBytes(8));
    final k = s['key'] as String?;
    if (k != null) {
      key = unhex(k);
      keyCreated = s['keyCreated'] as int?;
      keys = await Keys.derive(key!);
    }
    stun = s['stun'] as bool? ?? true;
    auto = s['auto'] as bool? ?? false;
    rx = (s['rx'] as Map?)?.cast<String, Object?>();
    tx = (s['tx'] as Map?)?.cast<String, Object?>();
    checks = ((s['checks'] as List?) ?? [])
        .map((e) => (e as Map).cast<String, Object?>())
        .toList();
    if (_logFile.existsSync()) {
      for (final line in await _logFile.readAsLines()) {
        final i = line.indexOf('\t');
        if (i > 0) {
          log.add((
            int.tryParse(line.substring(0, i)) ?? 0,
            line.substring(i + 1),
          ));
        }
      }
    }
    await save();
    final age = keyCreated == null
        ? ''
        : ', ${(DateTime.now().millisecondsSinceEpoch - keyCreated!) ~/ 86400000} Tage alt';
    note('Start ($name), Schlüssel ${key == null ? 'fehlt' : 'vorhanden$age'}');
    // Without clicking (smoke tests, two instances on one Mac): K0_KEY=<pairing code>,
    // K0_CONNECT=relay,lan, K0_SEND=1 (100 MB once the data channel is open).
    final env = Platform.environment;
    final envKey = codeToKey(env['K0_KEY'] ?? '');
    if (envKey != null && (key == null || hex(key!) != hex(envKey))) {
      await setKey(envKey, 'K0_KEY');
    }
    _sendOnOpen = env['K0_SEND'] == '1';
    final connect = (env['K0_CONNECT'] ?? '').split(',');
    if (keys != null) {
      final today = stamp(DateTime.now().millisecondsSinceEpoch)
          .substring(0, 10);
      if (!checks.any((c) => c['day'] == today)) {
        unawaited(probeAll('erster Start heute'));
      }
      if (auto || connect.contains('relay')) unawaited(startRelays('Start'));
      if (auto || connect.contains('lan')) unawaited(startLan());
    }
  }

  bool _sendOnOpen = false;

  Future<void> save() => _stateFile.writeAsString(
    jsonEncode({
      'device': deviceId,
      'key': key == null ? null : hex(key!),
      'keyCreated': keyCreated,
      'stun': stun,
      'auto': auto,
      'rx': rx,
      'tx': tx,
      'checks': checks,
    }),
  );

  void note(String text) {
    final t = DateTime.now().millisecondsSinceEpoch;
    log.add((t, text));
    _logFile.writeAsStringSync(
      '$t\t${text.replaceAll('\n', ' ')}\n',
      mode: FileMode.append,
    );
    notifyListeners();
  }

  String logText() => log.map((e) => '${stamp(e.$1)}  ${e.$2}').join('\n');

  Future<void> clearLog() async {
    log.clear();
    checks.clear();
    if (_logFile.existsSync()) await _logFile.delete();
    await save();
    notifyListeners();
  }

  void setStun(bool v) {
    stun = v;
    save();
    notifyListeners();
  }

  void setAuto(bool v) {
    auto = v;
    save();
    notifyListeners();
  }

  // ---- Pairing ----

  Future<void> setKey(Uint8List k, String how) async {
    key = k;
    keyCreated = DateTime.now().millisecondsSinceEpoch;
    keys = await Keys.derive(k);
    await save();
    note('Gekoppelt ($how)');
  }

  Future<void> dropKey() async {
    await disconnect();
    key = null;
    keyCreated = null;
    keys = null;
    await save();
    note('Schlüssel gelöscht');
  }

  // ---- Relays ----

  Future<void> probeAll(String reason) async {
    if (keys == null || probing) return;
    probing = true;
    note('Relays prüfen ($reason)');
    final results = await Future.wait(
      relays.map((u) => probeRelay(u, keys!, deviceId)),
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final r in results) {
      checks.add({
        'day': stamp(now).substring(0, 10),
        't': now,
        'relay': r['relay'],
        'ok': r['ok'],
        'ms': r['echoMs'],
      });
      note(
        r['ok'] == true
            ? '  ${r['relay']}: ok, offen ${r['openMs']} ms, bestätigt ${r['okMs']} ms, Echo ${r['echoMs']} ms'
            : '  ${r['relay']}: FEHLER ${r['error']}',
      );
    }
    probing = false;
    await save();
    notifyListeners();
  }

  Future<void> startRelays(String reason) async {
    if (keys == null) return;
    _stopRelays();
    pool = RelayPool(relays, keys!, (m, v) => _onSignal(m, v, false), note)
      ..start();
    note('Verbinden über Relays ($reason), STUN ${stun ? 'an' : 'aus'}');
    Future<void> hello() async {
      if (pool != null && !dcOpen) {
        if (await _signalRelay({'t': 'hello'}) == 0) {
          note('Hallo: noch kein Relay offen');
        }
      }
    }

    Timer(const Duration(milliseconds: 1500), hello);
    _hello = Timer.periodic(const Duration(seconds: 15), (_) => hello());
    notifyListeners();
  }

  void _stopRelays() {
    _hello?.cancel();
    pool?.stop();
    pool = null;
  }

  Future<int> _signalRelay(Map<String, Object?> msg) async => pool == null
      ? 0
      : pool!.send({
          ...msg,
          'from': deviceId,
          'name': name,
          'ts': DateTime.now().millisecondsSinceEpoch,
        });

  // ---- Bonjour ----

  Future<void> startLan() async {
    if (keys == null || lan != null) return;
    lan = Lan(keys!, deviceId, (m, v) => _onSignal(m, v, true), note);
    try {
      await lan!.start();
    } on Object catch (e) {
      note('Bonjour: $e');
      lan = null;
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    _stopRelays();
    await lan?.stop();
    lan = null;
    await _closePc();
    note('Getrennt');
  }

  // ---- Signalling ----

  Future<void> _onSignal(
    Map<String, Object?> msg,
    String via,
    bool overLan,
  ) async {
    final from = msg['from'];
    final to = msg['to'];
    final ts = msg['ts'];
    if (from is! String || from == deviceId || (to != null && to != deviceId)) {
      return;
    }
    if (ts is! int ||
        (DateTime.now().millisecondsSinceEpoch - ts).abs() > _staleMs) {
      note('Veraltete Nachricht verworfen (${msg['t']})');
      return;
    }
    Future<int> reply(Map<String, Object?> m) =>
        overLan ? lan!.send(m, to: from) : _signalRelay({...m, 'to': from});
    final useStun = !overLan && stun;
    final kind = overLan ? 'lan' : 'relay';
    switch (msg['t']) {
      case 'hello':
        if (peerName == null) {
          note('Gegenstelle gefunden über $via: ${msg['name']}');
        }
        peerName = msg['name'] as String?;
        if (dcOpen) return;
        if (msg['reply'] != true) await reply({'t': 'hello', 'reply': true});
        // Two hellos can arrive together (reply and periodic one): only one offer.
        if (deviceId.compareTo(from) < 0 && _attempt == null && !_offering) {
          _offering = true;
          try {
            final sdp = await _makeOffer(useStun, kind);
            await reply({'t': 'offer', 'sid': sid, 'sdp': sdp});
            note('Angebot gesendet');
          } finally {
            _offering = false;
          }
        }
      case 'offer':
        peerName = msg['name'] as String?;
        note('Angebot erhalten über $via');
        final sdp = await _takeOffer(msg['sdp'] as String, useStun, kind);
        await reply({'t': 'answer', 'sid': msg['sid'], 'sdp': sdp});
      case 'answer':
        if (msg['sid'] == sid && pc != null) {
          note('Antwort erhalten über $via');
          await pc!.setRemoteDescription(
            RTCSessionDescription(msg['sdp'] as String, 'answer'),
          );
        }
    }
  }

  // ---- Direct code (no relays, no STUN) ----

  Future<void> makeDirectCode() async {
    final sdp = await _makeOffer(false, 'direct');
    directOut = await seal(keys!, {
      't': 'offer',
      'sid': sid,
      'sdp': sdp,
      'from': deviceId,
      'name': name,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    note('Direktcode erzeugt (ohne STUN), warte auf Antwort der Gegenstelle');
  }

  Future<void> takeDirectCode(String code) async {
    final msg = await open(keys!, code.trim());
    if (msg == null || msg['from'] == deviceId) {
      note('Direktcode ungültig (anderer Schlüssel oder eigener Code)');
      return;
    }
    final ts = msg['ts'];
    if (ts is! int ||
        (DateTime.now().millisecondsSinceEpoch - ts).abs() > _staleMs) {
      note('Direktcode älter als 10 Minuten, neu erzeugen');
      return;
    }
    peerName = msg['name'] as String?;
    if (msg['t'] == 'offer') {
      final sdp = await _takeOffer(msg['sdp'] as String, false, 'direct');
      directOut = await seal(keys!, {
        't': 'answer',
        'sid': msg['sid'],
        'sdp': sdp,
        'from': deviceId,
        'name': name,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
      note(
        'Direktcode übernommen, Antwort steht oben: bei der Gegenstelle einfügen',
      );
    } else if (msg['t'] == 'answer' && msg['sid'] == sid && pc != null) {
      await pc!.setRemoteDescription(
        RTCSessionDescription(msg['sdp'] as String, 'answer'),
      );
      note('Antwort übernommen, verbinde');
    } else {
      note('Antwort passt nicht zum letzten Direktcode');
    }
  }

  // ---- WebRTC ----

  Future<void> _closePc() async {
    _attempt?.cancel();
    _attempt = null;
    _pumpToken++;
    final old = pc;
    final oldDc = dc;
    pc = null;
    dc = null;
    dcOpen = false;
    connState = 'keine';
    await oldDc?.close();
    await old?.close();
    notifyListeners();
  }

  Future<RTCPeerConnection> _newPc(
    bool useStun,
    String kind, {
    Duration wait = const Duration(seconds: 25),
  }) async {
    await _closePc();
    final p = await createPeerConnection({
      'iceServers': [
        if (useStun)
          for (final u in stunServers) {'urls': u},
      ],
      'sdpSemantics': 'unified-plan',
    });
    pc = p;
    via = kind;
    final sw = Stopwatch()..start();
    final gathered = _gatheredDone = Completer<void>();
    p.onIceGatheringState = (s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete &&
          !gathered.isCompleted) {
        gathered.complete();
      }
    };
    p.onConnectionState = (s) {
      if (pc != p) return;
      connState = s.name
          .replaceFirst('RTCPeerConnectionState', '')
          .toLowerCase();
      note('Verbindung: $connState (${sw.elapsedMilliseconds} ms)');
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        note(
          'Keine Verbindung zustande gekommen. Im selben WLAN erneut versuchen, ggf. mit STUN.',
        );
        _closePc();
      }
    };
    p.onDataChannel = _setupDc;
    _attempt = Timer(wait, () {
      _attempt = null;
      if (pc == p && !dcOpen) {
        note(
          'Zeitüberschreitung nach ${wait.inSeconds} s'
          '${kind == 'direct' ? '' : ', neuer Versuch beim nächsten Hallo'}',
        );
        _closePc();
      }
    });
    notifyListeners();
    return p;
  }

  Future<String> _localSdp(RTCPeerConnection p) async {
    await _gatheredDone!.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {},
    );
    return (await p.getLocalDescription())!.sdp!;
  }

  Future<String> _makeOffer(bool useStun, String kind) async {
    final p = await _newPc(
      useStun,
      kind,
      wait: kind == 'direct'
          ? const Duration(minutes: 10)
          : const Duration(seconds: 25),
    );
    sid = hex(randomBytes(8));
    _setupDc(
      await p.createDataChannel('k0', RTCDataChannelInit()..ordered = true),
    );
    await p.setLocalDescription(await p.createOffer());
    return _localSdp(p);
  }

  Future<String> _takeOffer(String sdp, bool useStun, String kind) async {
    final p = await _newPc(
      useStun,
      kind,
      wait: kind == 'direct'
          ? const Duration(minutes: 1)
          : const Duration(seconds: 25),
    );
    await p.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    await p.setLocalDescription(await p.createAnswer());
    return _localSdp(p);
  }

  void _setupDc(RTCDataChannel ch) {
    dc = ch;
    ch.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen) _onOpen(ch);
      if (s == RTCDataChannelState.RTCDataChannelClosed && dc == ch) {
        note('Datenkanal geschlossen');
        _pumpToken++;
        dcOpen = false;
        dc = null;
        notifyListeners();
      }
    };
    ch.onMessage = (m) {
      if (m.isBinary) {
        _onChunk(m.binary);
      } else {
        _onControl((jsonDecode(m.text) as Map).cast<String, Object?>());
      }
    };
    if (ch.state == RTCDataChannelState.RTCDataChannelOpen) _onOpen(ch);
  }

  Future<void> _onOpen(RTCDataChannel ch) async {
    if (dcOpen || dc != ch) return;
    dcOpen = true;
    _attempt?.cancel();
    _attempt = null;
    final how = switch (via) {
      'direct' => 'Direktcode, ohne Relays',
      'lan' => 'Bonjour, ohne Relays',
      _ => 'über Relays',
    };
    note('Datenkanal offen ($how)');
    await _sendText({'t': 'info', 'name': name});
    await _describePath();
    if (tx != null && tx!['done'] != true) {
      await _offerTransfer('Fortsetzen');
    } else if (_sendOnOpen) {
      _sendOnOpen = false;
      await startTransfer();
    }
  }

  Future<void> _sendText(Map<String, Object?> m) async {
    if (dc != null && dcOpen) {
      await dc!.send(RTCDataChannelMessage(jsonEncode(m)));
    }
  }

  Future<void> _describePath() async {
    final p = pc;
    if (p == null) return;
    final stats = await p.getStats();
    final byId = {for (final r in stats) r.id: r};
    StatsReport? pair;
    for (final r in stats) {
      final sel = r.values['selectedCandidatePairId'];
      if (r.type == 'transport' && sel != null) pair = byId[sel];
    }
    pair ??= stats
        .where(
          (r) =>
              r.type == 'candidate-pair' &&
              r.values['state'] == 'succeeded' &&
              r.values['nominated'] == true,
        )
        .firstOrNull;
    if (pair == null) {
      note('Weg: unbekannt (keine Statistik)');
      return;
    }
    final l = byId[pair.values['localCandidateId']]?.values ?? const {};
    final r = byId[pair.values['remoteCandidateId']]?.values ?? const {};
    final lk = addressKind((l['address'] ?? l['ip']) as String?);
    final rk = addressKind((r['address'] ?? r['ip']) as String?);
    final types = [l['candidateType'], r['candidateType']];
    final way = types.contains('relay')
        ? 'über TURN'
        : types.contains('srflx') || lk == 'öffentlich' || rk == 'öffentlich'
        ? 'über das Internet (STUN)'
        : 'direkt im WLAN';
    final rtt = pair.values['currentRoundTripTime'];
    note(
      'Weg: $way; hier ${l['candidateType']}/${l['protocol']} ($lk), Gegenstelle ${r['candidateType']}/${r['protocol']} ($rk)'
      '${rtt is num ? ', RTT ${(rtt * 1000).round()} ms' : ''}',
    );
  }

  // ---- Transfer ----

  Future<void> ping() => _sendText({
    't': 'ping',
    'ts': DateTime.now().microsecondsSinceEpoch / 1000,
  });

  Future<void> startTransfer() async {
    tx = {
      'id': hex(randomBytes(8)),
      'seed': bytesToBig(randomBytes(4)).toInt(),
      'size': total,
      'done': false,
      'sent': 0,
    };
    await save();
    await _offerTransfer('Neue Übertragung');
  }

  Future<void> resetRx() async {
    rx = null;
    await save();
    note('Empfangsstand gelöscht');
  }

  Future<void> _offerTransfer(String reason) async {
    if (!dcOpen) return;
    note(
      '$reason: ${(tx!['id'] as String).substring(0, 6)}, ${mb(tx!['size'] as int)} MB',
    );
    await _sendText({
      't': 'xfer',
      'id': tx!['id'],
      'seed': tx!['seed'],
      'size': tx!['size'],
    });
  }

  Future<void> _onControl(Map<String, Object?> m) async {
    switch (m['t']) {
      case 'info':
        note('Gegenstelle: ${m['name']}');
      case 'ping':
        await _sendText({'t': 'pong', 'ts': m['ts']});
      case 'pong':
        note(
          'Ping ${(DateTime.now().microsecondsSinceEpoch / 1000 - (m['ts'] as num)).round()} ms',
        );
      case 'xfer':
        if (rx == null || rx!['id'] != m['id']) {
          rx = {
            'id': m['id'],
            'seed': m['seed'],
            'size': m['size'],
            'next': 0,
            'errors': 0,
          };
          await save();
        }
        final n = chunkCount(rx!['size'] as int);
        final next = rx!['next'] as int;
        if (next >= n) {
          await _sendText({
            't': 'done',
            'id': m['id'],
            'errors': rx!['errors'],
          });
          return;
        }
        _rxWatch = Stopwatch()..start();
        _rxFrom = next;
        note(
          'Empfang ${(m['id'] as String).substring(0, 6)}: ab ${mb(next * chunkSize)} MB von ${mb(rx!['size'] as int)} MB',
        );
        await _sendText({'t': 'want', 'id': m['id'], 'from': next});
      case 'want':
        if (tx != null && tx!['id'] == m['id']) {
          unawaited(_pump((m['from'] as num).toInt()));
        }
      case 'done':
        if (tx != null && tx!['id'] == m['id'] && tx!['done'] != true) {
          tx!['done'] = true;
          await save();
          note(
            'Gegenstelle hat alles (${mb(tx!['size'] as int)} MB), Prüffehler: ${m['errors']}',
          );
        }
    }
  }

  final _verify = Uint32List(chunkSize ~/ 4);

  Future<void> _onChunk(Uint8List buf) async {
    final r = rx;
    if (r == null || buf.length < 4) return;
    final index = ByteData.sublistView(buf).getUint32(0);
    final next = r['next'] as int;
    if (index != next) {
      note('Stück $index statt $next, verworfen');
      return;
    }
    final size = r['size'] as int;
    final len = (size - index * chunkSize).clamp(0, chunkSize);
    fillChunk((r['seed'] as num).toInt(), index, _verify);
    final want = _verify.buffer.asUint8List(0, len);
    var same = buf.length - 4 == len;
    for (var i = 0; same && i < len; i++) {
      same = buf[i + 4] == want[i];
    }
    if (!same) r['errors'] = (r['errors'] as int) + 1;
    r['next'] = next + 1;
    final n = chunkCount(size);
    if ((next + 1) % 16 == 0 || next + 1 == n) {
      await save();
      notifyListeners();
    }
    if (next + 1 == n) {
      final secs = (_rxWatch?.elapsedMilliseconds ?? 0) / 1000;
      final part = (n - _rxFrom) * chunkSize;
      note(
        'Empfang fertig: ${mb(size)} MB, Prüffehler ${r['errors']}; letzter Abschnitt ${mb(part)} MB in '
        '${secs.toStringAsFixed(1)} s (${(part / 1048576 / (secs > 0 ? secs : 0.001)).toStringAsFixed(1)} MB/s)',
      );
      await _sendText({'t': 'done', 'id': r['id'], 'errors': r['errors']});
    }
  }

  Future<void> _pump(int from) async {
    final token = ++_pumpToken;
    final ch = dc!;
    final t = tx!;
    final size = t['size'] as int;
    final seed = (t['seed'] as num).toInt();
    final n = chunkCount(size);
    final words = Uint32List(chunkSize ~/ 4);
    final sw = Stopwatch()..start();
    note('Senden ab ${mb(from * chunkSize)} MB');
    for (var i = from; i < n; i++) {
      if (token != _pumpToken || !dcOpen) {
        note('Senden unterbrochen bei ${mb(i * chunkSize)} MB');
        return;
      }
      if (i % 8 == 0) {
        while (await ch.getBufferedAmount() > 4 << 20) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
          if (token != _pumpToken || !dcOpen) break;
        }
      }
      fillChunk(seed, i, words);
      final len = (size - i * chunkSize).clamp(0, chunkSize);
      final msg = Uint8List(4 + len);
      ByteData.sublistView(msg).setUint32(0, i);
      msg.setRange(4, 4 + len, words.buffer.asUint8List(0, len));
      try {
        await ch.send(RTCDataChannelMessage.fromBinary(msg));
      } on Object catch (e) {
        note('Senden: $e');
        return;
      }
      if (i % 16 == 0) {
        t['sent'] = i + 1;
        notifyListeners();
      }
    }
    t['sent'] = n;
    note(
      'Alles abgeschickt: ${mb((n - from) * chunkSize)} MB in ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s, warte auf Bestätigung',
    );
  }

  @override
  void dispose() {
    _stopRelays();
    lan?.stop();
    pc?.close();
    super.dispose();
  }
}
