// #46: Error texts of the core and the Dart binding are English and for logs only; the UI shows ARB texts.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/player/audio_core.dart';
import 'package:woodshed_player/ui/messages.dart';
import 'package:woodshed_player/ui/player_view.dart';
import 'package:woodshed_player/ui/style.dart';
import 'package:wp_core/wp_core.dart';

import 'fakes.dart';

const _germanWords = [
  'datei',
  'fehler',
  'nicht',
  'kein',
  'konnte',
  'geladen',
  'angelegt',
  'speicher',
  'audio-kern',
];

void main() {
  test('#46/AK2: WpException texts in wp_core.dart are English', () {
    final binding = File('packages/wp_core/lib/wp_core.dart').readAsStringSync();
    final texts = RegExp(r"WpException\('([^']*)'\)")
        .allMatches(binding)
        .map((m) => m.group(1)!)
        .toList();
    expect(texts, hasLength(2));
    for (final t in texts) {
      expect(t.runes.every((r) => r >= 0x20 && r <= 0x7e), isTrue, reason: t);
      for (final w in _germanWords) {
        expect(t.toLowerCase(), isNot(contains(w)), reason: t);
      }
    }
  });

  test('#46/AK3: the UI never shows core error texts or WpException.message', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final src = f.readAsStringSync();
      for (final pattern in [
        'WpException',
        'WpPlayer.errorMessage',
        'wp_error_message',
        '.errorMessage(',
      ]) {
        if (src.contains(pattern)) offenders.add('${f.path}: $pattern');
      }
    }
    expect(offenders, isEmpty);
  });

  testWidgets('#46/AK3: a load error shows the ARB text, not the core text', (
    tester,
  ) async {
    const error = LoadError(WpCode.fileNotFound, 'gone.mp3');
    await tester.pumpWidget(
      MaterialApp(
        locale: testLocale,
        localizationsDelegates: testDelegates,
        supportedLocales: testLocales,
        theme: woodshedTheme(Brightness.light),
        home: Scaffold(
          body: PlayerView(
            state: const PlayerViewState(error: error),
            actions: PlayerViewActions(
              open: () {},
              playPause: () {},
              seek: (_) {},
              volume: (_) {},
              speedOn: (_) {},
              speed: (_) {},
              loopOn: (_) {},
              loopEnd: (_) {},
              loopStart: (_) {},
            ),
          ),
        ),
      ),
    );
    expect(find.text(loadErrorMessage(de, error)), findsOneWidget);
    expect(find.textContaining('File not found'), findsNothing);
    expect(find.textContaining('Could not load file'), findsNothing);
  });
}
