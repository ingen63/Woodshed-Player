// JSON genau wie `JSONEncoder` mit `.prettyPrinted, .sortedKeys` der Swift-App (#16):
// `"schlüssel" : wert`, zwei Leerzeichen Einzug, `/` als `\/`, ganze Zahlen ohne `.0`.
// So bleibt library.json auch byte-gleich zur Swift-App vergleichbar (Golden-Dateien).

String swiftPrettyJson(Object? value) {
  final out = StringBuffer();
  _write(out, value, 0);
  return out.toString();
}

void _write(StringBuffer out, Object? v, int depth) {
  final pad = '  ' * (depth + 1);
  final end = '  ' * depth;
  switch (v) {
    case null:
      out.write('null');
    case bool b:
      out.write(b ? 'true' : 'false');
    case int i:
      out.write(i);
    case double d:
      out.write(_number(d));
    case String s:
      _string(out, s);
    case List l:
      if (l.isEmpty) {
        out.write('[\n\n$end]');
        return;
      }
      out.write('[\n');
      for (var i = 0; i < l.length; i++) {
        out.write(pad);
        _write(out, l[i], depth + 1);
        out.write(i < l.length - 1 ? ',\n' : '\n');
      }
      out.write('$end]');
    case Map m:
      if (m.isEmpty) {
        out.write('{\n\n$end}');
        return;
      }
      final keys = m.keys.cast<String>().toList()..sort();
      out.write('{\n');
      for (var i = 0; i < keys.length; i++) {
        out.write(pad);
        _string(out, keys[i]);
        out.write(' : ');
        _write(out, m[keys[i]], depth + 1);
        out.write(i < keys.length - 1 ? ',\n' : '\n');
      }
      out.write('$end}');
    default:
      throw ArgumentError('Nicht als JSON darstellbar: ${v.runtimeType}');
  }
}

String _number(double d) {
  if (!d.isFinite) throw ArgumentError('JSON kennt kein $d');
  if (d == d.truncateToDouble() && d.abs() < 1e15) {
    final i = d.toInt();
    return (i == 0 && d.isNegative) ? '-0' : '$i';
  }
  // Exponent zweistellig wie Swift: 1e-07
  return d.toString().replaceAllMapped(
    RegExp(r'e([+-]?)(\d)$'),
    (m) => 'e${m[1] == '+' ? '+' : m[1]}0${m[2]}',
  );
}

void _string(StringBuffer out, String s) {
  out.write('"');
  for (final c in s.runes) {
    switch (c) {
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      case 0x2f:
        out.write(r'\/');
      case 0x0a:
        out.write(r'\n');
      case 0x0d:
        out.write(r'\r');
      case 0x09:
        out.write(r'\t');
      case 0x08:
        out.write(r'\b');
      case 0x0c:
        out.write(r'\f');
      default:
        if (c < 0x20) {
          out.write('\\u${c.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.writeCharCode(c);
        }
    }
  }
  out.write('"');
}
