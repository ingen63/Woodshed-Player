# Test and hygiene targets for the Flutter app (app/) and the C++ audio core (core/), #7.
# Strategy and test matrix: docs/TESTS.md. Developer tools: Flutter, CMake, Homebrew llvm
# (clang-format, clang-tidy). core/third_party/ is never formatted, linted or read.
.PHONY: help test test-core test-wasm test-app test-hook format format-check lint lint-dart lint-core \
        coverage coverage-diff mutants fuzz report sanitize network-free

SHELL := /bin/bash
# A failing build must not be hidden by `| tail` (GNU Make 3.81 on macOS has no .SHELLFLAGS).
PIPEFAIL := set -o pipefail;

LLVM_BIN     ?= $(shell brew --prefix llvm 2>/dev/null)/bin
CLANG_FORMAT ?= $(shell command -v clang-format 2>/dev/null || echo $(LLVM_BIN)/clang-format)
CLANG_TIDY   ?= $(shell command -v clang-tidy 2>/dev/null || echo $(LLVM_BIN)/clang-tidy)
RUN_TIDY     ?= $(shell command -v run-clang-tidy 2>/dev/null || echo $(LLVM_BIN)/run-clang-tidy)

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

# ---- Tests ----
test: test-core test-app test-hook

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

# #7/AK7: the hook after a commit, in a staged git repository with fake tools
test-hook:
	cd app && flutter test --reporter failures-only tool/after_commit_hook_test.dart

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

# ---- Not set up yet ----
define not_yet
	@echo "make $@: noch nicht eingerichtet (#$(1))"; exit 1
endef

coverage:      ; $(call not_yet,8)
coverage-diff: ; $(call not_yet,8)
mutants:       ; $(call not_yet,11)
fuzz:          ; $(call not_yet,10)
report:        ; $(call not_yet,12)
sanitize:      ; $(call not_yet,57)
network-free:  ; $(call not_yet,58)
