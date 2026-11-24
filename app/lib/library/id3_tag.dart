// ID3 tags of the MP3 export (#141/AK8, AK9): writes an ID3v2.3 tag and takes the tags off an MP3 file
// so that only its MPEG frames remain. ID3v2.3 with UTF-16 is what Finder, Music and other programs
// read most widely; the year goes into TYER, which they show as «Year».
import 'dart:convert';
import 'dart:typed_data';

/// ID3v2.3 tag with the fields that are set (empty ones are left out); no padding.
Uint8List id3v2Tag({String? title, String? artist, String? album, int? year}) {
  final frames = BytesBuilder(copy: false);
  void frame(String id, String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return;
    // encoding 1: UTF-16 with byte order mark (little endian), no terminator
    final data = <int>[1, 0xff, 0xfe];
    for (final unit in v.codeUnits) {
      data
        ..add(unit & 0xff)
        ..add(unit >> 8);
    }
    frames
      ..add(ascii.encode(id))
      ..add(_be32(data.length))
      ..add(const [0, 0])
      ..add(data);
  }

  frame('TIT2', title);
  frame('TPE1', artist);
  frame('TALB', album);
  frame('TYER', year?.toString().padLeft(4, '0'));
  final body = frames.toBytes();
  return Uint8List.fromList([
    ...ascii.encode('ID3'),
    3, 0, // version 2.3.0
    0, // no flags
    ..._syncsafe(body.length),
    ...body,
  ]);
}

/// #141/AK9: the MPEG frames of an MP3 file without its tags: ID3v2 at the start (also several, and a
/// v2.4 footer), ID3v1 and APEv2 at the end. The audio stays byte for byte.
Uint8List mp3Frames(Uint8List b) {
  var start = 0;
  while (start + 10 <= b.length &&
      b[start] == 0x49 && // I
      b[start + 1] == 0x44 && // D
      b[start + 2] == 0x33) {
    final size =
        (b[start + 6] & 0x7f) << 21 |
        (b[start + 7] & 0x7f) << 14 |
        (b[start + 8] & 0x7f) << 7 |
        (b[start + 9] & 0x7f);
    final footer = b[start + 3] == 4 && b[start + 5] & 0x10 != 0 ? 10 : 0;
    final next = start + 10 + size + footer;
    if (next > b.length) break;
    start = next;
  }
  var end = b.length;
  // [s] at [pos]; the callers make sure it lies within start … end
  bool at(int pos, String s) {
    for (var i = 0; i < s.length; i++) {
      if (b[pos + i] != s.codeUnitAt(i)) return false;
    }
    return true;
  }

  // ID3v1 and APEv2 may come in either order
  for (;;) {
    if (end - 128 >= start && at(end - 128, 'TAG')) {
      end -= 128;
      continue;
    }
    if (end - 32 >= start && at(end - 32, 'APETAGEX')) {
      final p = end - 32;
      // footer: size of the tag (items and footer), flags bit 31: there is a header as well
      final size =
          b[p + 12] | b[p + 13] << 8 | b[p + 14] << 16 | b[p + 15] << 24;
      final total = size + (b[p + 23] & 0x80 != 0 ? 32 : 0);
      if (total >= 32 && end - total >= start) {
        end -= total;
        continue;
      }
    }
    break;
  }
  return Uint8List.sublistView(b, start, end);
}

List<int> _be32(int v) => [
  v >> 24 & 0xff,
  v >> 16 & 0xff,
  v >> 8 & 0xff,
  v & 0xff,
];

List<int> _syncsafe(int v) => [
  v >> 21 & 0x7f,
  v >> 14 & 0x7f,
  v >> 7 & 0x7f,
  v & 0x7f,
];
