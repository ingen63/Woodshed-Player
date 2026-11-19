// #8/AK4, #8/AK6: tests of the pre-push hook (tools/git-hooks/pre-push).
//
// Every test creates a small git repository with the hook, tools/coverage-min and the coverage
// check (app/tool/coverage*.dart, copied). A fake `make` first on the PATH stands in for
// `make coverage-run`: it records its arguments, fails on request (a failing test) or writes the
// staged lcov files. The real coverage check then decides, so the tests cover minimum reached and
// missed with real input files. One test pushes for real to a bare repository with
// core.hooksPath = tools/git-hooks.
//
// Run: cd app && flutter test tool/pre_push_hook_test.dart   (or `make test-tools`)
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _source = Directory.current.parent.path;
const _zero = '0000000000000000000000000000000000000000';

/// Fake make: records `make args`; fails if FAKE_FAIL=make, otherwise copies the staged lcov files.
const _fakeMake = r'''#!/bin/sh
echo "make $*" >> "$FAKE_LOG"
if [ "${FAKE_FAIL:-}" = "make" ]; then
  echo "FAIL loadsFlac (fake test failure)"
  exit 2
fi
if [ -f "$FAKE_DIR/dart.lcov" ]; then
  mkdir -p app/coverage && cp "$FAKE_DIR/dart.lcov" app/coverage/lcov.info
fi
if [ -f "$FAKE_DIR/core.lcov" ]; then
  mkdir -p core/build-cov && cp "$FAKE_DIR/core.lcov" core/build-cov/lcov.info
fi
exit 0
''';

/// lcov record: [covered] of [total] lines run.
String _lcov(String path, int covered, int total) {
  final b = StringBuffer('SF:$path\n');
  for (var i = 1; i <= total; i++) {
    b.writeln('DA:$i,${i <= covered ? 1 : 0}');
  }
  return (b..writeln('end_of_record')).toString();
}

class _Result {
  _Result(this.exitCode, this.output, this.calls);

  final int exitCode;
  final String output;
  final List<String> calls;
}

class _Repo {
  _Repo(this.root);

  final Directory root;
  Directory get repo => Directory('${root.path}/repo');
  Directory get fake => Directory('${root.path}/fake');
  File get log => File('${root.path}/make.log');

  static Future<_Repo> create() async {
    final tmp = await Directory.systemTemp.createTemp('wp_pre_push');
    // Real path (macOS: /var -> /private/var), as git rev-parse --show-toplevel reports it.
    final r = _Repo(Directory(tmp.resolveSymbolicLinksSync()));
    final bin = Directory('${r.root.path}/bin')..createSync();
    final make = File('${bin.path}/make')..writeAsStringSync(_fakeMake);
    await Process.run('chmod', ['755', make.path]);
    r.fake.createSync();
    r.repo.createSync();
    r.git(['init', '-q', '-b', 'main']);
    r.git(['config', 'user.email', 'test@example.invalid']);
    r.git(['config', 'user.name', 'Test']);
    r.git(['config', 'commit.gpgsign', 'false']);
    for (final p in [
      'tools/git-hooks/pre-push',
      'tools/coverage-min',
      'app/tool/coverage.dart',
      'app/tool/coverage_check.dart',
    ]) {
      File(
        '$_source/$p',
      ).copySync((File('${r.repo.path}/$p')..createSync(recursive: true)).path);
    }
    await Process.run('chmod', [
      '755',
      '${r.repo.path}/tools/git-hooks/pre-push',
    ]);
    r.write('app/lib/logic.dart', 'int twice(int x) => 2 * x;\n');
    r.write('core/src/engine.cpp', 'int f() { return 1; }\n');
    r.write('.gitignore', 'app/coverage/\ncore/build-cov/\n');
    r.git(['add', '-A']);
    r.git(['commit', '-q', '-m', 'Start (#1)']);
    return r;
  }

  String git(List<String> args) {
    final res = Process.runSync('git', args, workingDirectory: repo.path);
    if (res.exitCode != 0) throw StateError('git $args: ${res.stderr}');
    return '${res.stdout}'.trim();
  }

  void write(String rel, String text) => File('${repo.path}/$rel')
    ..createSync(recursive: true)
    ..writeAsStringSync(text);

  /// Coverage that `make coverage-run` will write: core and Dart logic, covered of 10 lines.
  void stageCoverage({int core = 9, int dart = 9}) {
    File('${fake.path}/core.lcov')
        .writeAsStringSync(_lcov('${repo.path}/core/src/engine.cpp', core, 10));
    File('${fake.path}/dart.lcov')
        .writeAsStringSync(_lcov('lib/logic.dart', dart, 10));
  }

  Map<String, String> get env => {
    'PATH': '${root.path}/bin:${Platform.environment['PATH']}',
    'FAKE_LOG': log.path,
    'FAKE_DIR': fake.path,
    'TMPDIR': root.path,
  };

  /// Runs the hook as git does, with one line per ref on stdin.
  Future<_Result> runHook({String? stdinLine, String fail = ''}) async {
    if (log.existsSync()) log.deleteSync();
    final head = git(['rev-parse', 'HEAD']);
    final proc = await Process.start(
      'bash',
      ['${repo.path}/tools/git-hooks/pre-push', 'origin', 'file:///x'],
      workingDirectory: repo.path,
      environment: {...env, 'FAKE_FAIL': fail},
    );
    proc.stdin.writeln(
      stdinLine ?? 'refs/heads/main $head refs/heads/main $_zero',
    );
    await proc.stdin.close();
    final out = await proc.stdout.transform(utf8.decoder).join();
    final err = await proc.stderr.transform(utf8.decoder).join();
    final code = await proc.exitCode;
    return _Result(
      code,
      '$out$err',
      log.existsSync() ? log.readAsLinesSync() : <String>[],
    );
  }
}

void main() {
  late _Repo r;

  setUp(() async => r = await _Repo.create());
  tearDown(() => r.root.deleteSync(recursive: true));

  group('#8/AK4 pre-push hook', () {
    test(
      'tests green and every part reaches the minimum: push goes ahead',
      () async {
        r.stageCoverage(core: 8, dart: 9); // 80 % and 90 %, minimum 80 %
        final res = await r.runHook();
        expect(res.exitCode, 0, reason: res.output);
        expect(res.calls, ['make coverage-run']);
        expect(res.output, contains('every part reaches 80 %. Pushing.'));
      },
    );

    test('a failing test aborts the push and names the reason', () async {
      r.stageCoverage();
      final res = await r.runHook(fail: 'make');
      expect(res.exitCode, 1);
      expect(res.output, contains('FAIL loadsFlac (fake test failure)'));
      expect(res.output, contains('pre-push: a test failed'));
      expect(res.output, contains('Push aborted.'));
      expect(res.output, isNot(contains('checking coverage')));
    });

    test(
      'the core below the minimum aborts the push and names the part',
      () async {
        r.stageCoverage(core: 7, dart: 10);
        final res = await r.runHook();
        expect(res.exitCode, 1);
        expect(
          res.output,
          contains('C++ core (core/): 70.0 % is below 80.0 %'),
        );
        expect(res.output, contains('a part is below the minimum of 80 %'));
        expect(res.output, contains('Push aborted.'));
      },
    );

    test('the Dart logic below the minimum aborts the push', () async {
      r.stageCoverage(core: 10, dart: 5);
      final res = await r.runHook();
      expect(res.exitCode, 1);
      expect(
        res.output,
        contains('Dart logic (app/lib): 50.0 % is below 80.0 %'),
      );
    });

    test('the minimum is read from tools/coverage-min', () async {
      r.stageCoverage(core: 7, dart: 10);
      r.write('tools/coverage-min', '70\n');
      final res = await r.runHook();
      expect(res.exitCode, 0, reason: res.output);
      expect(res.output, contains('checking coverage per part (minimum 70 %)'));
    });

    test('without tools/coverage-min the push is aborted', () async {
      File('${r.repo.path}/tools/coverage-min').deleteSync();
      final res = await r.runHook();
      expect(res.exitCode, 1);
      expect(res.output, contains('tools/coverage-min is missing'));
      expect(res.calls, isEmpty);
    });

    test('missing coverage data aborts the push', () async {
      // make succeeds but writes no lcov file
      final res = await r.runHook();
      expect(res.exitCode, 1);
      expect(res.output, contains('coverage file missing'));
      expect(res.output, contains('coverage could not be checked'));
    });

    test('only deleting a remote branch checks nothing', () async {
      final res = await r.runHook(
        stdinLine:
            '(delete) $_zero refs/heads/old ${r.git(['rev-parse', 'HEAD'])}',
      );
      expect(res.exitCode, 0);
      expect(res.calls, isEmpty);
    });

    test('installed with core.hooksPath, git push runs it and is refused below the minimum', () async {
      final remote = Directory('${r.root.path}/remote.git');
      await Process.run('git', ['init', '-q', '--bare', remote.path]);
      r.git(['remote', 'add', 'origin', remote.path]);
      r.git(['config', 'core.hooksPath', 'tools/git-hooks']);

      Future<ProcessResult> push() => Process.run(
        'git',
        ['push', '-q', 'origin', 'main'],
        workingDirectory: r.repo.path,
        environment: r.env,
      );
      String remoteHead() =>
          '${Process.runSync('git', ['rev-parse', '--verify', '-q', 'refs/heads/main'], workingDirectory: remote.path).stdout}'
              .trim();

      r.stageCoverage(core: 5, dart: 10);
      final refused = await push();
      expect(refused.exitCode, isNot(0));
      expect(
        '${refused.stdout}${refused.stderr}',
        contains('C++ core (core/): 50.0 % is below 80.0 %'),
      );
      expect(remoteHead(), isEmpty);

      r.stageCoverage(core: 10, dart: 10);
      final accepted = await push();
      expect(accepted.exitCode, 0, reason: '${accepted.stderr}');
      expect(remoteHead(), r.git(['rev-parse', 'HEAD']));
    });
  });
}
