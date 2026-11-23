// #125: the variables WP_<RESOURCE>_REQUIRED (required_resource.dart). The C++ side is tested in
// core/tests/capi_tests.cpp (requiredVariable).
import 'package:flutter_test/flutter_test.dart';

import 'required_resource.dart';

const _var = 'WP_SELFTEST_REQUIRED';

Matcher _failureWith(List<String> parts) => throwsA(
  isA<TestFailure>().having(
    (e) => e.message,
    'message',
    allOf([for (final p in parts) contains(p)]),
  ),
);

void main() {
  group('#125 required resources', () {
    test('#125/AK2 unset or empty: skipped with the reason', () {
      for (final env in [
        <String, String>{},
        const {_var: ''},
      ]) {
        final skipped = <String>[];
        final run = needs(
          _var,
          available: false,
          reason: 'selftest resource missing',
          environment: env,
          skip: skipped.add,
        );
        expect(run, isFalse);
        expect(skipped, [
          'selftest resource missing (set WP_SELFTEST_REQUIRED=1 to require it)',
        ]);
      }
    });

    test('#125/AK2 with the resource the test runs, required or not', () {
      for (final env in [
        <String, String>{},
        const {_var: '1'},
      ]) {
        expect(
          needs(
            _var,
            available: true,
            reason: 'x',
            environment: env,
            skip: (_) => fail('not skipped'),
          ),
          isTrue,
        );
      }
    });

    test('#125/AK3 required without the resource fails', () {
      expect(
        () => needs(
          _var,
          available: false,
          reason: 'selftest resource missing',
          environment: const {_var: '1'},
          skip: (_) => fail('not skipped'),
        ),
        _failureWith([
          'selftest resource missing',
          'WP_SELFTEST_REQUIRED=1 requires it',
        ]),
      );
    });

    test(
      '#125/AK3 an invalid value fails with the variable and the allowed value',
      () {
        for (final bad in ['0', 'yes', 'true', ' 1']) {
          for (final available in [true, false]) {
            expect(
              () => needs(
                _var,
                available: available,
                reason: 'x',
                environment: {_var: bad},
                skip: (_) {},
              ),
              _failureWith(['WP_SELFTEST_REQUIRED=$bad', 'use 1']),
              reason: '$bad, available $available',
            );
          }
        }
      },
    );

    test('#125/AK2 the variables of this run have allowed values', () {
      for (final v in requiredVariables) {
        expect(() => isRequired(v), returnsNormally, reason: v);
      }
    });
  });
}
