// Natürliche Sortierung wie `localizedStandardCompare` der Swift-App: ohne Gross-/Kleinschreibung,
// Umlaute neben ihrem Grundbuchstaben, Zahlen nach ihrem Wert («Track 2» vor «Track 10»).

const _fold = {
  'ä': 'a',
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'å': 'a',
  'æ': 'ae',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ö': 'o',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ø': 'o',
  'œ': 'oe',
  'ü': 'u',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ß': 'ss',
};

String _key(String s) {
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final ch in lower.split('')) {
    out.write(_fold[ch] ?? ch);
  }
  return out.toString();
}

final _partPattern = RegExp(r'\d+|\D+');

/// Sort key of [naturalCompare], computed once per text (#59: sorting 10'000 titles folded and split
/// every title again in each of the ~130'000 comparisons).
class NaturalKey implements Comparable<NaturalKey> {
  factory NaturalKey(String text) {
    final parts = [for (final m in _partPattern.allMatches(_key(text))) m[0]!];
    return NaturalKey._(text, parts, [for (final p in parts) int.tryParse(p)]);
  }

  NaturalKey._(this.text, this._parts, this._numbers);

  final String text;
  final List<String> _parts;
  final List<int?> _numbers;

  @override
  int compareTo(NaturalKey o) {
    final pa = _parts, pb = o._parts;
    for (var i = 0; i < pa.length && i < pb.length; i++) {
      final x = pa[i], y = pb[i];
      final nx = _numbers[i], ny = o._numbers[i];
      final c = (nx != null && ny != null)
          ? (nx != ny ? nx.compareTo(ny) : x.length.compareTo(y.length))
          : x.compareTo(y);
      if (c != 0) return c;
    }
    if (pa.length != pb.length) return pa.length.compareTo(pb.length);
    return text.compareTo(
      o.text,
    ); // gleich nach Regeln: stabil nach Originaltext
  }
}

int naturalCompare(String a, String b) =>
    NaturalKey(a).compareTo(NaturalKey(b));

/// Sorts [items] by [naturalCompare] of [text], with one key per item.
List<T> sortedNaturally<T>(Iterable<T> items, String Function(T) text) {
  final keyed = [for (final i in items) (NaturalKey(text(i)), i)];
  keyed.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final k in keyed) k.$2];
}
