// Writes the overview page «Testqualität» (#12) from the existing results; `make report`.
//
// Usage: dart app/tool/report/report_run.dart [--root <repository>] [--out <folder>]
//          [--base <commit>] [--texts <file>] [--no-gh] [--summary]
//   --out      output folder (default local/test-quality/report), the page is index.html
//   --base     base of the coverage of the changed lines (default DIFF_BASE, else origin/main)
//   --texts    text table of the page (default texts_de.json next to this file)
//   --no-gh    do not ask GitHub (layers 3 and 4 show «no data»)
//   --summary  also a short Markdown summary on standard output (GitHub run summary)
// Inputs below the repository, each optional (missing data is shown as such, never an error):
//   local/test-quality/junit/*.xml     JUnit: ctest (core.xml); flutter test writes JSON to
//                                      local/test-quality/flutter/<name>.json, converted here to
//                                      junit/<name>.xml
//   app/coverage/lcov.info, core/build-cov/lcov.info, tools/coverage-min   (make coverage-run)
//   local/mutants/full|diff/results.json   (make mutants, make mutants-diff)
//   issues and comments via `gh issue list` (only while generating; the app never does this)
// History per version: local/test-quality/history/<version>.json. Exit code 0, 2 on wrong usage.
import 'dart:convert';
import 'dart:io';

import '../coverage.dart';
import 'report.dart';

String? _run(String exe, List<String> args, String dir) {
  try {
    final r = Process.runSync(exe, args, workingDirectory: dir);
    return r.exitCode == 0 ? '${r.stdout}' : null;
  } on ProcessException {
    return null;
  }
}

Never _usage() {
  stderr.writeln(
    'usage: dart app/tool/report/report_run.dart [--root <dir>] [--out <dir>] '
    '[--base <commit>] [--texts <file>] [--no-gh] [--summary]',
  );
  exit(2);
}

/// Converts every flutter JSON result into JUnit and reads the JUnit files; core, app and tools
/// always appear (without file as «no data»).
List<JUnitSource> readJUnit(String root) {
  final flutterDir = Directory('$root/local/test-quality/flutter');
  final junitDir = Directory('$root/local/test-quality/junit');
  if (flutterDir.existsSync()) {
    junitDir.createSync(recursive: true);
    for (final f in flutterDir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      final name = f.uri.pathSegments.last.replaceFirst(RegExp(r'\.json$'), '');
      final out = File('${junitDir.path}/$name.xml');
      if (out.existsSync() &&
          !out.lastModifiedSync().isBefore(f.lastModifiedSync())) {
        continue;
      }
      out.writeAsStringSync(
        flutterJsonToJUnit(f.readAsStringSync(), suiteName: name),
      );
      out.setLastModifiedSync(f.lastModifiedSync());
    }
  }
  final names = {'core', 'app', 'tools'};
  if (junitDir.existsSync()) {
    for (final f in junitDir.listSync().whereType<File>()) {
      if (f.path.endsWith('.xml')) {
        names.add(f.uri.pathSegments.last.replaceFirst(RegExp(r'\.xml$'), ''));
      }
    }
  }
  return [
    for (final n in names)
      () {
        final f = File('${junitDir.path}/$n.xml');
        if (!f.existsSync()) return JUnitSource(n);
        try {
          final cases = parseJUnit(f.readAsStringSync());
          // an aborted run without a single test case is no data
          if (cases.isEmpty) return JUnitSource(n);
          return JUnitSource(n, cases: cases, when: f.lastModifiedSync());
        } on FileSystemException catch (e) {
          return JUnitSource(n, error: e.message);
        }
      }(),
  ];
}

MutantsData? _mutants(String root, String mode) {
  final f = File('$root/local/mutants/$mode/results.json');
  return f.existsSync() ? parseMutants(f.readAsStringSync()) : null;
}

DiffCoverage? _diffCoverage(String root, String base) {
  if (_run('git', [
        'rev-parse',
        '--verify',
        '--quiet',
        '$base^{commit}',
      ], root) ==
      null) {
    return DiffCoverage(base, ok: false);
  }
  final changed = <String, Set<int>>{};
  for (final spec in ['$base...HEAD', base]) {
    final diff = _run('git', [
      'diff',
      '-U0',
      '--no-color',
      '--no-ext-diff',
      spec,
    ], root);
    if (diff == null) return DiffCoverage(base, ok: false);
    changedLines(diff)
        .forEach((f, l) => changed.putIfAbsent(f, () => <int>{}).addAll(l));
  }
  try {
    return diffCoverage(changed, readCoverage(root), base);
  } on FileSystemException {
    return null;
  }
}

List<Map<String, Object?>>? _issues(String root) {
  final out = _run('gh', [
    'issue',
    'list',
    '--state',
    'all',
    '--limit',
    '2000',
    '--json',
    'number,title,state,stateReason,labels,body,comments',
  ], root);
  if (out == null) return null;
  try {
    return [
      for (final i in jsonDecode(out) as List<Object?>)
        (i! as Map).cast<String, Object?>(),
    ];
  } on Object {
    return null;
  }
}

String _version(String root) {
  final f = File('$root/app/pubspec.yaml');
  if (!f.existsSync()) return '?';
  final m = RegExp(
    r'^version:\s*(\S+)',
    multiLine: true,
  ).firstMatch(f.readAsStringSync());
  return m?.group(1) ?? '?';
}

void main(List<String> args) {
  String? root, out, base, texts;
  var gh = true, summary = false;
  for (var i = 0; i < args.length; i++) {
    String next() => i + 1 < args.length ? args[++i] : _usage();
    switch (args[i]) {
      case '--root':
        root = next();
      case '--out':
        out = next();
      case '--base':
        base = next();
      case '--texts':
        texts = next();
      case '--no-gh':
        gh = false;
      case '--summary':
        summary = true;
      default:
        _usage();
    }
  }
  final top = _run('git', [
    'rev-parse',
    '--show-toplevel',
  ], root ?? Directory.current.path)?.trim();
  final repo = Directory(top ?? root ?? Directory.current.path).absolute.path
      .replaceFirst(RegExp(r'/$'), '');
  final outDir = Directory(
    out == null
        ? '$repo/local/test-quality/report'
        : (out.startsWith('/') ? out : '${Directory.current.path}/$out'),
  )..createSync(recursive: true);
  final textFile = File(
    texts ?? Platform.script.resolve('texts_de.json').toFilePath(),
  );
  final t = Texts.parse(textFile.readAsStringSync());

  CoverageData? coverage;
  final minFile = File('$repo/tools/coverage-min');
  try {
    if (minFile.existsSync()) {
      coverage = readCoverageData(
        repo,
        parseMinimum(minFile.readAsStringSync()),
      );
    }
  } on FormatException catch (e) {
    stderr.writeln('report: ${e.message}');
  }
  final diffBase = base ?? Platform.environment['DIFF_BASE'] ?? 'origin/main';
  final files =
      _run('git', [
        'ls-files',
        '--cached',
        '--others',
        '--exclude-standard',
      ], repo)?.split('\n').where((l) => l.isNotEmpty).toList() ??
      const <String>[];
  final input = ReportInput(
    version: _version(repo),
    commit: _run('git', ['rev-parse', '--short', 'HEAD'], repo)?.trim() ?? '?',
    generated: DateTime.now(),
    junit: readJUnit(repo),
    coverage: coverage,
    diff: coverage == null ? null : _diffCoverage(repo, diffBase),
    mutantsFull: _mutants(repo, 'full'),
    mutantsDiff: _mutants(repo, 'diff'),
    issues: gh ? _issues(repo) : null,
    marks: testMarks(repo, files),
  );
  final report = Report(input, t);
  input.previous = recordHistory(
    Directory('$repo/local/test-quality/history'),
    input.version,
    report.metrics,
  );
  final page = File('${outDir.path}/index.html')
    ..writeAsStringSync(renderPage(report, t));
  stderr.writeln('report: ${page.path}');
  if (summary) stdout.write(renderSummary(report, t, page.path));
}
