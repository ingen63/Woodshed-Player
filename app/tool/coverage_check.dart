// Checks the line coverage per part against tools/coverage-min (#8).
//
// Usage: dart app/tool/coverage_check.dart [--root <repository>]
// Reads app/coverage/lcov.info and core/build-cov/lcov.info (written by `make coverage-run`).
// Exit code 0: every part with a minimum reaches it; 1: a part is below the minimum or a logic
// file is not loaded by any test; 2: coverage data or tools/coverage-min missing.
import 'dart:io';

import 'coverage.dart';

void main(List<String> args) {
  var root = Directory.current.path;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--root' && i + 1 < args.length) {
      root = args[++i];
    } else {
      stderr.writeln('usage: dart app/tool/coverage_check.dart [--root <dir>]');
      exit(2);
    }
  }
  root = Directory(root).absolute.path;
  if (root.endsWith('/')) root = root.substring(0, root.length - 1);
  try {
    final min = parseMinimum(
      File('$root/tools/coverage-min').readAsStringSync(),
    );
    final e = evaluate(
      min: min,
      coverage: readCoverage(root),
      sources: readDartSources(root),
    );
    stdout.write(report(e));
    exit(e.failures.isEmpty ? 0 : 1);
  } on FileSystemException catch (err) {
    stderr.writeln('coverage check: ${err.message}: ${err.path}');
    exit(2);
  } on FormatException catch (err) {
    stderr.writeln('coverage check: ${err.message}');
    exit(2);
  }
}
