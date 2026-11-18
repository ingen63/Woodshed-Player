// #16/AK4: Titel, Künstler, Album und Cover aus ID3, FLAC und WAV. Testdateien werden hier gebaut.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/metadata.dart';

final cover = Uint8List.fromList([0xff, 0xd8, 0xff, 0x00, 1, 2, 3, 0xff, 0xd9]);
final backCover = Uint8List.fromList([9, 9, 9]);

List<int> syncsafe(int v) => [
  v >> 21 & 0x7f,
  v >> 14 & 0x7f,
  v >> 7 & 0x7f,
  v & 0x7f,
];
List<int> be(int v, int n) => [
  for (var i = n - 1; i >= 0; i--) v >> (8 * i) & 0xff,
];
List<int> le32(int v) => [v & 255, v >> 8 & 255, v >> 16 & 255, v >> 24 & 255];

List<int> utf16le(String s) => [
  0xff,
  0xfe,
  for (final c in s.codeUnits) ...[c & 0xff, c >> 8],
];

/// ID3v2-Tag; frames als (id, daten).
Uint8List id3(
  int major,
  List<(String, List<int>)> frames, {
  bool unsync = false,
  int padding = 20,
}) {
  final body = <int>[];
  for (final (id, data) in frames) {
    var d = data;
    var flags = 0;
    if (unsync && major == 4) {
      d = _unsync(d);
      flags = 0x02;
    }
    body
      ..addAll(id.codeUnits)
      ..addAll(switch (major) {
        2 => be(d.length, 3),
        3 => be(d.length, 4),
        _ => syncsafe(d.length),
      });
    if (major > 2) body.addAll([0, flags]);
    body.addAll(d);
  }
  var tag = [...body, ...List.filled(padding, 0)];
  if (unsync && major == 3) tag = _unsync(tag);
  return Uint8List.fromList([
    ...'ID3'.codeUnits,
    major,
    0,
    unsync && major == 3 ? 0x80 : 0,
    ...syncsafe(tag.length),
    ...tag,
    // danach MP3-Daten
    0xff, 0xfb, 0x90, 0x00,
  ]);
}

List<int> _unsync(List<int> d) {
  final out = <int>[];
  for (var i = 0; i < d.length; i++) {
    out.add(d[i]);
    if (d[i] == 0xff &&
        (i + 1 == d.length || d[i + 1] == 0 || d[i + 1] & 0xe0 == 0xe0)) {
      out.add(0);
    }
  }
  return out;
}

List<int> text(int enc, String s) => [
  enc,
  ...switch (enc) {
    0 => latin1.encode(s),
    1 => utf16le(s),
    _ => utf8.encode(s),
  },
];

List<int> apic(int type, Uint8List data, {int enc = 0}) => [
  enc,
  ...'image/jpeg'.codeUnits,
  0,
  type,
  ...(enc == 1 ? [...utf16le('Bild'), 0, 0] : [...'Bild'.codeUnits, 0]),
  ...data,
];

Uint8List flac({
  List<String> comments = const [],
  List<(int, Uint8List)> pictures = const [],
}) {
  final blocks = <List<int>>[];
  blocks.add([0, ...be(34, 3), ...List.filled(34, 0)]); // STREAMINFO
  final vendor = utf8.encode('Testencoder');
  final vc = [...le32(vendor.length), ...vendor, ...le32(comments.length)];
  for (final c in comments) {
    final b = utf8.encode(c);
    vc.addAll([...le32(b.length), ...b]);
  }
  blocks.add([4, ...be(vc.length, 3), ...vc]);
  for (final (type, data) in pictures) {
    final mime = 'image/jpeg'.codeUnits;
    final pic = [
      ...be(type, 4),
      ...be(mime.length, 4),
      ...mime,
      ...be(0, 4),
      ...List.filled(16, 0),
      ...be(data.length, 4),
      ...data,
    ];
    blocks.add([6, ...be(pic.length, 3), ...pic]);
  }
  blocks.last[0] |= 0x80;
  return Uint8List.fromList(
    [
      'fLaC'.codeUnits,
      ...blocks,
      [0xff, 0xf8],
    ].expand((e) => e).toList(),
  );
}

void main() {
  test('ID3v2.3 mit UTF-16, Vorderseite bevorzugt', () {
    final m = readMetadata(
      id3(3, [
        ('TIT2', text(1, 'Übung Nr. 1')),
        ('TPE1', text(1, 'Testband')),
        ('TALB', text(0, 'Testalbum')),
        ('APIC', apic(4, backCover, enc: 1)),
        ('APIC', apic(3, cover, enc: 1)),
      ]),
    );
    expect(m.title, 'Übung Nr. 1');
    expect(m.artist, 'Testband');
    expect(m.album, 'Testalbum');
    expect(m.artwork, cover);
  });

  test(
    'ID3v2.4 mit UTF-8, Synchsafe-Grössen, mehrere Werte und Unsynchronisation',
    () {
      final long = 'L' * 200; // > 127 Bytes: Synchsafe-Grösse nötig
      final m = readMetadata(
        id3(4, [
          ('TIT2', text(3, '$long\u0000Zweitwert')),
          ('TPE1', text(3, 'Bänd')),
          ('APIC', apic(0, cover)),
        ], unsync: true),
      );
      expect(m.title, long);
      expect(m.artist, 'Bänd');
      expect(m.artwork, cover);
    },
  );

  test('ID3v2.3 mit Unsynchronisation des ganzen Tags', () {
    final m = readMetadata(
      id3(3, [('TIT2', text(0, 'A')), ('APIC', apic(3, cover))], unsync: true),
    );
    expect(m.title, 'A');
    expect(m.artwork, cover);
  });

  test('ID3v2.2 (TT2, TP1, PIC)', () {
    final m = readMetadata(
      id3(2, [
        ('TT2', text(0, 'Alt')),
        ('TP1', text(0, 'Künstler')),
        ('PIC', [0, ...'JPG'.codeUnits, 3, 0, ...cover]),
      ]),
    );
    expect(m.title, 'Alt');
    expect(m.artist, 'Künstler');
    expect(m.artwork, cover);
  });

  test('ID3v1 am Dateiende ergänzt fehlende Felder', () {
    String field(String s) => s.padRight(30, '\u0000');
    final v1 = latin1.encode(
      'TAG${field('V1 Titel')}${field('V1 Band')}${field('V1 Album')}'.padRight(
        128,
        '\u0000',
      ),
    );
    final file = Uint8List.fromList([
      ...id3(3, [('TIT2', text(0, 'V2 Titel'))]),
      ...List.filled(100, 0),
      ...v1,
    ]);
    final m = readMetadata(file);
    expect(m.title, 'V2 Titel');
    expect(m.artist, 'V1 Band');
    expect(m.album, 'V1 Album');
  });

  test('FLAC: Vorbis-Kommentare und PICTURE', () {
    final m = readMetadata(
      flac(
        comments: ['title=Sinus', 'ARTIST=Testband', 'Album=Tests', 'kaputt'],
        pictures: [(4, backCover), (3, cover)],
      ),
    );
    expect(m.title, 'Sinus');
    expect(m.artist, 'Testband');
    expect(m.album, 'Tests');
    expect(m.artwork, cover);
  });

  test('FLAC mit vorangestelltem ID3', () {
    final tag = id3(3, [('TPE1', text(0, 'Aus ID3'))]);
    final file = Uint8List.fromList([
      ...tag.sublist(0, tag.length - 4),
      ...flac(comments: ['TITLE=Aus FLAC']),
    ]);
    final m = readMetadata(file);
    expect(m.title, 'Aus FLAC');
    expect(m.artist, 'Aus ID3');
  });

  test('ohne Angaben oder Unsinn: leer, keine Ausnahme', () {
    expect(readMetadata(Uint8List(0)).isEmpty, isTrue);
    expect(
      readMetadata(Uint8List.fromList(List.generate(500, (i) => i * 7 & 255)))
          .isEmpty,
      isTrue,
    );
    // abgeschnittenes Tag
    final cut = id3(3, [('TIT2', text(0, 'Abgeschnitten'))]);
    expect(
      () => readMetadata(Uint8List.sublistView(cut, 0, 15)),
      returnsNormally,
    );
    // abgeschnittenes FLAC
    final f = flac(comments: ['TITLE=x'], pictures: [(3, cover)]);
    expect(
      () => readMetadata(Uint8List.sublistView(f, 0, f.length - 8)),
      returnsNormally,
    );
  });
}
