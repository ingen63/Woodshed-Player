// #109: the screen wake lock in a real browser (flutter test --platform chrome, make test-web). Chrome knows
// the API; whether it grants the lock depends on the test page (visible or not), so both answers are fine,
// but neither may throw. The VM run of flutter test skips this file.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/wake_lock_web.dart';

void main() {
  test('#109/AK1 Chrome offers the Screen Wake Lock API', () {
    expect(WebWakeLock.create(), isNotNull);
  });

  test('#109/AK4 request and release never throw, granted or not', () async {
    final api = WebWakeLock.create()!;
    final lock = await api.request();
    if (lock != null) {
      expect(lock.released, isFalse);
      lock.release();
      expect(lock.released, isTrue);
      lock.release(); // twice: no error
    }
    api.onVisible(() {}); // listening only, no error
  });
}
