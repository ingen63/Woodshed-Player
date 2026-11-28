// #13: shared helpers of the UI tests with the real core (integration_test). Rules (#13/AK2, taken from
// VivaPlan): wait for states, never for time. Every wait pumps frame by frame until a condition holds;
// the only time limit is [hangGuard] against a hang. The language is always fixed (English, or the
// pseudo language in pseudo_locale_test.dart). Test audio is generated (sineWav), each test works in
// its own temporary folder, never in the real library.
import 'dart:io';
import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/app_controller.dart';
import 'package:woodshed_player/app/smoke.dart';
import 'package:woodshed_player/l10n/app_localizations.dart';
import 'package:woodshed_player/main.dart';
import 'package:woodshed_player/metronome/tap_tempo.dart';

/// #134: keeps the app in front, as for a user who types, while a test sends simulated keys. When the
/// window is not in front (another app active, «Failed to foreground app»), the engine reports the app as
/// inactive and the view as unfocused, and Flutter parks the keyboard focus on the root scope until the
/// app is active again: the simulated keys then reach no shortcut. The test ignores both reports and
/// makes the app active and the view focused (Flutter gives the focus back to the node that had it).
void keepAppInFront(WidgetTester tester) {
  final binding = tester.binding;
  binding.platformDispatcher.onViewFocusChange = (event) {
    if (event.state == ViewFocusState.focused) {
      binding.handleViewFocusChanged(event);
    }
  };
  SystemChannels.lifecycle.setMessageHandler((message) async {
    if (message == AppLifecycleState.resumed.toString()) _resume(binding);
    return null;
  });
  addTearDown(() {
    binding.platformDispatcher.onViewFocusChange =
        binding.handleViewFocusChanged;
    SystemChannels.lifecycle.setMessageHandler((message) async {
      for (final state in AppLifecycleState.values) {
        if (message == state.toString()) {
          binding.handleAppLifecycleStateChanged(state);
        }
      }
      return null;
    });
  });
  _resume(binding);
  binding.handleViewFocusChanged(
    ViewFocusEvent(
      viewId: tester.view.viewId,
      state: ViewFocusState.focused,
      direction: ViewFocusDirection.undefined,
    ),
  );
}

/// Steps to [AppLifecycleState.resumed] through the states between, as the engine does. #165: without a
/// state yet it goes straight to resumed, as Flutter does for a first lifecycle message. macOS has no
/// initial lifecycle state (`initialLifecycleState` is empty) and the engine reports one only when the
/// window becomes active or hidden; a test app that never comes to the front has none.
void _resume(WidgetsBinding binding) {
  const path = [
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ];
  final current = binding.lifecycleState;
  if (current == null) {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    return;
  }
  for (final state in path.skip(path.indexOf(current) + 1)) {
    binding.handleAppLifecycleStateChanged(state);
  }
}

/// #134: what the engine reports when another app comes to the front (for the regression test).
Future<void> sendToBack(WidgetTester tester) async {
  tester.binding.platformDispatcher.onViewFocusChange?.call(
    ViewFocusEvent(
      viewId: tester.view.viewId,
      state: ViewFocusState.unfocused,
      direction: ViewFocusDirection.undefined,
    ),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    SystemChannels.lifecycle.codec.encodeMessage(
      AppLifecycleState.inactive.toString(),
    ),
    (_) {},
  );
}

/// #134: where the keyboard focus is, for the message of a failed shortcut.
String focusInfo() =>
    'focus: ${FocusManager.instance.primaryFocus}, '
    'keys down: ${HardwareKeyboard.instance.logicalKeysPressed}';

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

/// #115: shows area [a] by its tab and waits for the frame.
Future<void> showArea(WidgetTester tester, AppArea a) async {
  await tester.tap(find.byKey(Key('area:${a.name}')));
  await tester.pumpAndSettle();
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
