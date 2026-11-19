// #13/AK4: the library storage of the web app in a real browser (flutter test --platform chrome, make
// test-web): Origin Private File System (OPFS, file_store_web.dart) and handing over picked files
// (file_platform_web.dart). Works in its own OPFS folder. The VM run of flutter test skips this file.
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/file_platform_web.dart';
import 'package:woodshed_player/app/file_store_web.dart';

const dir = 'wp_test_storage';

Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  setUp(() => OpfsFileStore.clear(dir));
  tearDown(() => OpfsFileStore.clear(dir));

  test('#13/AK4 OPFS: write, read, exists, rename, delete', () async {
    final s = await OpfsFileStore.open(dir);
    expect(await s.exists('a.json'), isFalse);
    expect(await s.read('a.json'), isNull);
    await s.write('a.json', bytes('{"v":1}'));
    await s.write('audio/x/b.mp3', bytes('mp3')); // sub folders are created
    expect(utf8.decode((await s.read('a.json'))!), '{"v":1}');
    expect(await s.exists('audio/x/b.mp3'), isTrue);
    await s.write('a.json', bytes('{"v":2}')); // replaces the whole file
    expect(utf8.decode((await s.read('a.json'))!), '{"v":2}');
    await s.rename('a.json', 'c.json');
    expect(await s.exists('a.json'), isFalse);
    expect(utf8.decode((await s.read('c.json'))!), '{"v":2}');
    await s.delete('c.json');
    await s.delete('c.json'); // already gone: no error
    expect(await s.exists('c.json'), isFalse);
    expect(() => s.rename('missing', 'x'), throwsStateError);
    // In the browser there are no paths: the core gets the name.
    expect(s.locate('audio/x/b.mp3'), 'audio/x/b.mp3');
    expect(s.localPath('audio/x/b.mp3'), isNull);
  });

  test('#13/AK4 OPFS: SHA-256, storage line, survives reopening', () async {
    final s = await OpfsFileStore.open(dir);
    await s.write('abc', bytes('abc'));
    // SHA-256 of «abc» (FIPS 180-2, example B.1)
    expect(
      await s.sha256('abc'),
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
    expect(await s.sha256('missing'), isNull);
    final info = await s.storageInfo();
    expect(info.quota, greaterThan(0));
    expect(info.used, greaterThanOrEqualTo(0));
    final again = await OpfsFileStore.open(dir);
    expect(utf8.decode((await again.read('abc'))!), 'abc');
    await OpfsFileStore.clear(dir);
    expect(await (await OpfsFileStore.open(dir)).exists('abc'), isFalse);
  });

  test('#13/AK4 picked files are handed over once by their key', () async {
    final f = WebFilePlatform();
    final k1 = f.register('Song.mp3', bytes('one'));
    final k2 = f.register('Song.mp3', bytes('two'));
    expect(k1, isNot(k2)); // same name, own key each
    expect(k1, endsWith('/Song.mp3'));
    expect(utf8.decode((await f.take(k2))!), 'two');
    expect(await f.take(k2), isNull); // only once
    expect(utf8.decode((await f.take(k1))!), 'one');
    expect(await f.supportDir(), isNull);
  });
}
