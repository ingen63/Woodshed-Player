// #13/AK2, AK7: the rules of the UI tests (integration_test/) and web tests (test/web/), checked in their
// source: wait for states, never for time; no time limit except the guard against a hang; every UI test
// fixes its language (startApp in ui_helpers.dart: English, or the pseudo language).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _dartFiles(String dir) =>
    Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart') && !f.path.contains('wp_core/'));

void main() {
  final files = [..._dartFiles('integration_test'), ..._dartFiles('test/web')];

  test('#13/AK2 no fixed waiting time in the UI and web tests', () {
    final waits = RegExp(
      r'pump\(\s*(const\s+)?Duration|pumpAndSettle\(\s*(const\s+)?Duration|'
      r'Future(<\w+>)?\.delayed|\bsleep\(|Timeout\(',
    );
    expect(files.length, greaterThanOrEqualTo(6));
    for (final f in files) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        expect(waits.hasMatch(line), isFalse, reason: '${f.path}:${i + 1}');
        // the only times: the guard against a hang, and the test's own tap clock
        if (line.contains('Duration(')) {
          expect(
            line.contains('hangGuard') || line.contains('now = now.add('),
            isTrue,
            reason: '${f.path}:${i + 1}',
          );
        }
      }
    }
  });

  test('#13/AK2 every wait in the UI tests goes through pumpUntil', () {
    final helpers = File('integration_test/ui_helpers.dart').readAsStringSync();
    expect(helpers, contains('Future<void> pumpUntil('));
    expect(helpers, contains('await tester.pump();')); // frame by frame
    expect(helpers, contains('watch.elapsed > hangGuard'));
  });

  test('#13/AK7 every UI test fixes its language', () {
    final helpers = File('integration_test/ui_helpers.dart').readAsStringSync();
    expect(helpers, contains("Locale locale = const Locale('en')"));
    expect(helpers, contains('locale: locale,'));
    final tests = _dartFiles('integration_test')
        .where((f) => f.path.endsWith('_test.dart'))
        .toList();
    expect(tests, hasLength(greaterThanOrEqualTo(3)));
    for (final f in tests) {
      final src = f.readAsStringSync();
      final starts = RegExp(r'pumpWidget\(|startApp\(').allMatches(src).length;
      final viaHelper = RegExp(r'startApp\(').allMatches(src).length;
      expect(
        starts,
        viaHelper,
        reason: '${f.path}: start the app with startApp',
      );
      expect(src, isNot(contains('Platform.localeName')), reason: f.path);
    }
    expect(
      File('integration_test/pseudo_locale_test.dart').readAsStringSync(),
      contains('l10n: const PseudoLocalizationsDelegate()'),
    );
  });
}
