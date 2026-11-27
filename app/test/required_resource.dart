// #125: tests that need something special (the core built for macOS, an audio device, Python,
// actionlint) are skipped with a reason in the output. In the CI job that provides the resource, a
// variable WP_<RESOURCE>_REQUIRED=1 turns the skip into a failure. Unset or empty: skip; 1: required;
// any other value: failure that names the variable and the allowed value. The C++ side:
// core/tests/test_required.hpp. Variables, tests and jobs: docs/TESTS.md «Pflicht-Variablen (#125)».
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const macosCoreRequired = 'WP_MACOS_CORE_REQUIRED';
const audioDeviceRequired = 'WP_AUDIO_DEVICE_REQUIRED';
const pythonRequired = 'WP_PYTHON_REQUIRED';
const actionlintRequired = 'WP_ACTIONLINT_REQUIRED';
const optimizedBuildRequired = 'WP_OPTIMIZED_BUILD_REQUIRED';
const lameRequired = 'WP_LAME_REQUIRED'; // #141
const windowsRequired = 'WP_WINDOWS_REQUIRED'; // #60: Windows paths (AK4)

/// Every variable of #125 (Dart and C++), for the check of their values.
const requiredVariables = [
  macosCoreRequired,
  audioDeviceRequired,
  pythonRequired,
  actionlintRequired,
  optimizedBuildRequired,
  lameRequired,
  windowsRequired,
];

/// Whether [variable] makes its resource required: unset or empty → false, `1` → true; any other
/// value fails with the variable's name and the allowed value.
bool isRequired(String variable, [Map<String, String>? environment]) {
  final value = (environment ?? Platform.environment)[variable] ?? '';
  if (value.isEmpty) return false;
  if (value == '1') return true;
  fail(
    '$variable=$value is not allowed: use 1 (required) or leave it empty (skip)',
  );
}

/// Call at the start of a test body: `if (!needs(...)) return;`. Whether the test can run; without
/// the resource it is skipped with [reason], or fails if [variable] is 1.
bool needs(
  String variable, {
  required bool available,
  required String reason,
  Map<String, String>? environment,
  void Function(String reason) skip = markTestSkipped,
}) {
  final required = isRequired(variable, environment);
  if (available) return true;
  if (required) fail('$reason, but $variable=1 requires it');
  skip('$reason (set $variable=1 to require it)');
  return false;
}

/// Whether python3 is on the path.
bool get hasPython => Process.runSync('which', ['python3']).exitCode == 0;

/// The core library from core/build for the FFI tests; [coreAvailable] and [coreMissing] go to
/// [needs] with [macosCoreRequired].
final coreLibrary = File('../core/build/libwp_core.dylib');
bool get coreAvailable => Platform.isMacOS && coreLibrary.existsSync();
String get coreMissing => Platform.isMacOS
    ? 'core library missing (cmake --build core/build)'
    : 'the FFI tests need macOS';
