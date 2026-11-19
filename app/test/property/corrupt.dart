// Damaged JSON files for the robustness tests (#10/AK3, AK7, AK8): changed types, missing fields, wrong
// references, extreme values, foreign version numbers and truncated files, chosen by a Random.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'property.dart';

/// Every container (map or list) in [json] with its path, root first.
List<(Object, String)> containers(Object? json, [String path = r'$']) => [
  if (json is Map) (json, path),
  if (json is List) (json, path),
  if (json is Map)
    for (final e in json.entries) ...containers(e.value, '$path.${e.key}'),
  if (json is List)
    for (var i = 0; i < json.length; i++) ...containers(json[i], '$path[$i]'),
];

/// Values of another type, extreme values included (no NaN or infinity: JSON has none, see [extremeText]).
Object? otherValue(Random r, Object? old) => switch (r.nextInt(14)) {
  0 => null,
  1 => !(old is bool && old),
  2 => -1,
  3 => 0,
  4 => 1e308,
  5 => -1e308,
  6 => 9007199254740993, // 2^53 + 1, not exact in JavaScript
  7 => 'x' * (1 + r.nextInt(3) * 5000),
  8 => '',
  9 => <Object?>[old],
  10 => <String, Object?>{'value': old},
  11 => 3.5,
  12 => '1763560000000-0-',
  _ => '${old ?? ''}-',
};

/// A deep copy of decoded JSON.
Object? copyJson(Object? j) => jsonDecode(jsonEncode(j));

/// The kinds of damage, for the failure message and the statistics of a test.
enum Damage {
  typeChange,
  missingField,
  wrongReference,
  extremeValue,
  versionNumber,
  missingStamp,
  truncated,
}

/// Damages [json] once; returns the bytes of the damaged file and the kind of damage.
(Uint8List, Damage) corrupt(
  Random r,
  Object? json, {
  List<String> ids = const [],
}) {
  final damage = pick(r, Damage.values);
  final j = copyJson(json);
  final nodes = containers(j);
  final (node, _) = pick(r, nodes);
  switch (damage) {
    case Damage.typeChange:
      if (node is Map && node.isNotEmpty) {
        final k = pick(r, node.keys.toList());
        node[k] = otherValue(r, node[k]);
      } else if (node is List && node.isNotEmpty) {
        final i = r.nextInt(node.length);
        node[i] = otherValue(r, node[i]);
      }
    case Damage.missingField:
      if (node is Map && node.isNotEmpty) {
        node.remove(pick(r, node.keys.toList()));
      } else if (node is List && node.isNotEmpty) {
        node.removeAt(r.nextInt(node.length));
      }
    case Damage.wrongReference:
      // a folder, loop or track that does not exist, or the ID of another one
      final maps = [
        for (final (n, _) in nodes)
          if (n is Map) n,
      ];
      final m = pick(r, maps);
      final key = pick(r, const [
        'folderId',
        'folderID',
        'activeLoop',
        'id',
        'fileName',
      ]);
      m[key] = ids.isNotEmpty && r.nextBool()
          ? pick(r, ids)
          : 'FFFFFFFF-0000-4000-8000-${r.nextInt(1 << 30)}';
    case Damage.extremeValue:
      return (extremeText(r, jsonEncode(j)), damage);
    case Damage.versionNumber:
      if (j is Map) {
        j['formatVersion'] = pick(r, <Object?>[
          0,
          1,
          3,
          99,
          -2,
          '2',
          2.5,
          null,
        ]);
      }
    case Damage.missingStamp:
      final stamps = [
        for (final (n, _) in nodes)
          if (n is Map && n['stamps'] is Map && (n['stamps'] as Map).isNotEmpty)
            n['stamps'] as Map,
      ];
      if (stamps.isNotEmpty) {
        final s = pick(r, stamps);
        if (r.nextBool()) {
          s.remove(pick(r, s.keys.toList()));
        } else {
          s[pick(r, s.keys.toList())] = pick(r, const [
            '99999999999999999999-0-a',
            '-5-0-a',
            '1-x-a',
            '8640000000000001-0-a',
            '1-2147483648-a',
            '',
          ]);
        }
      }
    case Damage.truncated:
      final b = utf8.encode(jsonEncode(j));
      return (Uint8List.fromList(b.sublist(0, r.nextInt(b.length))), damage);
  }
  return (Uint8List.fromList(utf8.encode(jsonEncode(j))), damage);
}

/// Replaces a number in [text] with an extreme one that JSON allows but Dart reads as infinity, as a
/// value beyond 64 bits or as a huge negative number.
Uint8List extremeText(Random r, String text) {
  final numbers = RegExp(r'(?<=[:\[,]\s*)-?\d+(\.\d+)?(e[+-]?\d+)?')
      .allMatches(text)
      .toList();
  if (numbers.isEmpty) return Uint8List.fromList(utf8.encode(text));
  final m = pick(r, numbers);
  final value = pick(r, const [
    '1e400',
    '-1e400',
    '123456789012345678901234567890',
    '-9223372036854775809',
    '1e-400',
  ]);
  return Uint8List.fromList(
    utf8.encode(text.replaceRange(m.start, m.end, value)),
  );
}
