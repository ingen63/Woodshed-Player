// Tests of tool/slow_tests.dart (#128) on a staged JSON file of `flutter test --file-reporter json`
// (tool/testdata/slow_tests.json) and the staged source of its test file
// (tool/testdata/slow_tests_source.txt). Limits: logic 0.25 s, widget 2.0 s.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'slow_tests.dart';

const _file = '/repo/app/test/a_test.dart';

final _json = File('tool/testdata/slow_tests.json').readAsStringSync();
final _source = File('tool/testdata/slow_tests_source.txt').readAsLinesSync();

List<String>? _read(String path) => path == _file ? _source : null;

List<String> _names(List<TestTime> tests) => [for (final t in tests) t.name];

void main() {
  test('#128/AK4 tests under their limit are not listed; a widget test has its own limit', () {
    final names = _names(slowTests(_json, _read));
    // 0.2 s logic, 1.5 s widget (over the logic limit, under the widget limit)
    expect(names, isNot(contains('logic fast')));
    expect(names, isNot(contains('widget under its limit')));
  });

  test('#128/AK4 over the limit with «// slow: <reason>» in the comment block directly above: not listed', () {
    final names = _names(slowTests(_json, _read));
    expect(names, isNot(contains('logic slow with reason')));
    // declared through a helper (property.dart): the line in the test file counts
    expect(names, isNot(contains('property slow with reason')));
  });

  test('#128/AK3, #128/AK4 over the limit without a reason: listed with file, line, kind and seconds, slowest first', () {
    final slow = slowTests(_json, _read);
    expect(
      [
        for (final t in slow)
          '${relativePath(t.path, '/repo')}:${t.line} ${t.widget} '
              '${t.seconds} ${t.name}',
      ],
      [
        // «// slow:» without a reason does not count
        'app/test/a_test.dart:30 true 2.5 widget slow',
        // a reason above a code line belongs to no test
        'app/test/a_test.dart:21 false 0.3 logic slow, reason too far up',
      ],
    );
  });

  test('#128/AK4 loading a file, setUpAll and tearDownAll do not count', () {
    // 9 s loading and 5 s each for setUpAll and tearDownAll in the staged file
    expect(
      testTimes(_json).where((t) => t.seconds >= 5 || t.name.startsWith('(')),
      isEmpty,
    );
  });
}
