// #131: Google's answer survives the start of the web app. It is taken from the address before the first
// frame (Flutter's hash URL strategy then replaces the address) and handed to the Google module, which is
// loaded only later. Runs in Chrome (flutter test --platform chrome, make test-web); nothing is sent.
@TestOn('browser')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:woodshed_player/app/file_store_web.dart';
import 'package:woodshed_player/library/library.dart';
import 'package:woodshed_player/sync/providers/google_auth.dart';
import 'package:woodshed_player/sync/providers/google_auth_web.dart';
import 'package:woodshed_player/sync/providers/google_platform_web.dart';
import 'package:woodshed_player/sync/oauth_return_web.dart';
import 'package:woodshed_player/sync/secret_store.dart';

void main() {
  late String start;
  setUp(
    () =>
        start = '${web.window.location.pathname}${web.window.location.search}',
  );
  tearDown(() => web.window.history.replaceState(null, '', start));

  /// Back from Google with [fragment]; the first frame then replaces the address, the module loads later.
  Future<GoogleAuth> comeBack(String fragment, MemorySecretStore store) async {
    web.window.history.replaceState(null, '', '$start#$fragment');
    final answer = takeStartAnswer();
    web.window.history.replaceState(null, '', '$start#/'); // what Flutter does
    final backend = openGoogle(
      library: Library(
        await OpfsFileStore.open('wp-test-oauth-return'),
        probe: (_) => 1,
        readSource: (_) async => null,
      ),
      secrets: store,
      openUrl: (_) async {},
      playing: () => false,
      fragment: answer,
    );
    await backend.load();
    return (backend as dynamic).auth as GoogleAuth;
  }

  Future<MemorySecretStore> pending(String state) async {
    final store = MemorySecretStore();
    await store.write(
      WebGoogleAuth.pendingKey,
      jsonEncode({'state': state, 'silent': false, 't': 0}),
    );
    return store;
  }

  test('#131/AK1 the answer is taken although the module loads after the first frame', () async {
    final store = await pending('s1');
    final auth = await comeBack(
      'state=s1&access_token=token-1&expires_in=3599&scope=${Uri.encodeComponent(googleScope)}',
      store,
    );
    expect(auth.signedIn, isTrue);
    expect(await auth.token(), 'token-1');
    expect(await store.read(WebGoogleAuth.pendingKey), isNull);
  });

  test('#131/AK2 no token in the address or the history after the start', () {
    final before = web.window.history.length;
    web.window.history.replaceState(
      null,
      '',
      '$start#state=s1&access_token=secret-token',
    );
    expect(takeStartAnswer(), 'state=s1&access_token=secret-token');
    expect(web.window.location.href, isNot(contains('secret-token')));
    expect(web.window.location.hash, isEmpty);
    expect(web.window.history.length, before); // replaced, no entry left behind
  });

  test(
    '#131/AK3 an answer with another or no state is still ignored',
    () async {
      for (final fragment in [
        'state=forged&access_token=evil&expires_in=3599',
        'access_token=evil',
      ]) {
        final store = await pending('s1');
        final auth = await comeBack(fragment, store);
        expect(auth.signedIn, isFalse, reason: fragment);
        expect(
          await store.read(WebGoogleAuth.tokenKey),
          isNull,
          reason: fragment,
        );
      }
    },
  );

  test('#131 without an answer the address stays as it is', () {
    web.window.history.replaceState(null, '', '$start#/');
    expect(takeStartAnswer(), '');
    expect(web.window.location.hash, '#/');
  });
}
