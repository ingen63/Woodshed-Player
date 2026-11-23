// Line coverage per part and of the changed lines (#8).
//
// Pure functions behind tool/coverage_check.dart and tool/coverage_diff.dart, tested in
// tool/coverage_test.dart. Only dart:io, so the tools run with plain `dart <file>` from any
// directory (the pre-push hook and its tests rely on that).
//
// Parts (rules in docs/TESTS.md, section «Abdeckung»):
// - C++ core: everything under core/src that the instrumented build compiles (llvm-cov).
// - Dart logic: app/lib without UI, web-only and generated files (flutter test --coverage).
// - Dart UI: app/lib/ui, app/lib/main.dart and every file declaring a widget; shown, no threshold.
// - Dart web only: *_web.dart or files importing package:web / dart:js_interop; the VM cannot
//   load them, so they are listed, not measured.
// - Generated: app/lib/l10n/app_localizations*.dart (gen-l10n); listed, not measured.
import 'dart:io';

/// Executable lines of one file: line number -> hits.
typedef LineHits = Map<int, int>;

/// Reads an lcov file. Paths become relative to the repository: absolute paths below [root] lose
/// the root, relative paths get [prefix] (flutter writes `lib/...` relative to `app/`).
Map<String, LineHits> parseLcov(
  String text, {
  String root = '',
  String prefix = '',
}) {
  final files = <String, LineHits>{};
  LineHits? current;
  final rootSlash = root.isEmpty || root.endsWith('/') ? root : '$root/';
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('SF:')) {
      var path = line.substring(3);
      if (rootSlash.isNotEmpty && path.startsWith(rootSlash)) {
        path = path.substring(rootSlash.length);
      } else if (!path.startsWith('/')) {
        path = '$prefix$path';
      }
      current = files.putIfAbsent(path, () => <int, int>{});
    } else if (line.startsWith('DA:') && current != null) {
      final fields = line.substring(3).split(',');
      final n = int.parse(fields[0]);
      // llvm-cov may print counters beyond 64 bits for merged profiles; such a line ran.
      final hits =
          int.tryParse(fields[1]) ??
          (RegExp(r'^\d+$').hasMatch(fields[1])
              ? 1 << 62
              : throw FormatException('bad lcov line: $line'));
      final before = current[n];
      current[n] = before == null || hits > before ? hits : before;
    } else if (line == 'end_of_record') {
      current = null;
    }
  }
  return files;
}

enum Part {
  core('C++ core (core/)', threshold: true),
  dartLogic('Dart logic (app/lib)', threshold: true),
  dartUi('Dart UI (app/lib)', threshold: false),
  dartWeb('Dart web only', threshold: false),
  generated('Generated (gen-l10n)', threshold: false),
  other('Other', threshold: false);

  const Part(this.label, {required this.threshold});

  final String label;

  /// Whether the part must reach the minimum from tools/coverage-min.
  final bool threshold;
}

final _widget = RegExp(r'extends\s+(StatelessWidget|StatefulWidget|State<)');
final _webImport = RegExp(
  r'''import\s+['"](package:web/|dart:js_interop|dart:js_interop_unsafe|dart:html)''',
);

/// Part of a file given its repository path and, for Dart, its source text.
Part classify(String path, String source) {
  if (path.startsWith('core/src/') || path.startsWith('core/include/')) {
    return Part.core;
  }
  if (!path.startsWith('app/lib/') || !path.endsWith('.dart')) {
    return Part.other;
  }
  if (path.startsWith('app/lib/l10n/app_localizations')) return Part.generated;
  if (path.endsWith('_web.dart') || _webImport.hasMatch(source)) {
    return Part.dartWeb;
  }
  if (path.startsWith('app/lib/ui/') ||
      path == 'app/lib/main.dart' ||
      _widget.hasMatch(source)) {
    return Part.dartUi;
  }
  return Part.dartLogic;
}

/// True if a Dart file has no executable code (only constants, abstract interfaces and comments), so
/// the VM reports no lines for it even when it is imported. Rule: no parenthesis outside comments, or
/// only abstract classes whose members are bodiless declarations (`Future<void> f(int a);`).
bool declarationsOnly(String source) {
  final lines = source
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('//'))
      .toList();
  if (!lines.any((l) => l.contains('('))) return true;
  final abstractClass = RegExp(r'^abstract (interface )?class \w+[^{(]*\{$');
  for (final l in lines) {
    if (l.startsWith('import ') || l == '}' || l.startsWith('@')) continue;
    if (abstractClass.hasMatch(l)) continue;
    if (l.contains('{') ||
        l.contains('=>') ||
        l.contains('=') ||
        !l.endsWith(';')) {
      return false;
    }
  }
  return true;
}

class PartResult {
  PartResult(this.part);

  final Part part;
  int lines = 0;
  int covered = 0;
  final files = <String>[];

  /// Files of this part that no test loaded (counted as failure for a part with threshold).
  final unloaded = <String>[];

  double get percent => lines == 0 ? 100 : 100 * covered / lines;
}

class CoverageResult {
  CoverageResult(this.min, this.results);

  final double min;
  final Map<Part, PartResult> results;

  /// Reasons why the check fails; empty if every part with threshold reaches [min].
  List<String> get failures {
    final out = <String>[];
    for (final r in results.values) {
      if (!r.part.threshold) continue;
      if (r.lines == 0 && r.unloaded.isEmpty) {
        out.add('${r.part.label}: no coverage data');
        continue;
      }
      if (r.percent < min) {
        out.add(
          '${r.part.label}: ${formatPercent(r.percent)} is below '
          '${formatPercent(min)}',
        );
      }
      for (final f in r.unloaded) {
        out.add('${r.part.label}: $f is not loaded by any test');
      }
    }
    return out;
  }
}

/// Coverage per part. [coverage] is the merged lcov data (repository paths), [sources] the source
/// text of every Dart file under app/lib (path -> text), so files without data are found too.
CoverageResult evaluate({
  required double min,
  required Map<String, LineHits> coverage,
  required Map<String, String> sources,
}) {
  final results = {for (final p in Part.values) p: PartResult(p)};
  for (final entry in coverage.entries) {
    final part = classify(entry.key, sources[entry.key] ?? '');
    final r = results[part]!..files.add(entry.key);
    r.lines += entry.value.length;
    r.covered += entry.value.values.where((h) => h > 0).length;
  }
  for (final entry in sources.entries) {
    if (coverage.containsKey(entry.key)) continue;
    final part = classify(entry.key, entry.value);
    final r = results[part]!..files.add(entry.key);
    if (part == Part.dartLogic || part == Part.dartUi) {
      if (!declarationsOnly(entry.value)) r.unloaded.add(entry.key);
    }
  }
  for (final r in results.values) {
    r.files.sort();
    r.unloaded.sort();
  }
  return CoverageResult(min, results);
}

String formatPercent(double p) => '${p.toStringAsFixed(1)} %';

/// Report of [evaluate] for the terminal.
String report(CoverageResult e) {
  final b = StringBuffer(
    'Line coverage per part (minimum ${formatPercent(e.min)} from '
    'tools/coverage-min)\n',
  );
  for (final part in [Part.core, Part.dartLogic, Part.dartUi]) {
    final r = e.results[part]!;
    final rule = part.threshold
        ? (r.percent >= e.min && r.unloaded.isEmpty ? 'ok' : 'BELOW MINIMUM')
        : 'shown, no minimum';
    b.writeln(
      '  ${part.label.padRight(24)} ${formatPercent(r.percent).padLeft(8)}'
      '  (${r.covered} of ${r.lines} lines)  $rule',
    );
  }
  final web = e.results[Part.dartWeb]!;
  if (web.files.isNotEmpty) {
    b.writeln(
      '  Dart web only, not measurable in the VM (docs/TESTS.md): '
      '${web.files.join(', ')}',
    );
  }
  final gen = e.results[Part.generated]!;
  if (gen.files.isNotEmpty) {
    b.writeln('  Generated, not counted: ${gen.files.join(', ')}');
  }
  final failures = e.failures;
  if (failures.isEmpty) {
    b.writeln('Every part reaches the minimum.');
  } else {
    b.writeln('Coverage check failed:');
    for (final f in failures) {
      b.writeln('  - $f');
    }
  }
  return b.toString();
}

/// Reads the minimum (a number of percent) from the text of tools/coverage-min.
double parseMinimum(String text) {
  final value = double.tryParse(text.trim());
  if (value == null || value < 0 || value > 100) {
    throw FormatException('tools/coverage-min must hold a percentage: $text');
  }
  return value;
}

/// Source files whose changed lines coverage-diff looks at.
final measuredSource = RegExp(r'\.(dart|c|cc|cpp|h|hpp|mm)$');

/// Changed or added lines per file from `git diff -U0` output.
Map<String, Set<int>> changedLines(String diff) {
  final files = <String, Set<int>>{};
  String? current;
  final hunk = RegExp(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@');
  for (final line in diff.split('\n')) {
    if (line.startsWith('+++ ')) {
      current = line == '+++ /dev/null' ? null : line.substring(6);
    } else if (current != null) {
      final m = hunk.firstMatch(line);
      if (m == null) continue;
      final start = int.parse(m.group(1)!);
      final count = m.group(2) == null ? 1 : int.parse(m.group(2)!);
      final set = files.putIfAbsent(current, () => <int>{});
      for (var i = start; i < start + count; i++) {
        set.add(i);
      }
    }
  }
  files.removeWhere((_, s) => s.isEmpty);
  return files;
}

/// «3, 5–7» for {3, 5, 6, 7}.
String lineRanges(Iterable<int> lines) {
  final sorted = lines.toList()..sort();
  final out = <List<int>>[];
  for (final n in sorted) {
    if (out.isNotEmpty && n == out.last[1] + 1) {
      out.last[1] = n;
    } else {
      out.add([n, n]);
    }
  }
  return out
      .map((r) => r[0] == r[1] ? '${r[0]}' : '${r[0]}–${r[1]}')
      .join(', ');
}

/// Markdown report of the coverage of the changed executable lines. A hint, never a gate.
String diffReport(
  Map<String, Set<int>> changed,
  Map<String, LineHits> coverage, {
  required String base,
}) {
  final b = StringBuffer('### Coverage of the changed code (base $base)\n\n');
  if (changed.isEmpty) {
    b.writeln('No changed source files.');
    return b.toString();
  }
  var total = 0, covered = 0;
  final missing = <String, List<int>>{};
  for (final file in changed.keys.toList()..sort()) {
    final hits = coverage[file] ?? const <int, int>{};
    for (final n in changed[file]!) {
      final h = hits[n];
      if (h == null) continue; // not executable or not measured
      total++;
      if (h > 0) {
        covered++;
      } else {
        missing.putIfAbsent(file, () => []).add(n);
      }
    }
  }
  if (total == 0) {
    b.writeln(
      'No changed executable lines (only comments, declarations, tests or '
      'files outside the measurement).',
    );
    return b.toString();
  }
  b.writeln(
    '**${formatPercent(100 * covered / total)}** of the changed executable '
    'lines are run by tests ($covered of $total). This is a hint, not a '
    'gate; the minimum applies per part.\n',
  );
  if (missing.isEmpty) {
    b.writeln('Every changed executable line is covered.');
  } else {
    b.writeln('Lines not covered:\n');
    missing.forEach((f, lines) => b.writeln('- `$f`: ${lineRanges(lines)}'));
  }
  return b.toString();
}

/// Merges lcov data of several files (highest hit count per line).
Map<String, LineHits> merge(Iterable<Map<String, LineHits>> parts) {
  final out = <String, LineHits>{};
  for (final part in parts) {
    part.forEach((file, hits) {
      final target = out.putIfAbsent(file, () => <int, int>{});
      hits.forEach((n, h) {
        final before = target[n];
        target[n] = before == null || h > before ? h : before;
      });
    });
  }
  return out;
}

/// Coverage files of `make coverage-run`, relative to the repository [root].
const dartLcov = 'app/coverage/lcov.info';
const coreLcov = 'core/build-cov/lcov.info';

/// Reads both coverage files below [root]; throws [FileSystemException] if one is missing.
Map<String, LineHits> readCoverage(String root) {
  final dart = File('$root/$dartLcov');
  final core = File('$root/$coreLcov');
  for (final f in [dart, core]) {
    if (!f.existsSync()) {
      throw FileSystemException(
        'coverage file missing, run make coverage',
        f.path,
      );
    }
  }
  return merge([
    parseLcov(dart.readAsStringSync(), root: root, prefix: 'app/'),
    parseLcov(core.readAsStringSync(), root: root),
  ]);
}

/// Source text of every Dart file under app/lib (repository paths).
Map<String, String> readDartSources(String root) {
  final dir = Directory('$root/app/lib');
  if (!dir.existsSync()) return {};
  final out = <String, String>{};
  for (final f in dir.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    out[f.path.substring(root.length + 1)] = f.readAsStringSync();
  }
  return out;
}
