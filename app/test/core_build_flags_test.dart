// #9/AK7: the core is built without fused multiply-add everywhere, so the app renders the same
// samples as the reference cases (core/tests/reference_tests.cpp) and the web core. Apple Clang
// contracts a * b + c into FMA on arm64, WebAssembly has none; the time stretch amplified the
// difference up to 2e-2. Runs from app/ like the other tests.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  group('#9/AK7 no FMA contraction in any build of the core', () {
    test('CMake (tests, tools, web) builds with -ffp-contract=off', () {
      expect(
        read('../core/CMakeLists.txt'),
        contains('add_compile_options(-ffp-contract=off)'),
      );
    });

    for (final platform in ['macos', 'ios']) {
      test('Flutter plugin on $platform builds with -ffp-contract=off', () {
        final podspec = read('packages/wp_core/$platform/wp_core.podspec');
        expect(
          podspec,
          contains("'OTHER_CFLAGS' => '\$(inherited) -ffp-contract=off'"),
        );
        expect(
          podspec,
          contains(
            "'OTHER_CPLUSPLUSFLAGS' => '\$(inherited) -ffp-contract=off'",
          ),
        );
      });
    }
  });
}
