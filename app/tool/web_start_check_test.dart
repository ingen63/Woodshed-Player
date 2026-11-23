// Tests of the start check of the web app (#72/AK3), the Roboto alias it relies on (#72/AK2) and the
// second start with titles Inter cannot draw (#82).
import 'dart:io';

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/device_settings.dart';
import 'package:woodshed_player/library/stamps.dart';
import 'package:woodshed_player/library/track.dart';

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

  group('fallback fonts (#82)', () {
    test('#82/AK1 the seeded device opens the library section (#123 collapses it by default)', () {
      // Same keys as the app writes for an open library section.
      expect(
        jsonDecode(seedDevice()),
        const DeviceSettings(
          deviceId: '0123456789abcdef',
          libraryOpen: true,
        ).toJson(),
      );
    });

    test(
      '#82/AK1 the seeded library is valid and holds CJK and emoji titles',
      () {
        final json = jsonDecode(seedLibrary()) as Map<String, Object?>;
        expect(json['formatVersion'], SharedState.formatVersion);
        final state = SharedState.fromJson(json);
        final titles = [
          for (final e in state.tracks.entries)
            Track.fromShared(e.key, e.value.values).title,
        ];
        expect(titles, fallbackTitles);
        // CJK ideographs and emoji: no glyph in Inter, so the engine looks for a fallback font.
        expect(
          titles.join().runes.any((r) => r >= 0x4E00 && r <= 0x9FFF),
          isTrue,
        );
        expect(titles.join().runes.any((r) => r >= 0x1F300), isTrue);
      },
    );

    test('#82/AK4 the engine looking for a fallback font is recognized', () {
      StartEvent console(String type, String text) =>
          StartEvent('Runtime.consoleAPICalled', {
            'type': type,
            'args': [
              {'value': text},
            ],
          });
      expect(fallbackFontRequested([console('log', 'hello')]), isFalse);
      final warning = console(
        'warning',
        'Permanent HTTP failure (status 410) for Noto Sans SC 1 at '
            'fonts/fallback/notosanssc/v40/x.woff2.',
      );
      expect(fallbackFontRequested([warning]), isTrue);
      // A warning is no problem of the start.
      expect(problems([warning], origin), isEmpty);
    });

    test('#82/AK1 the bootstrap answers fallback font requests itself', () {
      final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
      expect(bootstrap, contains("fontFallbackBaseUrl: 'fonts/fallback/'"));
      expect(
        bootstrap,
        contains("new URL('fonts/fallback/', document.baseURI)"),
      );
      expect(bootstrap, contains('new Response(null, { status: 410'));
      // The interception is installed before the engine loads.
      expect(
        bootstrap.indexOf('window.fetch ='),
        lessThan(bootstrap.indexOf('_flutter.loader.load(')),
      );
    });

    test('#82/AK2 no fallback font is bundled', () {
      expect(Directory('web/fonts/fallback').existsSync(), isFalse);
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.toLowerCase(), isNot(contains('noto')));
    });
  });
}
