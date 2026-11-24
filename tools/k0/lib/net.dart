// K0 (#52): the two ways the native test program finds its peer and exchanges the (sealed) signalling messages:
// public Nostr relays over WebSocket (like the test page), and Bonjour plus a TCP connection in the same Wi-Fi
// (native devices only, no internet, no relays). Bonjour itself lives in macos/Runner/MainFlutterWindow.swift.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'protocol.dart';

typedef OnSignal = Future<void> Function(Map<String, Object?> msg, String via);
typedef Note = void Function(String text);

String relayHost(String url) =>
    url.replaceFirst(RegExp(r'^wss?://'), '').replaceFirst(RegExp('/.*'), '');

class RelayPool {
  RelayPool(this.urls, this.keys, this.onMessage, this.note);

  final List<String> urls;
  final Keys keys;
  final OnSignal onMessage;
  final Note note;
  final _sockets = <String, WebSocket>{};
  final _seen = <String>{};
  bool _running = false;

  int get openCount => _sockets.length;

  void start() {
    _running = true;
    for (final url in urls) {
      _connect(url);
    }
  }

  void stop() {
    _running = false;
    for (final ws in _sockets.values) {
      ws.close();
    }
    _sockets.clear();
  }

  Future<void> _connect(String url) async {
    final host = relayHost(url);
    try {
      final ws = await WebSocket.connect(url)
          .timeout(const Duration(seconds: 10));
      if (!_running) {
        await ws.close();
        return;
      }
      _sockets[url] = ws;
      _failures.remove(url);
      final since = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60;
      ws.add(
        jsonEncode([
          'REQ',
          'k0',
          {
            'kinds': [nostrKind],
            'authors': [keys.pubkey],
            'since': since,
          },
        ]),
      );
      note('Relay $host offen');
      ws.listen(
        (Object? data) => _onFrame(host, data),
        onDone: () {
          if (_sockets[url] != ws) return;
          _sockets.remove(url);
          note('Relay $host geschlossen');
          _retry(url);
        },
        onError: (Object e) => note('Relay $host: Fehler'),
      );
    } on Object catch (e) {
      // Only the first failure in a row is logged; retries back off up to a minute.
      if (!_failures.containsKey(url)) {
        note('Relay $host: keine Verbindung (${e.runtimeType})');
      }
      _failures[url] = (_failures[url] ?? 0) + 1;
      _retry(url);
    }
  }

  final _failures = <String, int>{};

  void _retry(String url) {
    if (_running) {
      final n = _failures[url] ?? 0;
      Timer(Duration(seconds: n >= 4 ? 60 : 5 << n), () {
        if (_running && !_sockets.containsKey(url)) _connect(url);
      });
    }
  }

  Future<void> _onFrame(String host, Object? data) async {
    if (data is! String) return;
    final Object? m;
    try {
      m = jsonDecode(data);
    } on FormatException {
      return;
    }
    if (m is! List || m.isEmpty) return;
    if (m[0] == 'EVENT' && m.length > 2 && m[2] is Map) {
      final ev = m[2] as Map;
      final id = ev['id'];
      final content = ev['content'];
      if (id is! String || content is! String || !_seen.add(id)) return;
      final msg = await open(keys, content);
      if (msg != null) await onMessage(msg, host);
    } else if (m[0] == 'OK' && m.length > 3 && m[2] == false) {
      note('Relay $host lehnt ab: ${m[3]}');
    } else if (m[0] == 'NOTICE' || m[0] == 'CLOSED') {
      note('Relay $host: ${m[0]} ${m.last}');
    }
  }

  Future<int> send(Map<String, Object?> msg) async {
    final frame = jsonEncode([
      'EVENT',
      nostrEvent(keys, await seal(keys, msg)),
    ]);
    for (final ws in _sockets.values) {
      ws.add(frame);
    }
    return _sockets.length;
  }
}

/// One relay alone: open, subscribe, publish a probe, wait for OK and echo (test point 4).
Future<Map<String, Object?>> probeRelay(
  String url,
  Keys keys,
  String deviceId,
) async {
  final sw = Stopwatch()..start();
  final result = <String, Object?>{
    'relay': relayHost(url),
    'ok': false,
    'openMs': null,
    'okMs': null,
    'echoMs': null,
  };
  WebSocket? ws;
  try {
    ws = await WebSocket.connect(url).timeout(const Duration(seconds: 10));
    result['openMs'] = sw.elapsedMilliseconds;
    final done = Completer<void>();
    final ev = nostrEvent(
      keys,
      await seal(keys, {
        't': 'probe',
        'from': deviceId,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }),
    );
    ws.listen((Object? data) {
      if (data is! String) return;
      final m = jsonDecode(data);
      if (m is! List || m.length < 3) return;
      if (m[0] == 'OK' && m[1] == ev['id']) {
        if (m[2] == false) {
          result['error'] = 'abgelehnt: ${m.length > 3 ? m[3] : ''}';
          if (!done.isCompleted) done.complete();
        } else {
          result['okMs'] = sw.elapsedMilliseconds;
        }
      } else if (m[0] == 'EVENT' &&
          m[2] is Map &&
          (m[2] as Map)['id'] == ev['id']) {
        result['echoMs'] = sw.elapsedMilliseconds;
      }
      if (result['okMs'] != null &&
          result['echoMs'] != null &&
          !done.isCompleted) {
        done.complete();
      }
    }, onDone: () => done.isCompleted ? null : done.complete());
    ws.add(
      jsonEncode([
        'REQ',
        'probe',
        {
          'kinds': [nostrKind],
          'authors': [keys.pubkey],
          'since': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 5,
        },
      ]),
    );
    ws.add(jsonEncode(['EVENT', ev]));
    await done.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => result['error'] ??= 'Zeitüberschreitung',
    );
  } on Object catch (e) {
    result['error'] = 'keine Verbindung (${e.runtimeType})';
  } finally {
    await ws?.close();
  }
  result['ok'] = result['okMs'] != null && result['echoMs'] != null;
  return result;
}

/// Bonjour discovery plus one TCP connection per peer, newline-delimited sealed messages. The device with the
/// lower id dials. Only instances whose TXT tag matches the pairing key are contacted.
class Lan {
  Lan(this.keys, this.deviceId, this.onMessage, this.note);

  final Keys keys;
  final String deviceId;
  final OnSignal onMessage;
  final Note note;
  static const _channel = MethodChannel('k0/bonjour');
  ServerSocket? _server;
  final _peers = <String, Socket>{};
  final _dialing = <String>{};

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _server!.listen((s) => _attach(s, null));
    _channel.setMethodCallHandler(_onCall);
    await _channel.invokeMethod<void>('start', {
      'name': deviceId,
      'port': _server!.port,
      'tag': keys.lanTag,
    });
    note('Bonjour: suche im WLAN (Port ${_server!.port})');
  }

  Future<void> stop() async {
    _channel.setMethodCallHandler(null);
    await _channel.invokeMethod<void>('stop');
    for (final s in _peers.values) {
      s.destroy();
    }
    _peers.clear();
    await _server?.close();
    _server = null;
  }

  Future<Object?> _onCall(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
    switch (call.method) {
      case 'published':
        note('Bonjour: angemeldet');
      case 'error':
        note('Bonjour: Fehler ${args['text']}');
      case 'lost':
        if (args['name'] != deviceId) note('Bonjour: Gerät verschwunden');
      case 'found':
        final name = args['name'] as String? ?? '';
        if (name == deviceId) return null;
        if (args['tag'] != keys.lanTag) {
          note('Bonjour: fremdes Testgerät (anderer Schlüssel), ignoriert');
          return null;
        }
        final addresses = (args['addresses'] as List?)?.cast<String>() ?? [];
        note(
          'Bonjour: Gegenstelle gefunden (${addresses.map(addressKind).join(', ')})',
        );
        if (deviceId.compareTo(name) < 0 &&
            !_peers.containsKey(name) &&
            _dialing.add(name)) {
          await _dial(name, addresses, args['port'] as int? ?? 0);
        }
    }
    return null;
  }

  Future<void> _dial(String name, List<String> addresses, int port) async {
    try {
      for (final a in addresses) {
        try {
          final s = await Socket.connect(
            a,
            port,
            timeout: const Duration(seconds: 3),
          );
          _attach(s, name);
          await send({'t': 'hello'}, to: name);
          return;
        } on SocketException {
          continue;
        }
      }
      note('Bonjour: Gegenstelle nicht erreichbar');
    } finally {
      _dialing.remove(name);
    }
  }

  void _attach(Socket socket, String? peer) {
    if (peer != null) _peers[peer] = socket;
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          (line) async {
            final msg = await open(keys, line);
            if (msg == null) return;
            final from = msg['from'];
            if (from is String && peer == null) {
              peer = from;
              _peers[from] = socket;
            }
            await onMessage(msg, 'Bonjour/TCP');
          },
          onDone: () {
            if (peer != null && _peers[peer] == socket) _peers.remove(peer);
          },
          onError: (Object _) {},
        );
  }

  /// Sends to one peer, or to all connected peers. Returns the number of peers reached.
  Future<int> send(Map<String, Object?> msg, {String? to}) async {
    final full = {
      ...msg,
      'from': deviceId,
      'name': 'Mac Testprogramm',
      'ts': DateTime.now().millisecondsSinceEpoch,
      'to': ?to,
    };
    final line = '${await seal(keys, full)}\n';
    var n = 0;
    for (final e in _peers.entries) {
      if (to == null || e.key == to) {
        e.value.write(line);
        n++;
      }
    }
    return n;
  }
}
