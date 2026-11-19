// #57, #10: sanitizer, fuzzing and random test runs in .github/workflows/test-quality.yml and the make targets
// they call. The runs themselves happen on GitHub; this test pins down when they start and what
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
}
