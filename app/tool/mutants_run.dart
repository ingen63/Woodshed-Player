// Mutation tests (#11): make mutants (everything) and make mutants-diff (the lines changed since
// BASE). Strategy, limits, test selection and open mutants: docs/TESTS.md «Mutationstests (#11)».
//
// Usage: dart app/tool/mutants_run.dart [--part all|core|dart] [--base <commit>] [--jobs <n>]
//                                       [--memory-mib <n>] [--file <regex>] [--fresh]
//
// - Without --base: every mutant (make mutants), results in local/mutants/full/.
//   With --base: only mutants on lines changed since the base (`git diff base...HEAD` and the
//   working tree), results in local/mutants/diff/.
// - core: builds core/build-mutants with Mull (Homebrew llvm or CC/CXX of the same major version as
//   the plugin) and ASan/UBSan like make sanitize, runs the self-test (#11/AK4) and every test
//   program with mull-runner. Tools:
//   MULL_RUNNER, MULL_PLUGIN or MULL_DIR (default ~/.local/opt/mull, docs/TESTS.md).
// - dart: the Dart logic of app/lib; each mutant runs the tests that import its file in one of
//   --jobs copies of app/ (local/mutants/<mode>/dart/ws<n>).
// - --fresh forgets the Mull cache (local/mutants/core-cache.db): by default a killed mutant of an
//   unchanged test program stays killed, the others run again.
//
// Writes summary.txt, missed.txt and results.json. Exit code 3 if a mutant is not detected (and
// not excluded with a reason in tools/mutants-exclude.txt), 2 on a usage or tool error, else 0.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'coverage.dart' show changedLines;
import 'mutants.dart';

/// Time limits: Mull takes max(10 × baseline, minimum); a Dart mutant max(minimum, 3 × baseline).
const coreMinimumTimeoutMs = 20000;
const dartMinimumTimeout = Duration(seconds: 60);

/// Test programs of the core and their arguments (ctest in core/CMakeLists.txt, without the
/// benchmarks). capi_tests and device_tests use miniaudio's null device, so parallel mutants open
/// no audio device.
List<(String, List<String>)> coreTestPrograms(String core) => [
  ('engine_tests', []),
  ('metronome_tests', []),
  ('waveform_tests', []),
  ('player_tests', []),
  ('recorder_tests', []),
  ('capi_tests', ['--null-backend']),
  ('device_tests', []),
  ('realtime_tests', []),
  ('reference_tests', ['--dump', '$core/build-mutants/reference_native.bin']),
  (
    'fuzz_decoder_replay',
    ['$core/tests/fuzz/regressions/decoder', '$core/tests/fuzz/corpus/decoder'],
  ),
  (
    'fuzz_capi_replay',
    ['$core/tests/fuzz/regressions/capi', '$core/tests/fuzz/corpus/capi'],
  ),
  // #116: trimming
  ('trim_tests', []),
  (
    'fuzz_trim_replay',
    ['$core/tests/fuzz/regressions/trim', '$core/tests/fuzz/corpus/trim'],
  ),
];

late String root;
late String out;
late int jobs;
late int memoryMiB;
String? base;
RegExp? fileFilter;
var fresh = false;

Never usage(String message) {
  stderr.writeln('mutants: $message');
  stderr.writeln(
    'usage: dart app/tool/mutants_run.dart [--part all|core|dart] [--base <commit>] '
    '[--jobs <n>] [--memory-mib <n>] [--file <regex>] [--fresh]',
  );
  exit(2);
}

String git(List<String> args) {
  final r = Process.runSync('git', args, workingDirectory: root);
  if (r.exitCode != 0) {
    throw ProcessException('git', args, '${r.stderr}'.trim(), r.exitCode);
  }
  return '${r.stdout}';
}

Future<void> main(List<String> args) async {
  var part = 'all';
  jobs = 4;
  memoryMiB = 0;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    String value() =>
        i + 1 < args.length ? args[++i] : usage('$a needs a value');
    switch (a) {
      case '--part':
        part = value();
      case '--base':
        base = value();
      case '--jobs':
        jobs = int.tryParse(value()) ?? 0;
      case '--memory-mib':
        memoryMiB = int.tryParse(value()) ?? 0;
      case '--file':
        fileFilter = RegExp(value());
      case '--fresh':
        fresh = true;
      default:
        usage('unknown argument $a');
    }
  }
  if (!['all', 'core', 'dart'].contains(part) || jobs < 1) {
    usage('bad --part or --jobs');
  }
  root = Directory.current.path;
  try {
    root = git(['rev-parse', '--show-toplevel']).trim();
    if (base != null) {
      git(['rev-parse', '--verify', '--quiet', '${base!}^{commit}']);
    }
  } on ProcessException {
    usage(
      'not in a git repository, or base "$base" not found (set BASE=<commit>)',
    );
  }
  out = '$root/local/mutants/${base == null ? 'full' : 'diff'}';
  Directory(out).createSync(recursive: true);

  final List<Exclusion> exclusions;
  try {
    exclusions = parseExclusions(
      File('$root/tools/mutants-exclude.txt').readAsStringSync(),
    );
  } on FormatException catch (e) {
    stderr.writeln('mutants: tools/mutants-exclude.txt: ${e.message}');
    exit(2);
  }

  Map<String, Set<int>>? changed;
  if (base != null) {
    changed = {};
    for (final spec in ['${base!}...HEAD', base!]) {
      changedLines(git(['diff', '-U0', '--no-color', '--no-ext-diff', spec]))
          .forEach((f, l) => changed!.putIfAbsent(f, () => <int>{}).addAll(l));
    }
  }

  final all = <Mutant>[];
  final durations = <String, Duration>{};
  final notes = <String>[];
  if (part != 'dart') {
    final w = Stopwatch()..start();
    all.addAll(await runCore(changed, notes));
    durations['core'] = w.elapsed;
  }
  if (part != 'core') {
    final w = Stopwatch()..start();
    all.addAll(await runDart(changed, notes));
    durations['dart'] = w.elapsed;
  }
  final excluded = applyExclusions(all, exclusions);
  final unused = exclusions.where((e) => e.used == 0).toList();
  if (base == null && part == 'all' && fileFilter == null) {
    for (final e in unused) {
      notes.add(
        'exclusion without a match (tools/mutants-exclude.txt:${e.lineNumber}): '
        '${e.file} | ${e.mutator} | ${e.code}',
      );
    }
  }

  final head = git(['rev-parse', 'HEAD']).trim();
  final title =
      'Mutation tests (#11), ${base == null ? 'full run' : 'lines changed since $base'}, '
      '${DateTime.now().toIso8601String().substring(0, 16)}, at ${head.substring(0, 7)}, '
      '$jobs in parallel, $excluded excluded';
  final summary = summaryText(
    all,
    title: title,
    durations: durations,
    notes: notes,
  );
  File('$out/summary.txt').writeAsStringSync(summary);
  File('$out/missed.txt').writeAsStringSync(
    all
        .where((m) => m.outcome == Outcome.survived)
        .map((m) => '${missedLine(m)}\n')
        .join(),
  );
  File('$out/results.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert({
      'mode': base == null ? 'full' : 'diff',
      'base': base,
      'head': head,
      'date': DateTime.now().toUtc().toIso8601String(),
      'jobs': jobs,
      'durations': {
        for (final MapEntry(:key, :value) in durations.entries)
          key: value.inSeconds,
      },
      'counts': {
        for (final MapEntry(:key, :value) in counts(all).entries)
          key: {for (final e in value.entries) e.key.name: e.value},
      },
      'mutants': [for (final m in all) m.toJson()],
    }),
  );
  stdout.write(summary);
  stdout.writeln('results: ${out.substring(root.length + 1)}/');
  exit(exitCodeFor(all));
}

// ---------------------------------------------------------------------------------------------
// C++ core with Mull
// ---------------------------------------------------------------------------------------------

final _sourceCache = <String, List<String>>{};
String sourceLine(String rel, int line) {
  final lines = _sourceCache.putIfAbsent(rel, () {
    final f = File('$root/$rel');
    return f.existsSync() ? f.readAsLinesSync() : const <String>[];
  });
  return line >= 1 && line <= lines.length ? lines[line - 1].trim() : '';
}

String? which(String name) {
  final r = Process.runSync('sh', ['-c', 'command -v $name']);
  final p = '${r.stdout}'.trim();
  return r.exitCode == 0 && p.isNotEmpty ? p : null;
}

/// A path without spaces for the build: Mull's AST check splits the recorded compiler command
/// line at spaces (CMakeLists.txt, WP_MULL_PLUGIN).
String spaceFreeRoot() {
  if (!root.contains(' ')) return root;
  final hash = root.codeUnits.fold(7, (h, c) => (h * 31 + c) & 0xffffff);
  final link = Link(
    '${Directory.systemTemp.path}/wp-mutants-${hash.toRadixString(16)}',
  );
  if (link.existsSync() && link.targetSync() != root) link.deleteSync();
  if (!link.existsSync()) link.createSync(root);
  return link.path;
}

Future<List<Mutant>> runCore(
  Map<String, Set<int>>? changed,
  List<String> notes,
) async {
  final env = Platform.environment;
  final mullDir = env['MULL_DIR'] ?? '${env['HOME']}/.local/opt/mull';
  String? cc = env['MULL_CC'] ?? env['CC'];
  String? cxx = env['MULL_CXX'] ?? env['CXX'];
  if (cc == null && Platform.isMacOS) {
    final llvm = '${Process.runSync('brew', ['--prefix', 'llvm']).stdout}'
        .trim();
    cc = '$llvm/bin/clang';
    cxx = '$llvm/bin/clang++';
  }
  cc ??= 'clang';
  cxx ??= 'clang++';
  final version = '${Process.runSync(cc, ['--version']).stdout}';
  final major = RegExp(r'clang version (\d+)').firstMatch(version)?.group(1);
  final runner =
      env['MULL_RUNNER'] ??
      (File('$mullDir/bin/mull-runner').existsSync()
          ? '$mullDir/bin/mull-runner'
          : which('mull-runner') ?? which('mull-runner-$major'));
  final plugin =
      env['MULL_PLUGIN'] ??
      [
        '$mullDir/lib/mull-ir-frontend-$major',
        '/usr/lib/mull-ir-frontend-$major',
        '/usr/local/lib/mull-ir-frontend-$major',
      ].where((p) => File(p).existsSync()).firstOrNull;
  if (runner == null || plugin == null || major == null) {
    stderr.writeln(
      'mutants: Mull not found (mull-runner: ${runner ?? '-'}, plugin for clang '
      '${major ?? '?'}: ${plugin ?? '-'}). Installation: docs/TESTS.md «Mutationstests (#11)».',
    );
    exit(2);
  }

  final src = spaceFreeRoot();
  final core = '$src/core';
  final build = '$core/build-mutants';
  final reports = Directory('$out/core');
  if (reports.existsSync()) reports.deleteSync(recursive: true);
  reports.createSync(recursive: true);
  var ranges = '';
  if (changed != null) {
    final lines = <String>[];
    changed.forEach((file, set) {
      if (!RegExp(r'^core/(src|web)/.*\.(c|cc|cpp|h|hpp|mm)$').hasMatch(file)) {
        return;
      }
      for (final n in set.toList()..sort()) {
        lines.add('$src/$file:$n');
      }
    });
    if (lines.isEmpty) {
      notes.add('core: no changed lines in core/src or core/web');
      return [];
    }
    ranges = '${reports.path}/ranges.txt'.replaceFirst(root, src);
    File(ranges).writeAsStringSync('${lines.join('\n')}\n');
  }

  stdout.writeln('core: Mull ${plugin.split('/').last}, $cc');
  Future<void> step(String what, List<String> cmd) async {
    final r = await Process.run(cmd.first, cmd.sublist(1));
    if (r.exitCode != 0) {
      final text = '${r.stdout}${r.stderr}'.split('\n');
      stderr.writeln(text.sublist(max(0, text.length - 30)).join('\n'));
      stderr.writeln('mutants: $what failed');
      exit(2);
    }
  }

  const flags = '-g -O1';
  await step('cmake (core/build-mutants)', [
    'cmake',
    '-S',
    core,
    '-B',
    build,
    '-DCMAKE_BUILD_TYPE=Debug',
    '-DCMAKE_C_FLAGS_DEBUG=$flags',
    '-DCMAKE_CXX_FLAGS_DEBUG=$flags',
    '-DCMAKE_OBJCXX_FLAGS_DEBUG=$flags',
    '-DCMAKE_C_COMPILER=$cc',
    '-DCMAKE_CXX_COMPILER=$cxx',
    '-DWP_MULL_PLUGIN=$plugin',
    '-DWP_MULL_RANGES=$ranges',
    // like make sanitize (#57): the workflow runs every core test under ASan and UBSan, so a mutant
    // that writes outside a buffer is detected there
    '-DWP_SANITIZE=address,undefined',
    // No coverage filter: Mull's filter skipped functions the tests do execute (Engine::apply in
    // engine_tests, everything in the shared library for capi_tests). Every test program runs
    // every mutant linked into it; the cache keeps reruns short.
    '-DWP_COVERAGE=OFF',
  ]);
  await step('build (core/build-mutants)', [
    'cmake',
    '--build',
    build,
    '-j',
    '${Platform.numberOfProcessors}',
  ]);

  final cache = '$src/local/mutants/core-cache.db';
  if (fresh) {
    for (final suffix in ['', '-shm', '-wal']) {
      final f = File('$cache$suffix');
      if (f.existsSync()) f.deleteSync();
    }
  }
  final runEnv = {
    'WP_TEST_MEMORY_LIMIT_MB': '${memoryMiB > 0 ? memoryMiB : 1024}',
    // leaks off on every platform (LeakSanitizer does not run on macOS): the same mutants count
    // and exit with an error code instead of abort(): on macOS every abort writes a crash report
    'ASAN_OPTIONS': 'halt_on_error=1:abort_on_error=0:detect_leaks=0',
    'UBSAN_OPTIONS':
        "print_stacktrace=0:halt_on_error=1:abort_on_error=0:"
        "suppressions='$core/tests/sanitizer/ubsan.supp'",
  };
  Future<List<Mutant>> mull(
    String name,
    List<String> args, {
    int minimumTimeoutMs = coreMinimumTimeoutMs,
    String? cachePath,
  }) async {
    final report = name;
    final dir = build;
    final r = await Process.run(runner, [
      '--workers',
      '$jobs',
      '--timeout',
      '300000', // warm-up and baseline run; the mutants get --minimum-timeout
      '--minimum-timeout',
      '$minimumTimeoutMs',
      if (cachePath == null) '--no-cache' else ...['--cache-path', cachePath],
      '--reporters',
      'Elements',
      '--report-dir',
      reports.path,
      '--report-name',
      report,
      '--allow-surviving',
      '--no-output',
      '--ld-search-path',
      dir,
      '$dir/$name',
      ...args,
    ], environment: runEnv);
    File('${reports.path}/$report.log')
        .writeAsStringSync('${r.stdout}${r.stderr}');
    final json = File('${reports.path}/$report.json');
    if (r.exitCode == 0 &&
        '${r.stdout}${r.stderr}'.contains('No mutants found')) {
      return [];
    }
    if (r.exitCode != 0 || !json.existsSync()) {
      final text = '${r.stdout}${r.stderr}'.split('\n');
      stderr.writeln(text.sublist(max(0, text.length - 15)).join('\n'));
      if (originalTestFailed('${r.stdout}${r.stderr}')) {
        // #103: Mull shows nothing of the failed test (--no-output); run it again by itself, in
        // the same directory and with the same environment as mull-runner
        final again = await runLimited(
          '$dir/$name',
          args,
          workingDirectory: Directory.current.path,
          timeout: const Duration(minutes: 5),
          memoryMiB: 4096,
          environment: runEnv,
        );
        final report = originalTestReport('$dir/$name', args, again);
        File('${reports.path}/$name.original.log')
            .writeAsStringSync('$report\n');
        stderr.writeln(report);
      }
      stderr.writeln('mutants: mull-runner $name failed');
      exit(2);
    }
    final found = parseMullReport(json.readAsStringSync(), [
      root,
      src,
      File(src).resolveSymbolicLinksSync(),
    ], sourceLine);
    return found;
  }

  // #11/AK4: an endless loop that fills memory ends through the memory guard (killed), one without
  // memory through the time limit (timeout); the run goes on.
  if (changed == null) {
    final w = Stopwatch()..start();
    final self = await mull('mutants_selftest', [], minimumTimeoutMs: 5000);
    // the two loops (fill: memory, count: time) have the same source line
    final fill = [
      for (final m in self)
        if (m.mutator == 'cxx_add_assign_to_sub_assign') m.outcome,
    ];
    if (fill.length != 2 ||
        !fill.contains(Outcome.killed) ||
        !fill.contains(Outcome.timeout)) {
      stderr.writeln(
        'mutants: self-test failed, expected one killed (memory guard) and one timeout: $fill',
      );
      exit(2);
    }
    notes.add(
      'self-test (#11/AK4): memory mutant killed, endless loop timeout, '
      '${w.elapsed.inSeconds} s',
    );
    stdout.writeln(notes.last);
  }

  final found = <Mutant>[];
  for (final (name, args) in coreTestPrograms(core)) {
    final w = Stopwatch()..start();
    final ms = await mull(name, args, cachePath: cache);
    stdout.writeln(
      'core: $name ${ms.length} mutants, '
      '${ms.where((m) => m.outcome == Outcome.survived).length} not detected, '
      '${w.elapsed.inSeconds} s',
    );
    found.addAll(ms);
  }
  return mergeMutants(
    found.where((m) => fileFilter == null || fileFilter!.hasMatch(m.file)),
  );
}

// ---------------------------------------------------------------------------------------------
// Dart logic
// ---------------------------------------------------------------------------------------------

/// Files of the copies: everything of app/ except build output and caches; the package
/// configuration from the original (flutter test --no-pub). The folders next to app/ that tests
/// read (../core, ../docs, …) are links.
Future<void> prepareWorkspace(String ws) async {
  final app = '$root/app';
  Directory('$ws/app').createSync(recursive: true);
  final r = await Process.run('rsync', [
    '-a',
    '--delete',
    '--exclude=/.dart_tool/',
    '--exclude=/build/',
    '--exclude=/coverage/',
    '--exclude=Pods/',
    '--exclude=/test/web/wp_core/',
    '$app/',
    '$ws/app/',
  ]);
  if (r.exitCode != 0) {
    stderr.writeln('mutants: rsync failed: ${r.stderr}');
    exit(2);
  }
  Directory('$ws/app/.dart_tool').createSync(recursive: true);
  for (final f in ['package_config.json', 'package_graph.json', 'version']) {
    final src = File('$app/.dart_tool/$f');
    if (src.existsSync()) src.copySync('$ws/app/.dart_tool/$f');
  }
  for (final e in Directory(root).listSync()) {
    final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (name == 'app' || name == 'local' || name == '.git') continue;
    final link = Link('$ws/$name');
    if (!link.existsSync()) link.createSync(e.path);
  }
}

Future<List<Mutant>> runDart(
  Map<String, Set<int>>? changed,
  List<String> notes,
) async {
  final app = '$root/app';
  final sources = <String, String>{};
  for (final dir in ['lib', 'test', 'integration_test', 'tool']) {
    final d = Directory('$app/$dir');
    if (!d.existsSync()) continue;
    for (final f in d.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      sources[f.path.substring(app.length + 1)] = f.readAsStringSync();
    }
  }
  final graph = importGraph(sources);
  final tests = sources.keys
      .where((p) => p.startsWith('test/') && p.endsWith('_test.dart'))
      .where((p) => !p.startsWith('test/web/')) // browser tests (make test-web)
      .toList();

  // the files and their mutants
  final plan = <String, List<DartSite>>{};
  final skipped = <String, String>{};
  for (final path
      in sources.keys.where((p) => p.startsWith('lib/')).toList()..sort()) {
    final rel = 'app/$path';
    if (fileFilter != null && !fileFilter!.hasMatch(rel)) continue;
    final reason = dartScopeExclusion(rel, sources[path]!);
    if (reason != null) {
      skipped[rel] = reason;
      continue;
    }
    var sites = dartMutations(sources[path]!);
    if (changed != null) {
      final lines = changed[rel] ?? const <int>{};
      sites = sites.where((s) => lines.contains(s.line)).toList();
    }
    if (sites.isNotEmpty) plan[path] = sites;
  }
  if (plan.isEmpty) {
    notes.add(
      changed == null
          ? 'dart: no mutants'
          : 'dart: no changed lines in the Dart logic',
    );
    return [];
  }
  final total = plan.values.fold(0, (a, s) => a + s.length);
  stdout.writeln(
    'dart: ${plan.length} files, $total mutants, $jobs copies of app/ '
    '(${skipped.length} files outside the logic)',
  );

  final wsRoot = '$out/dart';
  final workspaces = [for (var i = 0; i < jobs; i++) '$wsRoot/ws$i'];
  await Future.wait(workspaces.map(prepareWorkspace));
  final limit = memoryMiB > 0 ? memoryMiB : 4096;

  Future<RunResult> flutterTest(
    String ws,
    List<String> files,
    Duration timeout,
  ) => runLimited(
    'flutter',
    [
      'test',
      '--no-pub',
      '--reporter',
      'failures-only',
      '--concurrency',
      '2',
      ...files,
    ],
    workingDirectory: '$ws/app',
    timeout: timeout,
    memoryMiB: limit,
  );

  // baseline per file: the selected tests pass unchanged and give the time limit
  final queue = <(String, DartSite, List<String>, Duration)>[];
  final result = <Mutant>[];
  for (final MapEntry(key: path, value: sites) in plan.entries) {
    final selected = testsFor(path, graph, tests);
    final rel = 'app/$path';
    final lines = sources[path]!.split('\n');
    Mutant mutantOf(DartSite s) => Mutant(
      part: 'dart',
      file: rel,
      line: s.line,
      column: s.column,
      mutator: s.mutator,
      replacement: s.replacement,
      code: lines[s.line - 1].trim(),
    );
    if (selected.isEmpty) {
      // no test imports the file: every mutant survives
      for (final s in sites) {
        result.add(mutantOf(s)..note = 'no test imports the file');
      }
      continue;
    }
    final base = await flutterTest(
      workspaces.first,
      selected,
      const Duration(minutes: 10),
    );
    if (base.end != RunEnd.passed) {
      stderr.writeln(base.output.split('\n').take(40).join('\n'));
      stderr.writeln('mutants: the tests of $rel fail without a mutant');
      exit(2);
    }
    final limitTime = Duration(
      milliseconds: max(
        dartMinimumTimeout.inMilliseconds,
        base.elapsed.inMilliseconds * 3,
      ),
    );
    stdout.writeln(
      'dart: $rel ${sites.length} mutants, ${selected.length} test files, '
      'baseline ${base.elapsed.inSeconds} s, ${base.peakMiB} MiB',
    );
    for (final s in sites) {
      queue.add((path, s, selected, limitTime));
    }
  }

  var next = 0;
  var doneCount = 0;
  final progress = Stopwatch()..start();
  Future<void> worker(String ws) async {
    while (next < queue.length) {
      final (path, site, selected, limitTime) = queue[next++];
      final file = File('$ws/app/$path');
      final original = sources[path]!;
      file.writeAsStringSync(site.apply(original));
      final r = await flutterTest(ws, selected, limitTime);
      file.writeAsStringSync(original);
      final (outcome, note) = dartOutcome(r);
      final lines = original.split('\n');
      result.add(
        Mutant(
          part: 'dart',
          file: 'app/$path',
          line: site.line,
          column: site.column,
          mutator: site.mutator,
          replacement: site.replacement,
          code: lines[site.line - 1].trim(),
          outcome: outcome,
          note: note,
        ),
      );
      doneCount++;
      if (doneCount % 25 == 0 || doneCount == queue.length) {
        stdout.writeln(
          'dart: $doneCount/${queue.length}, ${progress.elapsed.inMinutes} min',
        );
      }
    }
  }

  await Future.wait(workspaces.map(worker));
  return mergeMutants(result);
}
