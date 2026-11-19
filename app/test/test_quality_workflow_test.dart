// #57, #10, #58, #13: sanitizer, fuzzing, random test, network check, checks, web, macOS and UI runs in
// .github/workflows/test-quality.yml and the make targets they call. The runs themselves happen on GitHub; this test pins down when they start and what
// they run. Runs from app/ like the other tests.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

/// The block of one job: from `  <name>:` up to the next job or the end.
String job(String workflow, String name) {
  final start = workflow.indexOf('\n  $name:\n');
  expect(start, isNot(-1), reason: 'job $name missing');
  final rest = workflow.substring(start + 1);
  final next = RegExp(r'\n  [a-z-]+:\n').firstMatch(rest.substring(1));
  return next == null ? rest : rest.substring(0, next.start + 1);
}

void main() {
  final workflow = read('../.github/workflows/test-quality.yml');
  final makefile = read('../Makefile');

  group('#57/AK1 ASan and UBSan', () {
    test('make sanitize builds core/build-asan with address,undefined', () {
      expect(makefile, contains('\nsanitize:\n'));
      expect(makefile, isNot(contains('sanitize:      ; \$(call not_yet')));
      expect(
        makefile,
        contains(
          '-B core/build-asan -DCMAKE_BUILD_TYPE=Debug '
          '-DWP_SANITIZE=address,undefined',
        ),
      );
      expect(makefile, contains('ctest --test-dir core/build-asan'));
    });

    test('runs on Linux on a push to main that changes core/, and by hand', () {
      expect(workflow, contains('branches: [main]'));
      expect(workflow, contains('workflow_dispatch:'));
      final changes = job(workflow, 'changes');
      expect(changes, contains("if: github.event_name == 'push'"));
      expect(changes, contains('^(core/|Makefile\$|'));
      final sanitize = job(workflow, 'sanitize');
      expect(sanitize, contains('runs-on: ubuntu-latest'));
      expect(sanitize, contains("needs.changes.outputs.core == 'true'"));
      expect(sanitize, contains("github.event_name == 'workflow_dispatch'"));
      expect(sanitize, contains('run: make sanitize\n'));
    });
  });

  group('#57/AK2 ThreadSanitizer', () {
    test('make sanitize-thread builds core/build-tsan with thread', () {
      expect(makefile, contains('\nsanitize-thread:\n'));
      expect(
        makefile,
        contains(
          '-B core/build-tsan -DCMAKE_BUILD_TYPE=Debug '
          '-DWP_SANITIZE=thread',
        ),
      );
    });

    test('runs nightly only after a new commit, and by hand', () {
      expect(workflow, contains('schedule:'));
      expect(workflow, contains("- cron: '17 2 * * *'"));
      final gate = job(workflow, 'nightly-gate');
      expect(gate, contains("if: github.event_name == 'schedule'"));
      expect(gate, contains('--event schedule --status success'));
      expect(gate, contains(r'if [ "$last" = "$GITHUB_SHA" ]'));
      final tsan = job(workflow, 'sanitize-thread');
      expect(tsan, contains('runs-on: ubuntu-latest'));
      expect(tsan, contains("needs.nightly-gate.outputs.run == 'true'"));
      expect(tsan, contains("github.event_name == 'workflow_dispatch'"));
      expect(tsan, contains('run: make sanitize-thread\n'));
    });
  });

  group('#10/AK4, AK9 fuzzing', () {
    test('make fuzz builds core/build-fuzz with libFuzzer, ASan and UBSan', () {
      expect(makefile, contains('\nfuzz: fuzz-build\n'));
      expect(makefile, isNot(contains('fuzz:          ; \$(call not_yet')));
      expect(makefile, contains('-DWP_SANITIZE=address,undefined'));
      expect(makefile, contains('-DWP_FUZZ=ON'));
      // regressions and the checked-in start corpus first, new corpus files in the build folder
      expect(
        makefile,
        contains(r'$(FUZZ_DIR)/corpus/$$t core/tests/fuzz/regressions/$$t'),
      );
      expect(makefile, contains('core/tests/fuzz/corpus/\$\$t'));
      expect(makefile, contains('-artifact_prefix='));
    });

    test('runs nightly only after a new commit, and by hand; findings fail and are kept', () {
      final fuzz = job(workflow, 'fuzz');
      expect(fuzz, contains('runs-on: ubuntu-latest'));
      expect(fuzz, contains("needs.nightly-gate.outputs.run == 'true'"));
      expect(fuzz, contains("github.event_name == 'workflow_dispatch'"));
      expect(fuzz, contains('run: make fuzz FUZZ_SECONDS='));
      expect(fuzz, contains('if: failure()'));
      expect(fuzz, contains('actions/upload-artifact@v4'));
      expect(fuzz, contains('core/build-fuzz/artifacts/'));
    });
  });

  group('#10/AK1, AK6 random tests', () {
    test('make property passes the number of cases and the seed', () {
      expect(makefile, contains('\nproperty:\n'));
      expect(
        makefile,
        contains(
          r'WP_PROPERTY_CASES=$(PROPERTY_CASES) WP_PROPERTY_SEED=$(PROPERTY_SEED)',
        ),
      );
    });

    test('nightly with many cases and a new seed', () {
      final property = job(workflow, 'property');
      expect(property, contains("needs.nightly-gate.outputs.run == 'true'"));
      expect(property, contains('make property PROPERTY_CASES=3000'));
      expect(property, contains(r'PROPERTY_SEED=${{ github.run_id }}'));
    });
  });

  group('#58/AK6 network check', () {
    test('make network-free runs the check, its tests and the #37 test', () {
      expect(makefile, contains('\nnetwork-free:\n'));
      expect(makefile, isNot(contains('call not_yet,58')));
      final target = makefile.substring(makefile.indexOf('\nnetwork-free:\n'));
      final body = target.substring(0, target.indexOf('\n\n'));
      expect(body, contains('dart app/tool/network_free.dart'));
      expect(body, contains('tool/network_free_test.dart'));
      // #58/AK5: without an account no HttpClient (#37/AK2) stays part of the check
      expect(body, contains('test/sync_app_test.dart'));
    });

    test('runs on every push to main without a path filter, and by hand', () {
      final job58 = job(workflow, 'network-free');
      expect(job58, contains("github.event_name == 'push'"));
      expect(job58, contains("github.event_name == 'workflow_dispatch'"));
      expect(job58, isNot(contains('needs:')));
      expect(job58, contains('runs-on: ubuntu-latest'));
      expect(job58, contains('run: make network-free\n'));
    });
  });

  final nightlyJobs = ['macos', 'sanitize-thread', 'fuzz', 'property'];

  group('#13/AK3 checks on Linux on every push with a code change', () {
    test('changes reports code and web changes', () {
      final changes = job(workflow, 'changes');
      expect(changes, contains('code: \${{ steps.diff.outputs.code }}'));
      expect(changes, contains('web: \${{ steps.diff.outputs.web }}'));
      expect(
        changes,
        contains(
          r"code=$(has '^(core/|app/|tools/|Makefile$|\.github/workflows/test-quality\.yml$)')",
        ),
      );
      expect(changes, contains(r'app/lib/.*_web\.dart$'));
    });

    test('format, lint, tests and coverage of core and Dart code', () {
      final checks = job(workflow, 'checks');
      expect(checks, contains('runs-on: ubuntu-latest'));
      expect(checks, contains("needs.changes.outputs.code == 'true'"));
      expect(checks, contains("github.event_name == 'workflow_dispatch'"));
      expect(checks, contains('run: make format-check\n'));
      expect(checks, contains('run: make lint\n'));
      expect(checks, contains('make coverage-run'));
      // the minimum comes from tools/coverage-min through the check of #8
      expect(checks, contains('dart app/tool/coverage_check.dart'));
      expect(checks, contains('set -o pipefail'));
    });

    test('the same Flutter version as the Pages workflow', () {
      final version = RegExp(r'FLUTTER_VERSION: ([\d.]+)');
      final pages = read('../.github/workflows/pages.yml');
      expect(
        version.firstMatch(workflow)!.group(1),
        version.firstMatch(pages)!.group(1),
      );
      expect(workflow, isNot(contains('channel: stable')));
    });
  });

  group(
    '#13/AK3, AK5 nightly macOS and iOS build, UI tests, app smoke test',
    () {
      test('macOS job after the gate, builds, UI tests and the smoke test', () {
        final mac = job(workflow, 'macos');
        expect(mac, contains('runs-on: macos-latest'));
        expect(mac, contains("needs.nightly-gate.outputs.run == 'true'"));
        expect(mac, contains("WP_AUDIO_BACKEND: 'null'"));
        expect(mac, contains('flutter build macos --debug'));
        expect(mac, contains('flutter build ios --simulator --debug'));
        expect(mac, contains('flutter test integration_test -d macos'));
        final smoke = mac.indexOf('tools/smoke_app.sh');
        expect(
          smoke,
          greaterThan(mac.indexOf('flutter build macos --release')),
        );
        expect(
          makefile,
          contains('flutter test integration_test -d macos'),
        ); // make test-ui
      });

      test('mutation tests on the diff are planned as a nightly job (#11)', () {
        expect(
          workflow,
          contains('Mutation tests on the diff follow with #11'),
        );
      });
    },
  );

  group('#13/AK4 web build and web tests in Chrome', () {
    test('on a push with a web change, and by hand', () {
      final web = job(workflow, 'web');
      expect(web, contains('runs-on: ubuntu-latest'));
      expect(web, contains("needs.changes.outputs.web == 'true'"));
      expect(web, contains("github.event_name == 'workflow_dispatch'"));
      expect(web, contains('make test-web'));
      expect(web, contains('flutter build web'));
    });

    test('make test-web runs test/web in Chrome with the WASM core', () {
      final target = makefile.substring(makefile.indexOf('\ntest-web:\n'));
      final body = target.substring(0, target.indexOf('\n\n'));
      expect(body, contains('app/tool/build_web_core.sh'));
      expect(body, contains('app/test/web/wp_core/'));
      expect(body, contains('tools/chrome_autoplay.sh'));
      expect(body, contains('--platform chrome'));
      expect(body, contains('test/web/'));
    });
  });

  group('#13/AK8 nightly jobs: gate, nightly=true, own concurrency group', () {
    test('workflow_dispatch has the boolean input nightly', () {
      expect(
        workflow,
        contains('  workflow_dispatch:\n    inputs:\n      nightly:\n'),
      );
      expect(workflow, contains('type: boolean'));
    });

    test('every nightly job: after a new commit, or by hand with nightly', () {
      for (final name in nightlyJobs) {
        final j = job(workflow, name);
        expect(j, contains('needs: nightly-gate'), reason: name);
        expect(
          j,
          contains(
            "(github.event_name == 'workflow_dispatch' && inputs.nightly)",
          ),
          reason: name,
        );
        expect(
          j,
          contains(
            "(github.event_name == 'schedule' && needs.nightly-gate.outputs.run == 'true')",
          ),
          reason: name,
        );
      }
    });

    test('nightly runs have their own group, only pushes are cancelled', () {
      expect(
        workflow,
        contains(
          "(github.event_name == 'schedule' || inputs.nightly) && 'nightly'",
        ),
      );
      expect(
        workflow,
        contains(r"cancel-in-progress: ${{ github.event_name == 'push' }}"),
      );
    });
  });

  group('#13/AK9 run summary', () {
    test('coverage, coverage-diff and the overview page', () {
      final checks = job(workflow, 'checks');
      expect(checks, contains('dart app/tool/coverage_diff.dart --base'));
      expect(checks, contains(r'>> "$GITHUB_STEP_SUMMARY"'));
      expect(checks, contains('cat coverage-check.txt'));
      expect(checks, contains('cat coverage-diff.txt'));
      // overview page of #12 as an artifact as soon as make report exists
      expect(checks, contains('name: test-quality-report'));
      expect(checks, contains('path: build/report/'));
      expect(checks, contains('make report'));
    });
  });
}
