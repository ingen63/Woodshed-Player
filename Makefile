# Test and hygiene targets for the Flutter app (app/) and the C++ audio core (core/), #7.
# Strategy and test matrix: docs/TESTS.md. Developer tools: Flutter, CMake, Homebrew llvm
# (clang-format, clang-tidy). core/third_party/ is never formatted, linted or read.
.PHONY: help test test-core test-wasm test-app test-hook test-tools format format-check lint lint-dart \
        lint-core coverage coverage-run coverage-core coverage-app coverage-diff mutants fuzz report \
        sanitize network-free

SHELL := /bin/bash
# A failing build must not be hidden by `| tail` (GNU Make 3.81 on macOS has no .SHELLFLAGS).
PIPEFAIL := set -o pipefail;

LLVM_BIN     ?= $(shell brew --prefix llvm 2>/dev/null)/bin
CLANG_FORMAT ?= $(shell command -v clang-format 2>/dev/null || echo $(LLVM_BIN)/clang-format)
CLANG_TIDY   ?= $(shell command -v clang-tidy 2>/dev/null || echo $(LLVM_BIN)/clang-tidy)
RUN_TIDY     ?= $(shell command -v run-clang-tidy 2>/dev/null || echo $(LLVM_BIN)/run-clang-tidy)
# Coverage (#8): llvm-cov and llvm-profdata must match the compiler, on macOS the Xcode ones.
LLVM_COV      ?= $(shell xcrun --find llvm-cov 2>/dev/null || command -v llvm-cov 2>/dev/null || echo $(LLVM_BIN)/llvm-cov)
LLVM_PROFDATA ?= $(shell xcrun --find llvm-profdata 2>/dev/null || command -v llvm-profdata 2>/dev/null || echo $(LLVM_BIN)/llvm-profdata)
BASE ?= origin/main

# Our own sources from git, tracked and new (not ignored); none has a space in its path.
# Generated l10n files are excluded.
LS_FILES   = git ls-files --cached --others --exclude-standard
DART_FILES = $(LS_FILES) -- 'app/*.dart' | grep -v '^app/lib/l10n/app_localizations'
CPP_FILES  = $(LS_FILES) -- core | grep -v '^core/third_party/' | grep -E '\.(c|cc|cpp|h|hpp|mm)$$'

help:
	@echo "make test           core (ctest), app (flutter test) and the hook tests"
	@echo "make test-wasm      core tests under Node.js (Emscripten)"
	@echo "make format         dart format and clang-format"
	@echo "make format-check   fails if a file is not formatted"
	@echo "make lint           flutter analyze (strict), C++ warnings as errors, clang-tidy"
	@echo "make coverage       all tests with line coverage, checked per part against tools/coverage-min"
	@echo "make coverage-diff  coverage of the lines changed since BASE (default origin/main), a hint"

# ---- Tests ----
test: test-core test-app test-tools

test-core:
	cmake -S core -B core/build -DCMAKE_BUILD_TYPE=Release >/dev/null
	$(PIPEFAIL) cmake --build core/build -j 8 2>&1 | tail -20
	ctest --test-dir core/build --output-on-failure

test-wasm:
	emcmake cmake -S core -B core/build-wasm -DCMAKE_BUILD_TYPE=Release >/dev/null
	$(PIPEFAIL) cmake --build core/build-wasm -j 8 2>&1 | tail -20
	ctest --test-dir core/build-wasm --output-on-failure

test-app:
	cd app && flutter test --reporter failures-only

# Tests of the tools in staged git repositories with fake tools: the hook after a commit (#7/AK7),
# coverage check and diff, pre-push hook (#8/AK6)
TOOL_TESTS = tool/after_commit_hook_test.dart tool/coverage_test.dart tool/pre_push_hook_test.dart
test-tools:
	cd app && flutter test --reporter failures-only $(TOOL_TESTS)
test-hook: test-tools

# ---- Formatting (#7/AK2) ----
format:
	$(DART_FILES) | xargs dart format -o write
	$(CPP_FILES) | xargs "$(CLANG_FORMAT)" -i

format-check:
	$(DART_FILES) | xargs dart format -o none --set-exit-if-changed
	$(CPP_FILES) | xargs "$(CLANG_FORMAT)" --dry-run --Werror

# ---- Warnings are errors (#7/AK3) ----
lint: lint-dart lint-core

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
	LLVM_PROFILE_FILE="$(CURDIR)/$(COV_DIR)/prof/%p-%m.profraw" ctest --test-dir $(COV_DIR) --output-on-failure
	"$(LLVM_PROFDATA)" merge -sparse $(COV_DIR)/prof/*.profraw -o $(COV_DIR)/wp.profdata
	objs=$$(find $(COV_DIR) -maxdepth 1 -type f \( -name '*_tests' -o -name 'libwp_core.*' \) | sort | sed 's/^/-object=/'); \
	  "$(LLVM_COV)" export -format=lcov -instr-profile=$(COV_DIR)/wp.profdata $$objs \
	  -ignore-filename-regex='/(third_party|tests)/' > $(COV_DIR)/lcov.info 2>$(COV_DIR)/llvm-cov.log

coverage-app:
	cd app && flutter test --coverage --reporter failures-only
	cd app && flutter test --reporter failures-only $(TOOL_TESTS)

# #8/AK3: a hint, not a gate
coverage-diff: coverage-run
	dart app/tool/coverage_diff.dart --base $(BASE)

# ---- Not set up yet ----
define not_yet
	@echo "make $@: noch nicht eingerichtet (#$(1))"; exit 1
endef

mutants:       ; $(call not_yet,11)
fuzz:          ; $(call not_yet,10)
report:        ; $(call not_yet,12)
sanitize:      ; $(call not_yet,57)
network-free:  ; $(call not_yet,58)
