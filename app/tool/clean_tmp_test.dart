// tools/clean-tmp.sh: removes what aborted test runs left in the temp directory, nothing else.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final script = File('../tools/clean-tmp.sh').absolute.path;

  test('old leftovers go; recent ones, the mutation cache and foreign entries stay', () {
    final tmp = Directory.systemTemp.createTempSync('clean_tmp_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    Directory entry(String name, {bool old = true}) {
      final d = Directory('${tmp.path}/$name')..createSync();
      final f = File('${d.path}/f')..writeAsStringSync('x');
      if (old) {
        final t = DateTime.now().subtract(const Duration(hours: 2));
        f.setLastModifiedSync(t);
        Process.runSync('touch', ['-t', _touch(t), d.path]);
      }
      return d;
    }

    final gone = [
      entry('flutter_tools.abc123'),
      entry('wp_ui_testXYZ'),
      entry('wp-run-123'),
    ];
    final stay = [
      entry('flutter_tools.recent', old: false),
      entry('wp-mutants-6a8f7d'),
      entry('com.example.other'),
      entry('flutter_toolsx'),
    ];
    final r = Process.runSync(script, [], environment: {'TMPDIR': tmp.path});
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(r.stdout, contains('removed 3 entries'));
    for (final d in gone) {
      expect(d.existsSync(), isFalse, reason: d.path);
    }
    for (final d in stay) {
      expect(d.existsSync(), isTrue, reason: d.path);
    }
  });

  test('-n only lists', () {
    final tmp = Directory.systemTemp.createTempSync('clean_tmp_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final d = Directory('${tmp.path}/flutter_tools.old')..createSync();
    Process.runSync('touch', ['-t', _touch(DateTime(2020)), d.path]);
    final r = Process.runSync(
      script,
      ['-n'],
      environment: {'TMPDIR': tmp.path},
    );
    expect(r.stdout, contains('would remove 1 entries'));
    expect(d.existsSync(), isTrue);
  });
}

String _touch(DateTime t) =>
    '${t.year}${_2(t.month)}${_2(t.day)}${_2(t.hour)}${_2(t.minute)}';
String _2(int v) => v.toString().padLeft(2, '0');
