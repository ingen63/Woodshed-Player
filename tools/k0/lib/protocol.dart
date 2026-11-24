// Feasibility test K0 (#52): protocol and crypto of the native test program, byte-identical to the test page
// (web/k0/k0.mjs); test/vectors.json pins both. Pairing key: 32 bytes, base32 code. HKDF-SHA256 (empty salt)
// derives the AES-256-GCM key of the signalling envelope ("woodshed-k0/enc"), the shared Nostr identity
// ("woodshed-k0/nostr") and the Bonjour tag ("woodshed-k0/lan").
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

const nostrKind = 25052;
const chunkSize = 64 * 1024;
final _aad = utf8.encode('woodshed-k0');
final _random = Random.secure();

Uint8List randomBytes(int n) =>
    Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List unhex(String s) {
  if (s.length.isOdd || RegExp('[^0-9a-fA-F]').hasMatch(s)) {
    throw const FormatException('bad hex');
  }
  return Uint8List.fromList([
    for (var i = 0; i < s.length; i += 2)
      int.parse(s.substring(i, i + 2), radix: 16),
  ]);
}

// ---- Pairing code ----

const _b32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// Base32 (RFC 4648, no padding) in groups of four.
String keyToCode(List<int> key) {
  var bits = 0;
  var value = 0;
  final out = StringBuffer();
  for (final b in key) {
    value = ((value << 8) | b) & 0xffff;
    bits += 8;
    while (bits >= 5) {
      out.write(_b32[(value >> (bits - 5)) & 31]);
      bits -= 5;
    }
  }
  if (bits > 0) out.write(_b32[(value << (5 - bits)) & 31]);
  final s = out.toString();
  return [
    for (var i = 0; i < s.length; i += 4) s.substring(i, min(i + 4, s.length)),
  ].join('-');
}

/// Parses a pairing code; spaces, dashes and case do not matter. Null unless it holds 32 bytes.
Uint8List? codeToKey(String code) {
  final s = code.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  if (s.length != 52 || RegExp('[^A-Z2-7]').hasMatch(s)) return null;
  var bits = 0;
  var value = 0;
  final out = <int>[];
  for (final c in s.split('')) {
    value = ((value << 5) | _b32.indexOf(c)) & 0xffff;
    bits += 5;
    if (bits >= 8) {
      out.add((value >> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return Uint8List.fromList(out.sublist(0, 32));
}

// ---- Keys and envelope ----

Uint8List sha256(List<int> data) =>
    Uint8List.fromList(const DartSha256().hashSync(data).bytes);

Future<Uint8List> _hkdf(List<int> key, String info, int length) async {
  final out = await Hkdf(hmac: Hmac.sha256(), outputLength: length).deriveKey(
    secretKey: SecretKey(key),
    nonce: const [],
    info: utf8.encode(info),
  );
  return Uint8List.fromList(await out.extractBytes());
}

class Keys {
  Keys._(this.enc, this.sk, this.pubkey, this.lanTag);

  final Uint8List enc;
  final BigInt sk;
  final String pubkey;
  final String lanTag;

  static Future<Keys> derive(List<int> key) async {
    final enc = await _hkdf(key, 'woodshed-k0/enc', 32);
    final nostr = await _hkdf(key, 'woodshed-k0/nostr', 32);
    final lan = await _hkdf(key, 'woodshed-k0/lan', 8);
    final sk = bytesToBig(nostr) % (_n - BigInt.one) + BigInt.one;
    return Keys._(enc, sk, hex(xOnly(sk)), hex(lan));
  }
}

final _gcm = AesGcm.with256bits();

Future<String> seal(
  Keys keys,
  Map<String, Object?> message, {
  List<int>? nonce,
}) async {
  final box = await _gcm.encrypt(
    utf8.encode(jsonEncode(message)),
    secretKey: SecretKey(keys.enc),
    nonce: nonce ?? randomBytes(12),
    aad: _aad,
  );
  return base64.encode(box.concatenation());
}

/// Decrypts an envelope; null if it is not one of ours.
Future<Map<String, Object?>?> open(Keys keys, String text) async {
  try {
    final raw = base64.decode(text);
    if (raw.length < 12 + 16) return null;
    final box = SecretBox.fromConcatenation(
      raw,
      nonceLength: 12,
      macLength: 16,
    );
    final plain = await _gcm.decrypt(
      box,
      secretKey: SecretKey(keys.enc),
      aad: _aad,
    );
    final message = jsonDecode(utf8.decode(plain));
    return message is Map<String, Object?> && message['t'] is String
        ? message
        : null;
  } on Object {
    return null;
  }
}

// ---- secp256k1 and BIP-340 ----

final _p = BigInt.two.pow(256) - BigInt.two.pow(32) - BigInt.from(977);
final _n = BigInt.parse(
  'fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141',
  radix: 16,
);
final _gx = BigInt.parse(
  '79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798',
  radix: 16,
);
final _gy = BigInt.parse(
  '483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8',
  radix: 16,
);

BigInt bytesToBig(List<int> bytes) {
  var n = BigInt.zero;
  for (final b in bytes) {
    n = (n << 8) | BigInt.from(b);
  }
  return n;
}

Uint8List bigToBytes(BigInt n) {
  final out = Uint8List(32);
  for (var i = 31; i >= 0; i--) {
    out[i] = (n & BigInt.from(0xff)).toInt();
    n >>= 8;
  }
  return out;
}

BigInt _m(BigInt a) =>
    a % _p; // Dart's % is never negative for a positive modulus

typedef _J = (BigInt, BigInt, BigInt);
final _inf = (BigInt.zero, BigInt.one, BigInt.zero);

_J _double(_J p) {
  final (x, y, z) = p;
  if (z == BigInt.zero || y == BigInt.zero) return _inf;
  final s = _m(BigInt.from(4) * x * y * y);
  final m = _m(BigInt.from(3) * x * x);
  final x2 = _m(m * m - BigInt.two * s);
  return (
    x2,
    _m(m * (s - x2) - BigInt.from(8) * y * y * y * y),
    _m(BigInt.two * y * z),
  );
}

_J _add(_J p, _J q) {
  if (p.$3 == BigInt.zero) return q;
  if (q.$3 == BigInt.zero) return p;
  final z1z1 = _m(p.$3 * p.$3);
  final z2z2 = _m(q.$3 * q.$3);
  final u1 = _m(p.$1 * z2z2);
  final u2 = _m(q.$1 * z1z1);
  final s1 = _m(p.$2 * q.$3 * z2z2);
  final s2 = _m(q.$2 * p.$3 * z1z1);
  if (u1 == u2) return s1 == s2 ? _double(p) : _inf;
  final h = _m(u2 - u1);
  final r = _m(s2 - s1);
  final hh = _m(h * h);
  final hhh = _m(h * hh);
  final x3 = _m(r * r - hhh - BigInt.two * u1 * hh);
  return (x3, _m(r * (u1 * hh - x3) - s1 * hhh), _m(h * p.$3 * q.$3));
}

_J _mul(BigInt k, BigInt x, BigInt y) {
  var r = _inf;
  _J a = (x, y, BigInt.one);
  while (k > BigInt.zero) {
    if (k.isOdd) r = _add(r, a);
    a = _double(a);
    k >>= 1;
  }
  return r;
}

(BigInt, BigInt)? _affine(_J p) {
  if (p.$3 == BigInt.zero) return null;
  final zi = p.$3.modInverse(_p);
  final zi2 = _m(zi * zi);
  return (_m(p.$1 * zi2), _m(p.$2 * zi2 * zi));
}

Uint8List xOnly(BigInt sk) => bigToBytes(_affine(_mul(sk, _gx, _gy))!.$1);

Uint8List _tagged(String tag, List<List<int>> parts) {
  final t = sha256(utf8.encode(tag));
  return sha256([...t, ...t, for (final p in parts) ...p]);
}

/// BIP-340 signature of a 32-byte message.
Uint8List schnorrSign(List<int> msg, BigInt sk, {List<int>? aux}) {
  final pub = _affine(_mul(sk, _gx, _gy))!;
  final d = pub.$2.isEven ? sk : _n - sk;
  final px = bigToBytes(pub.$1);
  final auxHash = _tagged('BIP0340/aux', [aux ?? randomBytes(32)]);
  final db = bigToBytes(d);
  final t = [for (var i = 0; i < 32; i++) db[i] ^ auxHash[i]];
  final k0 = bytesToBig(_tagged('BIP0340/nonce', [t, px, msg])) % _n;
  if (k0 == BigInt.zero) throw StateError('nonce is zero');
  final r = _affine(_mul(k0, _gx, _gy))!;
  final k = r.$2.isEven ? k0 : _n - k0;
  final rx = bigToBytes(r.$1);
  final e = bytesToBig(_tagged('BIP0340/challenge', [rx, px, msg])) % _n;
  return Uint8List.fromList([...rx, ...bigToBytes((k + e * d) % _n)]);
}

/// BIP-340 verification (for the tests).
bool schnorrVerify(List<int> msg, List<int> pubkey, List<int> sig) {
  final x = bytesToBig(pubkey);
  if (x >= _p) return false;
  final c = _m(x * x * x + BigInt.from(7));
  var y = c.modPow((_p + BigInt.one) >> 2, _p);
  if (_m(y * y) != c) return false;
  if (y.isOdd) y = _p - y;
  final r = bytesToBig(sig.sublist(0, 32));
  final s = bytesToBig(sig.sublist(32));
  if (r >= _p || s >= _n) return false;
  final e =
      bytesToBig(
        _tagged('BIP0340/challenge', [sig.sublist(0, 32), pubkey, msg]),
      ) %
      _n;
  final point = _affine(_add(_mul(s, _gx, _gy), _mul(_n - e, x, y)));
  return point != null && point.$2.isEven && point.$1 == r;
}

/// A signed ephemeral Nostr event (NIP-01) carrying [content].
Map<String, Object?> nostrEvent(
  Keys keys,
  String content, {
  int? createdAt,
  List<int>? aux,
}) {
  final at = createdAt ?? DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final id = sha256(
    utf8.encode(
      jsonEncode([0, keys.pubkey, at, nostrKind, <Object>[], content]),
    ),
  );
  return {
    'pubkey': keys.pubkey,
    'created_at': at,
    'kind': nostrKind,
    'tags': <Object>[],
    'content': content,
    'id': hex(id),
    'sig': hex(schnorrSign(id, keys.sk, aux: aux)),
  };
}

// ---- Test data ----

/// Fills [words] with the test data of chunk [index] of transfer [seed] (xorshift32, like k0.mjs).
Uint32List fillChunk(int seed, int index, Uint32List words) {
  var x = (seed ^ (((index + 1) * 0x9e3779b9) & 0xffffffff)) & 0xffffffff;
  if (x == 0) x = 1;
  for (var i = 0; i < words.length; i++) {
    x ^= (x << 13) & 0xffffffff;
    x ^= x >> 17;
    x ^= (x << 5) & 0xffffffff;
    words[i] = x;
  }
  return words;
}

int chunkCount(int size) => (size + chunkSize - 1) ~/ chunkSize;

/// Classifies a candidate address without revealing it.
String addressKind(String? address) {
  if (address == null || address.isEmpty) return 'unbekannt';
  if (address.endsWith('.local')) return 'mDNS';
  if (RegExp(r'^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.|127\.)')
      .hasMatch(address)) {
    return 'privat';
  }
  if (RegExp(r'^(fe80:|fc|fd|::1$)', caseSensitive: false).hasMatch(address)) {
    return 'privat';
  }
  return 'öffentlich';
}
