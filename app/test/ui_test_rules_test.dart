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

final _realTimeWait = RegExp(r'Future(<\w+>)?\.delayed|\bsleep\(');
final _loopStart = RegExp(r'\b(for|while)\s*\(');

/// A real-time wait in [lines]: its line (1-based) and whether it sits inside a `for`/`while` loop without and with
/// `hangGuard` in the loop header.
typedef _Wait = ({int line, bool unguardedLoop, bool guardedLoop});

List<_Wait> _realTimeWaits(List<String> lines) {
  final waits = <_Wait>[];
  final loops = <(int, bool)>[]; // (brace depth before the loop, guarded)
  var depth = 0;
  String? header; // loop header until its `{`
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (header == null && _loopStart.hasMatch(line)) header = '';
    var unguardedHeader = false;
    if (header != null) {
      header += line;
      unguardedHeader = !header.contains('hangGuard');
      if (line.contains('{')) {
        loops.add((depth, !unguardedHeader));
        header = null;
      } else if (line.trimRight().endsWith(';') &&
          '('.allMatches(header).length == ')'.allMatches(header).length) {
        header = null; // loop without braces ends here
      }
    }
    if (_realTimeWait.hasMatch(line)) {
      waits.add((
        line: i + 1,
        unguardedLoop: unguardedHeader || loops.any((l) => !l.$2),
        guardedLoop: loops.any((l) => l.$2),
      ));
    }
    depth += '{'.allMatches(line).length - '}'.allMatches(line).length;
    loops.removeWhere((l) => depth <= l.$1);
  }
  return waits;
}

/// #78/AK2: lines (1-based) of [lines] that wait in real time inside a `for` or `while` loop whose header has no
/// `hangGuard`, i.e. a polling loop with a fixed number of rounds. Allowed is only the polling step of a wait for a
/// state bounded by `hangGuard` (`eventually`, `waitUntil` in fakes.dart).
List<int> fixedCountWaitLoops(List<String> lines) => [
  for (final w in _realTimeWaits(lines))
    if (w.unguardedLoop) w.line,
];

/// The justification a fixed real-time pause needs in its own line (#95/AK2): it watches that something stays out.
final _absenceReason = RegExp(r'// absence: \S');

/// #95/AK3: lines (1-based) of [lines] with a fixed real-time pause that is neither a single yield
/// (`Duration.zero`), nor the polling step of a wait bounded by `hangGuard`, nor justified in the same line with
/// `// absence: <what stays out>`.
List<int> unjustifiedFixedWaits(List<String> lines) {
  final hits = <int>[];
  for (final w in _realTimeWaits(lines)) {
    final line = lines[w.line - 1];
    // the statement up to its `;`, which may span lines
    var statement = line;
    for (var j = w.line; !statement.contains(';') && j < lines.length; j++) {
      statement += lines[j];
    }
    if (statement.contains('Duration.zero')) continue;
    if (w.guardedLoop && !w.unguardedLoop) continue;
    if (_absenceReason.hasMatch(line)) continue;
    hits.add(w.line);
  }
  return hits;
}

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

  group('#78/AK2 widget tests wait for states, not in fixed-count loops', () {
    test('no real-time polling loop without a hang guard under test/', () {
      final widgetTests = _dartFiles('test')
          .where((f) => !f.path.startsWith('test/web/'))
          // this file holds the old loops as text (regression case below)
          .where((f) => !f.path.endsWith('ui_test_rules_test.dart'))
          .toList();
      expect(widgetTests.length, greaterThanOrEqualTo(30));
      for (final f in widgetTests) {
        expect(
          fixedCountWaitLoops(f.readAsLinesSync()),
          isEmpty,
          reason: '${f.path}: wait with waitUntil/eventually (fakes.dart)',
        );
      }
    });

    test('the check finds the old loops (regression, #78)', () {
      // the former waits in home_page_test.dart and recording_test.dart
      const old = [
        'await tester.runAsync(() async {',
        '  for (var i = 0; i < 100 && app.library.tracks.isEmpty; i++) {',
        '    await Future<void>.delayed(const Duration(milliseconds: 5));',
        '  }',
        '});',
        'for (',
        '  var i = 0;',
        '  i < 200 && app.core.loadState != WpCode.loadRunning;',
        '  i++',
        ') {',
        '  await Future<void>.delayed(const Duration(milliseconds: 5));',
        '}',
        'for (var i = 0; i < 20; i++) {',
        '  app.finishLoads(30);',
        '  if (done) {',
        '    break;',
        '  }',
        '  await Future.delayed(const Duration(milliseconds: 5));',
        '}',
        'while (!done()) sleep(const Duration(milliseconds: 5));',
        'await Future<void>.delayed(Duration.zero);', // single yield, no loop
      ];
      expect(fixedCountWaitLoops(old), [3, 11, 18, 20]);
      const guarded = [
        'final watch = Stopwatch()..start();',
        'while (!done() && watch.elapsed < hangGuard) {',
        '  await Future<void>.delayed(const Duration(milliseconds: 5));',
        '}',
      ];
      expect(fixedCountWaitLoops(guarded), isEmpty);
      final fakes = File('test/fakes.dart').readAsStringSync();
      expect(fakes, contains('Future<void> eventually('));
      expect(fakes, contains('runAsync(() => eventually(done, what'));
    });
  });

  group('#95/AK3 a fixed real-time pause under test/ is justified', () {
    test('every fixed pause under test/ watches that something stays out', () {
      final all = _dartFiles('test')
          // this file holds the forbidden pauses as text (cases below)
          .where((f) => !f.path.endsWith('ui_test_rules_test.dart'))
          .toList();
      expect(all.length, greaterThanOrEqualTo(30));
      for (final f in all) {
        expect(
          unjustifiedFixedWaits(f.readAsLinesSync()),
          isEmpty,
          reason:
              '${f.path}: wait for a state with waitUntil/eventually (fakes.dart), '
              'or justify the pause in its line with «// absence: …»',
        );
      }
    });

    test('the check finds the former pauses and lets the allowed ones pass (counter-check)', () {
      // the former pauses (#95): sync_app_test.dart, library_rules_test.dart, file_store_test.dart,
      // appearance_test.dart
      const old = [
        'await Future<void>.delayed(const Duration(milliseconds: 100));',
        'await Future<void>.delayed(const Duration(milliseconds: 10));',
        'await Future<void>.delayed(const Duration(milliseconds: 60)); // wait',
        'Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));',
        'await Future<void>.delayed(',
        '  const Duration(milliseconds: 60),',
        '); // absence: the comment is not in the line of the pause',
        'sleep(const Duration(milliseconds: 5));',
        'await Future<void>.delayed(_quiet); // absence:',
      ];
      expect(unjustifiedFixedWaits(old), [1, 2, 3, 4, 5, 8, 9]);
      const allowed = [
        'await Future<void>.delayed(Duration.zero);',
        'Future<void> settle() => Future<void>.delayed(Duration.zero);',
        'await Future<void>.delayed(_quiet); // absence: no second save',
        'final watch = Stopwatch()..start();',
        'while (!done() && watch.elapsed < hangGuard) {',
        '  await Future<void>.delayed(const Duration(milliseconds: 5));',
        '}',
      ];
      expect(unjustifiedFixedWaits(allowed), isEmpty);
      // a guarded loop does not excuse a pause in an unguarded loop inside it
      const nested = [
        'while (!done() && watch.elapsed < hangGuard) {',
        '  for (var i = 0; i < 3; i++) {',
        '    await Future<void>.delayed(const Duration(milliseconds: 5));',
        '  }',
        '}',
      ];
      expect(unjustifiedFixedWaits(nested), [3]);
      // the real polling step in fakes.dart passes
      expect(
        unjustifiedFixedWaits(File('test/fakes.dart').readAsLinesSync()),
        isEmpty,
      );
    });
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
