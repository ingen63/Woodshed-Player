// #57, #10, #58, #13, #59, #11, #64, #77, #67: actionlint, contract native/WASM, sanitizer, fuzzing, random test, network check, checks, web, macOS, UI, bench and mutation runs in
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

/// #79: what keeps the workflows from using one fixed Emscripten version.
/// Empty when every workflow sets `EMSDK_VERSION` exactly once, installs and
/// activates emsdk only with it (never `latest` or a literal version), all
/// workflows agree and docs/TESTS.md names only that version.
List<String> emsdkProblems(Map<String, String> workflows, String docs) {
  final problems = <String>[];
  final versions = <String>{};
  for (final MapEntry(key: name, value: text) in workflows.entries) {
    final settings = RegExp(r'EMSDK_VERSION: *(\S+)').allMatches(text).toList();
    if (settings.length != 1) {
      problems.add('$name sets EMSDK_VERSION ${settings.length} times');
    }
    for (final setting in settings) {
      final version = setting.group(1)!;
      if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(version)) {
        problems.add('$name: EMSDK_VERSION $version is not fixed');
      }
      versions.add(version);
    }
    final calls = RegExp(r'emsdk" (install|activate) (\S+)').allMatches(text);
    if (calls.isEmpty) problems.add('$name installs no Emscripten');
    for (final call in calls) {
      if (call.group(2) != r'"$EMSDK_VERSION"') {
        problems.add('$name: ${call.group(0)}');
      }
    }
    if (text.contains('latest >')) problems.add('$name uses latest');
  }
  if (versions.length != 1) problems.add('versions differ: $versions');
  final documented = RegExp(r'Emscripten (\d+\.\d+\.\d+)')
      .allMatches(docs)
      .map((m) => m.group(1)!)
      .toSet();
  if (documented.isEmpty ||
      !documented.containsAll(versions) ||
      !versions.containsAll(documented)) {
    problems.add('docs/TESTS.md names $documented, workflows $versions');
  }
  return problems;
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

  group('#67 fuzz inputs against the WASM core', () {
    /// The recipe of one make target, up to the next blank line.
    String recipe(String name) {
      final target = makefile.substring(makefile.indexOf('\n$name:'));
      return target.substring(0, target.indexOf('\n\n'));
    }

    test('#67/AK1, AK3 the WASM build replays regressions and start corpus in make test-wasm', () {
      // the same replay tests as natively (fuzz_<target>_replay, regressions first, whole folders)
      final web = read('../core/web/web.cmake');
      expect(web, contains('include(tests/fuzz/fuzz.cmake)'));
      expect(
        web.indexOf('include(tests/fuzz/fuzz.cmake)'),
        greaterThan(web.indexOf('include(tests/reference.cmake)')),
      );
      final fuzz = read('../core/tests/fuzz/fuzz.cmake');
      expect(
        fuzz,
        contains(
          r'${WP_FUZZ_DIR}/regressions/${name} ${WP_FUZZ_DIR}/corpus/${name}',
        ),
      );
      expect(
        read('../core/tests/fuzz/replay_main.cpp'),
        contains('fs::directory_iterator(arg)'),
      );
      expect(
        recipe('test-wasm-compare'),
        contains('ctest --test-dir core/build-wasm'),
      );
    });

    test(
      '#67/AK2, AK3 make fuzz-wasm runs every input of make fuzz under Node.js',
      () {
        final target = recipe('fuzz-wasm');
        expect(target, contains('emcmake cmake -S core -B \$(FUZZ_WASM_DIR)'));
        expect(target, contains('core/tests/fuzz/regressions/\$\$t'));
        expect(target, contains('core/tests/fuzz/corpus/\$\$t'));
        // the corpus grown by make fuzz, if there is one
        expect(target, contains('\$(FUZZ_DIR)/corpus/\$\$t'));
        expect(target, contains('node "fuzz_\$\${t}_replay.js" "\$\$@"'));
        expect(target, contains('exit 1'));
      },
    );

    test(
      '#67/AK2 runs nightly in the fuzz job after make fuzz, Emscripten fixed',
      () {
        final fuzz = job(workflow, 'fuzz');
        final native = fuzz.indexOf('run: make fuzz FUZZ_SECONDS=');
        final emsdk = fuzz.indexOf(r'emsdk" install "$EMSDK_VERSION"');
        final wasm = fuzz.indexOf('make fuzz-wasm\n');
        expect(native, isNot(-1));
        expect(emsdk, greaterThan(native));
        expect(wasm, greaterThan(emsdk));
        expect(fuzz, contains('emsdk_env.sh'));
        expect(fuzz, isNot(contains('install latest')));
        expect(fuzz, contains('core/build-wasm/fuzz_*_replay.log'));
      },
    );
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

  group('#59/AK5 performance and load tests nightly, not on every push', () {
    test('make bench runs the core cases with label bench and the Dart cases with tag bench', () {
      expect(makefile, contains('\nbench:\n'));
      expect(
        makefile,
        contains(
          '-B core/build-bench -DCMAKE_BUILD_TYPE=Release -DWP_BENCH=ON',
        ),
      );
      expect(makefile, contains('ctest --test-dir core/build-bench -L bench'));
      expect(
        makefile,
        contains('flutter test --tags bench --reporter expanded bench/'),
      );
      // make test never runs them: the core registers them only with WP_BENCH, the Dart cases are outside test/
      final cmake = read('../core/CMakeLists.txt');
      expect(cmake, contains('if(WP_BENCH)\n  add_test(NAME bench_stretch'));
      expect(
        cmake,
        contains(
          'option(WP_BENCH "Register the performance and load tests (#59)" OFF)',
        ),
      );
      expect(File('bench/library_bench_test.dart').existsSync(), isTrue);
      expect(Directory('test/bench').existsSync(), isFalse);
    });

    test('the bench job runs nightly and puts the values with machine and date into the summary', () {
      final bench = job(workflow, 'bench');
      expect(bench, contains("needs.nightly-gate.outputs.run == 'true'"));
      expect(bench, contains('run: make bench\n'));
      expect(bench, contains('core/build-bench/bench.txt'));
      expect(bench, contains('date -u'));
      expect(bench, contains('lscpu'));
      expect(bench, contains('GITHUB_STEP_SUMMARY'));
      for (final push in [
        'checks',
        'web',
        'sanitize',
        'contract',
        'network-free',
      ]) {
        expect(
          job(workflow, push),
          isNot(contains('make bench')),
          reason: push,
        );
      }
    });
  });

  group('#11/AK1, AK5 mutation tests', () {
    test('make mutants and make mutants-diff run the mutation tool', () {
      expect(makefile, isNot(contains('mutants:       ; \$(call not_yet')));
      expect(
        makefile,
        contains(
          '\nmutants:\n\tdart app/tool/mutants_run.dart --jobs \$(MUTANTS_JOBS)',
        ),
      );
      expect(
        makefile,
        contains(
          '\nmutants-diff:\n\tdart app/tool/mutants_run.dart --base \$(BASE) --jobs',
        ),
      );
      expect(makefile, contains('BASE ?= origin/main'));
      expect(makefile, contains('tool/mutants_test.dart'));
    });

    test('the mutants-diff job runs nightly against the last nightly run and reports the missed', () {
      final j = job(workflow, 'mutants-diff');
      expect(j, contains('mull-project/mull'));
      expect(j, contains('--event schedule --status success'));
      expect(j, contains("--before='3 days ago'"));
      expect(j, contains('make mutants-diff BASE='));
      expect(j, contains('local/mutants/diff/summary.txt'));
      expect(j, contains('GITHUB_STEP_SUMMARY'));
      for (final push in [
        'checks',
        'web',
        'sanitize',
        'contract',
        'network-free',
      ]) {
        expect(job(workflow, push), isNot(contains('mutants')), reason: push);
      }
    });
  });

  final nightlyJobs = [
    'macos',
    'sanitize-thread',
    'fuzz',
    'property',
    'bench',
    'mutants-diff',
  ];

  group('#13/AK3 checks on Linux on every push with a code change', () {
    test('changes reports code and web changes', () {
      final changes = job(workflow, 'changes');
      expect(changes, contains('code: \${{ steps.diff.outputs.code }}'));
      expect(changes, contains('web: \${{ steps.diff.outputs.web }}'));
      expect(
        changes,
        contains(
          r'''echo "code=$(has '^(core/|app/|tools/|Makefile$|\.github/workflows/)')"''',
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

      test('mutation tests on the diff run as a nightly job (#11)', () {
        expect(workflow, contains('# - mutants-diff: mutation tests'));
        expect(job(workflow, 'mutants-diff'), contains('needs: nightly-gate'));
      });
    },
  );

  group('#77 contract native and WASM', () {
    /// The recipe of one make target, up to the next blank line.
    String recipe(String name) {
      final target = makefile.substring(makefile.indexOf('\n$name:'));
      return target.substring(0, target.indexOf('\n\n'));
    }

    test('#77/AK1 runs on Linux on a push that changes core/, and by hand', () {
      final contract = job(workflow, 'contract');
      expect(contract, contains('runs-on: ubuntu-latest'));
      expect(contract, contains('needs: changes'));
      expect(contract, contains("needs.changes.outputs.core == 'true'"));
      expect(contract, contains("github.event_name == 'workflow_dispatch'"));
      // core/ is part of the core path filter of «changes»
      expect(
        job(workflow, 'changes'),
        contains(r'''echo "core=$(has '^(core/|'''),
      );
    });

    test('#77/AK1 first the native reference cases, then the WASM compare', () {
      final contract = job(workflow, 'contract');
      final emsdk = contract.indexOf(r'emsdk" install "$EMSDK_VERSION"');
      final native = contract.indexOf('run: make reference-native\n');
      final wasm = contract.indexOf('make test-wasm-compare\n');
      expect(emsdk, isNot(-1));
      expect(native, greaterThan(emsdk));
      expect(wasm, greaterThan(native));
      expect(contract, contains('emsdk_env.sh'));
      // make reference-native writes the dump the WASM run reads
      expect(
        recipe('reference-native'),
        contains(
          'core/build/reference_tests --dump core/build/reference_native.bin',
        ),
      );
      final compare = recipe('test-wasm-compare');
      expect(compare, contains('test -f core/build/reference_native.bin'));
      expect(compare, contains('emcmake cmake -S core -B core/build-wasm'));
      expect(compare, contains('ctest --test-dir core/build-wasm'));
      // locally the same order in one target
      expect(
        makefile,
        contains(
          '\ntest-wasm: reference-native\n'
          '\t@\$(MAKE) --no-print-directory test-wasm-compare\n',
        ),
      );
    });

    test(
      '#77/AK2 the WASM run compares with 1e-6 and checks every C API function',
      () {
        final reference = read('../core/tests/reference.cmake');
        expect(
          reference,
          contains(
            'add_test(NAME reference_tests COMMAND reference_tests --compare \${WP_REFERENCE_DUMP})',
          ),
        );
        expect(
          reference,
          contains('"\${CMAKE_CURRENT_SOURCE_DIR}/build/reference_native.bin"'),
        );
        expect(reference, contains('add_test(NAME reference_api_coverage'));
        final cases = read('../core/tests/reference_tests.cpp');
        expect(cases, contains('constexpr double kContractTolerance = 1e-6;'));
      },
    );

    test('#77 Emscripten in a fixed version, the one in docs/TESTS.md', () {
      final version = RegExp(r'EMSDK_VERSION: (\d+\.\d+\.\d+)')
          .firstMatch(workflow);
      expect(version, isNotNull);
      final tests = read('../docs/TESTS.md');
      expect(tests, contains('Emscripten ${version!.group(1)}'));
      expect(job(workflow, 'contract'), isNot(contains('install latest')));
    });
  });

  group('#79 one fixed Emscripten version in all workflows', () {
    final pages = read('../.github/workflows/pages.yml');
    final docs = read('../docs/TESTS.md');
    final workflows = {'test-quality.yml': workflow, 'pages.yml': pages};

    test(
      '#79/AK1 job web and pages.yml install EMSDK_VERSION, none latest',
      () {
        expect(emsdkProblems(workflows, docs), isEmpty);
        final web = job(workflow, 'web');
        expect(web, contains(r'emsdk" install "$EMSDK_VERSION"'));
        expect(web, contains(r'emsdk" activate "$EMSDK_VERSION"'));
        expect(job(workflow, 'fuzz'), contains(r'install "$EMSDK_VERSION"'));
        expect(
          job(workflow, 'contract'),
          contains(r'install "$EMSDK_VERSION"'),
        );
        final deploy = job(pages, 'deploy');
        expect(deploy, contains(r'emsdk" install "$EMSDK_VERSION"'));
        expect(deploy, contains(r'emsdk" activate "$EMSDK_VERSION"'));
      },
    );

    test(
      '#79/AK2 one place per workflow, same version, as in docs/TESTS.md',
      () {
        final setting = RegExp(
          r'^  EMSDK_VERSION: (\d+\.\d+\.\d+) ',
          multiLine: true,
        );
        final versions = <String>{};
        for (final text in workflows.values) {
          expect(RegExp('EMSDK_VERSION:').allMatches(text), hasLength(1));
          // workflow-wide env, not inside a job
          versions.add(setting.firstMatch(text)!.group(1)!);
        }
        expect(versions, hasLength(1));
        expect(docs, contains('Emscripten ${versions.single}'));
      },
    );

    test('#79/AK3 the check fails on latest or a differing version', () {
      Map<String, String> variant(String name, String text) => {
        ...workflows,
        name: text,
      };
      final latestPages = pages.replaceFirst(
        r'install "$EMSDK_VERSION"',
        'install latest',
      );
      expect(
        emsdkProblems(variant('pages.yml', latestPages), docs),
        isNotEmpty,
      );
      final latestWeb = workflow.replaceFirst(
        r'activate "$EMSDK_VERSION"',
        'activate latest',
      );
      expect(
        emsdkProblems(variant('test-quality.yml', latestWeb), docs),
        isNotEmpty,
      );
      final literal = workflow.replaceFirst(
        r'install "$EMSDK_VERSION"',
        'install 7.0.0',
      );
      expect(
        emsdkProblems(variant('test-quality.yml', literal), docs),
        isNotEmpty,
      );
      final other = pages.replaceFirst(
        'EMSDK_VERSION: 7.0.0',
        'EMSDK_VERSION: 6.0.0',
      );
      expect(emsdkProblems(variant('pages.yml', other), docs), isNotEmpty);
      final twice = pages.replaceFirst(
        '    runs-on: ubuntu-latest\n',
        '    runs-on: ubuntu-latest\n    env:\n      EMSDK_VERSION: 7.0.0\n',
      );
      expect(emsdkProblems(variant('pages.yml', twice), docs), isNotEmpty);
      final oldDocs = docs.replaceFirst('Emscripten 7.0.0', 'Emscripten 6.0.0');
      expect(emsdkProblems(workflows, oldDocs), isNotEmpty);
    });
  });

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
      // overview page of #12 as an artifact, its summary in the run summary
      expect(checks, contains('name: test-quality-report'));
      expect(checks, contains('local/test-quality/report/'));
      expect(checks, contains('make -s report'));
      expect(checks, contains('cat report-summary.md'));
      expect(checks, contains('issues: read'));
      expect(checks, contains(r'GH_TOKEN: ${{ github.token }}'));
    });
  });

  group('#64 actionlint in make lint', () {
    test('#64/AK1 fixed version with checksum in the workflow, documented', () {
      final version = RegExp(r'ACTIONLINT_VERSION: (\d+\.\d+\.\d+)')
          .firstMatch(workflow);
      expect(version, isNotNull);
      expect(workflow, matches(RegExp(r'ACTIONLINT_SHA256: [0-9a-f]{64}')));
      final tests = read('../docs/TESTS.md');
      expect(tests, contains('`actionlint` ${version!.group(1)}'));
      expect(tests, contains('brew install actionlint'));
    });

    test('#64/AK2 make lint checks every file in .github/workflows/', () {
      expect(
        makefile,
        contains('\nlint: lint-dart lint-core lint-workflows\n'),
      );
      expect(
        makefile,
        contains(
          '\nlint-workflows:\n\t"\$(ACTIONLINT)" '
          r'$(wildcard .github/workflows/*.yml .github/workflows/*.yaml)',
        ),
      );
    });

    test(
      '#64/AK3 the Linux job checks installs actionlint and runs make lint',
      () {
        final checks = job(workflow, 'checks');
        expect(checks, contains('runs-on: ubuntu-latest'));
        expect(checks, contains(r'sha256sum -c'));
        expect(
          checks,
          contains(r'echo "ACTIONLINT=$RUNNER_TEMP/actionlint/actionlint"'),
        );
        // installed before make lint runs
        expect(
          checks.indexOf('ACTIONLINT='),
          lessThan(checks.indexOf('run: make lint\n')),
        );
      },
    );

    test('#64/AK4 a deliberate error in a workflow is reported', () {
      final actionlint = Platform.environment['ACTIONLINT'] ?? 'actionlint';
      final ProcessResult version;
      try {
        version = Process.runSync(actionlint, ['--version']);
      } on ProcessException {
        markTestSkipped('actionlint not installed');
        return;
      }
      expect(version.exitCode, 0);
      final dir = Directory.systemTemp.createTempSync('wp_actionlint_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final good = File('${dir.path}/good.yml')
        ..writeAsStringSync(
          'on: push\njobs:\n  x:\n    runs-on: ubuntu-latest\n'
          '    steps:\n      - run: echo "\${{ github.sha }}"\n',
        );
      final bad = File('${dir.path}/bad.yml')
        ..writeAsStringSync(
          'on: push\njobs:\n  x:\n    runs-on: ubuntu-latest\n'
          '    steps:\n      - run: echo "\${{ github.no_such_property }}"\n',
        );
      final ok = Process.runSync(actionlint, [good.path]);
      expect(ok.exitCode, 0, reason: '${ok.stdout}');
      final found = Process.runSync(actionlint, [bad.path]);
      expect(found.exitCode, isNot(0));
      expect('${found.stdout}', contains('no_such_property'));
    });
  });
}
