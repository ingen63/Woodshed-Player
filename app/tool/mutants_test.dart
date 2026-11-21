// #11: tests of the mutation tools (tool/mutants.dart, tool/mutants_run.dart): Dart mutations only
// in code, test selection by imports, exclusions only with a reason, Mull reports, limits.
//
// Run: cd app && flutter test tool/mutants_test.dart   (or `make test-tools`)
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'mutants.dart';

/// The mutations of [source] as «mutator@line:column».
List<String> _sites(String source) => [
  for (final s in dartMutations(source)) '${s.mutator}@${s.line}:${s.column}',
];

Mutant _m(String file, int line, String mutator, String code, Outcome o) =>
    Mutant(
      part: 'core',
      file: file,
      line: line,
      column: 5,
      mutator: mutator,
      replacement: '',
      code: code,
      outcome: o,
    );

void main() {
  group('#11/AK1: Dart mutations', () {
    test(
      'comparisons and logic are mutated, type arguments and arrows not',
      () {
        const src = 'bool f(List<int> a) => a.length < 3 && a.first >= 0;\n';
        expect(_sites(src), [
          'dart_lt_to_le@1:33',
          'dart_and_to_or@1:37',
          'dart_ge_to_gt@1:48',
        ]);
        final lt = dartMutations(src).first;
        expect(lt.apply(src), contains('a.length <= 3'));
      },
    );

    test('nothing inside comments, strings and interpolations', () {
      const src =
          "// a < b\n"
          "/* x == y /* nested + */ - z */\n"
          "final s = 'a < b \${x + 1}';\n"
          "final r = r'c == d';\n"
          "final t = '''e && f''';\n"
          'final n = x + 1;\n';
      expect(_sites(src), ['dart_add_to_sub@6:13']);
    });

    test('prefix ! is removed, != and the null check x! stay', () {
      const src =
          'if (!done && x! != y) {}\n'
          'final v = !(a);\n';
      expect(_sites(src).where((s) => s.startsWith('dart_remove_negation')), [
        'dart_remove_negation@1:5',
        'dart_remove_negation@2:11',
      ]);
    });

    test('++, --, += and true/false', () {
      const src =
          'i++;\n'
          '--j;\n'
          'k += 2;\n'
          'final a = true;\n';
      expect(_sites(src), [
        'dart_inc_to_dec@1:2',
        'dart_dec_to_inc@2:1',
        'dart_add_assign_to_sub_assign@3:3',
        'dart_true_to_false@4:11',
      ]);
    });

    test('a call that is a statement of its own is removed', () {
      const src =
          'void f() {\n'
          '  notifyListeners();\n'
          '  final x = g(1);\n'
          '  _save(x);\n'
          '  return h();\n'
          '}\n';
      final calls = dartMutations(src)
          .where((s) => s.mutator == 'dart_remove_void_call')
          .toList();
      expect(calls.map((s) => s.line), [2, 4]);
      expect(calls.first.apply(src), contains('  {}\n'));
    });

    test('only Dart logic is in scope', () {
      expect(dartScopeExclusion('app/lib/time_format.dart', ''), isNull);
      expect(
        dartScopeExclusion(
          'app/lib/ui/x.dart',
          "import 'package:flutter/material.dart';",
        ),
        contains('UI'),
      );
      expect(
        dartScopeExclusion('app/lib/player/audio_core_web.dart', ''),
        contains('web'),
      );
      expect(dartScopeExclusion('app/lib/main.dart', ''), isNotNull);
      expect(
        dartScopeExclusion('app/lib/l10n/app_localizations.dart', ''),
        isNotNull,
      );
    });
  });

  group('#11/AK3: test selection by imports', () {
    test(
      'the closest tests: direct importers first, then one step further',
      () {
        final graph = importGraph({
          'lib/a.dart': "import 'b.dart';\n",
          'lib/b.dart': "import 'c_io.dart'\n    if (dart.library.js_interop) 'c_web.dart';\n",
          'lib/c_io.dart': '',
          'lib/c_web.dart': '',
          'lib/d.dart': '',
          'test/a_test.dart': "import 'package:woodshed_player/a.dart';\n",
          'test/other_test.dart': "import '../lib/c_io.dart';\n",
          'test/none_test.dart': "import 'dart:io';\n",
        });
        final tests = [
          'test/a_test.dart',
          'test/none_test.dart',
          'test/other_test.dart',
        ];
        // b.dart: only a_test reaches it (through a.dart)
        expect(testsFor('lib/b.dart', graph, tests), ['test/a_test.dart']);
        // conditional import: c_web.dart is reached through b.dart and a.dart
        expect(testsFor('lib/c_web.dart', graph, tests), ['test/a_test.dart']);
        // c_io.dart: other_test imports it directly, a_test only through two files
        expect(testsFor('lib/c_io.dart', graph, tests), [
          'test/other_test.dart',
        ]);
        expect(testsFor('lib/d.dart', graph, tests), isEmpty);
      },
    );
  });

  group('#11/AK2: exclusions need a reason', () {
    test('entries with a reason, shared by the entries below', () {
      final list = parseExclusions(
        '# header without a reason\n'
        '\n'
        '# gleichwertig: x is never negative here,\n'
        '# so both branches give 0.\n'
        'core/src/a.cpp | cxx_lt_to_le | if (x < 0)\n'
        'core/src/a.cpp | cxx_gt_to_ge | if (x > 0)\n'
        '\n'
        '# Grenzfall: exactly 1 s.\n'
        'app/lib/b.dart | dart_ge_to_gt | if (d >= 1000) {\n',
      );
      expect(list.map((e) => e.mutator), [
        'cxx_lt_to_le',
        'cxx_gt_to_ge',
        'dart_ge_to_gt',
      ]);
      expect(list.first.reason, startsWith('gleichwertig: x is never'));
      expect(list.first.reason, endsWith('both branches give 0.'));
      expect(list[1].reason, list.first.reason);
      expect(list.last.reason, 'Grenzfall: exactly 1 s.');
    });

    test(
      '#61/AK3 the two kinds of the core: memory release and Mull\'s limit',
      () {
        final list = parseExclusions(
          '# Speicherfreigabe: frees a replaced title, nothing else changes.\n'
          'core/src/a.cpp | cxx_remove_void_call | collectGarbage();\n'
          '\n'
          '# Mull-Grenze: measured, the mutant has no effect.\n'
          'core/src/a.cpp | cxx_remove_void_call | cancelLoad();\n',
        );
        expect(list.first.reason, startsWith('Speicherfreigabe: frees'));
        expect(list.last.reason, startsWith('Mull-Grenze: measured'));
        expect(
          () => parseExclusions('# Leck: no\ncore/src/a.cpp | m | free(p);\n'),
          throwsFormatException,
        );
      },
    );

    test('an entry without a reason is an error', () {
      expect(
        () => parseExclusions('core/src/a.cpp | cxx_lt_to_le | if (x < 0)\n'),
        throwsFormatException,
      );
      expect(
        () => parseExclusions(
          '# just a comment\ncore/src/a.cpp | cxx_lt_to_le | if (x < 0)\n',
        ),
        throwsFormatException,
      );
      // the reason ends at an empty line
      expect(
        () => parseExclusions('# gleichwertig: a\nx | y | z\n\nx | y | w\n'),
        throwsFormatException,
      );
      expect(
        () => parseExclusions('# Grenzfall: a\nonly two | parts\n'),
        throwsFormatException,
      );
    });

    test('matched by file, mutator and source line, not by line number', () {
      final mutants = [
        _m(
          'core/src/a.cpp',
          40,
          'cxx_lt_to_le',
          'if (x  <  0)',
          Outcome.survived,
        ),
        _m(
          'core/src/a.cpp',
          41,
          'cxx_lt_to_le',
          'if (y < 0)',
          Outcome.survived,
        ),
        _m('core/src/a.cpp', 42, 'cxx_lt_to_le', 'if (x < 0)', Outcome.killed),
      ];
      final ex = parseExclusions(
        '# gleichwertig: x >= 0\ncore/src/a.cpp | cxx_lt_to_le | if (x < 0)\n',
      );
      expect(applyExclusions(mutants, ex), 1);
      expect(mutants.map((m) => m.outcome), [
        Outcome.excluded,
        Outcome.survived,
        Outcome.killed,
      ]);
      expect(mutants.first.note, 'gleichwertig: x >= 0');
      expect(ex.single.used, 1);
    });

    test(
      'a column picks one of two operators on the line; «||» stays in the line',
      () {
        final ex = parseExclusions(
          '# Grenzfall: only the second\n'
          'core/src/a.cpp | cxx_lt_to_le | if (a < b || c < d) | 20\n',
        );
        expect(ex.single.code, 'if (a < b || c < d)');
        expect(ex.single.column, 20);
        Mutant at(int column) => Mutant(
          part: 'core',
          file: 'core/src/a.cpp',
          line: 3,
          column: column,
          mutator: 'cxx_lt_to_le',
          replacement: '<=',
          code: 'if (a < b || c < d)',
        );
        final ms = [at(9), at(20)];
        expect(applyExclusions(ms, ex), 1);
        expect(ms.map((m) => m.outcome), [Outcome.survived, Outcome.excluded]);
      },
    );
  });

  group('#11/AK1: Mull reports', () {
    String report(String status) => jsonEncode({
      'files': {
        '/repo/core/src/engine.cpp': {
          'mutants': [
            {
              'mutatorName': 'cxx_lt_to_le',
              'replacement': '<=',
              'location': {
                'start': {'line': 7, 'column': 9},
              },
              'status': status,
            },
          ],
        },
      },
    });

    test('paths relative to the repository, outcomes mapped', () {
      final ms = parseMullReport(report('NoCoverage'), [
        '/repo',
      ], (f, l) => '$f@$l');
      expect(ms.single.file, 'core/src/engine.cpp');
      expect(ms.single.code, 'core/src/engine.cpp@7');
      expect(ms.single.outcome, Outcome.survived);
      expect(ms.single.note, 'not covered');
      expect(
        parseMullReport(report('Timeout'), [
          '/repo',
        ], (f, l) => '').single.outcome,
        Outcome.timeout,
      );
    });

    test('a mutant counts as detected if one test program detects it', () {
      final a = parseMullReport(report('Survived'), ['/repo'], (f, l) => '');
      final b = parseMullReport(report('Killed'), ['/repo'], (f, l) => '');
      final c = parseMullReport(report('Timeout'), ['/repo'], (f, l) => '');
      expect(mergeMutants([...a, ...b, ...c]).single.outcome, Outcome.killed);
      expect(mergeMutants([...a, ...c]).single.outcome, Outcome.timeout);
      expect(mergeMutants(a).single.outcome, Outcome.survived);
    });

    test('a mutant no program executes is «not covered», one executed only «not detected»', () {
      Mutant listed() =>
          parseMullReport(report('Killed'), ['/repo'], (f, l) => '').single
            ..outcome = Outcome.survived
            ..note = notCovered;
      final ran = parseMullReport(report('Survived'), ['/repo'], (f, l) => '');
      expect(mergeMutants([listed()]).single.note, notCovered);
      expect(mergeMutants([listed(), ...ran]).single.note, isNull);
      expect(mergeMutants([...ran, listed()]).single.note, isNull);
      final killed = parseMullReport(report('Killed'), ['/repo'], (f, l) => '');
      expect(
        mergeMutants([listed(), ...killed]).single.outcome,
        Outcome.killed,
      );
    });
  });

  group('#11/AK4: time and memory limit', () {
    final dir = Directory.systemTemp.path;
    test('an endless loop ends as timeout', () async {
      final r = await runLimited(
        'sh',
        ['-c', 'while :; do :; done'],
        workingDirectory: dir,
        timeout: const Duration(seconds: 1),
        memoryMiB: 1024,
      );
      expect(r.end, RunEnd.timeout);
      expect(r.elapsed, lessThan(const Duration(seconds: 5)));
      expect(dartOutcome(r).$1, Outcome.timeout);
    });

    test('growing memory in a child process ends the whole tree', () async {
      // perl in a child of sh grows to about 600 MiB and then waits; the limit is 200 MiB
      final r = await runLimited(
        'sh',
        [
          '-c',
          r'perl -e "\$x = q(a) x (600 * 1024 * 1024); sleep 60"; echo done',
        ],
        workingDirectory: dir,
        timeout: const Duration(seconds: 30),
        memoryMiB: 200,
        poll: const Duration(milliseconds: 50),
      );
      expect(r.end, RunEnd.memory);
      expect(r.output, isNot(contains('done')));
      expect(r.elapsed, lessThan(const Duration(seconds: 20)));
      expect(dartOutcome(r), (Outcome.killed, 'memory limit'));
    });

    test('passed, failed and compile errors', () async {
      final ok = await runLimited(
        'sh',
        ['-c', 'exit 0'],
        workingDirectory: dir,
        timeout: const Duration(seconds: 10),
        memoryMiB: 1024,
      );
      expect(dartOutcome(ok).$1, Outcome.survived);
      final failed = RunResult(
        RunEnd.failed,
        'Some tests failed.',
        Duration.zero,
        0,
      );
      expect(dartOutcome(failed).$1, Outcome.killed);
      final compile = RunResult(
        RunEnd.failed,
        "lib/time_format.dart:12:20: Error: The operator '-' isn't defined",
        Duration.zero,
        0,
      );
      expect(dartOutcome(compile).$1, Outcome.unviable);
    });
  });

  group('#103/AK1: output of a failed original test', () {
    test('only a failed original test is recognised', () {
      expect(
        originalTestFailed(
          '[error] Original test failed (warmup run)\nstatus: Failed\nstdout: \'\'\n',
        ),
        isTrue,
      );
      expect(
        originalTestFailed(
          '[info] No mutants found. Mutation score: infinitely high',
        ),
        isFalse,
      );
    });

    test(
      'the run again shows how it ended and the end of its output',
      () async {
        final dir = Directory.systemTemp.createTempSync('mutants_original_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final r = await runLimited(
          'sh',
          [
            '-c',
            'for i in 1 2 3 4 5; do echo "line \$i"; done; echo "FAIL last" >&2; exit 7',
          ],
          workingDirectory: dir.path,
          timeout: const Duration(seconds: 10),
          memoryMiB: 1024,
        );
        expect(r.end, RunEnd.failed);
        expect(r.exitCode, 7);
        final report = originalTestReport(
          'build/player_tests',
          ['--x'],
          r,
          lines: 3,
        );
        expect(report, contains('build/player_tests --x'));
        expect(report, contains('exit code 7'));
        expect(report, contains('last 3 of 6 lines'));
        expect(report, contains('FAIL last'));
        expect(report, isNot(contains('line 1')));
      },
    );

    test('a signal, the time and the memory limit are named', () {
      String how(RunEnd end, int? code) => originalTestReport(
        'p',
        const [],
        RunResult(end, 'x', Duration.zero, 2048, exitCode: code),
      ).split('\n')[1];
      expect(how(RunEnd.failed, -11), startsWith('ended by signal 11'));
      expect(how(RunEnd.timeout, -9), startsWith('time limit reached'));
      expect(
        how(RunEnd.memory, -9),
        startsWith('memory limit reached (2048 MiB)'),
      );
      expect(how(RunEnd.failed, null), startsWith('exit code unknown'));
    });
  });

  group('#11/AK5: summary with file and line', () {
    test('counts per part and every not detected mutant', () {
      final ms = [
        _m(
          'core/src/engine.cpp',
          7,
          'cxx_lt_to_le',
          'if (a < b)',
          Outcome.survived,
        ),
        _m('core/src/engine.cpp', 9, 'cxx_add_to_sub', 'x + 1', Outcome.killed),
        Mutant(
          part: 'dart',
          file: 'app/lib/time_format.dart',
          line: 3,
          column: 1,
          mutator: 'dart_true_to_false',
          replacement: 'false',
          code: 'return true;',
          outcome: Outcome.timeout,
        ),
      ];
      final text = summaryText(ms, title: 'T');
      expect(
        text,
        contains('core: 2 mutants: 1 killed, 0 timeout, 1 not detected'),
      );
      expect(text, contains('dart: 1 mutants: 0 killed, 1 timeout'));
      expect(
        text,
        contains('core/src/engine.cpp:7:5: cxx_lt_to_le | if (a < b)'),
      );
      expect(exitCodeFor(ms), 3);
      expect(exitCodeFor(ms.sublist(1)), 0);
    });
  });
}
