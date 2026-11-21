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

/// ID3v2 tag with exactly these bytes after the header (frames written by hand).
Uint8List rawId3(int major, List<int> body, {int flags = 0}) =>
    Uint8List.fromList([
      ...'ID3'.codeUnits,
      major,
      0,
      flags,
      ...syncsafe(body.length),
      ...body,
    ]);

/// One ID3v2.3/2.4 frame with these format flags (second flag byte).
List<int> frame(int major, String id, List<int> data, {int flags = 0}) => [
  ...id.codeUnits,
  ...(major == 4 ? syncsafe(data.length) : be(data.length, 4)),
  0,
  flags,
  ...data,
];

/// RIFF/WAVE file with these chunks (id, data); odd chunks get a pad byte.
Uint8List wav(List<(String, List<int>)> chunks, {String form = 'WAVE'}) {
  final body = <int>[...form.codeUnits];
  for (final (id, data) in chunks) {
    body.addAll([...id.codeUnits, ...le32(data.length), ...data]);
    if (data.length.isOdd) body.add(0);
  }
  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ...le32(body.length),
    ...body,
  ]);
}

/// LIST/INFO data with these sub-chunks (id, raw value); odd values get a pad byte.
List<int> info(List<(String, List<int>)> entries) => [
  ...'INFO'.codeUnits,
  for (final (id, v) in entries) ...[
    ...id.codeUnits,
    ...le32(v.length),
    ...v,
    if (v.length.isOdd) 0,
  ],
];

List<int> fmtChunk() => [
  1,
  0,
  1,
  0,
  ...le32(8000),
  ...le32(16000),
  2,
  0,
  16,
  0,
];

/// FLAC PICTURE block data.
List<int> flacPicture(int type, List<int> data, {String desc = ''}) {
  final mime = 'image/jpeg'.codeUnits;
  final d = utf8.encode(desc);
  return [
    ...be(type, 4),
    ...be(mime.length, 4),
    ...mime,
    ...be(d.length, 4),
    ...d,
    ...List.filled(16, 0),
    ...be(data.length, 4),
    ...data,
  ];
}

/// Vorbis comment block data; [count] defaults to the number of [comments].
List<int> vorbis(List<List<int>> comments, {int? count}) {
  final vendor = utf8.encode('Testencoder');
  return [
    ...le32(vendor.length),
    ...vendor,
    ...le32(count ?? comments.length),
    for (final c in comments) ...[...le32(c.length), ...c],
  ];
}

/// FLAC from raw blocks (type, data); [lastFlag] marks the last block.
Uint8List rawFlac(
  List<(int, List<int>)> blocks, {
  bool lastFlag = true,
  List<int> tail = const [],
}) => Uint8List.fromList([
  ...'fLaC'.codeUnits,
  for (var i = 0; i < blocks.length; i++) ...[
    blocks[i].$1 | (lastFlag && i == blocks.length - 1 ? 0x80 : 0),
    ...be(blocks[i].$2.length, 3),
    ...blocks[i].$2,
  ],
  ...tail,
]);

List<int> utf16be(String s) => [
  for (final c in s.codeUnits) ...[c >> 8, c & 0xff],
];
List<int> utf16leRaw(String s) => [
  for (final c in s.codeUnits) ...[c & 0xff, c >> 8],
];

/// Title of an ID3v2.3 tag with one TIT2 frame holding [data] (encoding byte first).
String? id3Title(List<int> data) =>
    readMetadata(rawId3(3, frame(3, 'TIT2', data))).title;

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

  // #61: one rule per test, found by mutation testing (make mutants).
  group('#16/AK4 metadata: general rules (#61)', () {
    test('metadata is empty only without any field', () {
      expect(const TrackMetadata().isEmpty, isTrue);
      expect(const TrackMetadata(title: 't').isEmpty, isFalse);
      expect(const TrackMetadata(artist: 'a').isEmpty, isFalse);
      expect(const TrackMetadata(album: 'b').isEmpty, isFalse);
      expect(TrackMetadata(artwork: cover).isEmpty, isFalse);
    });

    test('a RIFF file that is not WAVE is read for ID3v1 like any file', () {
      String field(String s) => s.padRight(30, '\u0000');
      final v1 = latin1.encode('TAG${field('V1')}'.padRight(128, '\u0000'));
      final file = Uint8List.fromList([
        ...wav([('data', List.filled(20, 1))], form: 'AVI '),
        ...v1,
      ]);
      expect(readMetadata(file).title, 'V1');
    });

    test('a file of exactly 128 bytes can be an ID3v1 tag', () {
      final v1 = latin1.encode(
        'TAG${'Kurz'.padRight(30, ' ')}'.padRight(128, ' '),
      );
      expect(v1.length, 128);
      expect(readMetadata(Uint8List.fromList(v1)).title, 'Kurz');
    });
  });

  group('#16/AK4 ID3v2 text encodings (#61)', () {
    test('UTF-16 with little-endian BOM', () {
      expect(id3Title([1, 0xff, 0xfe, ...utf16leRaw('Ab')]), 'Ab');
    });

    test('UTF-16 with big-endian BOM', () {
      expect(id3Title([1, 0xfe, 0xff, ...utf16be('Ab')]), 'Ab');
    });

    test('encoding 1 without BOM is little endian', () {
      expect(id3Title([1, ...utf16leRaw('Ab')]), 'Ab');
      // first character U+FF41: bytes 0x41 0xff, not a big-endian BOM
      expect(id3Title([1, ...utf16leRaw('ａb')]), 'ａb');
      // first character þ: bytes 0xfe 0x00, not a big-endian BOM
      expect(id3Title([1, ...utf16leRaw('þb')]), 'þb');
      // first character ÿ: bytes 0xff 0x00, not a little-endian BOM
      expect(id3Title([1, ...utf16leRaw('ÿb')]), 'ÿb');
    });

    test('encoding 2 is big endian; a BOM overrides it', () {
      expect(id3Title([2, ...utf16be('Ab')]), 'Ab');
      // first character þ: bytes 0x00 0xfe, not a little-endian BOM
      expect(id3Title([2, ...utf16be('þb')]), 'þb');
      expect(id3Title([2, 0xff, 0xfe, ...utf16leRaw('Ab')]), 'Ab');
    });

    test('a UTF-16 text that is only a BOM is empty', () {
      expect(id3Title([1, 0xfe, 0xff]), isNull);
      expect(id3Title([1, 0xff, 0xfe]), isNull);
      expect(id3Title([2, 0xff, 0xfe]), isNull);
    });

    test('an odd trailing byte of UTF-16 is ignored', () {
      expect(id3Title([1, 0xff, 0xfe, ...utf16leRaw('Ab'), 0x00]), 'Ab');
    });

    test('UTF-16 ends at a double zero on a character boundary', () {
      // Ā is 0x00 0x01 in little endian: its zero byte is no terminator
      expect(
        id3Title([1, 0xff, 0xfe, ...utf16leRaw('Ā'), 0, 0, ...utf16leRaw('B')]),
        'Ā',
      );
    });

    test('broken UTF-8 is read with replacement characters', () {
      expect(id3Title([3, 0x41, 0xc3]), 'A�');
    });
  });

  group('#16/AK4 ID3v2 structure (#61)', () {
    test('versions other than 2.2 to 2.4 are not read', () {
      final body = frame(4, 'TIT2', text(0, 'Neu'));
      expect(readMetadata(rawId3(5, body)).title, isNull);
      expect(readMetadata(rawId3(4, body)).title, 'Neu');
    });

    test('the last frame may end exactly at the end of the tag', () {
      for (final major in [2, 3, 4]) {
        final m = readMetadata(
          id3(major, [
            (major == 2 ? 'TT2' : 'TIT2', text(0, 'T')),
            (major == 2 ? 'TAL' : 'TALB', text(0, 'Ende')),
          ], padding: 0),
        );
        expect(m.title, 'T', reason: 'v2.$major');
        expect(m.album, 'Ende', reason: 'v2.$major');
      }
    });

    test('a frame larger than the tag ends reading; earlier frames stay', () {
      final body = [
        ...frame(3, 'TIT2', text(0, 'Davor')),
        ...'TPE1'.codeUnits,
        ...be(1000, 4),
        0,
        0,
        0,
        ...'x'.codeUnits,
      ];
      final m = readMetadata(rawId3(3, body));
      expect(m.title, 'Davor');
      expect(m.artist, isNull);
    });

    test('a frame of size 0 ends reading like padding', () {
      final body = [
        ...frame(3, 'TPE1', []),
        ...frame(3, 'TIT2', text(0, 'Danach')),
      ];
      expect(readMetadata(rawId3(3, body)).title, isNull);
    });

    test('v2.3: the extended header is skipped', () {
      final ext = [...be(6, 4), ...List.filled(6, 0)];
      final m = readMetadata(
        rawId3(3, [...ext, ...frame(3, 'TIT2', text(0, 'Erw'))], flags: 0x40),
      );
      expect(m.title, 'Erw');
    });

    test('v2.4: the extended header is skipped (size includes itself)', () {
      final ext = [...syncsafe(6), 1, 0];
      final m = readMetadata(
        rawId3(4, [...ext, ...frame(4, 'TIT2', text(0, 'Erw4'))], flags: 0x40),
      );
      expect(m.title, 'Erw4');
    });

    test('v2.4 unsynchronises per frame, never the whole tag', () {
      // header flag set, frame without its unsync flag: data stays as it is
      final m = readMetadata(
        rawId3(4, frame(4, 'APIC', apic(3, cover)), flags: 0x80),
      );
      expect(m.artwork, cover);
    });

    test('v2.4 per-frame unsync: 0xff 0x00 inside and 0xff at the end', () {
      final data = [0, 0x41, 0xff, 0x00, 0x42, 0xff];
      final m = readMetadata(rawId3(4, frame(4, 'TIT2', data, flags: 0x02)));
      expect(m.title, 'AÿBÿ');
    });

    test('v2.4: a data length indicator is skipped', () {
      final data = [...syncsafe(2), ...text(0, 'L')];
      final m = readMetadata(rawId3(4, frame(4, 'TIT2', data, flags: 0x01)));
      expect(m.title, 'L');
    });

    test('compressed or encrypted frames are skipped', () {
      for (final (major, flags) in [
        (3, 0x80),
        (3, 0x40),
        (4, 0x08),
        (4, 0x04),
      ]) {
        final body = [
          ...frame(major, 'TIT2', text(0, 'Gepackt'), flags: flags),
          ...frame(major, 'TIT2', text(0, 'Klar')),
        ];
        expect(
          readMetadata(rawId3(major, body)).title,
          'Klar',
          reason: 'v2.$major flags $flags',
        );
      }
    });
  });

  group('#16/AK4 ID3v2 pictures (#61)', () {
    test('of two front covers the first one wins', () {
      final m = readMetadata(
        id3(3, [('APIC', apic(3, cover)), ('APIC', apic(3, backCover))]),
      );
      expect(m.artwork, cover);
    });

    test('without a front cover the first picture wins', () {
      final m = readMetadata(
        id3(3, [('APIC', apic(4, cover)), ('APIC', apic(5, backCover))]),
      );
      expect(m.artwork, cover);
    });

    test('a front cover after it replaces another picture', () {
      final m = readMetadata(
        id3(3, [('APIC', apic(4, backCover)), ('APIC', apic(3, cover))]),
      );
      expect(m.artwork, cover);
    });

    test('a broken picture frame is skipped, other frames stay', () {
      for (final broken in [
        [0, ...'image'.codeUnits], // MIME type without end
        [0, ...'image/jpeg'.codeUnits, 0], // no picture type
        [0, ...'image/jpeg'.codeUnits, 0, 3, ...'Bild'.codeUnits, 0], // no data
      ]) {
        final m = readMetadata(
          id3(3, [('TIT2', text(0, 'Mit')), ('APIC', broken)]),
        );
        expect(m.title, 'Mit', reason: '$broken');
        expect(m.artwork, isNull, reason: '$broken');
      }
    });
  });

  group('#16/AK4 FLAC (#61)', () {
    test('the last block may end exactly at the end of the file', () {
      final f = rawFlac([
        (0, List.filled(34, 0)),
        (4, vorbis([utf8.encode('TITLE=Ende')])),
      ]);
      expect(readMetadata(f).title, 'Ende');
    });

    test(
      'without the last-block flag reading stops at the end of the file',
      () {
        final f = rawFlac([
          (0, List.filled(34, 0)),
          (4, vorbis([utf8.encode('TITLE=Offen')])),
        ], lastFlag: false);
        expect(readMetadata(f).title, 'Offen');
      },
    );

    test('a block larger than the file ends reading; earlier blocks stay', () {
      final f = Uint8List.fromList([
        ...rawFlac([
          (0, List.filled(34, 0)),
          (4, vorbis([utf8.encode('TITLE=Davor')])),
        ], lastFlag: false),
        6,
        ...be(5000, 3),
        ...List.filled(12, 0xff),
      ]);
      final m = readMetadata(f);
      expect(m.title, 'Davor');
      expect(m.artwork, isNull);
    });

    test('only as many comments as the block says are read', () {
      final f = rawFlac([
        (
          4,
          vorbis([
            utf8.encode('TITLE=Eins'),
            utf8.encode('ARTIST=Zwei'),
          ], count: 1),
        ),
      ]);
      final m = readMetadata(f);
      expect(m.title, 'Eins');
      expect(m.artist, isNull);
    });

    test('a comment count beyond the block stops at its end', () {
      final f = rawFlac([
        (4, vorbis([utf8.encode('TITLE=Eins')], count: 9)),
        (6, flacPicture(3, cover)),
      ]);
      final m = readMetadata(f);
      expect(m.title, 'Eins');
      expect(m.artwork, cover);
    });

    test('broken UTF-8 in a comment is read with replacement characters', () {
      final f = rawFlac([
        (
          4,
          vorbis([
            [...utf8.encode('TITLE=A'), 0xc3],
          ]),
        ),
      ]);
      expect(readMetadata(f).title, 'A�');
    });

    test('a picture with a description', () {
      final f = rawFlac([(6, flacPicture(3, cover, desc: 'Vorderseite'))]);
      expect(readMetadata(f).artwork, cover);
    });

    test('a single picture that is not the front cover is taken', () {
      final f = rawFlac([(6, flacPicture(4, backCover))]);
      expect(readMetadata(f).artwork, backCover);
    });

    test('of two pictures without front cover the first one wins', () {
      final f = rawFlac([
        (6, flacPicture(4, cover)),
        (6, flacPicture(5, backCover)),
      ]);
      expect(readMetadata(f).artwork, cover);
    });

    test('picture data longer than its block is not taken', () {
      final pic = flacPicture(3, cover);
      // data length field claims 100 bytes more than the block holds
      final lenAt = pic.length - cover.length - 4;
      pic.replaceRange(lenAt, lenAt + 4, be(cover.length + 100, 4));
      final f = rawFlac([
        (6, pic),
        (4, vorbis([utf8.encode('TITLE=${'x' * 200}')])),
      ]);
      final m = readMetadata(f);
      expect(m.artwork, isNull);
      expect(m.title, 'x' * 200);
    });
  });

  group('#16/AK4 WAV (#61)', () {
    test('LIST/INFO: INAM, IART and IPRD', () {
      final m = readMetadata(
        wav([
          ('fmt ', fmtChunk()),
          (
            'LIST',
            info([
              ('INAM', utf8.encode('Titel')),
              ('IART', utf8.encode('Band')),
              ('IPRD', utf8.encode('Album')),
            ]),
          ),
        ]),
      );
      expect(m.title, 'Titel');
      expect(m.artist, 'Band');
      expect(m.album, 'Album');
    });

    test('odd values and chunks are followed by a pad byte', () {
      final m = readMetadata(
        wav([
          ('junk', [1, 2, 3]),
          (
            'LIST',
            info([('INAM', utf8.encode('abc')), ('IART', utf8.encode('Band'))]),
          ),
          ('data', List.filled(4, 0)),
        ]),
      );
      expect(m.title, 'abc');
      expect(m.artist, 'Band');
    });

    test('a value reaching past its list is empty, earlier ones stay', () {
      final list = info([('INAM', utf8.encode('Gut'))]);
      // 10 bytes claimed, 4 there; the next chunk follows the list
      list.addAll([...'IART'.codeUnits, ...le32(10), ...'Band'.codeUnits]);
      final m = readMetadata(
        wav([('LIST', list), ('data', List.filled(16, 0x41))]),
      );
      expect(m.title, 'Gut');
      expect(m.artist, isNull);
    });

    test('broken UTF-8 in a value is read with replacement characters', () {
      final m = readMetadata(
        wav([
          (
            'LIST',
            info([
              ('INAM', [0x41, 0xc3]),
            ]),
          ),
        ]),
      );
      expect(m.title, 'A�');
    });

    test('a LIST that is not INFO is not read', () {
      final adtl = [
        ...'adtl'.codeUnits,
        ...info([('INAM', utf8.encode('X'))]).sublist(4),
      ];
      expect(readMetadata(wav([('LIST', adtl)])).title, isNull);
    });

    test('the first INFO list wins', () {
      final m = readMetadata(
        wav([
          ('LIST', info([('INAM', utf8.encode('Erste'))])),
          (
            'LIST',
            info([('INAM', utf8.encode('Zweite')), ('IART', utf8.encode('B'))]),
          ),
        ]),
      );
      expect(m.title, 'Erste');
      expect(m.artist, 'B');
    });

    test('an id3 chunk (either case) is read and wins over INFO', () {
      for (final id in ['id3 ', 'ID3 ']) {
        final tag = id3(3, [('TIT2', text(0, 'Aus ID3'))]);
        final m = readMetadata(
          wav([
            (
              'LIST',
              info([
                ('INAM', utf8.encode('Aus INFO')),
                ('IART', utf8.encode('Band')),
              ]),
            ),
            (id, tag),
          ]),
        );
        expect(m.title, 'Aus ID3', reason: id);
        expect(m.artist, 'Band', reason: id);
      }
    });

    test('an id3 chunk too short for the ID3 mark is ignored', () {
      final m = readMetadata(
        wav([
          ('LIST', info([('INAM', utf8.encode('Bleibt'))])),
          ('id3 ', 'ID'.codeUnits),
        ]),
      );
      expect(m.title, 'Bleibt');
    });

    test('an id3 chunk without an ID3 tag is ignored', () {
      final m = readMetadata(
        wav([
          ('LIST', info([('INAM', utf8.encode('Bleibt'))])),
          ('id3 ', [1, 2, 3, 4]),
        ]),
      );
      expect(m.title, 'Bleibt');
    });

    test('a chunk named like an id3 chunk only counts with its name', () {
      final tag = id3(3, [('TIT2', text(0, 'Versteckt'))]);
      expect(readMetadata(wav([('junk', tag)])).title, isNull);
    });
  });

  group('#91 damaged block at the end keeps the fields read so far', () {
    test('#91/AK1 WAV: a damaged or cut id3 chunk keeps LIST/INFO', () {
      final tag = id3(3, [('TIT2', text(0, 'Aus ID3'))]);
      final broken = <List<int>>[
        'ID3'.codeUnits, // only the mark
        [...'ID3'.codeUnits, 3, 0], // header cut before the flags
        rawId3(3, [0, 0], flags: 0x40), // extended header beyond the tag
        for (var n = 3; n < 13; n++) tag.sublist(0, n), // header cut
      ];
      for (final chunk in broken) {
        for (final pad in [false, true]) {
          // Without pad the chunk ends exactly at the end of the file.
          final f = wav([
            (
              'LIST',
              info([
                ('INAM', utf8.encode('Aus INFO')),
                ('IART', utf8.encode('Band')),
              ]),
            ),
            ('id3 ', chunk),
          ]);
          final bytes = chunk.length.isOdd && !pad
              ? Uint8List.sublistView(f, 0, f.length - 1)
              : f;
          final m = readMetadata(bytes);
          expect(m.title, 'Aus INFO', reason: '$chunk pad $pad');
          expect(m.artist, 'Band', reason: '$chunk pad $pad');
        }
      }
    });

    test('#91/AK1 WAV: chunks after a damaged id3 chunk are still read', () {
      final m = readMetadata(
        wav([
          ('id3 ', 'ID3'.codeUnits),
          ('LIST', info([('INAM', utf8.encode('Danach'))])),
        ]),
      );
      expect(m.title, 'Danach');
    });

    test('#91/AK2 FLAC: an empty last comment or picture block header at '
        'the end keeps earlier blocks', () {
      for (final type in [4, 6]) {
        final f = rawFlac(
          [
            (0, List.filled(34, 0)),
            (4, vorbis([utf8.encode('TITLE=Davor')])),
            (6, flacPicture(3, cover)),
          ],
          lastFlag: false,
          tail: [type | 0x80, 0, 0, 0],
        );
        final m = readMetadata(f);
        expect(m.title, 'Davor', reason: 'type $type');
        expect(m.artwork, cover, reason: 'type $type');
      }
    });

    test('#91/AK2 FLAC: a damaged comment block keeps the entries before', () {
      final comments = vorbis([
        utf8.encode('TITLE=Erste'),
        utf8.encode('ARTIST=Band'),
      ]);
      // The second entry claims more bytes than the file holds.
      final f = rawFlac([
        (0, List.filled(34, 0)),
        (6, flacPicture(3, cover)),
        (4, [...comments.sublist(0, comments.length - 15), ...le32(9999)]),
      ]);
      final m = readMetadata(f);
      expect(m.title, 'Erste');
      expect(m.artist, isNull);
      expect(m.artwork, cover);
    });
  });
}
