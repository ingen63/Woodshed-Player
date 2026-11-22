// License texts of the libraries in the audio core for the app's license page (#119).
// The assets are verbatim copies of the license files in core/third_party/; a test keeps them in sync.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Library folder in core/third_party/ → (name on the license page, asset, license file in the folder).
/// All four libraries are built into the core on every platform, the WASM core included.
const coreLicenses = {
  'miniaudio': (
    name: 'miniaudio',
    asset: 'assets/licenses/miniaudio/LICENSE',
    file: 'LICENSE',
  ),
  'signalsmith-stretch': (
    name: 'Signalsmith Stretch',
    asset: 'assets/licenses/signalsmith-stretch/LICENSE.txt',
    file: 'LICENSE.txt',
  ),
  'signalsmith-linear': (
    name: 'Signalsmith Linear',
    asset: 'assets/licenses/signalsmith-linear/LICENSE.txt',
    file: 'LICENSE.txt',
  ),
  'flac': (
    name: 'libFLAC',
    asset: 'assets/licenses/flac/COPYING.Xiph',
    file: 'COPYING.Xiph',
  ),
};

void registerCoreLicenses([AssetBundle? bundle]) {
  final b = bundle ?? rootBundle;
  for (final lib in coreLicenses.values) {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        lib.name,
      ], await b.loadString(lib.asset));
    });
  }
}
