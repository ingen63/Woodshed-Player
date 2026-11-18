// #27/AK4: Beide Schriften erscheinen mit vollem OFL-Text in der Lizenzregistrierung.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/ui/font_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '#27/AK4 Inter und JetBrains Mono stehen in der LicenseRegistry',
    () async {
      registerFontLicenses();
      final entries = await LicenseRegistry.licenses.toList();
      for (final name in fontLicenseAssets.keys) {
        final e = entries.where((l) => l.packages.contains(name)).toList();
        expect(e, isNotEmpty, reason: name);
        final text = e.first.paragraphs.map((p) => p.text).join('\n');
        expect(
          text,
          contains('SIL OPEN FONT LICENSE Version 1.1'),
          reason: name,
        );
        expect(text, contains('Copyright'), reason: name);
      }
    },
  );
}
