// #72/AK3: starts the built web app in headless Chrome and fails if a request fails during the
// start (HTTP status 400 or more, load error), a request leaves the own origin, or the console reports
// an error. Foreign hosts are unreachable for this Chrome (host resolver rules), so the start runs
// as if offline; a font or script fetched from a CDN shows up as a failed request.
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

Future<HttpServer> _serve(Directory dir) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    var path = Uri.decodeComponent(request.uri.path);
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
    final page = await _pageSocket(debugPort);
    final events = await _recordStart(page, origin);
    final found = problems(events, origin);
    if (found.isEmpty) {
      stdout.writeln(
        'web_start_check: start without failed requests and console errors',
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

/// Opens [origin] and records events until the Flutter view is there and a quiet period has passed.
Future<List<StartEvent>> _recordStart(WebSocket page, String origin) async {
  final events = <StartEvent>[];
  final replies = <int, Completer<Map<String, dynamic>>>{};
  var nextId = 0;
  page.listen((data) {
    final message = jsonDecode(data as String) as Map<String, dynamic>;
    final id = message['id'];
    if (id is int) {
      replies
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
  Future<Map<String, dynamic>> send(
    String method, [
    Map<String, dynamic>? params,
  ]) {
    final id = ++nextId;
    final reply = replies[id] = Completer();
    page.add(jsonEncode({'id': id, 'method': method, 'params': params ?? {}}));
    return reply.future.timeout(const Duration(seconds: 30));
  }

  for (final domain in ['Network', 'Runtime', 'Log', 'Page']) {
    await send('$domain.enable');
  }
  await send('Page.navigate', {'url': '$origin/'});
  final deadline = DateTime.now().add(const Duration(seconds: 60));
  while (true) {
    final result = await send('Runtime.evaluate', {
      'expression': "document.querySelector('flutter-view') !== null",
      'returnByValue': true,
    });
    if ((result['result'] as Map?)?['value'] == true) break;
    if (DateTime.now().isAfter(deadline)) {
      events.add(
        StartEvent('Runtime.exceptionThrown', {
          'exceptionDetails': {
            'text': 'Flutter view did not appear within 60 s',
          },
        }),
      );
      return events;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  // Fonts and the first frame load after the view appears.
  await Future<void>.delayed(const Duration(seconds: 5));
  return events;
}
