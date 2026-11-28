// #165/AK2: keepAppInFront of the UI tests (integration_test/ui_helpers.dart) also works without a
// lifecycle state, as on macOS when the test app never comes to the front (no initial state there).
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../integration_test/ui_helpers.dart';

/// Records the lifecycle states the binding passes through.
class _Recorder with WidgetsBindingObserver {
  final states = <AppLifecycleState>[];

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => states.add(state);
}

_Recorder _record(WidgetTester tester) {
  final r = _Recorder();
  tester.binding.addObserver(r);
  addTearDown(() => tester.binding.removeObserver(r));
  return r;
}

void main() {
  testWidgets('#165/AK2 without a lifecycle state: straight to resumed', (
    tester,
  ) async {
    // ignore: invalid_use_of_visible_for_testing_member
    tester.binding.resetInternalState(); // no state, as on macOS in the back
    expect(tester.binding.lifecycleState, isNull);
    final r = _record(tester);

    keepAppInFront(tester);

    expect(tester.binding.lifecycleState, AppLifecycleState.resumed);
    expect(r.states, [AppLifecycleState.resumed]);

    // the engine reports another app in front: the app stays resumed
    await sendToBack(tester);
    expect(tester.binding.lifecycleState, AppLifecycleState.resumed);
  });

  testWidgets('#165/AK2 from paused: through the states between', (
    tester,
  ) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    final r = _record(tester);

    keepAppInFront(tester);

    expect(r.states, [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
  });
}
