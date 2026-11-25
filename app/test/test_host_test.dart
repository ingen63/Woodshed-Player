// #151: the macOS app as host of the Swift tests does not start its Dart part.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/test_host.dart';

void main() {
  test(
    '#151/AK1 the variables of a Swift test run make the app a test host',
    () {
      for (final name in swiftTestHostVariables) {
        expect(isSwiftTestHost({name: '/tmp/x'}), isTrue, reason: name);
      }
    },
  );

  test('#151/AK5 a normal start is no test host', () {
    expect(isSwiftTestHost(const {}), isFalse);
    expect(
      isSwiftTestHost(const {'HOME': '/Users/x', 'WP_SMOKE': '1'}),
      isFalse,
    );
  });

  test('#151/AK1 Dart and Swift check the same variables', () {
    final swift = File('macos/Runner/MainFlutterWindow.swift')
        .readAsStringSync();
    for (final name in swiftTestHostVariables) {
      expect(swift, contains('"$name"'), reason: name);
    }
  });

  test('#151/AK1 main returns before anything else as test host', () {
    final main = File('lib/main.dart').readAsStringSync();
    final body = main.substring(main.indexOf('Future<void> main() async {'));
    expect(
      body.indexOf('if (swiftTestHost) return;'),
      lessThan(body.indexOf('WidgetsFlutterBinding.ensureInitialized()')),
    );
  });
}
