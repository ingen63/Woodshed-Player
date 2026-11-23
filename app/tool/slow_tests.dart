// Slow Dart tests (#128): lists every test of `flutter test --file-reporter json:<file>` that takes
// longer than its limit and has no `// slow: <reason>` comment directly above it. A hint, never an
// error. Tested in tool/slow_tests_test.dart; used by the overview page (tool/report/, layer
// «Hygiene»). Only dart:io and dart:convert (no package), like tool/coverage.dart.
//
// Usage: dart app/tool/slow_tests.dart [<flutter json> ...]
//   default: local/test-quality/flutter/app.json below the repository (written by make test-app)
// Prints one line per slow test without a reason (file:line, kind, seconds, name). Exit code 0, also
// with findings; 2 on wrong usage.
//
// Rules (docs/TESTS.md, «Laufzeitgrenze für Dart-Tests (#128)»):
// - A widget test is one declared with `testWidgets` (the JSON reporter names
//   package:flutter_test/src/widget_tester.dart as its location); every other test is a logic test.
// - The time of a test is from its testStart to its testDone event. Loading a file («loading …»),
//   setUpAll and tearDownAll are hidden tests and never count.
// - The reason is a comment line `// slow: <reason>` in the block of comment lines directly above
//   the line that declares the test (root_line of the JSON reporter, else line).
import 'dart:convert';
import 'dart:io';

/// Limit of a logic test (`test`) in seconds.
const logicLimit = 0.25;

/// Limit of a widget test (`testWidgets`) in seconds.
const widgetLimit = 2.0;

const _widgetTester = 'package:flutter_test/src/widget_tester.dart';

/// One test with its declaration and its run time.
class TestTime {
  TestTime({
    required this.path,
    required this.line,
    required this.name,
    required this.seconds,
    required this.widget,
  });

  /// File that declares the test (absolute path from the reporter), empty if unknown.
  final String path;

  /// Line of the declaration, 0 if unknown.
  final int line;
  final String name;
  final double seconds;
  final bool widget;

  double get limit => widget ? widgetLimit : logicLimit;
}

/// The run times of the visible tests in [jsonLines] (one JSON event per line). Lines that are no
/// JSON are skipped.
List<TestTime> testTimes(String jsonLines) {
  final starts = <int, (Map<String, Object?>, int)>{};
  final out = <TestTime>[];
  for (final line in const LineSplitter().convert(jsonLines)) {
    Object? e;
    try {
      e = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (e is! Map<String, Object?>) continue;
    switch (e['type']) {
      case 'testStart':
        final t = e['test']! as Map<String, Object?>;
        starts[t['id']! as int] = (t, (e['time'] as int?) ?? 0);
      case 'testDone':
        final s = starts[e['testID']! as int];
        if (s == null || e['hidden'] == true || e['skipped'] == true) continue;
        final (t, start) = s;
        final url = (t['root_url'] ?? t['url']) as String?;
        out.add(
          TestTime(
            path: url == null ? '' : _filePath(url),
            line: ((t['root_line'] ?? t['line']) as int?) ?? 0,
            name: '${t['name'] ?? ''}',
            seconds: (((e['time'] as int?) ?? start) - start) / 1000,
            widget: t['url'] == _widgetTester,
          ),
        );
    }
  }
  return out;
}

String _filePath(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && uri.scheme == 'file' ? uri.toFilePath() : url;
}

/// Whether the comment block directly above [line] (1-based) of [source] holds `// slow: <reason>`.
bool hasSlowReason(List<String> source, int line) {
  for (var i = line - 2; i >= 0 && i < source.length; i--) {
    final l = source[i].trim();
    if (!l.startsWith('//')) return false;
    if (RegExp(r'^//\s*slow:\s*\S').hasMatch(l)) return true;
  }
  return false;
}

/// The tests over their limit without a reason, slowest first. [source] returns the lines of a
/// file (null if it cannot be read: then the test counts as without reason).
List<TestTime> slowTests(
  String jsonLines,
  List<String>? Function(String path) source,
) {
  final cache = <String, List<String>?>{};
  return [
    for (final t in testTimes(jsonLines))
      if (t.seconds > t.limit &&
          !hasSlowReason(
            cache.putIfAbsent(t.path, () => source(t.path)) ?? const [],
            t.line,
          ))
        t,
  ]..sort((a, b) => b.seconds.compareTo(a.seconds));
}

/// Reads a source file for [slowTests]; null if it does not exist.
List<String>? readSource(String path) {
  final f = File(path);
  return f.existsSync() ? f.readAsLinesSync() : null;
}

/// [path] relative to [root] (the repository), unchanged outside it.
String relativePath(String path, String root) {
  final r = root.endsWith('/') ? root : '$root/';
  return path.startsWith(r) ? path.substring(r.length) : path;
}

void main(List<String> args) {
  if (args.any((a) => a.startsWith('-'))) {
    stderr.writeln('usage: dart app/tool/slow_tests.dart [<flutter json> ...]');
    exit(2);
  }
  final top = Process.runSync('git', ['rev-parse', '--show-toplevel']);
  final root = top.exitCode == 0
      ? '${top.stdout}'.trim()
      : Directory.current.path;
  final files = args.isEmpty
      ? ['$root/local/test-quality/flutter/app.json']
      : args;
  for (final f in files) {
    final file = File(f);
    if (!file.existsSync()) {
      stdout.writeln('slow tests: no data ($f missing)');
      continue;
    }
    final slow = slowTests(file.readAsStringSync(), readSource);
    stdout.writeln(
      'slow tests in $f: ${slow.length} without «// slow: <reason>» '
      '(limits: logic ${logicLimit}s, widget ${widgetLimit}s)',
    );
    for (final t in slow) {
      stdout.writeln(
        '  ${relativePath(t.path, root)}:${t.line} '
        '${t.widget ? 'widget' : 'logic'} '
        '${t.seconds.toStringAsFixed(2)}s  ${t.name}',
      );
    }
  }
}
