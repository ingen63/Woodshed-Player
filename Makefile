# Test and hygiene targets for the Flutter app (app/) and the C++ audio core (core/), #7.
# Strategy and test matrix: docs/TESTS.md. Developer tools: Flutter, CMake, Homebrew llvm
# (clang-format, clang-tidy), actionlint. core/third_party/ is never formatted, linted or read.
.PHONY: help test test-core test-wasm reference-native test-wasm-compare test-app test-hook test-tools format format-check lint lint-dart \
        lint-core lint-workflows coverage coverage-run coverage-core coverage-app coverage-diff mutants \
        mutants-diff fuzz fuzz-wasm fuzz-wasm-build fuzz-wasm-findings report sanitize sanitize-thread test-core-debug network-free fuzz fuzz-build property \
        test-ui test-ios test-web test-web-start smoke-app pseudo-l10n bench clean-tmp

SHELL := /bin/bash
# A failing build must not be hidden by `| tail` (GNU Make 3.81 on macOS has no .SHELLFLAGS).
PIPEFAIL := set -o pipefail;

LLVM_BIN     ?= $(shell brew --prefix llvm 2>/dev/null)/bin
CLANG_FORMAT ?= $(shell command -v clang-format 2>/dev/null || echo $(LLVM_BIN)/clang-format)
CLANG_TIDY   ?= $(shell command -v clang-tidy 2>/dev/null || echo $(LLVM_BIN)/clang-tidy)
RUN_TIDY     ?= $(shell command -v run-clang-tidy 2>/dev/null || echo $(LLVM_BIN)/run-clang-tidy)
ACTIONLINT   ?= actionlint
# Coverage (#8): llvm-cov and llvm-profdata must match the compiler, on macOS the Xcode ones.
LLVM_COV      ?= $(shell xcrun --find llvm-cov 2>/dev/null || command -v llvm-cov 2>/dev/null || echo $(LLVM_BIN)/llvm-cov)
LLVM_PROFDATA ?= $(shell xcrun --find llvm-profdata 2>/dev/null || command -v llvm-profdata 2>/dev/null || echo $(LLVM_BIN)/llvm-profdata)
BASE ?= origin/main
# Test results for the overview page (#12): JUnit from ctest, the JSON reporter of flutter test
# (converted to JUnit by make report). Not checked in (local/).
QA_DIR   = $(CURDIR)/local/test-quality
JUNIT    = --output-junit "$(QA_DIR)/junit/core.xml"
FLUTTER_JSON = "--file-reporter=json:$(QA_DIR)/flutter/$(1).json"
QA_DIRS  = mkdir -p "$(QA_DIR)/junit" "$(QA_DIR)/flutter"

# Our own sources from git, tracked and new (not ignored); none has a space in its path.
# Generated l10n files are excluded.
LS_FILES   = git ls-files --cached --others --exclude-standard
DART_FILES = $(LS_FILES) -- 'app/*.dart' | grep -v '^app/lib/l10n/app_localizations'
CPP_FILES  = $(LS_FILES) -- core | grep -v '^core/third_party/' | grep -E '\.(c|cc|cpp|h|hpp|mm)$$'

help:
	@echo "make test           core (ctest), app (flutter test) and the hook tests"
	@echo "make clean-tmp      remove what aborted test runs left in the temp directory (unchanged for 60 min)"
	@echo "make test-wasm      core tests under Node.js (Emscripten)"
	@echo "make test-core-debug core tests in a Debug build (same cases and tolerances as Release)"
	@echo "make sanitize       core tests with AddressSanitizer and UndefinedBehaviorSanitizer"
	@echo "make sanitize-thread core tests with ThreadSanitizer"
	@echo "make fuzz           libFuzzer with ASan/UBSan, FUZZ_SECONDS per target (default 60)"
	@echo "make fuzz-wasm      fuzz regressions and corpus (also make fuzz's new files) against the WASM core"
	@echo "make fuzz-wasm-findings the findings of make fuzz against the WASM core, one result per input"
	@echo "make property      Dart random tests, PROPERTY_CASES cases, PROPERTY_SEED (printed on failure)"
	@echo "make format         dart format and clang-format"
	@echo "make format-check   fails if a file is not formatted"
	@echo "make lint           flutter analyze (strict), C++ warnings as errors, clang-tidy, actionlint"
	@echo "make coverage       all tests with line coverage, checked per part against tools/coverage-min"
	@echo "make coverage-diff  coverage of the lines changed since BASE (default origin/main), a hint"
	@echo "make network-free   no network code outside the provider modules, blocked packages, core, CSP"
	@echo "make test-ui        UI tests with the real core on macOS (integration_test)"
	@echo "make test-ios       smoke test with the real core on an iOS simulator (WP_IOS_DEVICE, boots it if needed)"
	@echo "make test-web       web tests in Chrome: OPFS and the WASM core (needs Emscripten)"
	@echo "make test-web-start the built web app starts without failed requests or console errors"
	@echo "make smoke-app      builds the macOS app (release) and runs its smoke test"
	@echo "make pseudo-l10n    regenerates the pseudo language of the UI tests after an ARB change"
	@echo "make bench          performance and load tests of core and library (nightly, not in make test)"
	@echo "make mutants        mutation tests of core (Mull) and Dart logic, results in local/mutants/full/"
	@echo "make mutants-diff   mutation tests of the lines changed since BASE (default origin/main)"
	@echo "make report         overview page of the test quality: local/test-quality/report/index.html"

# ---- Tests ----
test: clean-tmp test-core test-app test-tools

# Removes what aborted runs left in $TMPDIR (flutter_tools.* of about 240 MB each, wp_* test
# directories), unchanged for 60 minutes; see tools/clean-tmp.sh.
clean-tmp:
	@tools/clean-tmp.sh

test-core:
	cmake -S core -B core/build -DCMAKE_BUILD_TYPE=Release >/dev/null
	$(PIPEFAIL) cmake --build core/build -j 8 2>&1 | tail -20
	@$(QA_DIRS)
	ctest --test-dir core/build --output-on-failure $(JUNIT)

# #57/AK3: the same tests in Debug (asserts on, no optimisation), same tolerances as Release.
# Only time limits are skipped there (core/tests/test_timing.hpp).
test-core-debug:
	cmake -S core -B core/build-debug -DCMAKE_BUILD_TYPE=Debug >/dev/null
	$(PIPEFAIL) cmake --build core/build-debug -j 8 2>&1 | tail -20
	ctest --test-dir core/build-debug --output-on-failure -j 4

# #9/AK7: the WASM reference cases compare their samples with the native run
# (core/build/reference_native.bin, tolerance 1e-6), so that one is rendered first. The workflow
# (#77) runs the two halves as separate steps: reference-native, then test-wasm-compare.
test-wasm: reference-native
	@$(MAKE) --no-print-directory test-wasm-compare

reference-native:
	cmake -S core -B core/build -DCMAKE_BUILD_TYPE=Release >/dev/null
	$(PIPEFAIL) cmake --build core/build -j 8 --target reference_tests 2>&1 | tail -20
	$(PIPEFAIL) core/build/reference_tests --dump core/build/reference_native.bin | tail -2

test-wasm-compare:
	@test -f core/build/reference_native.bin || { echo "core/build/reference_native.bin missing: run make reference-native first"; exit 1; }
	emcmake cmake -S core -B core/build-wasm -DCMAKE_BUILD_TYPE=Release >/dev/null
	$(PIPEFAIL) cmake --build core/build-wasm -j 8 2>&1 | tail -20
	ctest --test-dir core/build-wasm --output-on-failure

test-app:
	@$(QA_DIRS)
	cd app && flutter test --reporter failures-only $(call FLUTTER_JSON,app)

# Tests of the tools in staged git repositories with fake tools: the hook after a commit (#7/AK7),
# coverage check and diff, pre-push hook (#8/AK6)
TOOL_TESTS = tool/after_commit_hook_test.dart tool/coverage_test.dart tool/pre_push_hook_test.dart \
             tool/network_free_test.dart tool/mutants_test.dart tool/report/report_test.dart \
             tool/web_start_check_test.dart tool/clean_tmp_test.dart
test-tools:
	@$(QA_DIRS)
	cd app && flutter test --reporter failures-only $(call FLUTTER_JSON,tools) $(TOOL_TESTS)
test-hook: test-tools

# ---- Formatting (#7/AK2) ----
format:
	$(DART_FILES) | xargs dart format -o write
	$(CPP_FILES) | xargs "$(CLANG_FORMAT)" -i

format-check:
	$(DART_FILES) | xargs dart format -o none --set-exit-if-changed
	$(CPP_FILES) | xargs "$(CLANG_FORMAT)" --dry-run --Werror

# ---- Warnings are errors (#7/AK3) ----
lint: lint-dart lint-core lint-workflows

lint-dart:
	cd app && flutter analyze --no-pub
	cd app/packages/wp_core && flutter analyze --no-pub

# The build uses -Wall -Wextra -Werror for our own targets (core/CMakeLists.txt) and writes
# compile_commands.json for clang-tidy (core/.clang-tidy).
lint-core:
	cmake -S core -B core/build -DCMAKE_BUILD_TYPE=Release >/dev/null
	$(PIPEFAIL) cmake --build core/build -j 8 2>&1 | tail -20
	"$(RUN_TIDY)" -p core/build -quiet -config-file core/.clang-tidy -clang-tidy-binary "$(CLANG_TIDY)" \
	  'core/(src|tests|tools)/.*\.(cpp|mm)$$' 2>&1 | { grep -E 'error:|warning:' || true; }; \
	  exit $${PIPESTATUS[0]}

# Every workflow in .github/workflows/ (#64); actionlint runs shellcheck on the run: scripts when it is
# installed. Any finding fails.
lint-workflows:
	"$(ACTIONLINT)" $(wildcard .github/workflows/*.yml .github/workflows/*.yaml)

# ---- Coverage (#8), strategy in docs/TESTS.md ----
coverage: coverage-run
	dart app/tool/coverage_check.dart

# All tests with coverage data: app/coverage/lcov.info and core/build-cov/lcov.info.
coverage-run: coverage-core coverage-app

# Instrumented core build in core/build-cov (Release, like the normal tests). Every test program
# and the shared library (C API) count; only our own sources end up in the report.
COV_DIR = core/build-cov
coverage-core:
	cmake -S core -B $(COV_DIR) -DCMAKE_BUILD_TYPE=Release -DWP_COVERAGE=ON >/dev/null
	$(PIPEFAIL) cmake --build $(COV_DIR) -j 8 2>&1 | tail -20
	mkdir -p $(COV_DIR)/prof && find $(COV_DIR)/prof -name '*.profraw' -delete
	@$(QA_DIRS)
	LLVM_PROFILE_FILE="$(CURDIR)/$(COV_DIR)/prof/%p-%m.profraw" ctest --test-dir $(COV_DIR) --output-on-failure $(JUNIT)
	"$(LLVM_PROFDATA)" merge -sparse $(COV_DIR)/prof/*.profraw -o $(COV_DIR)/wp.profdata
	objs=$$(find $(COV_DIR) -maxdepth 1 -type f \( -name '*_tests' -o -name 'libwp_core.*' \) | sort | sed 's/^/-object=/'); \
	  "$(LLVM_COV)" export -format=lcov -instr-profile=$(COV_DIR)/wp.profdata $$objs \
	  -ignore-filename-regex='/(third_party|tests)/' > $(COV_DIR)/lcov.info 2>$(COV_DIR)/llvm-cov.log

coverage-app:
	@$(QA_DIRS)
	cd app && flutter test --coverage --reporter failures-only $(call FLUTTER_JSON,app)
	cd app && flutter test --reporter failures-only $(call FLUTTER_JSON,tools) $(TOOL_TESTS)

# #8/AK3: a hint, not a gate
coverage-diff: coverage-run
	dart app/tool/coverage_diff.dart --base $(BASE)

# ---- Sanitizers (#57), docs/TESTS.md ----
# Separate Debug builds, core/build stays untouched. WP_SANITIZE instruments every target (also
# third_party) and sets the sanitizer options for ctest; any finding fails its test. A
# self-test with a deliberate bug per sanitizer proves that. Fuzz targets (#10, make fuzz) build in
# the same way with -DWP_SANITIZE=address,undefined.
sanitize:
	cmake -S core -B core/build-asan -DCMAKE_BUILD_TYPE=Debug -DWP_SANITIZE=address,undefined >/dev/null
	$(PIPEFAIL) cmake --build core/build-asan -j 8 2>&1 | tail -20
	ctest --test-dir core/build-asan --output-on-failure -j 4

# #57/AK2: ThreadSanitizer; player_tests and engine_tests control playback, seek, tempo and loop
# from other threads while rendering.
sanitize-thread:
	cmake -S core -B core/build-tsan -DCMAKE_BUILD_TYPE=Debug -DWP_SANITIZE=thread >/dev/null
	$(PIPEFAIL) cmake --build core/build-tsan -j 8 2>&1 | tail -20
	ctest --test-dir core/build-tsan --output-on-failure -j 4

# ---- Fuzzing (#10), docs/TESTS.md ----
# libFuzzer needs clang with libFuzzer (Homebrew llvm; Apple Clang has none, on Linux the system
# clang). Build core/build-fuzz with ASan and UBSan (#57) and coverage instrumentation for all code;
# each target starts from the checked-in regressions and start corpus (core/tests/fuzz/) and keeps
# new corpus files in core/build-fuzz/corpus/<target> (not checked in). A finding (crash, sanitizer
# report, broken invariant, timeout, out of memory) stops the run and fails; the input is saved as
# core/build-fuzz/artifacts/<target>/crash-* (or leak-, timeout-, oom-). Check it into
# core/tests/fuzz/regressions/<target>/ once the bug is fixed.
FUZZ_SECONDS ?= 60
FUZZ_TARGETS ?= decoder capi
FUZZ_DIR      = core/build-fuzz
FUZZ_CC      ?= $(if $(filter Darwin,$(shell uname -s)),$(LLVM_BIN)/clang,clang)
FUZZ_CXX     ?= $(if $(filter Darwin,$(shell uname -s)),$(LLVM_BIN)/clang++,clang++)
# Options of the sanitizers like in ctest (core/CMakeLists.txt); a finding aborts.
FUZZ_ENV = UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=1:suppressions='$(CURDIR)/core/tests/sanitizer/ubsan.supp'" \
           ASAN_OPTIONS="halt_on_error=1:allocator_may_return_null=1$(if $(filter Darwin,$(shell uname -s)),,:detect_leaks=1)" \
           LSAN_OPTIONS="suppressions='$(CURDIR)/core/tests/sanitizer/lsan.supp'"

# #105/AK3: on a finding, print the whole report (sanitizer report with stack, UBSan runtime error,
# broken invariant, libFuzzer timeout or out of memory) from its first line on, at most 300 lines;
# without such a line the last 40 lines of the log.
FUZZ_REPORT = awk 'f || /==ERROR:|ERROR: libFuzzer|runtime error:|FUZZ INVARIANT FAILED/ { f = 1; \
  if (++n <= 300) print } END { exit !f }' "$(1)" || tail -40 "$(1)"

fuzz-build:
	cmake -S core -B $(FUZZ_DIR) -DCMAKE_BUILD_TYPE=RelWithDebInfo -DWP_SANITIZE=address,undefined \
	  -DWP_FUZZ=ON -DCMAKE_C_COMPILER="$(FUZZ_CC)" -DCMAKE_CXX_COMPILER="$(FUZZ_CXX)" >/dev/null
	$(PIPEFAIL) cmake --build $(FUZZ_DIR) -j 8 --target $(addprefix fuzz_,$(FUZZ_TARGETS)) 2>&1 | tail -20

fuzz: fuzz-build
	@for t in $(FUZZ_TARGETS); do \
	  mkdir -p $(FUZZ_DIR)/corpus/$$t $(FUZZ_DIR)/artifacts/$$t; \
	  echo "fuzz_$$t: $(FUZZ_SECONDS) s"; \
	  $(FUZZ_ENV) $(FUZZ_DIR)/fuzz_$$t $(FUZZ_DIR)/corpus/$$t core/tests/fuzz/regressions/$$t \
	    core/tests/fuzz/corpus/$$t -max_total_time=$(FUZZ_SECONDS) -timeout=10 -rss_limit_mb=2048 \
	    -max_len=65536 -print_final_stats=1 -artifact_prefix=$(FUZZ_DIR)/artifacts/$$t/ \
	    > $(FUZZ_DIR)/fuzz_$$t.log 2>&1; rc=$$?; \
	  grep -E '^(stat::number_of_executed_units|stat::new_units_added|INFO: seed corpus)' \
	    $(FUZZ_DIR)/fuzz_$$t.log; \
	  if [ $$rc -ne 0 ]; then $(call FUZZ_REPORT,$(FUZZ_DIR)/fuzz_$$t.log); \
	    echo "fuzz_$$t: finding, input in $(FUZZ_DIR)/artifacts/$$t/"; exit 1; fi; \
	done

# #67: the same inputs against the WASM core under Node.js (Emscripten): regressions, start corpus
# and, if present, the corpus that make fuzz grew in core/build-fuzz/corpus/<target> (nightly in
# the fuzz job). make test-wasm already replays regressions and start corpus (ctest
# fuzz_<target>_replay); a finding (abort, trap) fails and names the input it was running.
FUZZ_WASM_DIR = core/build-wasm
fuzz-wasm-build:
	emcmake cmake -S core -B $(FUZZ_WASM_DIR) -DCMAKE_BUILD_TYPE=Release >/dev/null
	$(PIPEFAIL) cmake --build $(FUZZ_WASM_DIR) -j 8 \
	  --target $(addsuffix _replay,$(addprefix fuzz_,$(FUZZ_TARGETS))) 2>&1 | tail -20

fuzz-wasm: fuzz-wasm-build
	@for t in $(FUZZ_TARGETS); do \
	  set -- "$(CURDIR)/core/tests/fuzz/regressions/$$t" "$(CURDIR)/core/tests/fuzz/corpus/$$t"; \
	  if [ -d "$(FUZZ_DIR)/corpus/$$t" ]; then set -- "$$@" "$(CURDIR)/$(FUZZ_DIR)/corpus/$$t"; fi; \
	  log="$(FUZZ_WASM_DIR)/fuzz_$${t}_replay.log"; \
	  (cd $(FUZZ_WASM_DIR) && node "fuzz_$${t}_replay.js" "$$@") > "$$log" 2>&1; rc=$$?; \
	  echo "fuzz_$$t (WASM): $$(tail -1 "$$log")"; \
	  if [ $$rc -ne 0 ]; then tail -20 "$$log"; \
	    echo "fuzz_$$t (WASM): finding, the last replayed input above is the cause"; exit 1; fi; \
	done

# #88: when make fuzz has a finding, replay each input of core/build-fuzz/artifacts/<target>/ on its
# own against the WASM core, so the nightly fuzz job shows whether the browser core fails as well.
# One line per input in the log and in FUZZ_FINDINGS_REPORT (job artifact); a replay that runs
# longer than FUZZ_WASM_TIMEOUT seconds counts as a finding. Only reports, never fails because of a
# WASM result: the job stays red through the native finding.
FUZZ_WASM_TIMEOUT    ?= 60
FUZZ_FINDINGS_REPORT  = $(FUZZ_WASM_DIR)/fuzz_findings_wasm.txt
FUZZ_TIMEOUT_CMD      = $(shell command -v timeout || command -v gtimeout)
fuzz-wasm-findings: fuzz-wasm-build
	@: > "$(FUZZ_FINDINGS_REPORT)"; \
	for t in $(FUZZ_TARGETS); do \
	  for f in $(FUZZ_DIR)/artifacts/$$t/*; do \
	    [ -f "$$f" ] || continue; \
	    name=$$(basename "$$f"); log="$(FUZZ_WASM_DIR)/fuzz_$${t}_finding_$$name.log"; \
	    (cd $(FUZZ_WASM_DIR) && $(if $(FUZZ_TIMEOUT_CMD),"$(FUZZ_TIMEOUT_CMD)" $(FUZZ_WASM_TIMEOUT)) \
	      node "fuzz_$${t}_replay.js" "$(CURDIR)/$$f") > "$$log" 2>&1; rc=$$?; \
	    if [ $$rc -eq 0 ]; then result="no"; \
	    elif [ $$rc -eq 124 ]; then result="yes (timeout after $(FUZZ_WASM_TIMEOUT) s)"; \
	    else result="yes (exit $$rc)"; fi; \
	    echo "fuzz_$$t: $$name: finding under WASM: $$result" | tee -a "$(FUZZ_FINDINGS_REPORT)"; \
	    if [ $$rc -ne 0 ]; then tail -5 "$$log"; fi; \
	  done; \
	done; \
	if [ ! -s "$(FUZZ_FINDINGS_REPORT)" ]; then \
	  echo "no inputs in $(FUZZ_DIR)/artifacts/" | tee "$(FUZZ_FINDINGS_REPORT)"; fi

# ---- Random tests (#10), docs/TESTS.md ----
# The Dart random tests (app/test/property/) also run in make test with 100 cases and the fixed seed.
# Here with more cases or another seed; a failure names the case seed to check in as a regression
# (app/test/property/regressions.json).
PROPERTY_CASES ?= 100
PROPERTY_SEED  ?= 20261119
property:
	cd app && WP_PROPERTY_CASES=$(PROPERTY_CASES) WP_PROPERTY_SEED=$(PROPERTY_SEED) \
	  flutter test --reporter failures-only test/property/

# ---- Network freedom (#58), docs/TESTS.md ----
# The check (app/tool/network_free.dart, needs the app's packages) with its own tests, and the #37 test
# that the app without an account creates no HttpClient. Network code belongs in app/lib/sync/providers/.
network-free:
	cd app && flutter pub get >/dev/null
	dart app/tool/network_free.dart
	cd app && flutter test --reporter failures-only tool/network_free_test.dart test/sync_app_test.dart

# ---- UI tests, web tests and the app smoke test (#13), docs/TESTS.md ----
# UI tests with the real core: start, import, play/pause, loop, tempo, shortcuts, pseudo language.
# Without an audio device: make test-ui WP_AUDIO_BACKEND=null (the core's null device).
test-ui: clean-tmp
	cd app && $(if $(WP_AUDIO_BACKEND),WP_AUDIO_BACKEND=$(WP_AUDIO_BACKEND) )flutter test integration_test -d macos

# #99/AK2: the smoke test with the real core on an iOS simulator (tools/ios_sim_test.sh). WP_IOS_DEVICE
# picks the simulator (name or UDID, default a booted or the first iPhone); one it boots is shut down
# again. Without an audio device: make test-ios WP_AUDIO_BACKEND=null, as on macOS.
test-ios:
	$(if $(WP_AUDIO_BACKEND),WP_AUDIO_BACKEND=$(WP_AUDIO_BACKEND) )$(if $(WP_IOS_DEVICE),WP_IOS_DEVICE="$(WP_IOS_DEVICE)" )tools/ios_sim_test.sh

# Web code in a real browser (#13/AK4): the WASM core next to the test page (test/web/wp_core/, not
# checked in), Chrome with autoplay allowed (the AudioContext needs no click then).
# #112: a run that hangs (e.g. Chrome never loads the test page) stops after WEB_TEST_LIMIT seconds with
# a message instead of blocking the CI job until its timeout. perl, because macOS has no `timeout`.
WEB_TEST_LIMIT ?= 300
test-web:
	app/tool/build_web_core.sh
	mkdir -p app/test/web/wp_core && cp app/web/wp_core/* app/test/web/wp_core/
	cd app && CHROME_EXECUTABLE="$(CURDIR)/tools/chrome_autoplay.sh" \
	  perl -e '$$SIG{ALRM} = sub { kill "KILL", -$$$$; }; setpgrp; alarm shift; system @ARGV; exit($$? >> 8 || ($$? ? 1 : 0))' \
	  $(WEB_TEST_LIMIT) flutter test --platform chrome --reporter failures-only test/web/ \
	  || { s=$$?; [ $$s -eq 137 ] && echo "test-web: Chrome tests did not finish within $(WEB_TEST_LIMIT) s (#112)" >&2; exit $$s; }
	$(MAKE) --no-print-directory test-web-start

# #72/AK3: the built web app starts in headless Chrome without failed requests, foreign hosts or
# console errors (app/tool/web_start_check.dart). #82: a second start with CJK and emoji titles in the
# library, whose fallback fonts are answered without a request. Needs the WASM core in app/web/wp_core/.
# The only web build of the CI job web (#83), so it stays a release build.
test-web-start:
	cd app && $(PIPEFAIL) flutter build web --release --no-wasm-dry-run 2>&1 | tail -1
	cd app && dart run tool/stamp_sw.dart build/web
	cd app && dart tool/web_start_check.dart build/web

# #13/AK5: smoke test of the built app (release): start, play a generated file, exit code 0.
smoke-app:
	cd app && $(PIPEFAIL) flutter build macos --release 2>&1 | tail -2
	tools/smoke_app.sh

# #13/AK7: the pseudo language follows the English texts (checked by test/pseudo_l10n_test.dart).
pseudo-l10n:
	cd app && flutter gen-l10n && dart run tool/pseudo_l10n.dart

# ---- Performance and load tests (#59), docs/TESTS.md ----
# Nightly in the workflow, not in make test: the core registers its cases only with -DWP_BENCH=ON
# (label «bench»: time stretch per buffer, 60-minute file, memory limit, reservation fallback), the
# Dart cases live in app/bench/ (tag «bench»), outside test/. Release build. The measured values (lines «BENCH …») go to
# $(BENCH_LOG) as well; a limit exceeded fails.
BENCH_LOG ?= core/build-bench/bench.txt
bench:
	cmake -S core -B core/build-bench -DCMAKE_BUILD_TYPE=Release -DWP_BENCH=ON >/dev/null
	$(PIPEFAIL) cmake --build core/build-bench -j 8 --target bench_tests 2>&1 | tail -20
	$(PIPEFAIL) ctest --test-dir core/build-bench -L bench -V 2>&1 \
	  | grep -E 'BENCH|FAILED|memory limit|load under|tests passed|tests failed|\*\*\*' \
	  | sed -E 's/^[0-9]+: //' | tee $(BENCH_LOG)
	$(PIPEFAIL) cd app && flutter test --tags bench --reporter expanded bench/ 2>&1 \
	  | grep -E 'BENCH|Expected|Actual|Reason|All tests passed|Some tests failed' \
	  | tee -a ../$(BENCH_LOG)

# ---- Mutation tests (#11), docs/TESTS.md ----
# C++ core with Mull (core/build-mutants, Homebrew llvm; MULL_DIR, default ~/.local/opt/mull, or
# MULL_RUNNER and MULL_PLUGIN), Dart logic of app/lib with an own mutator (app/tool/mutants.dart).
# MUTANTS_JOBS mutants run at the same time (default 4); each core test process ends above 1024 MiB,
# each Dart test run (flutter and its children) above 4096 MiB; time limit per mutant: core
# max(10 x baseline, 20 s), Dart max(3 x baseline, 60 s). Results (summary.txt, missed.txt,
# results.json) in local/mutants/full/ and local/mutants/diff/, not checked in. Exit code 3 if a
# mutant is not detected and not excluded with a reason (tools/mutants-exclude.txt).
# MUTANTS_ARGS e.g. "--part core", "--file engine", "--fresh" (forget the Mull cache).
MUTANTS_JOBS ?= 4
MUTANTS_ARGS ?=
mutants: clean-tmp
	dart app/tool/mutants_run.dart --jobs $(MUTANTS_JOBS) $(MUTANTS_ARGS)

mutants-diff: clean-tmp
	dart app/tool/mutants_run.dart --base $(BASE) --jobs $(MUTANTS_JOBS) $(MUTANTS_ARGS)

# ---- Overview page of the test quality (#12), docs/TESTS.md ----
# Reads what is there (JUnit of make test, coverage of make coverage-run, local/mutants/, issues via
# gh) and writes local/test-quality/report/index.html (offline, not checked in); missing data is
# shown as «keine Daten». REPORT_ARGS e.g. "--out build/report", "--no-gh", "--summary".
REPORT_ARGS ?=
report:
	dart app/tool/report/report_run.dart $(REPORT_ARGS)
