// #7/AK7: tests of the Claude Code hook after a commit (.claude/hooks/after-commit.sh).
//
// Every test creates a small git repository and puts fake `cmake`, `ctest`, `flutter` and `xcodebuild`
// first on the PATH. The fakes record their arguments and fail on request, so the tests check which
// steps the hook runs and what it reports to Claude, without building anything.
//
// Run: cd app && flutter test tool/after_commit_hook_test.dart   (or `make test-hook`)
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _hook = File(
  '${Directory.current.parent.path}/.claude/hooks/after-commit.sh',
).absolute.path;

/// Records `tool args` and fails when `tool first-arg` is listed in FAKE_FAIL.
const _fakeTool = r'''#!/bin/sh
name="$(basename "$0")"
echo "$name $*" >> "$FAKE_LOG"
case ",${FAKE_FAIL:-}," in
  *",$name $1,"*) echo "error: fake failure in $name $1"; exit 1 ;;
esac
exit 0
''';

class _Repo {
  _Repo(this.root);

  final Directory root;
  Directory get repo => Directory('${root.path}/repo');
  File get log => File('${root.path}/tools.log');

  static Future<_Repo> create() async {
    final r = _Repo(await Directory.systemTemp.createTemp('wp_hook_test'));
    final bin = Directory('${r.root.path}/bin')..createSync();
    for (final tool in ['cmake', 'ctest', 'flutter', 'xcodebuild']) {
      final f = File('${bin.path}/$tool')..writeAsStringSync(_fakeTool);
      await Process.run('chmod', ['755', f.path]);
    }
    r.repo.createSync();
    r.git(['init', '-q']);
    r.git(['config', 'user.email', 'test@example.invalid']);
    r.git(['config', 'user.name', 'Test']);
    r.git(['config', 'commit.gpgsign', 'false']);
    for (final p in [
      'app/lib/main.dart',
      'app/test/main_test.dart',
      'core/src/engine.cpp',
      'core/tests/engine_tests.cpp',
      'WoodshedPlayer/Audio/AudioPlayer.swift',
      'docs/TESTS.md',
    ]) {
      r.write(p, '// start\n');
    }
    r.commit('Start (#1)');
    return r;
  }

  void git(List<String> args) {
    final res = Process.runSync('git', args, workingDirectory: repo.path);
    if (res.exitCode != 0) throw StateError('git $args: ${res.stderr}');
  }

  void write(String rel, String text) {
    File('${repo.path}/$rel')
      ..createSync(recursive: true)
      ..writeAsStringSync(text);
  }

  void change(List<String> paths) {
    for (final p in paths) {
      File('${repo.path}/$p')
          .writeAsStringSync('// changed\n', mode: FileMode.append);
    }
  }

  void commit(String message) {
    git(['add', '-A']);
    git(['commit', '-q', '-m', message]);
  }

  /// Runs the hook as Claude Code would after the Bash call [command].
  Future<_Result> runHook({
    String command = 'git commit -m "x"',
    String fail = '',
  }) async {
    if (log.existsSync()) log.deleteSync();
    final proc = await Process.start(
      'bash',
      [_hook],
      environment: {
        'PATH': '${root.path}/bin:${Platform.environment['PATH']}',
        'CLAUDE_PROJECT_DIR': repo.path,
        'TMPDIR': root.path,
        'FAKE_LOG': log.path,
        'FAKE_FAIL': fail,
      },
    );
    proc.stdin.write(
      jsonEncode({
        'tool_input': {'command': command},
      }),
    );
    await proc.stdin.close();
    final out = await proc.stdout.transform(utf8.decoder).join();
    await proc.stderr.drain<void>();
    final code = await proc.exitCode;
    final calls = log.existsSync() ? log.readAsLinesSync() : <String>[];
    return _Result(code, out, calls);
  }
}

class _Result {
  _Result(this.exitCode, this.stdout, this.calls);

  final int exitCode;
  final String stdout;
  final List<String> calls;

  Map<String, Object?>? get json =>
      stdout.trim().isEmpty ? null : jsonDecode(stdout) as Map<String, Object?>;
  bool get blocked => json?['decision'] == 'block';
  String get reason => (json?['reason'] as String?) ?? '';
  String get context {
    final h = json?['hookSpecificOutput'] as Map<String, Object?>?;
    return (h?['additionalContext'] as String?) ?? '';
  }
}

void main() {
  late _Repo r;

  setUp(() async => r = await _Repo.create());
  tearDown(() => r.root.deleteSync(recursive: true));

  group('#7/AK7 hook after commit', () {
    test(
      'Dart change with test: analyze and test, no C++ or builds, green',
      () async {
        r.change(['app/lib/main.dart', 'app/test/main_test.dart']);
        r.commit('Dart change (#7)');
        final res = await r.runHook();
        expect(res.exitCode, 0);
        expect(res.calls, [
          'flutter analyze --no-pub',
          'flutter test --reporter failures-only',
        ]);
        expect(res.blocked, isFalse);
        expect(res.context, contains('grün'));
        expect(res.context, contains('flutter test'));
      },
    );

    test('C++ change with test: core build, ctest, Dart checks and both app builds', () async {
      r.change(['core/src/engine.cpp', 'core/tests/engine_tests.cpp']);
      r.commit('Core change (#7)');
      final res = await r.runHook();
      expect(res.calls.map((c) => c.split(' ').take(2).join(' ')), [
        'cmake -S',
        'cmake --build',
        'ctest --test-dir',
        'flutter analyze',
        'flutter test',
        'flutter build',
        'flutter build',
      ]);
      expect(res.calls, contains('flutter build macos --debug'));
      expect(res.calls, contains('flutter build ios --simulator --debug'));
      expect(res.blocked, isFalse);
      expect(res.context, contains('grün'));
    });

    test(
      'logic without test: green steps, then the test-agent is requested',
      () async {
        r.change(['app/lib/main.dart']);
        r.commit('Logic only (#7)');
        final res = await r.runHook();
        expect(res.calls, hasLength(2));
        expect(res.blocked, isTrue);
        expect(
          res.reason,
          contains('ändert Logik ohne Tests (app/lib/main.dart)'),
        );
        expect(res.reason, contains('test-agent'));
        expect(res.reason, contains('SCHNELLMODUS'));
      },
    );

    test('C++ logic without test also requests the test-agent', () async {
      r.change(['core/src/engine.cpp']);
      r.commit('Core logic only (#7)');
      final res = await r.runHook();
      expect(res.blocked, isTrue);
      expect(res.reason, contains('core/src/engine.cpp'));
      expect(res.reason, contains('test-agent'));
    });

    test(
      'failure: the hook stops at the failing step and reports its error lines',
      () async {
        r.change(['app/lib/main.dart', 'app/test/main_test.dart']);
        r.commit('Breaks a test (#7)');
        final res = await r.runHook(fail: 'flutter test');
        expect(res.calls, [
          'flutter analyze --no-pub',
          'flutter test --reporter failures-only',
        ]);
        expect(res.blocked, isTrue);
        expect(res.reason, contains('«flutter test» ist fehlgeschlagen'));
        expect(res.reason, contains('error: fake failure in flutter test'));
        expect(res.reason, isNot(contains('SCHNELLMODUS')));
      },
    );

    test('failing core build: no further steps', () async {
      r.change(['core/src/engine.cpp', 'core/tests/engine_tests.cpp']);
      r.commit('Breaks the core (#7)');
      final res = await r.runHook(fail: 'cmake --build');
      expect(res.calls, hasLength(2));
      expect(res.reason, contains('«C++-Kern bauen» ist fehlgeschlagen'));
    });

    test('Swift change: xcodebuild test and iOS build only', () async {
      r.change(['WoodshedPlayer/Audio/AudioPlayer.swift']);
      r.commit('Swift change (#7)');
      final res = await r.runHook();
      expect(res.calls, hasLength(2));
      expect(res.calls.every((c) => c.startsWith('xcodebuild ')), isTrue);
      // Audio logic without a test in WoodshedPlayerTests/
      expect(res.reason, contains('test-agent'));
    });

    test('hook changed: its own tests run', () async {
      r.write('.claude/hooks/after-commit.sh', '# changed\n');
      r.commit('Hook change (#7)');
      final res = await r.runHook();
      expect(res.calls, [
        'flutter test --reporter failures-only tool/after_commit_hook_test.dart',
      ]);
      expect(res.context, contains('Hook-Tests'));
    });

    test('documents only: no steps and no output', () async {
      r.change(['docs/TESTS.md']);
      r.commit('Docs (#7)');
      final res = await r.runHook();
      expect(res.calls, isEmpty);
      expect(res.stdout.trim(), isEmpty);
    });

    test('commit message without issue number is reported', () async {
      r.change(['docs/TESTS.md']);
      r.commit('Docs without issue');
      final res = await r.runHook();
      expect(res.blocked, isTrue);
      expect(res.reason, contains('nicht das Format «Titel (#22)»'));
    });

    test('other Bash commands and test(auto) commits are ignored', () async {
      r.change(['app/lib/main.dart']);
      r.commit('Logic only (#7)');
      final other = await r.runHook(command: 'git status');
      expect(other.calls, isEmpty);
      expect(other.stdout.trim(), isEmpty);

      r.change(['app/test/main_test.dart']);
      r.commit('test(auto): tests for main (abc123)');
      final auto = await r.runHook();
      expect(auto.calls, isEmpty);
      expect(auto.stdout.trim(), isEmpty);
    });

    test('git -C <dir> commit is recognised as a commit', () async {
      r.change(['app/lib/main.dart', 'app/test/main_test.dart']);
      r.commit('Dart change (#7)');
      final res = await r.runHook(
        command: 'git -C "${r.repo.path}" commit -m x',
      );
      expect(res.calls, hasLength(2));
    });
  });
}
