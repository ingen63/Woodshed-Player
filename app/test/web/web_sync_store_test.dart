// #54/AK1: the browser keeps the Google token in IndexedDB of the page (flutter test --platform chrome,
// make test-web). A fresh database per run; nothing is sent. The VM run of flutter test skips this file.
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/sync/cloud_provider.dart';
import 'package:woodshed_player/sync/providers/http_transport.dart';
import 'package:woodshed_player/sync/providers/http_transport_web.dart';
import 'package:woodshed_player/sync/providers/idb_secret_store.dart';

void main() {
  test('#54/AK1 IndexedDB: write, read, overwrite, delete', () async {
    final db = 'wp-test-${DateTime.now().microsecondsSinceEpoch}';
    final store = IdbSecretStore(database: db);
    expect(await store.read('google.token'), isNull);
    await store.write('google.token', '{"accessToken":"a"}');
    expect(await store.read('google.token'), '{"accessToken":"a"}');
    await store.write('google.token', 'b');
    // another instance (a new page) sees the same entry
    expect(await IdbSecretStore(database: db).read('google.token'), 'b');
    await store.delete('google.token');
    await store.delete('google.token'); // twice: no error
    expect(await store.read('google.token'), isNull);
  });

  test('#54/AK11 a closed fetch transport sends nothing', () async {
    final t = FetchTransport()..close();
    await expectLater(
      t.send(
        HttpCall('GET', Uri.parse('https://www.googleapis.com/drive/v3/about')),
      ),
      throwsA(isA<CloudOffline>()),
    );
  });
}
