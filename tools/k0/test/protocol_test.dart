// K0 (#52): the native test program speaks the same protocol as the test page (vectors.json, written from
// web/k0/k0.mjs by web_k0_test.mjs).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_k0/protocol.dart';

void main() {
  final v = jsonDecode(
    File('test/vectors.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final key = unhex(v['key'] as String);

  test('#52/K0 BIP-340 official vectors sign and verify', () {
    for (final t in (v['bip340'] as List).cast<Map<String, dynamic>>()) {
      final msg = unhex(t['msg'] as String);
      final pk = unhex(t['pk'] as String);
      final sig = schnorrSign(
        msg,
        BigInt.parse(t['sk'] as String, radix: 16),
        aux: unhex(t['aux'] as String),
      );
      expect(hex(sig).toUpperCase(), t['sig']);
      expect(schnorrVerify(msg, pk, sig), isTrue);
      sig[5] ^= 1;
      expect(schnorrVerify(msg, pk, sig), isFalse);
    }
  });

  test('#52/K0 pairing code and derived keys match the test page', () async {
    expect(keyToCode(key), v['code']);
    expect(codeToKey(v['code'] as String), key);
    final keys = await Keys.derive(key);
    expect(hex(keys.enc), v['enc']);
    expect(keys.pubkey, v['pubkey']);
    expect(keys.lanTag, v['lanTag']);
  });

  test('#52/K0 envelope and Nostr event match the test page', () async {
    final keys = await Keys.derive(key);
    final message = (v['message'] as Map).cast<String, Object?>();
    final sealed = await seal(
      keys,
      message,
      nonce: List.generate(12, (i) => i),
    );
    expect(sealed, v['envelope']);
    expect(await open(keys, v['envelope'] as String), message);
    final ev = nostrEvent(
      keys,
      'abc',
      createdAt: 1700000000,
      aux: Uint8List(32),
    );
    expect(ev['id'], (v['event'] as Map)['id']);
    expect(ev['sig'], (v['event'] as Map)['sig']);
    expect(
      schnorrVerify(
        unhex(ev['id'] as String),
        unhex(keys.pubkey),
        unhex(ev['sig'] as String),
      ),
      isTrue,
    );
  });

  test('#52/K0 envelope opens with the same key only', () async {
    final a = await Keys.derive(List.filled(32, 1));
    final b = await Keys.derive(List.filled(32, 2));
    final sealed = await seal(a, {'t': 'offer', 'sdp': 'v=0'});
    expect(await open(a, sealed), {'t': 'offer', 'sdp': 'v=0'});
    expect(await open(b, sealed), isNull);
    expect(await open(a, 'not base64!'), isNull);
    expect(await open(a, base64.encode(Uint8List(20))), isNull);
    final raw = base64.decode(sealed);
    raw[raw.length - 1] ^= 1;
    expect(await open(a, base64.encode(raw)), isNull);
    expect(await open(a, await seal(a, {'no': 'type'})), isNull);
  });

  test('#52/K0 pairing code round trip and rejects', () {
    for (var i = 0; i < 20; i++) {
      final k = randomBytes(32);
      final code = keyToCode(k);
      expect(code.length, 52 + 12);
      expect(codeToKey(' ${code.toLowerCase().replaceAll('-', ' ')} '), k);
    }
    expect(codeToKey('ABCD'), isNull);
    expect(codeToKey('${v['code']}A'), isNull);
    expect(
      codeToKey((v['code'] as String).replaceFirst(RegExp('^.'), '1')),
      isNull,
    );
  });

  test('#52/K0 test data matches the test page', () {
    final c = v['chunk'] as Map<String, dynamic>;
    final words = fillChunk(
      c['seed'] as int,
      c['index'] as int,
      Uint32List(chunkSize ~/ 4),
    );
    expect(words.sublist(0, 4), c['first']);
    expect(hex(sha256(words.buffer.asUint8List())), c['sha256']);
    expect(chunkCount(100 * 1024 * 1024), 1600);
    expect(chunkCount(1), 1);
  });

  test('#52/K0 address kinds never show the address', () {
    expect(addressKind('abc.local'), 'mDNS');
    expect(addressKind('192.168.1.2'), 'privat');
    expect(addressKind('172.40.0.1'), 'öffentlich');
    expect(addressKind('fd00::1'), 'privat');
    expect(addressKind('8.8.8.8'), 'öffentlich');
    expect(addressKind(null), 'unbekannt');
  });
}
