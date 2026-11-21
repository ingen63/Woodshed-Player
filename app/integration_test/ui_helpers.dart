// #13: shared helpers of the UI tests with the real core (integration_test). Rules (#13/AK2, taken from
// VivaPlan): wait for states, never for time. Every wait pumps frame by frame until a condition holds;
// the only time limit is [hangGuard] against a hang. The language is always fixed (English, or the
// pseudo language in pseudo_locale_test.dart). Test audio is generated (sineWav), each test works in
// its own temporary folder, never in the real library.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/app/smoke.dart';
import 'package:woodshed_player/l10n/app_localizations.dart';
import 'package:woodshed_player/main.dart';
import 'package:woodshed_player/metronome/tap_tempo.dart';

/// Protection against a hang only; a passing test never comes near it, whatever the machine's load.
const hangGuard = Duration(seconds: 60);

/// Pumps frames until [done] holds (at least one); fails with [what] if [hangGuard] passes first.
Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() done,
  String what,
) async {
  final watch = Stopwatch()..start();
  // at least one frame, so the screen shows the state reached
  do {
    if (watch.elapsed > hangGuard) {
      fail('hang: «$what» not reached within ${hangGuard.inSeconds} s');
    }
    await tester.pump();
  } while (!done());
}

/// Window sizes of the three layouts (#30).
const desktopSize = Size(1280, 800),
    tabletSize = Size(820, 1100),
    phoneSize = Size(390, 844);

/// A temporary folder with a generated sine file «Sine test tone.wav» of [seconds].
({Directory dir, File wav}) testFolder({double seconds = 4}) {
  final dir = Directory.systemTemp.createTempSync('wp_ui');
  final wav = File('${dir.path}/Sine test tone.wav')
    ..writeAsBytesSync(sineWav(seconds: seconds));
  addTearDown(() => dir.deleteSync(recursive: true));
  return (dir: dir, wav: wav);
}

/// Starts the app with the real core and its library in [dir], silent, at [size] and in [locale]
/// (or with the texts of [l10n]); [recordingButton] as in the app (`recordingButtonFor`) or none.
Future<AppController> startApp(
  WidgetTester tester,
  Directory dir, {
  Size size = desktopSize,
  Locale locale = const Locale('en'),
  LocalizationsDelegate<AppLocalizations> l10n = AppLocalizations.delegate,
  TapTempo? tapTempo,
  Widget? Function(AppController controller)? recordingButton,
}) async {
  final controller = await createAppController(
    baseDir: Directory('${dir.path}/app'),
    tapTempo: tapTempo,
  );
  addTearDown(controller.player.pause);
  controller.player.setVolume(0); // silent
  controller.metronome.setVolume(0);
  setSize(tester, size);
  await tester.pumpWidget(
    WoodshedApp(
      controller: controller,
      locale: locale,
      localizationsDelegate: l10n,
      recordingButton: recordingButton,
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

void setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  // #99: no safe area of the real device (an iOS simulator reports its notch in physical pixels,
  // which at ratio 1 would cut off the layout); macOS has none anyway.
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  addTearDown(tester.view.reset);
}

/// Drops [files] onto the window the way macOS reports it (channel woodshed/files, #22) and waits until
/// the first one is loaded.
Future<void> dropFiles(
  WidgetTester tester,
  AppController c,
  List<File> files,
) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'woodshed/files',
    const StandardMethodCodec().encodeMethodCall(
      MethodCall('dropFiles', [for (final f in files) f.path]),
    ),
    (_) {},
  );
  await pumpUntil(
    tester,
    () => c.player.hasTrack && !c.player.isLoading,
    'track loaded',
  );
}

/// The English texts, to compare what the screen shows.
final en = lookupAppLocalizations(const Locale('en'));
