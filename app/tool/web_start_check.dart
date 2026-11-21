// #72/AK3: starts the built web app in headless Chrome and fails if a request fails during the
// start (HTTP status 400 or more, load error), a request leaves the own origin, or the console reports
// an error. Foreign hosts are unreachable for this Chrome (host resolver rules), so the start runs
// as if offline; a font or script fetched from a CDN shows up as a failed request.
//
// #82: a second start opens a library with titles Inter cannot draw (CJK, emoji), written into the
// page's OPFS beforehand. The web engine then asks for Noto fallback fonts; the bootstrap answers
// those without a request (web/flutter_bootstrap.js). The second start must be as clean as the first
// and must show that the engine did ask (its console warning names `fonts/fallback/`).
//
// Usage: dart tool/web_start_check.dart [<build directory>]   (default build/web, from app/)
// WP_CHROME names the Chrome binary; otherwise the usual places on macOS and Linux are tried.
// Uses dart:io only (no packages): a static file server on 127.0.0.1 and the DevTools protocol.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// What the check records from the DevTools protocol, reduced to what [problems] needs.
class StartEvent {
  StartEvent(this.method, this.params);

  final String method;
  final Map<String, dynamic> params;
}

/// The problems of a start, one line each; empty if the start was clean.
/// [origin] is the own origin, e.g. `http://127.0.0.1:8080`.
List<String> problems(List<StartEvent> events, String origin) {
  final out = <String>[];
  final urls = <String, String>{};
  for (final e in events) {
    final p = e.params;
    switch (e.method) {
      case 'Network.requestWillBeSent':
        final url = (p['request'] as Map)['url'] as String;
        urls[p['requestId'] as String] = url;
        if (!_isOwn(url, origin)) out.add('foreign request: $url');
      case 'Network.responseReceived':
        final response = p['response'] as Map;
        final status = (response['status'] as num).toInt();
        if (status >= 400) out.add('HTTP $status: ${response['url']}');
      case 'Network.loadingFailed':
        // Requests cancelled by the reload for cross-origin isolation (index.html) are no failures.
        if (p['canceled'] == true) break;
        final url = urls[p['requestId']] ?? '?';
        out.add('load failed (${p['errorText']}): $url');
      case 'Runtime.exceptionThrown':
        final details = p['exceptionDetails'] as Map;
        final exception = details['exception'] as Map?;
        out.add('exception: ${exception?['description'] ?? details['text']}');
      case 'Runtime.consoleAPICalled':
        if (p['type'] == 'error') {
          final args = (p['args'] as List).map(
            (a) => (a as Map)['value'] ?? a['description'],
          );
          out.add('console error: ${args.join(' ')}');
        }
      case 'Log.entryAdded':
        final entry = p['entry'] as Map;
        if (entry['level'] == 'error') {
          out.add('log error: ${entry['text']} ${entry['url'] ?? ''}');
        }
    }
  }
  return out;
}

/// Whether the web engine looked for a fallback font during the start (#82): it warns on the console
/// with the URL under `fonts/fallback/` when the bootstrap tells it the font is not bundled.
bool fallbackFontRequested(List<StartEvent> events) => events.any(
  (e) =>
      e.method == 'Runtime.consoleAPICalled' &&
      (e.params['args'] as List? ?? const []).any(
        (a) => '${(a as Map)['value']}'.contains('fonts/fallback/'),
      ),
);

/// Folder of the library in the page's OPFS (lib/app/platform_web.dart).
const libraryDir = 'WoodshedPlayer';

/// Invented titles with characters Inter lacks (#82/AK1): CJK and emoji.
const fallbackTitles = ['練習曲 第一番', 'Etude 🎸🎷'];

/// `library.json` (format 2) with one track per [fallbackTitles]. The tracks count as imported on
/// another device, so they are listed without an audio file on this one.
String seedLibrary() {
  const stamp = '1767225600000-0-c0ffee0000000000';
  var n = 0;
  return jsonEncode({
    'formatVersion': 2,
    'settings': {'values': <String, Object?>{}, 'stamps': <String, String>{}},
    'folders': <String, Object?>{},
    'tracks': {
      for (final title in fallbackTitles)
        '${++n}'.padLeft(64, '0'): {
          'values': {
            'fileName': '${'$n'.padLeft(64, '0')}.wav',
            'title': title,
            'duration': 1.0,
            'dateAdded': '2026-01-01T00:00:00.000Z',
          },
          'stamps': {
            for (final k in ['fileName', 'title', 'duration', 'dateAdded'])
              k: stamp,
          },
        },
    },
  });
}

/// Own origin, or a URL that never reaches the network (data:, blob:).
bool _isOwn(String url, String origin) =>
    url.startsWith('$origin/') ||
    url == origin ||
    url.startsWith('data:') ||
    url.startsWith('blob:');

const _types = <String, String>{
  'html': 'text/html; charset=utf-8',
  'js': 'text/javascript',
  'mjs': 'text/javascript',
  'json': 'application/json',
  'wasm': 'application/wasm',
  'png': 'image/png',
  'ico': 'image/x-icon',
  'ttf': 'font/ttf',
  'otf': 'font/otf',
  'woff2': 'font/woff2',
  'css': 'text/css',
  'txt': 'text/plain; charset=utf-8',
  'frag': 'text/plain',
};

/// Page of the check server (not in the build) used to write the library before the second start.
const seedPath = '/__seed__.html';

Future<HttpServer> _serve(Directory dir) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    var path = Uri.decodeComponent(request.uri.path);
    if (path == seedPath) {
      // An empty page of the own origin, so the check can write into its OPFS before the start.
      request.response.headers.set('Content-Type', _types['html']!);
      request.response.write('<!doctype html><title>seed</title>');
      await request.response.close();
      return;
    }
    if (path.endsWith('/')) path += 'index.html';
    final file = File('${dir.path}$path');
    final response = request.response;
    if (path.contains('..') || !file.existsSync()) {
      response.statusCode = HttpStatus.notFound;
    } else {
      final ext = path.split('.').last;
      response.headers.set(
        'Content-Type',
        _types[ext] ?? 'application/octet-stream',
      );
      await response.addStream(file.openRead());
    }
    await response.close();
  });
  return server;
}

String _findChrome() {
  final candidates = [
    Platform.environment['WP_CHROME'] ?? '',
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    'google-chrome',
    'google-chrome-stable',
    'chromium',
    'chromium-browser',
  ];
  for (final c in candidates) {
    if (c.isEmpty) continue;
    if (c.startsWith('/')) {
      if (File(c).existsSync()) return c;
    } else if (Process.runSync('which', [c]).exitCode == 0) {
      return c;
    }
  }
  throw StateError('web_start_check: no Chrome found (set WP_CHROME)');
}

Future<void> main(List<String> args) async {
  final dir = Directory(args.isEmpty ? 'build/web' : args.first);
  if (!File('${dir.path}/index.html').existsSync()) {
    stderr.writeln(
      'web_start_check: ${dir.path}/index.html missing, run flutter build web first',
    );
    exit(2);
  }
  final server = await _serve(dir);
  final origin = 'http://127.0.0.1:${server.port}';
  final profile = Directory.systemTemp.createTempSync('wp_start_check');
  final chrome = await Process.start(_findChrome(), [
    '--headless=new',
    '--remote-debugging-port=0',
    '--user-data-dir=${profile.path}',
    '--no-first-run',
    '--no-default-browser-check',
    // Wide enough that the library is shown next to the player (#82: its titles must be drawn).
    '--window-size=1400,900',
    // Every host except the own server is unreachable: the start must not depend on the internet.
    '--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1',
    'about:blank',
  ]);
  var exitCode = 1;
  try {
    final wsUrl = await chrome.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .map(
          (l) =>
              RegExp(r'DevTools listening on (ws://\S+)')
                  .firstMatch(l)
                  ?.group(1),
        )
        .firstWhere((u) => u != null)
        .timeout(const Duration(seconds: 30));
    final debugPort = Uri.parse(wsUrl!).port;
    final page = _DevTools(await _pageSocket(debugPort));
    for (final domain in ['Network', 'Runtime', 'Log', 'Page']) {
      await page.send('$domain.enable');
    }
    final found = problems(await _recordStart(page, origin), origin);
    // #82: second start with titles Inter cannot draw.
    await page.send('Page.navigate', {'url': '$origin$seedPath'});
    await _waitFor(page, "document.title === 'seed'");
    final seeded = await page.send('Runtime.evaluate', {
      'expression': _seedScript(seedLibrary()),
      'awaitPromise': true,
      'returnByValue': true,
    });
    if ((seeded['result'] as Map?)?['value'] != true) {
      found.add('#82: library with fallback titles not written: $seeded');
    }
    final fallbackEvents = await _recordStart(page, origin);
    found.addAll(problems(fallbackEvents, origin).map((p) => '#82: $p'));
    if (!fallbackFontRequested(fallbackEvents)) {
      found.add(
        '#82: the engine never looked for a fallback font (titles not drawn?)',
      );
    }
    if (found.isEmpty) {
      stdout.writeln(
        'web_start_check: start without failed requests and console errors, '
        'also with CJK and emoji titles',
      );
      exitCode = 0;
    } else {
      stderr.writeln(
        'web_start_check: ${found.length} problem(s) during the start:',
      );
      for (final f in found) {
        stderr.writeln('  $f');
      }
    }
    await page.close();
  } finally {
    chrome.kill();
    await chrome.exitCode;
    await server.close(force: true);
    try {
      profile.deleteSync(recursive: true);
    } on FileSystemException {
      // Chrome may still hold files for a moment; the temp directory is cleaned up by the system.
    }
  }
  exit(exitCode);
}

Future<WebSocket> _pageSocket(int debugPort) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$debugPort/json/list'),
    );
    final body = await (await request.close()).transform(utf8.decoder).join();
    final targets = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
    final target = targets.firstWhere((t) => t['type'] == 'page');
    return await WebSocket.connect(target['webSocketDebuggerUrl'] as String);
  } finally {
    client.close();
  }
}

/// Writes [json] as `library.json` into the library folder of the page's OPFS; resolves to true.
String _seedScript(String json) =>
    """(async () => {
  const root = await navigator.storage.getDirectory();
  const dir = await root.getDirectoryHandle('$libraryDir', {create: true});
  const file = await dir.getFileHandle('library.json', {create: true});
  const out = await file.createWritable();
  await out.write(${jsonEncode(json)});
  await out.close();
  return true;
})()""";

/// One DevTools connection to the page: commands with replies, events collected in [events].
class _DevTools {
  _DevTools(this._socket) {
    _socket.listen((data) {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      final id = message['id'];
      if (id is int) {
        _replies
            .remove(id)
            ?.complete((message['result'] as Map<String, dynamic>?) ?? {});
      } else if (message['method'] is String) {
        events.add(
          StartEvent(
            message['method'] as String,
            (message['params'] as Map<String, dynamic>?) ?? {},
          ),
        );
      }
    });
  }

  final WebSocket _socket;
  final _replies = <int, Completer<Map<String, dynamic>>>{};
  var _nextId = 0;
  List<StartEvent> events = [];

  Future<Map<String, dynamic>> send(
    String method, [
    Map<String, dynamic>? params,
  ]) {
    final id = ++_nextId;
    final reply = _replies[id] = Completer();
    _socket.add(
      jsonEncode({'id': id, 'method': method, 'params': params ?? {}}),
    );
    return reply.future.timeout(const Duration(seconds: 30));
  }

  Future<void> close() => _socket.close();
}

/// Polls [expression] until it is true; false after [timeout].
Future<bool> _waitFor(
  _DevTools page,
  String expression, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (true) {
    final result = await page.send('Runtime.evaluate', {
      'expression': expression,
      'returnByValue': true,
    });
    if ((result['result'] as Map?)?['value'] == true) return true;
    if (DateTime.now().isAfter(deadline)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
}

/// Opens [origin] and records events until the Flutter view is there and a quiet period has passed.
Future<List<StartEvent>> _recordStart(_DevTools page, String origin) async {
  final events = page.events = [];
  await page.send('Page.navigate', {'url': '$origin/'});
  if (!await _waitFor(
    page,
    "document.querySelector('flutter-view') !== null",
  )) {
    events.add(
      StartEvent('Runtime.exceptionThrown', {
        'exceptionDetails': {'text': 'Flutter view did not appear within 60 s'},
      }),
    );
    return events;
  }
  // Fonts and the first frame load after the view appears.
  await Future<void>.delayed(const Duration(seconds: 5));
  return events;
}
