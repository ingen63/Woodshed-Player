// Overview page «Testqualität» (#12): pure functions behind tool/report/report_run.dart, tested in
// tool/report/report_test.dart. Only dart:io and dart:convert (no package), like tool/coverage.dart.
//
// Four layers, each with its own status by a rule stated on the page, no overall grade (rules in
// docs/TESTS.md, section «Übersichtsseite Testqualität (#12)»):
// 1 Hygiene: failed and flaky tests from JUnit (ctest, flutter test converted from its JSON reporter),
//   slow Dart tests without a reason (tool/slow_tests.dart, #128) as a hint.
// 2 Adequacy: line coverage per part (tool/coverage.dart) and not detected mutants (local/mutants/).
// 3 Traceability: per acceptance criterion «with test», «checked», «manual only» or «without».
// 4 Outcome: bug issues with a found:* label name the test that should have caught them and the
//   regression test.
// Missing data is a status of its own («no data»), never an error. The page texts live in
// tool/report/texts_de.json, so this code stays English (#45/AK5).
import 'dart:convert';
import 'dart:io';

import '../coverage.dart';
import '../slow_tests.dart';

// ---------------------------------------------------------------- texts and status

/// Text table of the page: key -> text with `{name}` placeholders.
class Texts {
  Texts(this._map);

  factory Texts.parse(String json) =>
      Texts((jsonDecode(json) as Map<String, Object?>).cast<String, Object?>());

  final Map<String, Object?> _map;

  /// The text of [key] with [args] filled in; an unknown key is shown as itself.
  String call(String key, [Map<String, Object?> args = const {}]) {
    var s = _map[key] is String ? _map[key]! as String : key;
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  bool has(String key) => _map[key] is String;

  /// A number with one decimal and the decimal separator of the table.
  String number(double v, {int digits = 1}) =>
      v.toStringAsFixed(digits).replaceAll('.', call('decimal'));

  String percent(double v) => '${number(v)} %';
}

enum Status {
  ok('ok'),
  hint('hint'),
  fail('fail'),
  noData('noData');

  const Status(this.key);

  final String key;
}

// ---------------------------------------------------------------- layer 1: hygiene (JUnit)

class TestCase {
  TestCase(
    this.name, {
    this.seconds = 0,
    this.failed = false,
    this.flaky = false,
    this.skipped = false,
  });

  final String name;
  final double seconds;
  final bool failed;
  final bool flaky;
  final bool skipped;
}

/// The test cases of one JUnit file (ctest --output-junit, or written by [flutterJsonToJUnit]).
/// Tolerant: only `<testcase>` elements with their attributes and child elements are read.
List<TestCase> parseJUnit(String xml) {
  final out = <TestCase>[];
  final testcase = RegExp(
    r'<testcase\b((?:[^>"]|"[^"]*")*?)(?:/>|>([\s\S]*?)</testcase>)',
  );
  for (final m in testcase.allMatches(xml)) {
    final attrs = _attributes(m.group(1)!);
    final body = m.group(2) ?? '';
    final cls = attrs['classname'] ?? '';
    final name = attrs['name'] ?? '';
    final status = attrs['status'] ?? '';
    out.add(
      TestCase(
        cls.isEmpty || cls == name ? name : '$cls $name',
        seconds: double.tryParse(attrs['time'] ?? '') ?? 0,
        failed:
            RegExp(r'<(failure|error)\b').hasMatch(body) || status == 'fail',
        flaky: RegExp(r'<(flakyFailure|flakyError|rerunFailure|rerunError)\b')
            .hasMatch(body),
        skipped:
            RegExp(r'<skipped\b').hasMatch(body) ||
            status == 'notrun' ||
            status == 'disabled',
      ),
    );
  }
  return out;
}

Map<String, String> _attributes(String s) => {
  for (final m in RegExp(r'([\w:-]+)\s*=\s*"([^"]*)"').allMatches(s))
    m.group(1)!: _unescapeXml(m.group(2)!),
};

String _unescapeXml(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&amp;', '&');

String _escapeXml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// Converts the output of `flutter test --file-reporter json:<file>` (one JSON event per line) into
/// JUnit XML. Hidden tests (loading a suite) only count when they fail (a suite that does not
/// load). A test that passed in the end after an error is flaky: with `retry:` the JSON reporter
/// sends one testStart, an `error` event per failed attempt and testDone «success»; a test that
/// shows up twice with the same name and passes the second time counts the same. One that failed
/// in the end failed. Lines that are no JSON are skipped (an aborted run).
String flutterJsonToJUnit(String jsonLines, {String suiteName = 'flutter'}) {
  final suites = <int, String>{};
  final tests = <int, ({String name, int suite, bool hidden, int start})>{};
  final errors = <int, List<String>>{};
  // key «suite path␟name» -> results in order
  final results =
      <String, List<({String result, bool skipped, bool errors, double s})>>{};
  final order = <String>[];
  for (final line in const LineSplitter().convert(jsonLines)) {
    Object? e;
    try {
      e = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (e is! Map<String, Object?>) continue;
    switch (e['type']) {
      case 'suite':
        final s = e['suite']! as Map<String, Object?>;
        suites[s['id']! as int] = '${s['path'] ?? ''}';
      case 'testStart':
        final t = e['test']! as Map<String, Object?>;
        final name = '${t['name'] ?? ''}';
        tests[t['id']! as int] = (
          name: name,
          suite: (t['suiteID'] as int?) ?? -1,
          hidden: name.startsWith('loading '),
          start: (e['time'] as int?) ?? 0,
        );
      case 'error':
        errors.putIfAbsent(e['testID']! as int, () => []).add('${e['error']}');
      case 'testDone':
        final id = e['testID']! as int;
        final t = tests[id];
        if (t == null) continue;
        final result = '${e['result']}';
        final hidden = e['hidden'] == true || t.hidden;
        if (hidden && result == 'success') continue;
        final key = '${_shortPath(suites[t.suite] ?? '')}␟${t.name}';
        if (!results.containsKey(key)) order.add(key);
        results.putIfAbsent(key, () => []).add((
          result: result,
          skipped: e['skipped'] == true,
          errors: errors.containsKey(id),
          s: (((e['time'] as int?) ?? t.start) - t.start) / 1000,
        ));
    }
  }
  final b = StringBuffer('<?xml version="1.0" encoding="UTF-8"?>\n');
  var failures = 0;
  final cases = StringBuffer();
  for (final key in order) {
    final parts = key.split('␟');
    final runs = results[key]!;
    final last = runs.last;
    final seconds = runs.fold<double>(0, (a, r) => a + r.s);
    cases.write(
      '  <testcase classname="${_escapeXml(parts[0])}" '
      'name="${_escapeXml(parts[1])}" time="${seconds.toStringAsFixed(3)}"',
    );
    final failedEnd = last.result != 'success';
    final flaky =
        !failedEnd && runs.any((r) => r.result != 'success' || r.errors);
    if (failedEnd) failures++;
    if (!failedEnd && !flaky && !last.skipped) {
      cases.writeln('/>');
      continue;
    }
    cases.writeln('>');
    if (failedEnd) {
      cases.writeln('    <failure message="${_escapeXml(last.result)}"/>');
    } else if (flaky) {
      cases.writeln('    <flakyFailure message="passed on retry"/>');
    } else {
      cases.writeln('    <skipped/>');
    }
    cases.writeln('  </testcase>');
  }
  b.writeln(
    '<testsuite name="${_escapeXml(suiteName)}" tests="${order.length}" '
    'failures="$failures">',
  );
  b.write(cases);
  b.writeln('</testsuite>');
  return b.toString();
}

/// Suite paths relative to the app: «/…/app/test/x_test.dart» -> «test/x_test.dart».
String _shortPath(String path) {
  final i = path.lastIndexOf('/app/');
  return i < 0 ? path : path.substring(i + 5);
}

/// The JUnit results of one source (ctest, flutter test app, tool tests).
class JUnitSource {
  JUnitSource(this.name, {this.cases, this.when, this.error});

  final String name;
  final List<TestCase>? cases; // null: no data
  final DateTime? when;
  final String? error;

  List<TestCase> get failed => [...?cases?.where((c) => c.failed)];
  List<TestCase> get flaky => [...?cases?.where((c) => c.flaky)];
  int get skipped => cases?.where((c) => c.skipped).length ?? 0;
}

/// [slow]: Dart tests over their limit without a reason (#128), only a hint.
Status hygieneStatus(List<JUnitSource> sources, {int slow = 0}) {
  final withData = sources.where((s) => s.cases != null).toList();
  if (withData.isEmpty) return Status.noData;
  if (withData.any((s) => s.failed.isNotEmpty)) return Status.fail;
  if (slow > 0 || withData.any((s) => s.flaky.isNotEmpty)) return Status.hint;
  return Status.ok;
}

// ---------------------------------------------------------------- layer 2: adequacy

/// Coverage per part; a part is null when its lcov file is missing.
class CoverageData {
  CoverageData({
    required this.min,
    required this.parts,
    this.unloaded = const [],
    this.when,
  });

  final double min;
  final Map<Part, ({double percent, int lines, int covered})?> parts;
  final List<String> unloaded;
  final DateTime? when;

  bool get any => parts.values.any((p) => p != null);
}

/// Parts shown on the page (the others are listed by coverage_check).
const shownParts = [Part.core, Part.dartLogic, Part.dartUi];

/// Label of a part from the text table (`part.<name>`), else the English label of coverage.dart.
String partLabel(Texts t, Part p) =>
    t.has('part.${p.name}') ? t('part.${p.name}') : p.label;

/// Coverage from the files of `make coverage-run` below [root]; null if neither exists.
CoverageData? readCoverageData(String root, double min) {
  final dart = File('$root/$dartLcov');
  final core = File('$root/$coreLcov');
  if (!dart.existsSync() && !core.existsSync()) return null;
  final data = <Map<String, LineHits>>[];
  if (dart.existsSync()) {
    data.add(parseLcov(dart.readAsStringSync(), root: root, prefix: 'app/'));
  }
  if (core.existsSync()) {
    data.add(parseLcov(core.readAsStringSync(), root: root));
  }
  final result = evaluate(
    min: min,
    coverage: merge(data),
    sources: dart.existsSync() ? readDartSources(root) : const {},
  );
  final when = [
    for (final f in [dart, core])
      if (f.existsSync()) f.lastModifiedSync(),
  ]..sort();
  return CoverageData(
    min: min,
    parts: {
      for (final p in shownParts)
        p: (p == Part.core ? core : dart).existsSync()
            ? (
                percent: result.results[p]!.percent,
                lines: result.results[p]!.lines,
                covered: result.results[p]!.covered,
              )
            : null,
    },
    unloaded: [
      for (final p in shownParts.where((p) => p.threshold))
        ...result.results[p]!.unloaded,
    ],
    when: when.isEmpty ? null : when.last,
  );
}

/// Result of a mutation run (local/mutants/full|diff/results.json of tool/mutants_run.dart).
class MutantsData {
  MutantsData({
    required this.mode,
    required this.counts,
    required this.missed,
    this.base,
    this.head,
    this.date,
  });

  final String mode;
  final String? base;
  final String? head;
  final DateTime? date;

  /// part -> outcome -> number
  final Map<String, Map<String, int>> counts;

  /// «file:line:column: mutator | code» of every not detected mutant.
  final List<String> missed;

  int get survived => counts.values.fold(0, (a, c) => a + (c['survived'] ?? 0));
}

const mutantOutcomes = [
  'killed',
  'timeout',
  'survived',
  'excluded',
  'unviable',
];

/// Parses results.json; null if it is not valid.
MutantsData? parseMutants(String json) {
  try {
    final d = jsonDecode(json) as Map<String, Object?>;
    final counts = <String, Map<String, int>>{};
    (d['counts'] as Map<String, Object?>? ?? {}).forEach((part, c) {
      counts[part] = {
        for (final e in (c! as Map<String, Object?>).entries)
          e.key: (e.value! as num).toInt(),
      };
    });
    final missed = <String>[];
    for (final m in (d['mutants'] as List<Object?>? ?? const [])) {
      final x = m! as Map<String, Object?>;
      if (x['outcome'] != 'survived') continue;
      missed.add(
        '${x['file']}:${x['line']}:${x['column']}: ${x['mutator']} | '
        '${x['code']}',
      );
    }
    return MutantsData(
      mode: '${d['mode'] ?? ''}',
      base: d['base'] as String?,
      head: d['head'] as String?,
      date: DateTime.tryParse('${d['date']}')?.toLocal(),
      counts: counts,
      missed: missed,
    );
  } on Object {
    return null;
  }
}

/// Coverage of the changed lines against [base] (like tool/coverage_diff.dart).
class DiffCoverage {
  DiffCoverage(this.base, {this.total = 0, this.covered = 0, this.ok = true});

  final String base;
  final int total;
  final int covered;
  final bool ok; // false: base unknown
}

DiffCoverage diffCoverage(
  Map<String, Set<int>> changed,
  Map<String, LineHits> coverage,
  String base,
) {
  var total = 0, covered = 0;
  changed.forEach((file, lines) {
    if (!measuredSource.hasMatch(file)) return;
    final hits = coverage[file] ?? const <int, int>{};
    for (final n in lines) {
      final h = hits[n];
      if (h == null) continue;
      total++;
      if (h > 0) covered++;
    }
  });
  return DiffCoverage(base, total: total, covered: covered);
}

Status adequacyStatus(CoverageData? cov, MutantsData? mutants) {
  if (cov == null || !cov.any) return Status.noData;
  for (final p in shownParts.where((p) => p.threshold)) {
    final v = cov.parts[p];
    if (v != null && v.percent < cov.min) return Status.fail;
  }
  if (cov.unloaded.isNotEmpty) return Status.fail;
  final partMissing = shownParts
      .where((p) => p.threshold)
      .any((p) => cov.parts[p] == null);
  if (partMissing || mutants == null || mutants.survived > 0) {
    return Status.hint;
  }
  return Status.ok;
}

// ---------------------------------------------------------------- layer 3: traceability

typedef Criterion = ({int issue, int ak});

final _mark = RegExp(r'(?<![\w&])#0*(\d+)/AK0*(\d+)\b');
final _issueNumber = RegExp(r'(?<![\w&/])#0*(\d+)\b');
final _bareAk = RegExp(r'(?<![/\w])AK0*(\d+)\b');
final _call = RegExp(
  r'''\b(group|test|testWidgets)\(\s*r?(['"])((?:\\.|(?!\2)[^\\])*)\2''',
);

/// Marks of one test file: criterion -> locations «path:line». Every `#nn/AKn` counts (test name,
/// comment, group title). In Dart, a test whose own name says `AKn` inside a `group(...)` whose
/// title names exactly one issue number covers that issue's criterion n; without `AKn` it inherits
/// the criterion of the group, which is already counted at the group title.
Map<Criterion, List<String>> scanMarks(String path, String source) {
  final marks = <Criterion, List<String>>{};
  void add(int issue, int ak, int line) =>
      marks.putIfAbsent((issue: issue, ak: ak), () => []).add('$path:$line');
  final lines = source.split('\n');
  final lineStart = <int>[0];
  for (var i = 0; i < lines.length; i++) {
    lineStart.add(lineStart.last + lines[i].length + 1);
    for (final m in _mark.allMatches(lines[i])) {
      add(int.parse(m.group(1)!), int.parse(m.group(2)!), i + 1);
    }
  }
  if (!path.endsWith('.dart')) return marks;
  int lineOf(int offset) {
    var lo = 0, hi = lineStart.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (lineStart[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo; // 0-based
  }

  // groups: (first line, last line, issue numbers of the title)
  final groups = <({int from, int to, Set<int> ids})>[];
  final calls = _call.allMatches(source).toList();
  for (final m in calls.where((m) => m.group(1) == 'group')) {
    final from = lineOf(m.start);
    final indent = lines[from].length - lines[from].trimLeft().length;
    var to = lines.length - 1;
    for (var i = from + 1; i < lines.length; i++) {
      final l = lines[i];
      if (l.trim() == '});' && l.length - l.trimLeft().length == indent) {
        to = i;
        break;
      }
    }
    final ids = {
      for (final n in _issueNumber.allMatches(m.group(3)!))
        int.parse(n.group(1)!),
    };
    groups.add((from: from, to: to, ids: ids));
  }
  for (final m in calls.where((m) => m.group(1) != 'group')) {
    final line = lineOf(m.start);
    final name = m.group(3)!;
    final enclosing = groups
        .where((g) => g.from < line && line <= g.to && g.ids.isNotEmpty)
        .toList();
    if (enclosing.isEmpty) continue;
    // the innermost group that names issue numbers
    enclosing.sort((a, b) => b.from.compareTo(a.from));
    final ids = enclosing.first.ids;
    if (ids.length != 1) continue;
    final withoutMarks = name.replaceAll(_mark, '');
    for (final a in _bareAk.allMatches(withoutMarks)) {
      add(ids.first, int.parse(a.group(1)!), line + 1);
    }
  }
  return marks;
}

/// Test files whose marks count: Dart tests and tools of the app and its packages, core tests.
bool isTestFile(String path) {
  if (path.contains('/third_party/') || path.contains('/build')) return false;
  if (path.startsWith('core/tests/')) {
    return RegExp(r'\.(cpp|hpp|h|mm|cmake|txt)$').hasMatch(path);
  }
  if (!path.endsWith('.dart')) return false;
  return RegExp(r'^app/(test|integration_test|bench)/').hasMatch(path) ||
      RegExp(r'^app/tool/.*_test\.dart$').hasMatch(path) ||
      RegExp(r'^app/packages/[^/]+/test/').hasMatch(path);
}

/// The marks of every test file below [root] (git ls-files, else a walk).
Map<Criterion, List<String>> testMarks(String root, List<String> files) {
  final marks = <Criterion, List<String>>{};
  for (final f in files.where(isTestFile)) {
    final file = File('$root/$f');
    if (!file.existsSync()) continue;
    scanMarks(
      f,
      file.readAsStringSync(),
    ).forEach((k, v) => marks.putIfAbsent(k, () => []).addAll(v));
  }
  return marks;
}

// Check comments after CLAUDE.md («Prüfe #22»): a comment starting with «Prüfung …», «Erneute
// Prüfung …», «Nacharbeit AKn …» or «AKn erfüllt|ok in <commit>». A line «AKn erfüllt», «AKn ok»,
// «**AKn …** ✅» marks the criterion as checked, «nicht», «offen», «teilweise», «überholt» or ❌
// take it back; the last statement per criterion counts. An acceptance by the user («… durch den
// Anwender») is no check: the criterion stays «manual only».
final _checkHead = RegExp(
  r'^\W*(?:(?:Erneute )?Prüfung\b|Nacharbeit AK\d+|AK\d+ (?:erfüllt|ok) in [0-9a-f]{7})',
  caseSensitive: false,
);
final _byUser = RegExp(r'durch den Anwender', caseSensitive: false);
final _checkLine = RegExp(
  r'^\s*(?:[-*]\s+)?\**\s*((?:AK\d+(?:\s*,\s*|\s+und\s+)?)+)(.*)$',
  multiLine: true,
);
final _verdict = RegExp(
  r'✅|❌|\bnicht\b|\boffen\b|\bteilweise\b|überholt|erfüllt|\bok\b|ist belegt',
  caseSensitive: false,
);
final _checkAll = RegExp(
  r'\balle (?:\d+ |\w+ )?Kriterien (?:sind )?(?:erfüllt|ok)|Ergebnis: \d+ von \d+ Kriterien ok',
  caseSensitive: false,
);
final _negative = RegExp(
  r'^(?:❌|nicht|offen|teilweise|überholt)$',
  caseSensitive: false,
);

/// Checked criteria of one issue: criterion number -> day of the check (yyyy-mm-dd).
Map<int, String> checkedCriteria(List<Map<String, Object?>> comments, int n) {
  final res = <int, String>{};
  final sorted = [...comments]
    ..sort((a, b) => '${a['createdAt']}'.compareTo('${b['createdAt']}'));
  for (final c in sorted) {
    final body = '${c['body'] ?? ''}';
    final firstLine = body.trimLeft().split('\n').first;
    if (!_checkHead.hasMatch(firstLine) || _byUser.hasMatch(firstLine)) {
      continue;
    }
    final created = '${c['createdAt'] ?? ''}';
    final day = created.length >= 10 ? created.substring(0, 10) : created;
    if (_checkAll.hasMatch(body)) {
      for (var i = 1; i <= n; i++) {
        res[i] = day;
      }
    }
    for (final m in _checkLine.allMatches(body)) {
      final rest = m.group(2)!;
      final v = _verdict.firstMatch(
        rest.length > 120 ? rest.substring(0, 120) : rest,
      );
      if (v == null) continue;
      final numbers = [
        for (final d in RegExp(r'\d+').allMatches(m.group(1)!))
          int.parse(d.group(0)!),
      ];
      final positive = !_negative.hasMatch(v.group(0)!);
      for (final k in numbers) {
        if (positive) {
          res[k] = day;
        } else {
          res.remove(k);
        }
      }
    }
  }
  return res;
}

enum Kind { test, checked, manual, none }

class CriterionRow {
  CriterionRow(this.kind, this.text, this.evidence);

  final Kind kind;
  final String text;
  final List<String> evidence;
}

class IssueRow {
  IssueRow(this.number, this.title, this.state, this.items);

  final int number;
  final String title;
  final String state;
  final List<CriterionRow> items;

  int count(Kind k) => items.where((i) => i.kind == k).length;
}

final _checkbox = RegExp(r'^\s*[-*] \[( |x|X)\] (.+)$', multiLine: true);

/// Per issue with a checklist, the kind of every criterion in the order of the list. Issues closed
/// as not planned do not count.
List<IssueRow> requirements(
  List<Map<String, Object?>> issues,
  Map<Criterion, List<String>> marks,
) {
  final rows = <IssueRow>[];
  for (final it in issues) {
    if ('${it['stateReason']}'.toUpperCase() == 'NOT_PLANNED') continue;
    final number = (it['number']! as num).toInt();
    final crit = _checkbox.allMatches('${it['body'] ?? ''}').toList();
    if (crit.isEmpty) continue;
    final comments = [
      for (final c in (it['comments'] as List<Object?>? ?? const []))
        (c! as Map).cast<String, Object?>(),
    ];
    final checked = checkedCriteria(comments, crit.length);
    final items = <CriterionRow>[];
    for (var i = 0; i < crit.length; i++) {
      final n = i + 1;
      final text = crit[i].group(2)!.trim();
      final ev = marks[(issue: number, ak: n)] ?? const [];
      if (ev.isNotEmpty) {
        items.add(CriterionRow(Kind.test, text, ev));
      } else if (checked.containsKey(n)) {
        items.add(CriterionRow(Kind.checked, text, [checked[n]!]));
      } else {
        items.add(
          CriterionRow(
            crit[i].group(1) == ' ' ? Kind.none : Kind.manual,
            text,
            const [],
          ),
        );
      }
    }
    rows.add(IssueRow(number, '${it['title']}', '${it['state']}', items));
  }
  rows.sort((a, b) => a.number.compareTo(b.number));
  return rows;
}

Status traceabilityStatus(List<IssueRow>? rows) {
  if (rows == null) return Status.noData;
  return rows.every((r) => r.count(Kind.none) == 0) ? Status.ok : Status.hint;
}

// ---------------------------------------------------------------- layer 4: outcome

class Escape {
  Escape(this.number, this.title, this.found, this.which, this.regression);

  final int number;
  final String title;
  final String found;
  final String? which;
  final String? regression;
}

/// The answer below the bold heading [heading] in an issue body: the text after the heading up to
/// the next bold heading or blank line, without the hint in parentheses of the template; null if
/// empty.
String? answerAfter(String body, String heading) {
  final i = body.indexOf('**$heading');
  if (i < 0) return null;
  final close = body.indexOf('**', i + 2 + heading.length);
  if (close < 0) return null;
  var rest = body.substring(close + 2);
  final stop = RegExp(r'\n\s*\n|\n\*\*').firstMatch(rest);
  if (stop != null) rest = rest.substring(0, stop.start);
  rest = rest.trim().replaceFirst(RegExp(r'^:\s*'), '');
  rest = rest.replaceFirst(RegExp(r'^\([^)]*\)\s*'), '').trim();
  return rest.isEmpty ? null : rest;
}

/// Bug issues with a found:* label; [which] and [regression] are the headings of the template.
List<Escape> escapes(
  List<Map<String, Object?>> issues, {
  required String which,
  required String regression,
}) {
  final out = <Escape>[];
  for (final it in issues) {
    final labels = [
      for (final l in (it['labels'] as List<Object?>? ?? const []))
        '${(l! as Map)['name']}',
    ];
    final found = labels.where((l) => l.startsWith('found:')).toList();
    if (!labels.contains('bug') || found.isEmpty) continue;
    final body = '${it['body'] ?? ''}';
    out.add(
      Escape(
        (it['number']! as num).toInt(),
        '${it['title']}',
        found.first.substring(6).trim(),
        answerAfter(body, which),
        answerAfter(body, regression),
      ),
    );
  }
  out.sort((a, b) => a.number.compareTo(b.number));
  return out;
}

Status outcomeStatus(List<Escape>? esc) {
  if (esc == null || esc.isEmpty) return Status.noData;
  return esc.every((e) => e.which != null && e.regression != null)
      ? Status.ok
      : Status.hint;
}

// ---------------------------------------------------------------- history

/// Metrics of a run for the comparison with the previous version (null: no data).
typedef Metrics = Map<String, num?>;

const metricKeys = [
  'tests',
  'failed',
  'flaky',
  'coverage_core',
  'coverage_logic',
  'coverage_ui',
  'survived',
  'criteria_test',
  'criteria_checked',
  'escapes',
];

/// Whether a higher value is better.
const _higherIsBetter = {
  'tests',
  'coverage_core',
  'coverage_logic',
  'coverage_ui',
  'criteria_test',
  'criteria_checked',
};

/// Stores [metrics] as `<dir>/<version>.json` and returns the most recently written other version
/// with its metrics, or null on the first run.
({String version, Metrics metrics})? recordHistory(
  Directory dir,
  String version,
  Metrics metrics,
) {
  dir.createSync(recursive: true);
  final file = '${_safeName(version)}.json';
  final others =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json') && !f.path.endsWith('/$file'))
          .toList()
        ..sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
  ({String version, Metrics metrics})? prev;
  for (final f in others.reversed) {
    try {
      final d = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
      prev = (
        version: '${d['version']}',
        metrics: (d['metrics']! as Map<String, Object?>).map(
          (k, v) => MapEntry(k, v as num?),
        ),
      );
      break;
    } on Object {
      continue;
    }
  }
  File('${dir.path}/$file').writeAsStringSync(
    const JsonEncoder.withIndent(' ')
        .convert({'version': version, 'metrics': metrics}),
  );
  return prev;
}

String _safeName(String s) => s.replaceAll(RegExp(r'[^\w.+-]'), '_');

/// «+1,2 ▲», «−3 ▼» or «unverändert»; «–» without both values.
String delta(Texts t, String key, num? cur, num? prev) {
  if (cur == null || prev == null) return '–';
  final d = cur - prev;
  if (d.abs() < 0.05) return t('hist.same');
  final better = (d > 0) == _higherIsBetter.contains(key);
  final digits = cur is int && prev is int ? 0 : 1;
  return '${d > 0 ? '+' : '−'}${t.number(d.abs().toDouble(), digits: digits)} '
      '${better ? '▲' : '▼'}';
}

// ---------------------------------------------------------------- page

const _css = '''
:root{--bg:#fff;--fg:#1d2330;--muted:#5b6475;--line:#d9dde5;--ok:#1a7f4b;--hint:#9a6200;--fail:#c0262d;--none:#6b7280;--card:#f6f7fa}
@media (prefers-color-scheme:dark){:root{--bg:#14171d;--fg:#e6e9ef;--muted:#9aa3b2;--line:#2c313c;--ok:#4cc38a;--hint:#e0a030;--fail:#ff6b6b;--none:#9ca3af;--card:#1c2028}}
body{background:var(--bg);color:var(--fg);font:15px/1.5 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif;max-width:1000px;margin:0 auto;padding:24px 16px}
h1{margin:0 0 4px}h2{margin:4px 0 6px}h3{margin:14px 0 4px;font-size:16px}.muted{color:var(--muted)}
section{border:1px solid var(--line);border-radius:10px;padding:14px 18px;margin:16px 0;background:var(--card)}
.badge{display:inline-block;padding:2px 10px;border-radius:12px;font-weight:600;font-size:13px;border:1px solid currentColor;vertical-align:middle}
.ok{color:var(--ok)}.hint{color:var(--hint)}.fail{color:var(--fail)}.noData{color:var(--none)}
table{border-collapse:collapse;width:100%;margin:8px 0;display:block;overflow-x:auto}th,td{text-align:left;padding:4px 8px;border-bottom:1px solid var(--line);vertical-align:top;font-size:14px}
td.n,th.n{text-align:right;white-space:nowrap}details{margin:6px 0}summary{cursor:pointer;font-weight:600}
code{font-size:13px;overflow-wrap:anywhere}.rule{font-size:13px;color:var(--muted);margin:2px 0 10px}ul{margin:4px 0;padding-left:22px}
''';

// < > & and double quotes; slashes stay readable in paths.
const _esc = HtmlEscape(HtmlEscapeMode(escapeLtGt: true, escapeQuot: true));

String _e(Object? s) => _esc.convert('$s');

String _badge(Texts t, Status s) =>
    '<span class="badge ${s.key}">${_e(t('status.${s.key}'))}</span>';

String _table(
  List<String> head,
  List<List<String>> rows, {
  Set<int> num = const {},
}) {
  final b = StringBuffer('<table><tr>');
  for (var i = 0; i < head.length; i++) {
    b.write('<th${num.contains(i) ? ' class="n"' : ''}>${_e(head[i])}</th>');
  }
  b.write('</tr>');
  for (final r in rows) {
    b.write('<tr>');
    for (var i = 0; i < r.length; i++) {
      b.write('<td${num.contains(i) ? ' class="n"' : ''}>${r[i]}</td>');
    }
    b.write('</tr>');
  }
  return '$b</table>';
}

String _date(DateTime? d) {
  if (d == null) return '?';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// Everything the page shows; built by report_run.dart from the files, by the tests directly.
class ReportInput {
  ReportInput({
    required this.version,
    required this.commit,
    required this.generated,
    this.junit = const [],
    this.junitDir = 'local/test-quality/junit',
    this.coverage,
    this.diff,
    this.mutantsFull,
    this.mutantsDiff,
    this.issues,
    this.marks = const {},
    this.slow,
    this.previous,
  });

  final String version;
  final String commit;
  final DateTime generated;
  final List<JUnitSource> junit;
  final String junitDir;
  final CoverageData? coverage;
  final DiffCoverage? diff;
  final MutantsData? mutantsFull;
  final MutantsData? mutantsDiff;

  /// Issues from `gh issue list --json …`; null without GitHub.
  final List<Map<String, Object?>>? issues;
  final Map<Criterion, List<String>> marks;

  /// Dart tests over their limit without `// slow:` (tool/slow_tests.dart, #128), paths relative
  /// to the repository; null without the JSON result of the app tests.
  final List<TestTime>? slow;
  ({String version, Metrics metrics})? previous;
}

/// The evaluated layers.
class Report {
  Report(this.input, Texts t)
    : reqs = input.issues == null
          ? null
          : requirements(input.issues!, input.marks),
      esc = input.issues == null
          ? null
          : escapes(
              input.issues!,
              which: t('esc.whichHeading'),
              regression: t('esc.regressionHeading'),
            );

  final ReportInput input;
  final List<IssueRow>? reqs;
  final List<Escape>? esc;

  Status get hygiene =>
      hygieneStatus(input.junit, slow: input.slow?.length ?? 0);
  Status get adequacy => adequacyStatus(input.coverage, input.mutantsFull);
  Status get traceability => traceabilityStatus(reqs);
  Status get outcome => outcomeStatus(esc);

  int _kind(Kind k) => reqs?.fold<int>(0, (a, r) => a + r.count(k)) ?? 0;
  int get criteria => reqs?.fold<int>(0, (a, r) => a + r.items.length) ?? 0;

  Metrics get metrics {
    final withData = input.junit.where((s) => s.cases != null).toList();
    final hasJunit = withData.isNotEmpty;
    double? cov(Part p) {
      final v = input.coverage?.parts[p]?.percent;
      return v == null ? null : (v * 10).roundToDouble() / 10;
    }

    double? share(int n) => reqs == null || criteria == 0
        ? null
        : (1000 * n / criteria).roundToDouble() / 10;
    return {
      'tests': hasJunit
          ? withData.fold<int>(0, (a, s) => a + s.cases!.length)
          : null,
      'failed': hasJunit
          ? withData.fold<int>(0, (a, s) => a + s.failed.length)
          : null,
      'flaky': hasJunit
          ? withData.fold<int>(0, (a, s) => a + s.flaky.length)
          : null,
      'coverage_core': cov(Part.core),
      'coverage_logic': cov(Part.dartLogic),
      'coverage_ui': cov(Part.dartUi),
      'survived': input.mutantsFull?.survived,
      'criteria_test': share(_kind(Kind.test)),
      'criteria_checked': share(_kind(Kind.checked)),
      'escapes': esc?.length,
    };
  }
}

/// The HTML page: static, no scripts, no external resources (works offline).
String renderPage(Report r, Texts t) {
  final i = r.input;
  final h = StringBuffer()
    ..write(
      '<!doctype html><html lang="${_e(t('lang'))}"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>${_e(t('title'))}</title><style>$_css</style></head><body>',
    )
    ..write('<h1>${_e(t('title'))}</h1><p class="muted">')
    ..write(
      _e(
        t('intro', {
          'version': i.version,
          'commit': i.commit,
          'date': _date(i.generated),
        }),
      ),
    )
    ..write('</p>');
  _hygiene(h, r, t);
  _adequacy(h, r, t);
  _traceability(h, r, t);
  _outcome(h, r, t);
  _history(h, r, t);
  h.write('</body></html>\n');
  return h.toString();
}

void _section(StringBuffer h, Texts t, String key, Status s, String rule) {
  h.write(
    '<section id="${key.split('.').first}"><h2>${_e(t(key))} ${_badge(t, s)}</h2>'
    '<p class="rule">${_e(rule)}</p>',
  );
}

void _hygiene(StringBuffer h, Report r, Texts t) {
  _section(h, t, 'hygiene.title', r.hygiene, t('hygiene.rule'));
  final sources = r.input.junit;
  if (sources.every((s) => s.cases == null)) {
    h.write(
      '<p class="muted">${_e(t('hygiene.none', {'dir': r.input.junitDir}))}</p>',
    );
  }
  final rows = <List<String>>[];
  for (final s in sources) {
    if (s.cases == null) {
      rows.add([
        _e(s.name),
        _e(
          s.error == null
              ? t('noData')
              : t('hygiene.broken', {'name': s.name, 'error': s.error}),
        ),
        '',
        '',
        '',
        '',
        '',
      ]);
      continue;
    }
    final secs = s.cases!.fold<double>(0, (a, c) => a + c.seconds);
    rows.add([
      _e(s.name),
      '${s.cases!.length}',
      s.failed.isEmpty ? '0' : '<b class="fail">${s.failed.length}</b>',
      s.flaky.isEmpty ? '0' : '<b class="hint">${s.flaky.length}</b>',
      '${s.skipped}',
      _e(t.number(secs, digits: 0)),
      _e(_date(s.when)),
    ]);
  }
  if (rows.isNotEmpty) {
    h.write(
      _table(
        [
          t('hygiene.source'),
          t('hygiene.tests'),
          t('hygiene.failed'),
          t('hygiene.flaky'),
          t('hygiene.skipped'),
          t('hygiene.seconds'),
          t('asOf', {'date': ''}).trim(),
        ],
        rows,
        num: {1, 2, 3, 4, 5},
      ),
    );
  }
  void list(String key, List<String> names) {
    if (names.isEmpty) return;
    h.write('<p><b>${_e(t(key))}</b></p><ul>');
    for (final n in names) {
      h.write('<li><code>${_e(n)}</code></li>');
    }
    h.write('</ul>');
  }

  list('hygiene.failedList', [
    for (final s in sources)
      for (final c in s.failed) '${s.name}: ${c.name}',
  ]);
  list('hygiene.flakyList', [
    for (final s in sources)
      for (final c in s.flaky) '${s.name}: ${c.name}',
  ]);
  final slow = r.input.slow ?? const <TestTime>[];
  if (slow.isNotEmpty) {
    h.write(
      '<p><b>${_e(t('hygiene.slowList', {'logic': t.number(logicLimit, digits: 2), 'widget': t.number(widgetLimit)}))}</b></p><ul>',
    );
    for (final s in slow) {
      h.write('<li>${_e(_slowItem(t, s))}</li>');
    }
    h.write('</ul>');
  }
  final all = [
    for (final s in sources)
      for (final c in s.cases ?? const <TestCase>[]) (s.name, c),
  ]..sort((a, b) => b.$2.seconds.compareTo(a.$2.seconds));
  if (all.isNotEmpty) {
    h.write(
      '<details><summary>${_e(t('hygiene.slowest'))}</summary>'
      '${_table([t('hygiene.test'), t('hygiene.seconds')], [
        for (final (src, c) in all.take(10)) ['<code>${_e('$src: ${c.name}')}</code>', _e(t.number(c.seconds))],
      ], num: {1})}</details>',
    );
  }
  h.write('</section>');
}

void _adequacy(StringBuffer h, Report r, Texts t) {
  final cov = r.input.coverage;
  final min = cov?.min;
  _section(
    h,
    t,
    'fit.title',
    r.adequacy,
    t('fit.rule', {'min': min == null ? '?' : t.percent(min)}),
  );
  h.write('<h3>${_e(t('fit.coverage'))}</h3>');
  if (cov == null) {
    h.write('<p class="muted">${_e(t('fit.noCoverage'))}</p>');
  } else {
    h.write(
      _table(
        [t('fit.part'), t('fit.percent'), t('fit.min'), t('fit.lines')],
        [
          for (final p in shownParts)
            [
              _e(partLabel(t, p)),
              cov.parts[p] == null
                  ? _e(t('noData'))
                  : p.threshold
                  ? '<b class="${cov.parts[p]!.percent >= cov.min ? 'ok' : 'fail'}">'
                        '${_e(t.percent(cov.parts[p]!.percent))}</b>'
                  : _e(t.percent(cov.parts[p]!.percent)),
              _e(p.threshold ? t.percent(cov.min) : t('fit.noMin')),
              cov.parts[p] == null
                  ? '–'
                  : '${cov.parts[p]!.covered} / ${cov.parts[p]!.lines}',
            ],
        ],
        num: {1, 2, 3},
      ),
    );
    h.write('<p class="muted">${_e(t('asOf', {'date': _date(cov.when)}))}</p>');
    if (cov.unloaded.isNotEmpty) {
      h.write(
        '<p class="fail">${_e(t('fit.unloaded', {'files': cov.unloaded.join(', ')}))}</p>',
      );
    }
    final d = r.input.diff;
    if (d != null) {
      final text = !d.ok
          ? t('fit.diffNoData', {'base': d.base})
          : d.total == 0
          ? t('fit.diffNone', {'base': d.base})
          : t('fit.diff', {
              'base': d.base,
              'percent': t.percent(100 * d.covered / d.total),
              'covered': d.covered,
              'total': d.total,
            });
      h.write('<p>${_e(text)}</p>');
    }
  }
  h.write('<h3>${_e(t('fit.mutants'))}</h3>');
  final full = r.input.mutantsFull;
  if (full == null) {
    h.write('<p class="muted">${_e(t('fit.noMutants'))}</p>');
  } else {
    h.write(
      '<p>${_e(t('fit.mutantsFull', {'date': _date(full.date), 'head': _short(full.head)}))}</p>',
    );
    _mutantTable(h, full, t);
    h.write('<p class="rule">${_e(t('fit.mutantsRule'))}</p>');
    h.write(
      '<details><summary>${_e(t('fit.missedList', {'n': full.missed.length}))}</summary>',
    );
    if (full.missed.isEmpty) {
      h.write('<p>${_e(t('fit.missedNone'))}</p>');
    } else {
      h.write('<ul>');
      for (final m in full.missed) {
        h.write('<li><code>${_e(m)}</code></li>');
      }
      h.write('</ul>');
    }
    h.write('</details>');
  }
  final diff = r.input.mutantsDiff;
  if (diff == null) {
    h.write('<p class="muted">${_e(t('fit.noMutantsDiff'))}</p>');
  } else {
    h.write(
      '<p>${_e(t('fit.mutantsDiff', {'base': diff.base ?? '?', 'date': _date(diff.date), 'head': _short(diff.head)}))}</p>',
    );
    _mutantTable(h, diff, t);
    if (diff.missed.isNotEmpty) {
      h.write(
        '<details><summary>${_e(t('fit.missedList', {'n': diff.missed.length}))}</summary><ul>',
      );
      for (final m in diff.missed) {
        h.write('<li><code>${_e(m)}</code></li>');
      }
      h.write('</ul></details>');
    }
  }
  h.write('</section>');
}

String _short(String? sha) =>
    sha == null ? '?' : (sha.length > 7 ? sha.substring(0, 7) : sha);

void _mutantTable(StringBuffer h, MutantsData m, Texts t) {
  h.write(
    _table(
      [t('fit.part'), for (final o in mutantOutcomes) t('fit.outcome.$o')],
      [
        for (final e in m.counts.entries)
          [
            _e(e.key),
            for (final o in mutantOutcomes)
              o == 'survived' && (e.value[o] ?? 0) > 0
                  ? '<b class="hint">${e.value[o]}</b>'
                  : '${e.value[o] ?? 0}',
          ],
      ],
      num: {1, 2, 3, 4, 5},
    ),
  );
}

void _traceability(StringBuffer h, Report r, Texts t) {
  _section(h, t, 'req.title', r.traceability, t('req.rule'));
  final reqs = r.reqs;
  if (reqs == null) {
    h.write('<p class="muted">${_e(t('req.none'))}</p></section>');
    return;
  }
  h.write(
    '<p>${_e(t('req.total', {'test': r._kind(Kind.test), 'total': r.criteria, 'checked': r._kind(Kind.checked), 'manual': r._kind(Kind.manual), 'none': r._kind(Kind.none)}))}</p>',
  );
  final rows = <List<String>>[];
  for (final row in reqs) {
    final det = StringBuffer(
      '<details><summary>${_e(t('req.criteria'))}</summary><ul>',
    );
    for (var k = 0; k < row.items.length; k++) {
      final it = row.items[k];
      final ev = it.kind == Kind.checked
          ? t('req.checkedOn', {'date': it.evidence.first})
          : it.evidence.take(2).join(', ');
      det.write(
        '<li>AK${k + 1} ${_e(t('req.kind.${it.kind.name}'))}: ${_e(it.text)}'
        '${ev.isEmpty ? '' : ' <code class="muted">${_e(ev)}</code>'}</li>',
      );
    }
    det.write('</ul></details>');
    rows.add([
      '#${row.number} ${_e(row.title)} <span class="muted">'
          '(${_e(t.has('req.state.${row.state}') ? t('req.state.${row.state}') : row.state)})</span>$det',
      _e(t('req.ofN', {'n': row.count(Kind.test), 'total': row.items.length})),
      '${row.count(Kind.checked)}',
      '${row.count(Kind.manual)}',
      row.count(Kind.none) == 0
          ? '0'
          : '<b class="hint">${row.count(Kind.none)}</b>',
    ]);
  }
  h.write(
    _table(
      [
        t('req.issue'),
        t('req.test'),
        t('req.checked'),
        t('req.manual'),
        t('req.without'),
      ],
      rows,
      num: {1, 2, 3, 4},
    ),
  );
  h.write('</section>');
}

void _outcome(StringBuffer h, Report r, Texts t) {
  _section(h, t, 'esc.title', r.outcome, t('esc.rule'));
  final esc = r.esc;
  if (esc == null) {
    h.write('<p class="muted">${_e(t('req.none'))}</p>');
  } else if (esc.isEmpty) {
    h.write('<p class="muted">${_e(t('esc.none'))}</p>');
  } else {
    h.write(
      _table(
        [t('req.issue'), t('esc.found'), t('esc.which'), t('esc.regression')],
        [
          for (final e in esc)
            [
              '#${e.number} ${_e(e.title)}',
              _e(e.found),
              e.which == null ? '<b class="hint">–</b>' : _e(e.which),
              e.regression == null ? '<b class="hint">–</b>' : _e(e.regression),
            ],
        ],
      ),
    );
  }
  h.write('</section>');
}

void _history(StringBuffer h, Report r, Texts t) {
  final prev = r.input.previous;
  final cur = r.metrics;
  h.write(
    '<section id="hist"><h2>${_e(t('hist.title'))}</h2><p class="rule">'
    '${_e(prev == null ? t('hist.first') : t('hist.rule', {'version': prev.version}))}</p>',
  );
  String fmt(num? v) => v == null
      ? _e(t('noData'))
      : v is int
      ? '$v'
      : _e(t.number(v.toDouble()));
  h.write(
    _table(
      [
        t('hist.metric'),
        t('hist.current', {'version': r.input.version}),
        t('hist.previous'),
        t('hist.change'),
      ],
      [
        for (final k in metricKeys)
          [
            _e(t('hist.m.$k')),
            fmt(cur[k]),
            prev == null ? '–' : fmt(prev.metrics[k]),
            _e(delta(t, k, cur[k], prev?.metrics[k])),
          ],
      ],
      num: {1, 2, 3},
    ),
  );
  h.write('</section>');
}

String _slowItem(Texts t, TestTime s) => t('hygiene.slowItem', {
  'file': '${s.path}:${s.line}',
  'kind': t(s.widget ? 'hygiene.widget' : 'hygiene.logic'),
  'seconds': t.number(s.seconds, digits: 2),
  'name': s.name,
});

/// Short Markdown summary for the GitHub run summary.
String renderSummary(Report r, Texts t, String pagePath) {
  final i = r.input;
  final m = r.metrics;
  final cov = i.coverage;
  final b = StringBuffer()
    ..writeln(t('summary.title', {'version': i.version, 'commit': i.commit}))
    ..writeln()
    ..writeln(
      t('summary.hygiene', {'status': t('status.${r.hygiene.key}')}) +
          (m['tests'] == null
              ? ''
              : t('summary.tests', {
                  'tests': m['tests'],
                  'failed': m['failed'],
                  'flaky': m['flaky'],
                })) +
          (i.slow == null || i.slow!.isEmpty
              ? ''
              : t('summary.slow', {'n': i.slow!.length})),
    );
  for (final s in i.slow ?? const <TestTime>[]) {
    b.writeln('  - ${_slowItem(t, s)}');
  }
  b
    ..writeln(
      t('summary.fit', {'status': t('status.${r.adequacy.key}')}) +
          (cov == null
              ? ''
              : t('summary.coverage', {
                  'parts': [
                    for (final p in shownParts)
                      '${partLabel(t, p)} ${cov.parts[p] == null ? t('noData') : t.percent(cov.parts[p]!.percent)}',
                  ].join(', '),
                })) +
          (i.mutantsFull == null
              ? ''
              : t('summary.mutants', {'n': i.mutantsFull!.survived})),
    )
    ..writeln(
      t('summary.req', {'status': t('status.${r.traceability.key}')}) +
          (r.reqs == null
              ? ''
              : t('summary.criteria', {
                  'test': r._kind(Kind.test),
                  'total': r.criteria,
                  'checked': r._kind(Kind.checked),
                })),
    )
    ..writeln(t('summary.esc', {'status': t('status.${r.outcome.key}')}))
    ..writeln()
    ..writeln(t('summary.page', {'path': pagePath}));
  return b.toString();
}
