// #149: the saved appearance as a plain value, without a library. Imports track.dart directly, so the
// mutation tests of that file run it (app/tool/mutants.dart, testsFor).
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/track.dart';

void main() {
  test('#149/AK1 the default appearance is dark', () {
    expect(Appearance.standard, Appearance.dark);
  });

  test('#149/AK2 missing, unknown or wrongly typed values mean dark', () {
    for (final v in <Object?>[null, 42, '', 'sepia', 'DARK', 'System']) {
      expect(Appearance.parse(v), Appearance.dark, reason: '$v');
    }
  });

  test(
    '#149/AK3 #149/AK4 every saved value is read back as it is, System too',
    () {
      for (final a in Appearance.values) {
        expect(Appearance.parse(a.name), a);
      }
    },
  );
}
