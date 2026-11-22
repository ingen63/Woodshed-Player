// Mutation tests (#11): shared code of tool/mutants_run.dart (make mutants, make mutants-diff) and
// its tests (tool/mutants_test.dart). Strategy, limits and open mutants: docs/TESTS.md
// «Mutationstests (#11)».
//
// - C++ core: Mull (compiler plugin and mull-runner) mutates core/src and core/web; this file reads
//   its reports (Mutation Testing Elements JSON) and merges the test programs.
// - Dart logic: an own, small mutator without a new dependency. It changes one operator, literal or
//   call in a copy of app/, runs the tests that import the file and judges the outcome.
// - Both: exclusions with a reason (tools/mutants-exclude.txt), outcome, summary.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' show max;

/// Outcome of one mutant. «timeout» counts as detected (an endless loop), like in VivaPlan.
enum Outcome { killed, timeout, survived, excluded, unviable }

/// Labels of the summary.
const outcomeLabels = {
  Outcome.killed: 'killed',
  Outcome.timeout: 'timeout',
  Outcome.survived: 'not detected',
  Outcome.excluded: 'excluded',
  Outcome.unviable: 'not compilable',
};

class Mutant {
  Mutant({
    required this.part,
    required this.file,
    required this.line,
    required this.column,
    required this.mutator,
    required this.replacement,
    required this.code,
    this.outcome = Outcome.survived,
    this.note,
  });

  /// 'core' or 'dart'.
  final String part;

  /// Path relative to the repository root.
  final String file;
  final int line;
  final int column;
  final String mutator;
  final String replacement;

  /// The source line, trimmed.
  final String code;
  Outcome outcome;

  /// Reason of an exclusion, or how it was detected («memory limit», «not covered»).
  String? note;

  String get key => '$file:$line:$column:$mutator';

  factory Mutant.fromJson(Map<String, Object?> j) => Mutant(
    part: j['part']! as String,
    file: j['file']! as String,
    line: j['line']! as int,
    column: j['column']! as int,
    mutator: j['mutator']! as String,
    replacement: (j['replacement'] as String?) ?? '',
    code: (j['code'] as String?) ?? '',
    outcome: Outcome.values.byName(j['outcome']! as String),
    note: j['note'] as String?,
  );

  Map<String, Object?> toJson() => {
    'part': part,
    'file': file,
    'line': line,
    'column': column,
    'mutator': mutator,
    'replacement': replacement,
    'code': code,
    'outcome': outcome.name,
    if (note != null) 'note': note,
  };
}

// ---------------------------------------------------------------------------------------------
// Dart mutations
// ---------------------------------------------------------------------------------------------

/// Which characters of a Dart source are code (true), not comment or string literal. String
/// interpolation counts as string: nothing inside a literal is mutated.
List<bool> codeMask(String s) {
  final mask = List<bool>.filled(s.length, false);
  _scanCode(s, 0, mask, interpolation: false);
  return mask;
}

bool _isIdent(String c) => RegExp(r'[A-Za-z0-9_$]').hasMatch(c);

int _scanCode(String s, int i, List<bool> mask, {required bool interpolation}) {
  var depth = 0;
  while (i < s.length) {
    final c = s[i];
    final next = i + 1 < s.length ? s[i + 1] : '';
    if (c == '/' && next == '/') {
      while (i < s.length && s[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && next == '*') {
      var nesting = 0;
      while (i < s.length) {
        if (s.startsWith('/*', i)) {
          nesting++;
          i += 2;
        } else if (s.startsWith('*/', i)) {
          nesting--;
          i += 2;
          if (nesting == 0) break;
        } else {
          i++;
        }
      }
      continue;
    }
    if (c == "'" || c == '"') {
      final raw = i > 0 && s[i - 1] == 'r' && (i < 2 || !_isIdent(s[i - 2]));
      i = _scanString(s, i, mask, raw: raw);
      continue;
    }
    if (interpolation) {
      if (c == '{') depth++;
      if (c == '}') {
        if (depth == 0) return i + 1;
        depth--;
      }
    } else {
      mask[i] = true;
    }
    i++;
  }
  return i;
}

int _scanString(String s, int i, List<bool> mask, {required bool raw}) {
  final q = s[i];
  final triple = s.startsWith(q * 3, i);
  final close = triple ? q * 3 : q;
  i += close.length;
  while (i < s.length) {
    if (!raw && s[i] == r'\') {
      i += 2;
      continue;
    }
    if (s.startsWith(close, i)) return i + close.length;
    if (!raw && s[i] == r'$' && i + 1 < s.length && s[i + 1] == '{') {
      i = _scanCode(s, i + 2, mask, interpolation: true);
      continue;
    }
    if (!triple && s[i] == '\n') return i;
    i++;
  }
  return i;
}

/// One possible change of a Dart source: replace [length] characters at [offset].
class DartSite {
  DartSite(
    this.offset,
    this.length,
    this.replacement,
    this.mutator,
    this.line,
    this.column,
  );
  final int offset;
  final int length;
  final String replacement;
  final String mutator;
  final int line;
  final int column;

  String apply(String source) =>
      source.replaceRange(offset, offset + length, replacement);
}

/// Binary operators: dart format puts one space on each side, never inside type arguments
/// (`List<int>`) or arrows (`=>`), so « < » is always a comparison.
const _binary = [
  (' < ', ' <= ', 'dart_lt_to_le'),
  (' <= ', ' < ', 'dart_le_to_lt'),
  (' > ', ' >= ', 'dart_gt_to_ge'),
  (' >= ', ' > ', 'dart_ge_to_gt'),
  (' == ', ' != ', 'dart_eq_to_ne'),
  (' != ', ' == ', 'dart_ne_to_eq'),
  (' && ', ' || ', 'dart_and_to_or'),
  (' || ', ' && ', 'dart_or_to_and'),
  (' + ', ' - ', 'dart_add_to_sub'),
  (' - ', ' + ', 'dart_sub_to_add'),
  (' * ', ' / ', 'dart_mul_to_div'),
  (' / ', ' * ', 'dart_div_to_mul'),
  (' ~/ ', ' * ', 'dart_intdiv_to_mul'),
  (' % ', ' ~/ ', 'dart_rem_to_intdiv'),
  (' += ', ' -= ', 'dart_add_assign_to_sub_assign'),
  (' -= ', ' += ', 'dart_sub_assign_to_add_assign'),
];

final _statementCall = RegExp(
  r'^(\s*)(await\s+)?[A-Za-z_$][\w$]*(\??\.[A-Za-z_$][\w$]*)*\(.*\);\s*$',
);

/// Every mutation of [source]: binary operators, ++/--, removal of a negation, true/false, and
/// removal of a call that is a statement of its own on one line (like Mull's
/// cxx_remove_void_call). Only code counts (codeMask), never comments or strings.
List<DartSite> dartMutations(String source) {
  final mask = codeMask(source);
  final lineStarts = <int>[0];
  for (var i = 0; i < source.length; i++) {
    if (source[i] == '\n') lineStarts.add(i + 1);
  }
  int lineOf(int offset) {
    var lo = 0, hi = lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (lineStarts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  bool code(int from, int to) {
    for (var i = from; i < to; i++) {
      if (i >= mask.length || !mask[i]) return false;
    }
    return true;
  }

  final sites = <DartSite>[];
  void add(int offset, int length, String replacement, String mutator) {
    final l = lineOf(offset);
    sites.add(
      DartSite(
        offset,
        length,
        replacement,
        mutator,
        l + 1,
        offset - lineStarts[l] + 1,
      ),
    );
  }

  for (final (pattern, replacement, mutator) in _binary) {
    var i = source.indexOf(pattern);
    while (i >= 0) {
      // the operator itself (without the spaces) must be code
      if (code(i + 1, i + pattern.length - 1)) {
        add(i + 1, pattern.length - 2, replacement.trim(), mutator);
      }
      i = source.indexOf(pattern, i + 1);
    }
  }
  for (final (op, replacement, mutator) in [
    ('++', '--', 'dart_inc_to_dec'),
    ('--', '++', 'dart_dec_to_inc'),
  ]) {
    var i = source.indexOf(op);
    while (i >= 0) {
      final before = i > 0 ? source[i - 1] : ' ';
      final after = i + 2 < source.length ? source[i + 2] : ' ';
      // i++ / ++i, not «---» or «-- » in a comment (the mask already drops comments)
      if (code(i, i + 2) &&
          (_isIdent(before) ||
              before == ')' ||
              before == ']' ||
              _isIdent(after)) &&
          before != op[0] &&
          after != op[0]) {
        add(i, 2, replacement, mutator);
      }
      i = source.indexOf(op, i + 2);
    }
  }
  // prefix ! (not !=, not the postfix null check x!)
  for (var i = 0; i < source.length; i++) {
    if (source[i] != '!' || !mask[i]) continue;
    final before = i > 0 ? source[i - 1] : ' ';
    final after = i + 1 < source.length ? source[i + 1] : ' ';
    if (after == '=') continue;
    if (!' (![{,\n'.contains(before)) continue;
    if (!RegExp(r'[A-Za-z_$(!]').hasMatch(after)) continue;
    add(i, 1, '', 'dart_remove_negation');
  }
  for (final (word, replacement, mutator) in [
    ('true', 'false', 'dart_true_to_false'),
    ('false', 'true', 'dart_false_to_true'),
  ]) {
    for (final m in RegExp('\\b$word\\b').allMatches(source)) {
      if (!code(m.start, m.end)) continue;
      // a named parameter or field called «true...» cannot exist, but `.true` could
      if (m.start > 0 && source[m.start - 1] == '.') continue;
      add(m.start, word.length, replacement, mutator);
    }
  }
  // a call as a statement of its own: the previous code line ends a statement or opens a block
  final lines = source.split('\n');
  var previous = '';
  for (var l = 0; l < lines.length; l++) {
    final text = lines[l];
    final start = lineStarts[l];
    final m = _statementCall.firstMatch(text);
    final trimmed = text.trim();
    if (m != null &&
        !trimmed.startsWith('return') &&
        !trimmed.startsWith('super(') &&
        !trimmed.startsWith('assert(') &&
        (previous.endsWith(';') ||
            previous.endsWith('{') ||
            previous.endsWith('}')) &&
        _balanced(trimmed) &&
        code(start + m.group(1)!.length, start + text.trimRight().length)) {
      final indent = m.group(1)!.length;
      add(
        start + indent,
        text.trimRight().length - indent,
        '{}',
        'dart_remove_void_call',
      );
    }
    final codeText = _codeOnly(text, mask, start).trim();
    if (codeText.isNotEmpty) previous = codeText;
  }
  sites.sort((a, b) => a.offset.compareTo(b.offset));
  return sites;
}

bool _balanced(String s) {
  var depth = 0;
  for (final c in s.split('')) {
    if (c == '(') depth++;
    if (c == ')') depth--;
    if (depth < 0) return false;
  }
  return depth == 0;
}

String _codeOnly(String line, List<bool> mask, int start) {
  final b = StringBuffer();
  for (var i = 0; i < line.length; i++) {
    final at = start + i;
    b.write(at < mask.length && mask[at] ? line[i] : ' ');
  }
  return b.toString();
}

/// Why a file of app/lib is not mutated, or null if it is Dart logic (docs/TESTS.md): no UI
/// (Flutter widgets, Material), no web code (runs only in the browser) and not the app start.
String? dartScopeExclusion(String path, String source) {
  if (path.startsWith('app/lib/l10n/')) return 'generated (gen-l10n)';
  if (path == 'app/lib/main.dart' || path == 'app/lib/app/smoke.dart') {
    return 'app start (smoke test, UI tests)';
  }
  if (path == 'app/lib/app/app_controller.dart') {
    // its nearest tests are mostly widget tests: each mutant took minutes (#115: 80 mutants)
    return 'wiring of the UI (widget tests, UI tests)';
  }
  if (path.endsWith('_web.dart') ||
      RegExp(r'''import 'dart:js_interop|import 'package:web/''')
          .hasMatch(source)) {
    return 'web code (web tests in Chrome)';
  }
  if (RegExp(
    r'''import 'package:(flutter/(material|widgets|cupertino)|material_ui/)''',
  ).hasMatch(source)) {
    return 'UI (widget tests, UI tests)';
  }
  return null;
}

// ---------------------------------------------------------------------------------------------
// Test selection: the test files that import a file of app/lib, directly or through other files
// ---------------------------------------------------------------------------------------------

final _directive = RegExp(
  r'''^\s*(?:import|export|part)\s+([^;]*);''',
  multiLine: true,
);
final _uri = RegExp(r'''['"]([^'"]+\.dart)['"]''');

/// Dependencies per file (paths relative to app/) from import, export and part directives,
/// conditional imports included. [sources] maps app-relative paths to their text.
Map<String, Set<String>> importGraph(
  Map<String, String> sources, {
  String package = 'woodshed_player',
}) {
  final graph = <String, Set<String>>{};
  for (final MapEntry(key: path, value: text) in sources.entries) {
    final deps = graph.putIfAbsent(path, () => <String>{});
    for (final d in _directive.allMatches(text)) {
      for (final u in _uri.allMatches(d.group(1)!)) {
        final uri = u.group(1)!;
        if (uri.startsWith('package:$package/')) {
          deps.add('lib/${uri.substring('package:$package/'.length)}');
        } else if (!uri.contains(':')) {
          final dir = path.contains('/')
              ? path.substring(0, path.lastIndexOf('/'))
              : '';
          deps.add(_normalize(dir.isEmpty ? uri : '$dir/$uri'));
        }
      }
    }
  }
  return graph;
}

String _normalize(String path) {
  final out = <String>[];
  for (final part in path.split('/')) {
    if (part == '.' || part.isEmpty) continue;
    if (part == '..' && out.isNotEmpty && out.last != '..') {
      out.removeLast();
    } else {
      out.add(part);
    }
  }
  return out.join('/');
}

/// The test files of [tests] closest to [target] in the import graph: those that import it
/// directly; if none does, those that import a file importing it, and so on. A mutant runs only
/// these (#11/AK3): the unit tests of a file are meant to detect its mutants, and the widget tests
/// that reach nearly every file through the UI would make each mutant take a minute.
List<String> testsFor(
  String target,
  Map<String, Set<String>> graph,
  Iterable<String> tests,
) {
  final importers = <String, Set<String>>{};
  graph.forEach((file, deps) {
    for (final d in deps) {
      importers.putIfAbsent(d, () => <String>{}).add(file);
    }
  });
  final testSet = tests.toSet();
  final seen = <String>{target};
  var level = <String>{target};
  while (level.isNotEmpty) {
    final next = <String>{};
    for (final f in level) {
      for (final i in importers[f] ?? const <String>{}) {
        if (seen.add(i)) next.add(i);
      }
    }
    final found = next.where(testSet.contains).toList()..sort();
    if (found.isNotEmpty) return found;
    level = next;
  }
  return const [];
}

// ---------------------------------------------------------------------------------------------
// Exclusions with a reason (#11/AK2), tools/mutants-exclude.txt
// ---------------------------------------------------------------------------------------------

class Exclusion {
  Exclusion(
    this.file,
    this.mutator,
    this.code,
    this.reason,
    this.lineNumber, {
    this.column,
  });
  final String file;

  /// Only the mutant at this column (when the line holds the operator more than once).
  final int? column;
  final String mutator;
  final String code;
  final String reason;
  final int lineNumber;
  var used = 0;
}

/// Kinds of reasons allowed (docs/TESTS.md): equivalent mutants, boundary cases, and in the core
/// (#61/AK3) the release of memory without an observable effect and Mull's limit (a mutant Mull
/// does not switch effectively, measured by hand).
const exclusionKinds = [
  'gleichwertig',
  'Grenzfall',
  'Speicherfreigabe',
  'Mull-Grenze',
];

String _squash(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Reads the exclusion file. An entry is `<file> | <mutator> | <source line>`, optionally followed
/// by `| <column>` when the line holds the operator more than once; it needs a reason
/// above it: a comment block starting with one of [exclusionKinds] and a colon. Entries right
/// below each other share the reason, an empty line ends it. Throws a [FormatException] for an
/// entry without a reason or with a malformed line.
List<Exclusion> parseExclusions(String text) {
  final out = <Exclusion>[];
  String? reason;
  var inComment = false;
  final lines = text.split('\n');
  for (var n = 0; n < lines.length; n++) {
    final line = lines[n].trim();
    if (line.isEmpty) {
      reason = null;
      inComment = false;
      continue;
    }
    if (line.startsWith('#')) {
      final body = line.substring(1).trim();
      final kind = exclusionKinds
          .where((k) => body.startsWith('$k:'))
          .firstOrNull;
      if (kind != null) {
        reason = body;
        inComment = true;
      } else if (inComment && reason != null) {
        reason = '$reason $body';
      } else if (!inComment || reason == null) {
        reason = null; // a plain comment (header) gives no reason
      }
      continue;
    }
    inComment = false;
    // fields are separated by « | » (a source line may hold «||», never « | » in this code)
    var parts = line.split(' | ').map((p) => p.trim()).toList();
    int? column;
    if (parts.length == 4 && RegExp(r'^\d+$').hasMatch(parts.last)) {
      column = int.parse(parts.last);
      parts = parts.sublist(0, 3);
    }
    if (parts.length != 3 || parts.any((p) => p.isEmpty)) {
      throw FormatException(
        'line ${n + 1}: expected «<file> | <mutator> | <source line> [| <column>]»',
        line,
      );
    }
    if (reason == null) {
      throw FormatException(
        'line ${n + 1}: exclusion without a reason (# gleichwertig: …, # Grenzfall: …, '
        '# Speicherfreigabe: … or # Mull-Grenze: … above it)',
        line,
      );
    }
    out.add(
      Exclusion(
        parts[0],
        parts[1],
        _squash(parts[2]),
        reason,
        n + 1,
        column: column,
      ),
    );
  }
  return out;
}

/// Marks the not detected mutants that an exclusion matches (same file, mutator and source line,
/// whitespace ignored; the line number may move). Returns the number marked.
int applyExclusions(List<Mutant> mutants, List<Exclusion> exclusions) {
  var n = 0;
  for (final m in mutants) {
    if (m.outcome != Outcome.survived) continue;
    for (final e in exclusions) {
      if (e.file == m.file &&
          e.mutator == m.mutator &&
          e.code == _squash(m.code) &&
          (e.column == null || e.column == m.column)) {
        m.outcome = Outcome.excluded;
        m.note = e.reason;
        e.used++;
        n++;
        break;
      }
    }
  }
  return n;
}

// ---------------------------------------------------------------------------------------------
// Mull reports (Mutation Testing Elements JSON), one per test program
// ---------------------------------------------------------------------------------------------

Outcome _mullOutcome(String status) => switch (status) {
  'Killed' || 'RuntimeError' => Outcome.killed,
  'Timeout' => Outcome.timeout,
  'CompileError' => Outcome.unviable,
  'Ignored' => Outcome.excluded,
  _ => Outcome.survived, // Survived, NoCoverage
};

/// The mutants of one Mull report. [roots] are the prefixes that make a path relative to the
/// repository (the real path and the link without spaces, see mutants_run.dart); [lineOf] reads
/// a source line (for the summary and the exclusions).
List<Mutant> parseMullReport(
  String json,
  List<String> roots,
  String Function(String file, int line) lineOf,
) {
  final data = jsonDecode(json) as Map<String, Object?>;
  final files = (data['files'] as Map<String, Object?>?) ?? const {};
  final out = <Mutant>[];
  for (final MapEntry(key: path, value: entry) in files.entries) {
    var rel = path;
    for (final r in roots) {
      final prefix = r.endsWith('/') ? r : '$r/';
      if (rel.startsWith(prefix)) rel = rel.substring(prefix.length);
    }
    final mutants =
        ((entry as Map<String, Object?>)['mutants'] as List<Object?>?) ??
        const [];
    for (final raw in mutants) {
      final m = raw as Map<String, Object?>;
      final start =
          (m['location'] as Map<String, Object?>)['start']
              as Map<String, Object?>;
      final line = start['line'] as int;
      final status = m['status'] as String? ?? 'Survived';
      out.add(
        Mutant(
          part: 'core',
          file: rel,
          line: line,
          column: start['column'] as int,
          mutator: m['mutatorName'] as String? ?? '?',
          replacement: m['replacement'] as String? ?? '',
          code: lineOf(rel, line),
          outcome: _mullOutcome(status),
          note: status == 'NoCoverage' ? notCovered : null,
        ),
      );
    }
  }
  return out;
}

const _rank = {
  Outcome.killed: 4,
  Outcome.timeout: 3,
  Outcome.excluded: 2,
  Outcome.unviable: 1,
  Outcome.survived: 0,
};

/// Note of a mutant that no test program executes (Mull's coverage filter, #11/AK3).
const notCovered = 'not covered';

/// Merges the reports of several test programs: a mutant is detected if any program detects it.
/// A mutant some program executes without detecting it is «not detected», one that no program
/// executes «not detected, not covered».
List<Mutant> mergeMutants(Iterable<Mutant> all) {
  final byKey = <String, Mutant>{};
  for (final m in all) {
    final old = byKey[m.key];
    if (old == null ||
        _rank[m.outcome]! > _rank[old.outcome]! ||
        (_rank[m.outcome] == _rank[old.outcome] &&
            old.note == notCovered &&
            m.note != notCovered)) {
      byKey[m.key] = m;
    }
  }
  final out = byKey.values.toList()
    ..sort((a, b) {
      final f = a.file.compareTo(b.file);
      if (f != 0) return f;
      final l = a.line.compareTo(b.line);
      return l != 0 ? l : a.column.compareTo(b.column);
    });
  return out;
}

// ---------------------------------------------------------------------------------------------
// Running a test command with a time limit and a memory limit (#11/AK4)
// ---------------------------------------------------------------------------------------------

/// How a limited run ended.
enum RunEnd { passed, failed, timeout, memory }

class RunResult {
  RunResult(this.end, this.output, this.elapsed, this.peakMiB, {this.exitCode});
  final RunEnd end;
  final String output;
  final Duration elapsed;
  final int peakMiB;

  /// Exit code of the process (negative: ended by that signal), null if unknown.
  final int? exitCode;
}

/// Resident memory (KiB) per process and the children of each (ps works on macOS and Linux).
(Map<int, int>, Map<int, List<int>>) _processTable() {
  final r = Process.runSync('ps', ['-A', '-o', 'pid=,ppid=,rss=']);
  final rss = <int, int>{};
  final children = <int, List<int>>{};
  for (final line in '${r.stdout}'.split('\n')) {
    final f = line.trim().split(RegExp(r'\s+'));
    if (f.length < 3) continue;
    final pid = int.tryParse(f[0]), ppid = int.tryParse(f[1]);
    final kib = int.tryParse(f[2]);
    if (pid == null || ppid == null || kib == null) continue;
    rss[pid] = kib;
    children.putIfAbsent(ppid, () => []).add(pid);
  }
  return (rss, children);
}

List<int> _tree(int root, Map<int, List<int>> children) {
  final out = <int>[root];
  for (var i = 0; i < out.length; i++) {
    out.addAll(children[out[i]] ?? const []);
  }
  return out;
}

/// Runs [executable] and ends it with its whole process tree when it takes longer than
/// [timeout] or the tree holds more than [memoryMiB] of resident memory (checked every
/// [poll]). macOS has no address space limit for processes, so the tree is watched from outside.
///
/// The run gets its own temporary directory (TMPDIR) that is removed afterwards, however it ended:
/// a killed `flutter test` leaves its flutter_tools.* directory (about 240 MB) and the test
/// directories behind, and those would pile up in the system's temporary directory.
Future<RunResult> runLimited(
  String executable,
  List<String> args, {
  required String workingDirectory,
  required Duration timeout,
  required int memoryMiB,
  Map<String, String>? environment,
  Duration poll = const Duration(milliseconds: 250),
}) async {
  final watch = Stopwatch()..start();
  final tmp = Directory.systemTemp.createTempSync('wp-run-');
  try {
    return await _runLimited(
      executable,
      args,
      watch,
      workingDirectory: workingDirectory,
      timeout: timeout,
      memoryMiB: memoryMiB,
      environment: {...?environment, 'TMPDIR': tmp.path},
      poll: poll,
    );
  } finally {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // a process outside the tree may still write there; make clean-tmp removes it later
    }
  }
}

Future<RunResult> _runLimited(
  String executable,
  List<String> args,
  Stopwatch watch, {
  required String workingDirectory,
  required Duration timeout,
  required int memoryMiB,
  required Map<String, String> environment,
  required Duration poll,
}) async {
  final p = await Process.start(
    executable,
    args,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  final out = StringBuffer();
  final done = [
    p.stdout.transform(utf8.decoder).forEach(out.write),
    p.stderr.transform(utf8.decoder).forEach(out.write),
  ];
  RunEnd? forced;
  var peak = 0;
  void killTree() {
    final (_, children) = _processTable();
    for (final pid in _tree(p.pid, children).reversed) {
      Process.killPid(pid, ProcessSignal.sigkill);
    }
  }

  final timer = Timer.periodic(poll, (_) {
    if (forced != null) return;
    if (watch.elapsed > timeout) {
      forced = RunEnd.timeout;
      killTree();
      return;
    }
    final (rss, children) = _processTable();
    var kib = 0;
    for (final pid in _tree(p.pid, children)) {
      kib += rss[pid] ?? 0;
    }
    if (kib ~/ 1024 > peak) peak = kib ~/ 1024;
    if (kib ~/ 1024 > memoryMiB) {
      forced = RunEnd.memory;
      killTree();
    }
  });
  final code = await p.exitCode;
  timer.cancel();
  await Future.wait(done);
  watch.stop();
  return RunResult(
    forced ?? (code == 0 ? RunEnd.passed : RunEnd.failed),
    out.toString(),
    watch.elapsed,
    peak,
    exitCode: code,
  );
}

// ---------------------------------------------------------------------------------------------
// Failed original test of a core program (#103)
// ---------------------------------------------------------------------------------------------

/// Whether mull-runner stopped because the unmutated test program failed (warm-up or baseline
/// run). Mull runs with --no-output and shows nothing of the test then.
bool originalTestFailed(String mullOutput) =>
    mullOutput.contains('Original test failed');

/// What the job shows when the original test failed: the test program run again by itself with
/// the same arguments and environment, how it ended and the last [lines] lines of its output.
String originalTestReport(
  String program,
  List<String> args,
  RunResult r, {
  int lines = 60,
}) {
  final how = switch (r.end) {
    RunEnd.timeout => 'time limit reached',
    RunEnd.memory => 'memory limit reached (${r.peakMiB} MiB)',
    _ => switch (r.exitCode) {
      null => 'exit code unknown',
      final c when c < 0 => 'ended by signal ${-c}',
      final c => 'exit code $c',
    },
  };
  final text = r.output.trimRight().split('\n');
  final shown = text.sublist(max(0, text.length - lines));
  return [
    'original test run again without Mull: $program${args.map((a) => ' $a').join()}',
    '$how after ${r.elapsed.inMilliseconds} ms'
        '${shown.length < text.length ? ', last ${shown.length} of ${text.length} lines' : ''}:',
    ...shown,
  ].join('\n');
}

final _compileError = RegExp(
  r'(lib/\S+\.dart:\d+:\d+: Error:|Error: Compilation failed|Failed to load ")',
);

/// The outcome of a Dart mutant from its test run.
(Outcome, String?) dartOutcome(RunResult r) => switch (r.end) {
  RunEnd.passed => (Outcome.survived, null),
  RunEnd.timeout => (Outcome.timeout, null),
  RunEnd.memory => (Outcome.killed, 'memory limit'),
  RunEnd.failed when _compileError.hasMatch(r.output) => (
    Outcome.unviable,
    null,
  ),
  RunEnd.failed => (Outcome.killed, null),
};

// ---------------------------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------------------------

/// Counts per part and outcome.
Map<String, Map<Outcome, int>> counts(List<Mutant> mutants) {
  final out = <String, Map<Outcome, int>>{};
  for (final m in mutants) {
    final c = out.putIfAbsent(
      m.part,
      () => {for (final o in Outcome.values) o: 0},
    );
    c[m.outcome] = c[m.outcome]! + 1;
  }
  return out;
}

/// The text of `local/mutants/<mode>/summary.txt`: counts per part, then every not detected mutant
/// with file and line (#11/AK5).
String summaryText(
  List<Mutant> mutants, {
  required String title,
  Map<String, Duration> durations = const {},
  List<String> notes = const [],
}) {
  final b = StringBuffer('$title\n');
  final c = counts(mutants);
  for (final part in ['core', 'dart']) {
    final n = c[part];
    final time = durations[part];
    final t = time == null ? '' : ', ${_minutes(time)}';
    if (n == null) {
      b.writeln('$part: no mutants$t');
      continue;
    }
    final total = n.values.fold(0, (a, v) => a + v);
    b.writeln(
      '$part: $total mutants: '
      '${Outcome.values.map((o) => '${n[o]} ${outcomeLabels[o]}').join(', ')}$t',
    );
  }
  for (final note in notes) {
    b.writeln(note);
  }
  final missed = mutants.where((m) => m.outcome == Outcome.survived).toList();
  if (missed.isEmpty) {
    b.writeln('No undetected mutants.');
  } else {
    b.writeln('Not detected (${missed.length}):');
    for (final m in missed) {
      b.writeln('  ${missedLine(m)}');
    }
  }
  return b.toString();
}

/// «file:line:column: mutator → replacement | code» of a not detected mutant.
String missedLine(Mutant m) =>
    '${m.file}:${m.line}:${m.column}: ${m.mutator}'
    '${m.replacement.isEmpty ? '' : ' → ${m.replacement}'}'
    '${m.note == null ? '' : ' (${m.note})'} | ${m.code}';

String _minutes(Duration d) {
  final s = d.inSeconds;
  return s < 120 ? '$s s' : '${(s / 60).toStringAsFixed(1)} min';
}

/// Exit code of a run: 3 with not detected mutants (like cargo-mutants), else 0.
int exitCodeFor(List<Mutant> mutants) =>
    mutants.any((m) => m.outcome == Outcome.survived) ? 3 : 0;

// ---------------------------------------------------------------------------------------------
// Reusing the previous run: --rerun and --exclusions-only
// ---------------------------------------------------------------------------------------------

/// The mutants of a `results.json`.
List<Mutant> parseResults(String json) {
  final data = jsonDecode(json) as Map<String, Object?>;
  return [
    for (final m in (data['mutants'] as List? ?? const []))
      Mutant.fromJson((m as Map).cast<String, Object?>()),
  ];
}

/// Identity of a mutant across runs: without the line number, so a line that only moved keeps its
/// result, and with the source line, so a changed line is a new mutant.
String reuseKey(Mutant m) =>
    '${m.file}|${m.column}|${m.mutator}|${m.replacement}|${_squash(m.code)}';

/// The previous run for `--rerun`: a mutant it detected (killed, timeout, not compilable) keeps its
/// outcome, one it excluded stays not detected and gets the current exclusions again, one it did
/// not detect runs again (new tests may detect it now). Mutants it does not know run as well.
class Reuse {
  Reuse(Iterable<Mutant> previous) {
    for (final m in previous) {
      _byKey.putIfAbsent(reuseKey(m), () => []).add(m);
    }
  }

  final _byKey = <String, List<Mutant>>{};

  /// How many mutants [take] returned.
  var reused = 0;

  /// The previous result for [current] (at its current line), or null if it has to run.
  Mutant? take(Mutant current) {
    final list = _byKey[reuseKey(current)];
    if (list == null || list.isEmpty) return null;
    final old = list.first;
    if (old.outcome == Outcome.survived) return null;
    list.removeAt(0);
    reused++;
    final excluded = old.outcome == Outcome.excluded;
    return Mutant(
      part: current.part,
      file: current.file,
      line: current.line,
      column: current.column,
      mutator: current.mutator,
      replacement: current.replacement,
      code: current.code,
      outcome: excluded ? Outcome.survived : old.outcome,
      note: excluded ? null : old.note,
    );
  }
}

/// `--exclusions-only`: the mutants of the previous run as they were before the exclusions, so the
/// current tools/mutants-exclude.txt can be applied again without running a mutant.
List<Mutant> withoutExclusions(Iterable<Mutant> previous) => [
  for (final m in previous)
    m.outcome == Outcome.excluded
        ? (Mutant.fromJson(m.toJson())
            ..outcome = Outcome.survived
            ..note = null)
        : m,
];
