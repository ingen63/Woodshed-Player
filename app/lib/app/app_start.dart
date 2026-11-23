// Starting the sync never holds up the first frame (#54/AK1). With a stored sign-in the start reads the
// keychain, renews the token and runs a whole sync, which can take long or wait for a network that does
// not answer; the window stayed black until then. The app is shown right away, the sync follows.
import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_controller.dart';

/// Starts the sync of [controller] in the background; returns at once.
void startInBackground(AppController controller) => unawaited(
  controller.start().catchError(
    (Object e) => debugPrint('sync start failed: $e'),
  ),
);
