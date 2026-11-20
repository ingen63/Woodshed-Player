// #12: tests of the overview page «Testqualität» (tool/report/report.dart, report_run.dart): status
// rules per layer, marks of the tests, check comments, history, missing data, the page offline.
//
// Run: cd app && flutter test tool/report/report_test.dart   (or `make test-tools`)
// Issues with German check comments: tool/report/testdata/issues.json (numbers from 901, made up).
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../coverage.dart';
import 'report.dart';

final _t = Texts.parse(File('tool/report/texts_de.json').readAsStringSync());

List<Map<String, Object?>> _issues() => [
  for (final i in jsonDecode(
    File('tool/report/testdata/issues.json').readAsStringSync(),
  ) as List<Object?>)
    (i! as Map).cast<String, Object?>(),
];

Map<String, Object?> _issue(int n) =>
    _issues().firstWhere((i) => i['number'] == n);

ReportInput _input({
  List<JUnitSource> junit = const [],
  CoverageData? coverage,
  MutantsData? mutants,
  List<Map<String, Object?>>? issues,
  Map<Criterion, List<String>> marks = const {},
}) => ReportInput(
  version: '1.0.0',
  commit: 'abc1234',
  generated: DateTime(2026, 11, 20, 9, 30),
  junit: junit,
  coverage: coverage,
  mutantsFull: mutants,
  issues: issues,
  marks: marks,
);

CoverageData _cov(
  double core,
  double logic, {
  List<String> unloaded = const [],
}) => CoverageData(
  min: 80,
  parts: {
    Part.core: (percent: core, lines: 100, covered: core.round()),
    Part.dartLogic: (percent: logic, lines: 100, covered: logic.round()),
    Part.dartUi: (percent: 50, lines: 10, covered: 5),
  },
  unloaded: unloaded,
);

MutantsData _mut(int survived) => MutantsData(
  mode: 'full',
  counts: {
    'core': {'killed': 10, 'survived': survived},
  },
  missed: [for (var i = 0; i < survived; i++) 'core/src/a.cpp:$i:1: x | y'],
);

/// The status badge of a layer in the page («<h2>title <span class="badge key">…»).
String? _badge(String html, String section) =>
    RegExp('<section id="$section"><h2>[^<]*<span class="badge (\\w+)">')
        .firstMatch(html)
        ?.group(1);

const _ctestJUnit = '''<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="Linux" tests="3" failures="1">
  <testcase name="engine_tests" classname="engine_tests" time="1.5" status="run"/>
  <testcase name="player_tests" classname="player_tests" time="0.2" status="fail">
    <failure message="Failed"/>
  </testcase>
  <testcase name="bench_tests" classname="bench_tests" time="0" status="notrun">
    <skipped message="Disabled"/>
  </testcase>
</testsuite>
''';

/// Events of `flutter test --file-reporter json:…`: a passing test, a failing one, a flaky one
/// (failed, passed on retry), a skipped one and the hidden loading test of the suite. The retry
/// with `retry: 1` as flutter test 3.50 reports it: one testStart, an error, testDone «success».
String _flutterJson() => [
  {
    'type': 'suite',
    'suite': {'id': 0, 'path': '/x/app/test/a_test.dart'},
  },
  {
    'type': 'testStart',
    'test': {'id': 1, 'name': 'loading /x/app/test/a_test.dart', 'suiteID': 0},
    'time': 0,
  },
  {
    'type': 'testDone',
    'testID': 1,
    'result': 'success',
    'hidden': true,
    'time': 10,
  },
  for (final (id, name, result, skipped) in [
    (2, 'passes', 'success', false),
    (3, 'fails', 'failure', false),
    (4, 'flaky <1>', 'error', false),
    (5, 'flaky <1>', 'success', false),
    (6, 'skipped', 'success', true),
  ]) ...[
    {
      'type': 'testStart',
      'test': {'id': id, 'name': name, 'suiteID': 0},
      'time': 100,
    },
    {
      'type': 'testDone',
      'testID': id,
      'result': result,
      'skipped': skipped,
      'hidden': false,
      'time': 600,
    },
  ],
  // retry: 1 in flutter test: one start, an error of the first attempt, success
  {
    'type': 'testStart',
    'test': {'id': 7, 'name': 'retried', 'suiteID': 0},
    'time': 700,
  },
  {'type': 'error', 'testID': 7, 'error': 'Expected: <2>', 'isFailure': true},
  {
    'type': 'testDone',
    'testID': 7,
    'result': 'success',
    'skipped': false,
    'hidden': false,
    'time': 900,
  },
  {'type': 'done', 'success': false},
].map(jsonEncode).join('\n');

void main() {
  group('#12/AK1 make report writes the page from the existing results', () {
    late Directory repo, bin;

    void write(String path, String text) => File('${repo.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);

    ProcessResult run({bool ghWorks = true, List<String> args = const []}) {
      File('${bin.path}/gh').writeAsStringSync(
        ghWorks
            ? '#!/bin/sh\ncat "${Directory.current.path}/tool/report/testdata/issues.json"\n'
            : '#!/bin/sh\necho "not logged in" >&2\nexit 4\n',
      );
      Process.runSync('chmod', ['755', '${bin.path}/gh']);
      return Process.runSync(
        'dart',
        [
          '${Directory.current.path}/tool/report/report_run.dart',
          '--root',
          repo.path,
          ...args,
        ],
        environment: {'PATH': '${bin.path}:${Platform.environment['PATH']}'},
      );
    }

    String page() =>
        File('${repo.path}/local/test-quality/report/index.html')
            .readAsStringSync();

    setUp(() {
      // resolved: git reports /private/var/… for /var/… on macOS
      repo = Directory(
        Directory.systemTemp
            .createTempSync('wp_report_')
            .resolveSymbolicLinksSync(),
      );
      bin = Directory('${repo.path}/.bin')..createSync();
      Process.runSync('git', ['init', '-q'], workingDirectory: repo.path);
      write('.gitignore', '/local/\n/.bin/\n');
    });
    tearDown(() => repo.deleteSync(recursive: true));

    test('AK1: every input ends up on the page', () {
      write('app/pubspec.yaml', 'name: x\nversion: 2.3.4+5\n');
      write('tools/coverage-min', '80\n');
      write('app/lib/a.dart', 'int f(int x) {\n  return x;\n}\n');
      write(
        'app/coverage/lcov.info',
        'SF:lib/a.dart\nDA:1,1\nDA:2,1\nend_of_record\n',
      );
      write(
        'core/build-cov/lcov.info',
        'SF:${repo.path}/core/src/b.cpp\nDA:1,1\nDA:2,0\nend_of_record\n',
      );
      write('local/test-quality/junit/core.xml', _ctestJUnit);
      write('local/test-quality/flutter/app.json', _flutterJson());
      write(
        'local/mutants/full/results.json',
        jsonEncode({
          'mode': 'full',
          'head': '0123456789',
          'date': '2026-11-20T03:38:04Z',
          'counts': {
            'core': {'killed': 3, 'survived': 1},
          },
          'mutants': [
            {
              'outcome': 'survived',
              'file': 'core/src/b.cpp',
              'line': 2,
              'column': 3,
              'mutator': 'cxx_add_to_sub',
              'code': 'a + b',
            },
          ],
        }),
      );
      write('app/test/a_test.dart', "test('#901/AK1 marked', () {});\n");
      final r = run(args: ['--summary']);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final html = page();
      expect(html, contains('2.3.4+5'));
      // JUnit of ctest and of flutter test (converted)
      expect(
        File('${repo.path}/local/test-quality/junit/app.xml').existsSync(),
        isTrue,
      );
      expect(html, contains('player_tests'));
      expect(html, contains('app: test/a_test.dart fails'));
      // coverage per part, mutants, issues
      expect(html, contains('100,0 %'));
      expect(html, contains('50,0 %'));
      expect(html, contains('core/src/b.cpp:2:3: cxx_add_to_sub | a + b'));
      expect(html, contains('#901 ${_issue(901)['title']}'));
      expect(html, contains('test/a_test.dart:1'));
      expect(html, contains('#903 ${_issue(903)['title']}'));
      expect('${r.stdout}', contains('2.3.4+5'));
    });

    test('AK1: the page works offline: no script, no external resource', () {
      final r = run();
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final html = page();
      expect(html, startsWith('<!doctype html>'));
      expect(html, isNot(contains('<script')));
      expect(html, isNot(contains('<link')));
      expect(html, isNot(contains('src=')));
      expect(html, isNot(contains('url(')));
      expect(html, isNot(matches(RegExp(r'https?://'))));
    });

    test(
      'AK1: the page is not checked in (local/ is ignored in the repository)',
      () {
        final r = Process.runSync('git', [
          'check-ignore',
          '-q',
          'local/test-quality/report/index.html',
        ], workingDirectory: '..');
        expect(r.exitCode, 0);
        final makefile = File('../Makefile').readAsStringSync();
        expect(makefile, contains('dart app/tool/report/report_run.dart'));
        // quoted: the path of the repository may contain a space
        expect(
          makefile,
          contains('--output-junit "\$(QA_DIR)/junit/core.xml"'),
        );
        expect(makefile, contains('"--file-reporter=json:\$(QA_DIR)/flutter/'));
      },
    );

    test('AK5: without any data every layer says «no data», exit code 0', () {
      final r = run(ghWorks: false);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final html = page();
      for (final s in ['hygiene', 'fit', 'req', 'esc']) {
        expect(_badge(html, s), Status.noData.key, reason: s);
      }
      expect(html, contains(_t('req.none')));
      expect(html, contains(_t('fit.noCoverage')));
      expect(html, contains(_t('fit.noMutants')));
      expect(html, contains(_t('hist.first')));
    });

    test('AK5: broken files are «no data», not a crash', () {
      write('local/mutants/full/results.json', '{not json');
      write('local/test-quality/flutter/app.json', 'garbage\n{"type":');
      write('tools/coverage-min', 'eighty\n');
      write('app/coverage/lcov.info', 'SF:lib/a.dart\nDA:1,1\nend_of_record\n');
      final r = run(ghWorks: false, args: ['--no-gh']);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      final html = page();
      expect(_badge(html, 'fit'), Status.noData.key);
      expect(html, contains(_t('fit.noMutants')));
    });
  });

  group('#12/AK2 status per layer', () {
    test('AK2: hygiene from failed and flaky tests', () {
      expect(hygieneStatus([JUnitSource('core')]), Status.noData);
      expect(
        hygieneStatus([
          JUnitSource('core', cases: [TestCase('a')]),
          JUnitSource('app'),
        ]),
        Status.ok,
      );
      expect(
        hygieneStatus([
          JUnitSource('core', cases: [TestCase('a', flaky: true)]),
        ]),
        Status.hint,
      );
      expect(
        hygieneStatus([
          JUnitSource(
            'core',
            cases: [TestCase('a', flaky: true), TestCase('b', failed: true)],
          ),
        ]),
        Status.fail,
      );
    });

    test('AK2: JUnit of ctest: failed, skipped, time', () {
      final cases = parseJUnit(_ctestJUnit);
      expect(cases.map((c) => c.name), [
        'engine_tests',
        'player_tests',
        'bench_tests',
      ]);
      expect(cases.map((c) => c.failed), [false, true, false]);
      expect(cases.map((c) => c.skipped), [false, false, true]);
      expect(cases.first.seconds, 1.5);
    });

    test(
      'AK2: flutter JSON becomes JUnit with failed, flaky and skipped tests',
      () {
        final cases = parseJUnit(flutterJsonToJUnit(_flutterJson()));
        expect(cases.map((c) => c.name), [
          'test/a_test.dart passes',
          'test/a_test.dart fails',
          'test/a_test.dart flaky <1>',
          'test/a_test.dart skipped',
          'test/a_test.dart retried',
        ]);
        expect(cases.map((c) => c.failed), [false, true, false, false, false]);
        expect(cases.map((c) => c.flaky), [false, false, true, false, true]);
        expect(cases.map((c) => c.skipped), [false, false, false, true, false]);
        expect(cases.first.seconds, 0.5);
      },
    );

    test('AK2: a suite that does not load counts as failed', () {
      final json = [
        {
          'type': 'testStart',
          'test': {'id': 1, 'name': 'loading test/b_test.dart', 'suiteID': 0},
        },
        {'type': 'testDone', 'testID': 1, 'result': 'error', 'hidden': true},
      ].map(jsonEncode).join('\n');
      final cases = parseJUnit(flutterJsonToJUnit(json));
      expect(cases.single.failed, isTrue);
    });

    test('AK2: adequacy from coverage per part and not detected mutants', () {
      expect(adequacyStatus(null, _mut(0)), Status.noData);
      expect(adequacyStatus(_cov(85, 90), _mut(0)), Status.ok);
      expect(adequacyStatus(_cov(85, 90), _mut(2)), Status.hint);
      expect(adequacyStatus(_cov(85, 90), null), Status.hint);
      expect(adequacyStatus(_cov(79.9, 90), _mut(0)), Status.fail);
      expect(adequacyStatus(_cov(85, 70), null), Status.fail);
      expect(
        adequacyStatus(_cov(85, 90, unloaded: ['app/lib/x.dart']), _mut(0)),
        Status.fail,
      );
      // the UI part has no minimum
      final ui = _cov(85, 90);
      expect(ui.parts[Part.dartUi]!.percent, lessThan(80));
      // a part without data is a hint, not a failure (#12/AK5)
      final half = CoverageData(
        min: 80,
        parts: {
          Part.core: null,
          Part.dartLogic: (percent: 90, lines: 10, covered: 9),
          Part.dartUi: null,
        },
      );
      expect(adequacyStatus(half, _mut(0)), Status.hint);
    });

    test('AK2: results of a mutation run', () {
      final m = parseMutants(
        jsonEncode({
          'mode': 'diff',
          'base': 'origin/main',
          'counts': {
            'core': {'killed': 3, 'survived': 1},
            'dart': {'killed': 1, 'survived': 2, 'excluded': 1},
          },
          'mutants': [
            {'outcome': 'killed', 'file': 'a', 'line': 1},
            {
              'outcome': 'survived',
              'file': 'lib/x.dart',
              'line': 7,
              'column': 2,
              'mutator': 'dart_lt_to_le',
              'code': 'a < b',
            },
          ],
        }),
      )!;
      expect(m.survived, 3);
      expect(m.base, 'origin/main');
      expect(m.missed, ['lib/x.dart:7:2: dart_lt_to_le | a < b']);
      expect(parseMutants('[]'), isNull);
    });

    test('AK2: requirements: kinds per criterion and status', () {
      final rows = requirements(_issues(), {
        (issue: 901, ak: 1): ['app/test/a_test.dart:3'],
      });
      // #902 is not planned, #903 and #904 have no checklist
      expect(rows.map((r) => r.number), [901, 905, 906]);
      final kinds = {
        for (final r in rows) r.number: [for (final i in r.items) i.kind],
      };
      expect(kinds[901], [
        Kind.test,
        Kind.checked,
        Kind.manual,
        Kind.none,
        Kind.manual,
      ]);
      expect(traceabilityStatus(rows), Status.hint);
      expect(traceabilityStatus(null), Status.noData);
      expect(
        traceabilityStatus([
          for (final r in rows)
            if (r.count(Kind.none) == 0) r,
        ]),
        Status.ok,
      );
    });

    test(
      'AK2: outcome: escaped bugs name the test that should have caught them',
      () {
        final esc = escapes(
          _issues(),
          which: _t('esc.whichHeading'),
          regression: _t('esc.regressionHeading'),
        );
        // #906 has the label bug but no found:* label
        expect(esc.map((e) => e.number), [903, 904]);
        expect(esc.first.found, 'usage');
        expect(esc.first.which, isNotNull);
        expect(esc.first.regression, startsWith('`test/load_test.dart`'));
        // only the hints of the template: no answer
        expect(esc.last.which, isNull);
        expect(esc.last.regression, isNull);
        expect(outcomeStatus(esc), Status.hint);
        expect(outcomeStatus(esc.take(1).toList()), Status.ok);
        expect(outcomeStatus(const []), Status.noData);
        expect(outcomeStatus(null), Status.noData);
      },
    );

    test(
      'AK2: the page shows each layer with its status, no overall grade',
      () {
        final html = renderPage(
          Report(
            _input(
              junit: [
                JUnitSource('core', cases: [TestCase('a', failed: true)]),
              ],
              coverage: _cov(85, 90),
              mutants: _mut(0),
              issues: _issues(),
            ),
            _t,
          ),
          _t,
        );
        expect(_badge(html, 'hygiene'), Status.fail.key);
        expect(_badge(html, 'fit'), Status.ok.key);
        expect(_badge(html, 'req'), Status.hint.key);
        expect(_badge(html, 'esc'), Status.hint.key);
        expect(RegExp('class="badge').allMatches(html).length, 4);
        for (final key in ['hygiene.rule', 'req.rule', 'esc.rule']) {
          expect(html, contains(_t(key)));
        }
      },
    );
  });

  group('#12/AK3 marks of the tests and check comments', () {
    Set<String> marks(String path, String source) => {
      for (final e in scanMarks(path, source).entries)
        '#${e.key.issue}/AK${e.key.ak}@${e.value.join(',')}',
    };

    test(
      'AK3: in the test name and in a comment, leading zeros do not matter',
      () {
        expect(
          marks(
            'app/test/a_test.dart',
            "// #0907/AK2 and #907/AK03\ntest('#908/AK1: works', () {});\n",
          ),
          {
            '#907/AK2@app/test/a_test.dart:1',
            '#907/AK3@app/test/a_test.dart:1',
            '#908/AK1@app/test/a_test.dart:2',
          },
        );
        expect(marks('core/tests/x_tests.cpp', '  // #909/AK4: limit\n'), {
          '#909/AK4@core/tests/x_tests.cpp:1',
        });
        // no mark: other issue syntax, inside a word, anchor
        expect(
          marks('app/test/b_test.dart', "// FEA-9/AK1 a#9/AK1 &#9/AK1\n"),
          isEmpty,
        );
      },
    );

    test('AK3: AKn in a test inside a group that names exactly one issue', () {
      const src = '''
void main() {
  group('Loop (#910)', () {
    test('AK2 drag', () {});
    testWidgets(
      'AK3 and AK4',
      (t) async {},
    );
    group('inner', () {
      test('AK5 nested', () {});
    });
  });
  group('#911/AK1 whole group', () {
    test('inherits the criterion of the group', () {});
  });
  group('two issues #912 #913', () {
    test('AK1 does not count', () {});
  });
  test('AK6 outside of a group does not count', () {});
}
''';
      expect(marks('app/test/c_test.dart', src), {
        '#910/AK2@app/test/c_test.dart:3',
        '#910/AK3@app/test/c_test.dart:4',
        '#910/AK4@app/test/c_test.dart:4',
        '#910/AK5@app/test/c_test.dart:9',
        '#911/AK1@app/test/c_test.dart:12',
      });
    });

    test('AK3: which files are test files', () {
      expect(isTestFile('app/test/a_test.dart'), isTrue);
      expect(isTestFile('app/integration_test/app_test.dart'), isTrue);
      expect(isTestFile('app/tool/report/report_test.dart'), isTrue);
      expect(isTestFile('app/packages/wp_core/test/x_test.dart'), isTrue);
      expect(isTestFile('core/tests/engine_tests.cpp'), isTrue);
      expect(isTestFile('app/lib/main.dart'), isFalse);
      expect(isTestFile('app/tool/report/report.dart'), isFalse);
      expect(isTestFile('core/third_party/x/tests/a.cpp'), isFalse);
    });

    test('AK3: the order of the checklist is the criterion number', () {
      final row = requirements(
        [_issue(901)],
        {
          (issue: 901, ak: 4): ['x:1'],
        },
      ).single;
      expect(row.items[3].kind, Kind.test);
      expect(row.items[3].text, startsWith('AK4:'));
      expect(row.items[0].kind, Kind.none);
    });

    test('AK3: check comments after CLAUDE.md count as «checked»', () {
      List<Map<String, Object?>> comments(int n) => [
        for (final c in _issue(n)['comments']! as List<Object?>)
          (c! as Map).cast<String, Object?>(),
      ];
      // AK2 «erfüllt»; AK5 ✅ first, «nicht erfüllt» later: the last statement counts;
      // AK3 only by the user (manual), AK4 «offen» and a comment that is no check
      expect(checkedCriteria(comments(901), 5), {2: '2026-11-01'});
      // «Alle 2 Kriterien sind erfüllt»
      expect(checkedCriteria(comments(905), 2), {
        1: '2026-11-05',
        2: '2026-11-05',
      });
      // «AKn erfüllt in <commit>» starts a check, «AK1, AK2 ok», «teilweise» is not
      expect(checkedCriteria(comments(906), 3).keys, [1, 2]);
    });
  });

  group('#12/AK4 history', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('wp_hist_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('AK4: compares with the previous version, not with itself', () {
      expect(recordHistory(dir, '1.0.0', {'coverage_core': 80.0}), isNull);
      // the same version again: still no previous one
      expect(recordHistory(dir, '1.0.0', {'coverage_core': 81.0}), isNull);
      final prev = recordHistory(dir, '1.1.0', {'coverage_core': 82.5})!;
      expect(prev.version, '1.0.0');
      expect(prev.metrics['coverage_core'], 81.0);
      // the newest other version is the previous one
      sleep(const Duration(milliseconds: 20));
      recordHistory(dir, '1.2.0', {'coverage_core': 83.0});
      expect(recordHistory(dir, '1.1.0', {})!.version, '1.2.0');
    });

    test('AK4: change with direction (higher or lower is better)', () {
      expect(delta(_t, 'coverage_core', 82.5, 80.0), '+2,5 ▲');
      expect(delta(_t, 'coverage_core', 79.0, 80.0), '−1,0 ▼');
      expect(delta(_t, 'survived', 3, 5), '−2 ▲');
      expect(delta(_t, 'flaky', 1, 0), '+1 ▼');
      expect(delta(_t, 'survived', 3, 3), _t('hist.same'));
      expect(delta(_t, 'survived', null, 3), '–');
    });

    test('AK4: the page shows the previous version and every metric', () {
      final input = _input(coverage: _cov(85, 90), mutants: _mut(4))
        ..previous = (
          version: '0.9.0',
          metrics: {'coverage_core': 80.0, 'survived': 6},
        );
      final report = Report(input, _t);
      expect(report.metrics.keys, metricKeys);
      expect(report.metrics['survived'], 4);
      final html = renderPage(report, _t);
      expect(html, contains(_t('hist.rule', {'version': '0.9.0'})));
      expect(html, contains('+5,0 ▲'));
      expect(html, contains('−2 ▲'));
      for (final k in metricKeys) {
        expect(html, contains(_t('hist.m.$k')));
      }
    });
  });

  group('#12/AK5 missing data', () {
    test('AK5: an empty input renders «no data» everywhere', () {
      final report = Report(_input(), _t);
      expect(report.hygiene, Status.noData);
      expect(report.adequacy, Status.noData);
      expect(report.traceability, Status.noData);
      expect(report.outcome, Status.noData);
      expect(report.metrics.values, everyElement(isNull));
      final html = renderPage(report, _t);
      expect(html, contains(_t('status.noData')));
      expect(renderSummary(report, _t, 'x'), contains(_t('status.noData')));
    });

    test('AK5: every text key used by the page exists in the table', () {
      final keys = RegExp(r"""\bt\(\s*'([\w.]+)'""")
          .allMatches(File('tool/report/report.dart').readAsStringSync())
          .map((m) => m.group(1)!)
          .toSet();
      expect(keys, isNotEmpty);
      for (final k in keys) {
        expect(_t.has(k), isTrue, reason: k);
      }
      for (final s in Status.values) {
        expect(_t.has('status.${s.key}'), isTrue);
      }
      for (final k in Kind.values) {
        expect(_t.has('req.kind.${k.name}'), isTrue);
      }
      for (final o in mutantOutcomes) {
        expect(_t.has('fit.outcome.$o'), isTrue);
      }
    });

    test('AK5: the tool has its own tests in make test-tools', () {
      final makefile = File('../Makefile').readAsStringSync();
      expect(makefile, contains('tool/report/report_test.dart'));
    });
  });
}
