// Coverage of the changed lines (#8): which share of the lines changed since BASE is run by tests,
// with the lines that are not. A hint, not a gate: exit code 0 except for wrong usage (2).
//
// Usage: dart app/tool/coverage_diff.dart [--base <commit>] [--root <repository>]
// Base defaults to origin/main. Compared are the commits since the base (`git diff base...HEAD`)
// and the working tree (`git diff base`), so uncommitted changes show up locally too.
// Reads the coverage files of `make coverage-run`.
import 'dart:io';

import 'coverage.dart';

String _git(String root, List<String> args) {
  final r = Process.runSync('git', args, workingDirectory: root);
  if (r.exitCode != 0) {
    throw ProcessException('git', args, '${r.stderr}'.trim(), r.exitCode);
  }
  return '${r.stdout}';
}

void main(List<String> args) {
  var base = 'origin/main';
  var root = Directory.current.path;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--base' && i + 1 < args.length) {
      base = args[++i];
    } else if (args[i] == '--root' && i + 1 < args.length) {
      root = args[++i];
    } else {
      stderr.writeln(
        'usage: dart app/tool/coverage_diff.dart [--base <commit>] [--root <dir>]',
      );
      exit(2);
    }
  }
  try {
    root = _git(root, ['rev-parse', '--show-toplevel']).trim();
    _git(root, ['rev-parse', '--verify', '--quiet', '$base^{commit}']);
  } on ProcessException {
    stderr.writeln('coverage diff: base "$base" not found (set BASE=<commit>)');
    exit(2);
  }
  final changed = <String, Set<int>>{};
  for (final spec in ['$base...HEAD', base]) {
    final diff = _git(root, [
      'diff',
      '-U0',
      '--no-color',
      '--no-ext-diff',
      spec,
    ]);
    changedLines(diff).forEach((file, lines) {
      if (!measuredSource.hasMatch(file)) return;
      changed.putIfAbsent(file, () => <int>{}).addAll(lines);
    });
  }
  try {
    stdout.write(diffReport(changed, readCoverage(root), base: base));
  } on FileSystemException catch (err) {
    stderr.writeln('coverage diff: ${err.message}: ${err.path}');
    exit(2);
  }
}
