// Lizenztexte der gebündelten Schriften (SIL OFL 1.1) für die Lizenzseite der App (#27).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const fontLicenseAssets = {
  'Inter': 'assets/fonts/inter/OFL.txt',
  'JetBrains Mono': 'assets/fonts/jetbrains-mono/OFL.txt',
};

void registerFontLicenses([AssetBundle? bundle]) {
  final b = bundle ?? rootBundle;
  fontLicenseAssets.forEach((name, asset) {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([name], await b.loadString(asset));
    });
  });
}
