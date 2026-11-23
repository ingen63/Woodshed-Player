// #54/AK1: a start with a stored Google sign-in never holds up the app. The keychain or the token endpoint
// may hang (a hidden keychain prompt, a network that does not answer); the window is shown anyway and the
// sync follows in the background. Only simulated Google, never a real account (AK13).
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:woodshed_player/app/app_start.dart';
import 'package:woodshed_player/sync/cloud_account.dart';
import 'package:woodshed_player/sync/google_sync.dart';
import 'package:woodshed_player/sync/providers/google_auth_desktop.dart';
import 'package:woodshed_player/sync/providers/http_transport.dart';
import 'package:woodshed_player/sync/secret_store.dart';
import 'package:woodshed_player/sync/sync_service.dart';

import 'fakes.dart' show TestApp;
import 'home_page_test.dart' show pumpApp;

/// A keychain whose answer never comes.
class HangingSecrets implements SecretStore {
  final waiting = Completer<String?>();
  var reads = 0;

  @override
  Future<String?> read(String key) {
    reads++;
    return waiting.future;
  }

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

/// A keychain that refuses: its password prompt was cancelled or denied.
class RefusingSecrets implements SecretStore {
  @override
  Future<String?> read(String key) async =>
      throw PlatformException(code: 'keychain', message: 'read: -128');

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}

/// A network that never answers.
class HangingTransport implements HttpTransport {
  final calls = <HttpCall>[];

  @override
  Future<HttpReply> send(HttpCall call) {
    calls.add(call);
    return Completer<HttpReply>().future;
  }

  @override
  void close() {}
}

void main() {
  testWidgets(
    '#54/AK1 stored sign-in, the keychain hangs: the app is shown at once',
    (tester) async {
      final secrets = HangingSecrets();
      late GoogleBackend backend;
      final app = await pumpApp(
        tester,
        cloud: (lib) => CloudAccount(
          library: lib,
          loadGoogle: () async => backend = GoogleBackend(
            auth: DesktopGoogleAuth(
              transport: HangingTransport(),
              secrets: secrets,
              openBrowser: (_) async {},
            ),
            transport: HangingTransport(),
            library: lib,
            eagerDownload: true,
          ),
        ),
      );
      await tester.runAsync(() => app.library.setSyncProvider('google'));
      var started = false;
      unawaited(app.controller.start().whenComplete(() => started = true));
      await tester.runAsync(pumpEventQueue);
      expect(secrets.reads, 1, reason: 'the start waits for the keychain');
      expect(started, isFalse);
      // what the app does at its start: returns at once, the window is drawn and reacts
      startInBackground(app.controller);
      await tester.pump();
      expect(find.byKey(const Key('syncButton')), findsOneWidget);
      secrets.waiting.complete(
        null,
      ); // the keychain answers late: not signed in
      await tester.runAsync(pumpEventQueue);
      expect(started, isTrue);
      expect(backend.signedIn, isFalse);
      backend.dispose();
    },
  );

  testWidgets(
    '#54/AK1 stored sign-in, the token endpoint hangs: the app is shown at once',
    (tester) async {
      final secrets = MemorySecretStore();
      await secrets.write(DesktopGoogleAuth.refreshKey, 'refresh-stored');
      final net = HangingTransport();
      late GoogleBackend backend;
      final app = await pumpApp(
        tester,
        cloud: (lib) => CloudAccount(
          library: lib,
          loadGoogle: () async => backend = GoogleBackend(
            auth: DesktopGoogleAuth(
              transport: net,
              secrets: secrets,
              openBrowser: (_) async {},
            ),
            transport: net,
            library: lib,
            eagerDownload: true,
          ),
        ),
      );
      await tester.runAsync(() => app.library.setSyncProvider('google'));
      var started = false;
      unawaited(app.controller.start().whenComplete(() => started = true));
      // the sync of the start waits for the token renewal, which never answers
      await tester.runAsync(() => _until(() => net.calls.isNotEmpty));
      expect(net.calls.first.url.host, 'oauth2.googleapis.com');
      expect(started, isFalse);
      expect(backend.signedIn, isTrue);
      startInBackground(app.controller);
      await tester.pump();
      expect(find.byKey(const Key('syncButton')), findsOneWidget);
      // the app reacts while the sync still waits
      await tester.tap(find.byKey(const Key('syncButton')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      backend.dispose();
    },
  );

  testWidgets(
    '#54/AK1, AK5 the keychain refuses: not signed in, the hint asks to sign in again',
    (tester) async {
      final (app, backend) = await _app(tester, RefusingSecrets());
      startInBackground(app.controller);
      await tester.runAsync(
        () => _until(() => app.controller.cloud.needsSignIn),
      );
      await tester.pumpAndSettle();
      expect(backend().signedIn, isFalse);
      expect(app.controller.cloud.sync.inner, isA<NoSync>(), reason: 'no sync');
      expect(find.byKey(const Key('signInHint')), findsOneWidget);
    },
  );

  testWidgets(
    '#54/AK5 the keychain refuses during playback: the hint waits for its end',
    (tester) async {
      final (app, _) = await _app(tester, RefusingSecrets());
      final t = app.library.sortedTracks.first;
      await tester.tap(find.byKey(Key('track:${t.title}')));
      await tester.pump();
      app.finishLoads(30);
      await tester.pump();
      app.player.play();
      await tester.pump();
      expect(app.player.isPlaying, isTrue);
      startInBackground(app.controller);
      await tester.runAsync(
        () => _until(() => app.controller.cloud.needsSignIn),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('signInHint')), findsNothing);
      app.player.pause();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('signInHint')), findsOneWidget);
    },
  );
}

/// The app with a Google backend on [secrets] and a network that never answers.
Future<(TestApp, GoogleBackend Function())> _app(
  WidgetTester tester,
  SecretStore secrets,
) async {
  GoogleBackend? backend;
  final net = HangingTransport();
  final app = await pumpApp(
    tester,
    cloud: (lib) => CloudAccount(
      library: lib,
      loadGoogle: () async => backend = GoogleBackend(
        auth: DesktopGoogleAuth(
          transport: net,
          secrets: secrets,
          openBrowser: (_) async {},
        ),
        transport: net,
        library: lib,
        eagerDownload: true,
      ),
    ),
  );
  addTearDown(() => backend?.dispose());
  await tester.runAsync(() => app.library.setSyncProvider('google'));
  return (app, () => backend!);
}

/// Waits until [done] holds, at most a few seconds (no fixed wait, #95).
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 1000 && !done(); i++) {
    await pumpEventQueue();
  }
}
