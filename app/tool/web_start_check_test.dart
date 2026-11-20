// Tests of the start check of the web app (#72/AK3) and the Roboto alias it relies on (#72/AK2).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'web_start_check.dart';

const origin = 'http://127.0.0.1:8080';

StartEvent request(String id, String url) =>
    StartEvent('Network.requestWillBeSent', {
      'requestId': id,
      'request': {'url': url},
    });

StartEvent response(String url, int status) =>
    StartEvent('Network.responseReceived', {
      'response': {'url': url, 'status': status},
    });

void main() {
  group('problems (#72/AK3)', () {
    test('a clean start has no problems', () {
      final events = [
        request('1', '$origin/'),
        response('$origin/', 200),
        request('2', '$origin/assets/fonts/inter/Inter-Regular.ttf'),
        response('$origin/assets/fonts/inter/Inter-Regular.ttf', 200),
        request('3', 'data:font/woff2;base64,AAAA'),
        StartEvent('Runtime.consoleAPICalled', {
          'type': 'log',
          'args': [
            {'value': 'hello'},
          ],
        }),
      ];
      expect(problems(events, origin), isEmpty);
    });

    test('#72/AK3 a 404 at the start is a problem', () {
      const font =
          '$origin/fonts/fallback/roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2';
      final found = problems([request('1', font), response(font, 404)], origin);
      expect(found, ['HTTP 404: $font']);
    });

    test('#72/AK2 a request to a foreign host is a problem', () {
      const cdn = 'https://fonts.gstatic.com/s/roboto/v32/x.woff2';
      expect(problems([request('1', cdn)], origin), ['foreign request: $cdn']);
      // Another port on the same machine is another origin.
      expect(
        problems([request('1', 'http://127.0.0.1:9999/x')], origin),
        hasLength(1),
      );
    });

    test('a failed load names its URL, a cancelled one is no problem', () {
      final events = [
        request('1', '$origin/main.dart.js'),
        StartEvent('Network.loadingFailed', {
          'requestId': '1',
          'errorText': 'net::ERR_FAILED',
        }),
        request('2', '$origin/flutter.js'),
        StartEvent('Network.loadingFailed', {
          'requestId': '2',
          'errorText': 'net::ERR_ABORTED',
          'canceled': true,
        }),
      ];
      expect(problems(events, origin), [
        'load failed (net::ERR_FAILED): $origin/main.dart.js',
      ]);
    });

    test('exceptions, console errors and log errors are problems', () {
      final events = [
        StartEvent('Runtime.exceptionThrown', {
          'exceptionDetails': {
            'text': 'Uncaught',
            'exception': {'description': 'TypeError: x is null'},
          },
        }),
        StartEvent('Runtime.consoleAPICalled', {
          'type': 'error',
          'args': [
            {'value': 'broken'},
          ],
        }),
        StartEvent('Log.entryAdded', {
          'entry': {
            'level': 'error',
            'text': 'Failed to load resource',
            'url': '$origin/x',
          },
        }),
        StartEvent('Log.entryAdded', {
          'entry': {'level': 'warning', 'text': 'only a warning'},
        }),
      ];
      expect(problems(events, origin), [
        'exception: TypeError: x is null',
        'console error: broken',
        'log error: Failed to load resource $origin/x',
      ]);
    });
  });

  test('#72/AK2 pubspec declares Roboto as an alias of a bundled font', () {
    // Without a family named Roboto, Flutter's web engine downloads it from fontFallbackBaseUrl.
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final alias = RegExp(r'- family: Roboto\s+fonts:\s+- asset: (\S+)')
        .firstMatch(pubspec);
    expect(alias, isNotNull);
    final asset = alias!.group(1)!;
    expect(asset, startsWith('assets/fonts/inter/'));
    expect(File(asset).existsSync(), isTrue);
  });
}
