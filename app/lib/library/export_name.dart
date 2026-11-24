// File names of the export (#141/AK5–AK7). Pure functions, without the file system.

/// #141/AK5, AK6: «Title - Artist - Year»; a missing artist or year drops out with its « - ». Characters a
/// file name may not hold (`/`, `:`, `\`, control characters) become `-`; spaces around the parts and
/// the name go.
String exportBaseName(String title, String? artist, int? year) {
  String clean(String s) =>
      s.replaceAll(RegExp(r'[/:\\\x00-\x1f\x7f]'), '-').trim();
  final parts = [
    clean(title),
    clean(artist ?? ''),
    if (year != null) year.toString().padLeft(4, '0'),
  ].where((p) => p.isNotEmpty);
  return parts.join(' - ');
}

/// #141/AK7: «[base].[ext]», or «[base] (2).[ext]», «[base] (3).[ext]» … if [taken] says the name is used
/// (in the target folder or earlier in the same export). Upper and lower case do not count for [taken]:
/// the folders of macOS do not tell them apart.
String uniqueExportName(
  String base,
  bool Function(String name) taken, {
  String ext = 'mp3',
}) {
  var name = '$base.$ext';
  for (var n = 2; taken(name); n++) {
    name = '$base ($n).$ext';
  }
  return name;
}
