// Applies to every test under test/ (#62).
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

/// A tap that misses its widget fails the test instead of printing a warning (#62). In the
/// failures-only reporter such a warning showed the test name without [E], which read like a
/// failure under load.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  WidgetController.hitTestWarningShouldBeFatal = true;
  await testMain();
}
