// tools/ios_sim_test.sh (#155) with fake `xcrun` and `flutter` in PATH: a hanging smoke test stops
// after WP_IOS_TEST_LIMIT seconds with an error and the simulator's state in the log; in CI
// `flutter test` runs with -v.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _udid = '3C77BD39-D906-4EE7-A765-141CEFD8EFDF';

void main() {
  final script = File('../tools/ios_sim_test.sh').absolute.path;

  late Directory bin;
  late File calls;

  setUp(() {
    bin = Directory.systemTemp.createTempSync('ios_sim_test_');
    calls = File('${bin.path}/calls')..writeAsStringSync('');
    _fake(bin, 'xcrun', '''
echo "xcrun \$*" >> "${calls.path}"
case "\$*" in
  "simctl list devices available") echo "    iPhone 17 Pro ($_udid) (Booted)" ;;
  "simctl list devices") echo "    iPhone 17 Pro ($_udid) (Booted)" ;;
  simctl\\ get_app_container*) echo "/sim/Containers/Bundle/Runner.app" ;;
  *launchctl\\ list) echo "4711 0 UIKitApplication:ch.woodshed-player-app.ios[1a2b]" ;;
  *log\\ show*) echo "Runner: fake app log line" ;;
esac
''');
  });

  tearDown(() => bin.deleteSync(recursive: true));

  Future<ProcessResult> run(String flutter, Map<String, String> env) {
    _fake(bin, 'flutter', 'echo "flutter \$*" >> "${calls.path}"\n$flutter');
    return Process.run(
      script,
      [],
      environment: {
        'PATH': '${bin.path}:${Platform.environment['PATH']}',
        'CI': '',
        ...env,
      },
    );
  }

  test(
    '#155/AK1 a hanging smoke test stops after WP_IOS_TEST_LIMIT with an error',
    () async {
      final watch = Stopwatch()..start();
      final r = await run('sleep 300', {'WP_IOS_TEST_LIMIT': '2'});
      expect(r.exitCode, 124, reason: '${r.stdout}\n${r.stderr}');
      expect(r.stderr, contains('did not finish within 2 s'));
      // the hanging flutter and its sleep are gone, not left behind
      expect(watch.elapsed, lessThan(const Duration(seconds: 60)));
    },
  );

  test('#155/AK2 on the limit the log shows simulator state, running app and its system log', () async {
    final r = await run('sleep 300', {'WP_IOS_TEST_LIMIT': '2'});
    final out = '${r.stdout}';
    expect(out, contains('iPhone 17 Pro ($_udid) (Booted)'));
    expect(out, contains('app installed: /sim/Containers/Bundle/Runner.app'));
    expect(out, contains('app running: 4711 0 UIKitApplication:'));
    expect(out, contains('processes of flutter test'));
    expect(out, contains('sleep 300'));
    expect(out, contains('Runner: fake app log line'));
    expect(
      calls.readAsStringSync(),
      contains('simctl get_app_container $_udid ch.woodshed-player-app.ios'),
    );
  });

  test('#155/AK2 in CI flutter test runs with -v, locally without', () async {
    var r = await run('exit 0', {'CI': 'true'});
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    expect(
      calls.readAsStringSync(),
      contains(
        'flutter test integration_test/app_smoke_test.dart -d $_udid -v',
      ),
    );
    calls.writeAsStringSync('');
    r = await run('exit 0', {});
    expect(r.exitCode, 0);
    expect(calls.readAsStringSync(), isNot(contains(' -v')));
  });

  test(
    '#155/AK1 a finished run keeps its exit code and prints no diagnosis',
    () async {
      final r = await run('exit 3', {'WP_IOS_TEST_LIMIT': '60'});
      expect(r.exitCode, 3);
      expect(r.stdout, isNot(contains('simulator state')));
    },
  );
}

void _fake(Directory bin, String name, String body) {
  final f = File('${bin.path}/$name')..writeAsStringSync('#!/bin/bash\n$body');
  Process.runSync('chmod', ['+x', f.path]);
}
