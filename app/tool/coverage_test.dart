// #8/AK6: tests of the coverage check (tool/coverage_check.dart) and of coverage-diff
// (tool/coverage_diff.dart) with staged inputs: lcov files, diffs, minimum reached and missed.
//
// The pure functions are tested directly; the command line tools run with `dart` in a temporary
// directory or git repository.
//
// Run: cd app && flutter test tool/coverage_test.dart   (or `make test-tools`)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'coverage.dart';

final _tool = Directory('${Directory.current.path}/tool').absolute.path;

/// lcov record with the given line -> hits.
String _lcov(String path, Map<int, int> hits) {
  final b = StringBuffer('SF:$path\n');
  hits.forEach((n, h) => b.writeln('DA:$n,$h'));
  b.writeln('LF:${hits.length}');
  b.writeln('end_of_record');
  return b.toString();
}

/// [covered] of [total] lines run.
Map<int, int> _hits(int covered, int total) => {
  for (var i = 1; i <= total; i++) i: i <= covered ? 3 : 0,
};

const _logicSource = 'int twice(int x) => 2 * x;\n';
const _uiSource =
    "import 'package:flutter/widgets.dart';\n"
    'class V extends StatelessWidget {}\n';

/// Report text with runs of spaces reduced to one (the columns are padded).
String _squash(Object? text) => '$text'.replaceAll(RegExp(' +'), ' ');

ProcessResult _dart(List<String> args, String dir) =>
    Process.runSync('dart', args, workingDirectory: dir);

void main() {
  group('#8/AK1 lcov and parts', () {
    test('lcov paths become repository paths, hits are merged per line', () {
      final data = parseLcov(
        'SF:lib/a.dart\nDA:1,0\nDA:2,5\nDA:1,2\nend_of_record\n'
        'SF:/repo/core/src/e.cpp\nDA:7,0\nend_of_record\n',
        root: '/repo',
        prefix: 'app/',
      );
      expect(data.keys, ['app/lib/a.dart', 'core/src/e.cpp']);
      expect(data['app/lib/a.dart'], {1: 2, 2: 5}); // line 1: max(0, 2)
      expect(data['core/src/e.cpp'], {7: 0});
    });

    test('llvm-cov counters beyond 64 bits count as run', () {
      final data = parseLcov(
        'SF:/r/core/src/q.hpp\nDA:3,18446744073709550127\n',
        root: '/r',
      );
      expect(data['core/src/q.hpp']![3], greaterThan(0));
      expect(() => parseLcov('SF:x\nDA:3,abc\n'), throwsFormatException);
    });

    test('files are sorted into parts', () {
      expect(classify('core/src/engine.cpp', ''), Part.core);
      expect(classify('core/include/wp_core.h', ''), Part.core);
      expect(
        classify('app/lib/library/library.dart', _logicSource),
        Part.dartLogic,
      );
      expect(classify('app/lib/ui/style.dart', _logicSource), Part.dartUi);
      expect(classify('app/lib/main.dart', _logicSource), Part.dartUi);
      // A widget outside lib/ui is UI as well (e.g. metronome_panel.dart).
      expect(classify('app/lib/metronome/panel.dart', _uiSource), Part.dartUi);
      expect(
        classify('app/lib/x/state.dart', 'class _S extends State<W> {}'),
        Part.dartUi,
      );
      expect(classify('app/lib/app/file_store_web.dart', ''), Part.dartWeb);
      expect(
        classify('app/lib/app/bridge.dart', "import 'package:web/web.dart';"),
        Part.dartWeb,
      );
      expect(
        classify('app/lib/app/js.dart', "import 'dart:js_interop';"),
        Part.dartWeb,
      );
      expect(
        classify('app/lib/l10n/app_localizations_de.dart', ''),
        Part.generated,
      );
      expect(classify('app/test/a_test.dart', ''), Part.other);
    });

    test('declarations only: constants without code', () {
      expect(
        declarationsOnly("// x()\nconst a = 'b';\nconst c = '\${a}d';\n"),
        isTrue,
      );
      expect(declarationsOnly(_logicSource), isFalse);
    });

    test('declarations only: an abstract interface without bodies', () {
      expect(
        declarationsOnly(
          '// x\nabstract class A {\n  /// Doc (y).\n  Future<Uri?> f(Uri u, String s);\n\n'
          '  Future<void> g();\n}\n',
        ),
        isTrue,
      );
      expect(
        declarationsOnly('abstract class A {\n  int f() => 1;\n}\n'),
        isFalse,
      );
      expect(
        declarationsOnly(
          'abstract class A {\n  void f() {\n    g();\n  }\n}\n',
        ),
        isFalse,
      );
      expect(
        declarationsOnly(
          'abstract class A {\n  void f();\n}\nfinal a = b();\n',
        ),
        isFalse,
      );
      expect(
        declarationsOnly(
          'abstract class A {\n  A();\n  void f();\n}\nclass B {\n}\n',
        ),
        isFalse,
      );
    });

    test('#154/AK1: a one-line typedef is a declaration', () {
      expect(
        declarationsOnly(
          "import 'package:flutter/widgets.dart';\n\n"
          'abstract interface class A implements Listenable {\n'
          '  bool get on;\n  Future<void> f();\n}\n\n'
          'typedef Slot = ({A a, Widget widget});\n'
          'typedef Cb = void Function(int x);\n',
        ),
        isTrue,
      );
    });

    test('#154/AK2: a typedef next to code is not declarations only', () {
      expect(
        declarationsOnly('typedef Cb = void Function(int x);\nint f() => 1;\n'),
        isFalse,
      );
      expect(
        declarationsOnly(
          'typedef Slot = ({int a, int b});\nfinal s = (a: 1, b: g());\n',
        ),
        isFalse,
      );
    });

    test('the report shows UI, web and generated files apart from the parts with a minimum', () {
      final e = evaluate(
        min: 80,
        coverage: {
          'core/src/e.cpp': _hits(9, 10),
          'app/lib/a.dart': _hits(17, 20),
          'app/lib/ui/v.dart': _hits(1, 4),
        },
        sources: {
          'app/lib/a.dart': _logicSource,
          'app/lib/ui/v.dart': _uiSource,
          'app/lib/x_web.dart': _logicSource,
          'app/lib/l10n/app_localizations.dart': _logicSource,
        },
      );
      final text = report(e);
      expect(
        _squash(text),
        contains('C++ core (core/) 90.0 % (9 of 10 lines) ok'),
      );
      expect(
        _squash(text),
        contains('Dart logic (app/lib) 85.0 % (17 of 20 lines) ok'),
      );
      expect(
        _squash(text),
        contains('Dart UI (app/lib) 25.0 % (1 of 4 lines) shown, no minimum'),
      );
      expect(
        text,
        contains(
          'not measurable in the VM (docs/TESTS.md): app/lib/x_web.dart',
        ),
      );
      expect(
        text,
        contains('Generated, not counted: app/lib/l10n/app_localizations.dart'),
      );
      expect(text, contains('Every part reaches the minimum.'));
    });
  });

  group('#8/AK2 minimum per part', () {
    test('the minimum is a percentage', () {
      expect(parseMinimum('80\n'), 80);
      expect(parseMinimum('72.5'), 72.5);
      expect(() => parseMinimum(''), throwsFormatException);
      expect(() => parseMinimum('120'), throwsFormatException);
    });

    CoverageResult eval({
      required Map<int, int> core,
      required Map<int, int> logic,
      double min = 80,
      Map<String, String> extraSources = const {},
    }) => evaluate(
      min: min,
      coverage: {'core/src/e.cpp': core, 'app/lib/a.dart': logic},
      sources: {'app/lib/a.dart': _logicSource, ...extraSources},
    );

    test('exactly the minimum passes (4 of 5 = 80 %)', () {
      expect(eval(core: _hits(4, 5), logic: _hits(8, 10)).failures, isEmpty);
    });

    test('each part on its own: a high core does not lift a low logic part', () {
      // Together 99 of 110 lines = 90 %, but the logic part has 3 of 10 = 30 %.
      final f = eval(core: _hits(96, 100), logic: _hits(3, 10)).failures;
      expect(f, ['Dart logic (app/lib): 30.0 % is below 80.0 %']);
    });

    test(
      'a low core part fails, with the same data a lower minimum passes',
      () {
        final core = _hits(7, 10);
        expect(eval(core: core, logic: _hits(10, 10)).failures, [
          'C++ core (core/): 70.0 % is below 80.0 %',
        ]);
        expect(
          eval(core: core, logic: _hits(10, 10), min: 70).failures,
          isEmpty,
        );
      },
    );

    test('UI and web have no minimum', () {
      final e = evaluate(
        min: 80,
        coverage: {
          'core/src/e.cpp': _hits(1, 1),
          'app/lib/a.dart': _hits(1, 1),
          'app/lib/ui/v.dart': _hits(0, 50),
        },
        sources: {
          'app/lib/a.dart': _logicSource,
          'app/lib/ui/v.dart': _uiSource,
          'app/lib/p_web.dart': _logicSource,
        },
      );
      expect(e.failures, isEmpty);
      expect(e.results[Part.dartUi]!.percent, 0);
    });

    test('a logic file that no test loads fails; constants only do not', () {
      final f = eval(
        core: _hits(1, 1),
        logic: _hits(1, 1),
        extraSources: {
          'app/lib/unused.dart': _logicSource,
          'app/lib/info.dart': "const version = '1.0.0';\n",
        },
      ).failures;
      expect(f, [
        'Dart logic (app/lib): app/lib/unused.dart is not loaded by any test',
      ]);
    });

    test('a part without data fails', () {
      final e = evaluate(
        min: 80,
        coverage: {'app/lib/a.dart': _hits(1, 1)},
        sources: {'app/lib/a.dart': _logicSource},
      );
      expect(e.failures, ['C++ core (core/): no coverage data']);
    });

    group(
      'coverage_check.dart reads tools/coverage-min and both lcov files',
      () {
        late Directory root;

        void stage({required String min, required int coreCovered}) {
          File('${root.path}/tools/coverage-min')
            ..createSync(recursive: true)
            ..writeAsStringSync('$min\n');
          File('${root.path}/$dartLcov')
            ..createSync(recursive: true)
            ..writeAsStringSync(_lcov('lib/a.dart', _hits(9, 10)));
          File('${root.path}/$coreLcov')
            ..createSync(recursive: true)
            ..writeAsStringSync(
              _lcov('${root.path}/core/src/e.cpp', _hits(coreCovered, 10)),
            );
          File('${root.path}/app/lib/a.dart')
            ..createSync(recursive: true)
            ..writeAsStringSync(_logicSource);
        }

        setUp(() async {
          root = Directory(
            (await Directory.systemTemp.createTemp('wp_cov'))
                .resolveSymbolicLinksSync(),
          );
        });
        tearDown(() => root.deleteSync(recursive: true));

        test('minimum reached: exit code 0', () {
          stage(min: '80', coreCovered: 8);
          final r = _dart([
            '$_tool/coverage_check.dart',
            '--root',
            root.path,
          ], root.path);
          expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
          expect(
            _squash(r.stdout),
            contains('C++ core (core/) 80.0 % (8 of 10 lines) ok'),
          );
          expect(
            _squash(r.stdout),
            contains('Dart logic (app/lib) 90.0 % (9 of 10 lines) ok'),
          );
        });

        test('minimum missed: exit code 1 with the part and its share', () {
          stage(min: '85', coreCovered: 8);
          final r = _dart([
            '$_tool/coverage_check.dart',
            '--root',
            root.path,
          ], root.path);
          expect(r.exitCode, 1);
          expect(
            '${r.stdout}',
            contains('(minimum 85.0 % from tools/coverage-min)'),
          );
          expect(
            '${r.stdout}',
            contains('C++ core (core/): 80.0 % is below 85.0 %'),
          );
        });

        test('missing coverage data: exit code 2', () {
          stage(min: '80', coreCovered: 8);
          File('${root.path}/$coreLcov').deleteSync();
          final r = _dart([
            '$_tool/coverage_check.dart',
            '--root',
            root.path,
          ], root.path);
          expect(r.exitCode, 2);
          expect(
            '${r.stderr}',
            contains('coverage file missing, run make coverage'),
          );
        });
      },
    );
  });

  group('#8/AK3 coverage of the changed lines', () {
    test('changed lines from git diff -U0', () {
      const diff = '''
diff --git a/app/lib/a.dart b/app/lib/a.dart
--- a/app/lib/a.dart
+++ b/app/lib/a.dart
@@ -3 +3 @@ x
-old
+new
@@ -10,0 +11,3 @@
+a
+b
+c
diff --git a/core/src/gone.cpp b/core/src/gone.cpp
--- a/core/src/gone.cpp
+++ /dev/null
@@ -1,2 +0,0 @@
diff --git a/core/src/e.cpp b/core/src/e.cpp
--- a/core/src/e.cpp
+++ b/core/src/e.cpp
@@ -5,2 +4,0 @@
''';
      expect(changedLines(diff), {
        'app/lib/a.dart': {3, 11, 12, 13},
      });
    });

    test('line ranges', () {
      expect(lineRanges([7, 3, 5, 6]), '3, 5–7');
      expect(lineRanges([1]), '1');
    });

    test('share of the changed executable lines and the lines not covered', () {
      final text = diffReport(
        {
          'app/lib/a.dart': {1, 2, 3, 4, 9},
          'core/src/e.cpp': {20},
        },
        {
          // line 4 is not executable (no DA), 9 is a comment outside the data
          'app/lib/a.dart': {1: 1, 2: 0, 3: 0, 5: 1},
          'core/src/e.cpp': {20: 4},
        },
        base: 'origin/main',
      );
      // 4 executable changed lines (1, 2, 3, 20), 2 run: 50 %.
      expect(
        text,
        contains('### Coverage of the changed code (base origin/main)'),
      );
      expect(
        text,
        contains(
          '**50.0 %** of the changed executable lines are run by tests (2 of 4)',
        ),
      );
      expect(text, contains('- `app/lib/a.dart`: 2–3'));
      expect(text, isNot(contains('core/src/e.cpp`:')));
    });

    test('everything covered, nothing executable, nothing changed', () {
      expect(
        diffReport(
          {
            'a.dart': {1},
          },
          {
            'a.dart': {1: 2},
          },
          base: 'b',
        ),
        contains('Every changed executable line is covered.'),
      );
      expect(
        diffReport(
          {
            'a.dart': {1},
          },
          {},
          base: 'b',
        ),
        contains('No changed executable lines'),
      );
      expect(
        diffReport({}, {}, base: 'b'),
        contains('No changed source files.'),
      );
    });

    group('coverage_diff.dart in a git repository', () {
      late Directory root;

      void git(List<String> args) {
        final r = Process.runSync('git', args, workingDirectory: root.path);
        if (r.exitCode != 0) throw StateError('git $args: ${r.stderr}');
      }

      void write(String rel, String text) => File('${root.path}/$rel')
        ..createSync(recursive: true)
        ..writeAsStringSync(text);

      setUp(() async {
        root = Directory(
          (await Directory.systemTemp.createTemp('wp_cov_diff'))
              .resolveSymbolicLinksSync(),
        );
        git(['init', '-q']);
        git(['config', 'user.email', 'test@example.invalid']);
        git(['config', 'user.name', 'Test']);
        git(['config', 'commit.gpgsign', 'false']);
        write('app/lib/a.dart', 'l1\nl2\nl3\n');
        write('core/src/e.cpp', 'c1\nc2\n');
        write('docs/x.md', 'text\n');
        git(['add', '-A']);
        git(['commit', '-q', '-m', 'Start (#1)']);
        git(['tag', 'base']);
      });
      tearDown(() => root.deleteSync(recursive: true));

      test(
        'commits and working tree since the base, a hint with exit code 0',
        () {
          // Committed: line 2 of a.dart and line 3 (new) of e.cpp; uncommitted: line 4 of a.dart.
          write('app/lib/a.dart', 'l1\nL2\nl3\n');
          write('core/src/e.cpp', 'c1\nc2\nc3\n');
          write('docs/x.md', 'changed\n');
          git(['commit', '-q', '-am', 'Change (#1)']);
          write('app/lib/a.dart', 'l1\nL2\nl3\nl4\n');
          write(dartLcov, _lcov('lib/a.dart', {1: 1, 2: 1, 3: 1, 4: 0}));
          write(coreLcov, _lcov('${root.path}/core/src/e.cpp', {1: 1, 3: 0}));
          final r = _dart([
            '$_tool/coverage_diff.dart',
            '--base',
            'base',
            '--root',
            root.path,
          ], root.path);
          expect(r.exitCode, 0, reason: '${r.stderr}');
          // Changed executable: a.dart 2 (run), 4 (not run); e.cpp 3 (not run): 1 of 3.
          expect('${r.stdout}', contains('**33.3 %**'));
          expect('${r.stdout}', contains('(1 of 3)'));
          expect('${r.stdout}', contains('- `app/lib/a.dart`: 4'));
          expect('${r.stdout}', contains('- `core/src/e.cpp`: 3'));
          expect('${r.stdout}', isNot(contains('docs/x.md')));
        },
      );

      test('an unknown base is wrong usage (exit code 2)', () {
        final r = _dart([
          '$_tool/coverage_diff.dart',
          '--base',
          'nope',
          '--root',
          root.path,
        ], root.path);
        expect(r.exitCode, 2);
        expect('${r.stderr}', contains('base "nope" not found'));
      });
    });
  });
}
