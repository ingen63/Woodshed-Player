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

final _parts = RegExp(r'\d+|\D+');

int naturalCompare(String a, String b) {
  final pa = _parts.allMatches(_key(a)).map((m) => m[0]!).toList();
  final pb = _parts.allMatches(_key(b)).map((m) => m[0]!).toList();
  for (var i = 0; i < pa.length && i < pb.length; i++) {
    final x = pa[i], y = pb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = (nx != null && ny != null)
        ? (nx != ny ? nx.compareTo(ny) : x.length.compareTo(y.length))
        : x.compareTo(y);
    if (c != 0) return c;
  }
  if (pa.length != pb.length) return pa.length.compareTo(pb.length);
  return a.compareTo(b); // gleich nach Regeln: stabil nach Originaltext
}
