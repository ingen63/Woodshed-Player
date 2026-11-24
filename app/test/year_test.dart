// #141/AK1–AK3: the year of a track, read from its tag (generated test files), stored and synced.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/app/file_store_io.dart';
import 'package:woodshed_player/library/device_settings.dart';
import 'package:woodshed_player/library/metadata.dart';
import 'package:woodshed_player/library/track.dart';

import 'metadata_test.dart' show be, flac, id3, text;

/// ID3v1 tag (128 bytes) with this year field.
List<int> id3v1({String title = 'V1', String year = ''}) {
  String field(String s, int n) => s.padRight(n, '\u0000');
  return latin1.encode(
    'TAG${field(title, 30)}${field('', 30)}${field('', 30)}${field(year, 4)}'
        .padRight(128, '\u0000'),
  );
}

List<int> atom(String type, List<int> body) => [
  ...be(8 + body.length, 4),
  ...latin1.encode(type),
  ...body,
];

/// M4A with ftyp and moov/udta/meta/ilst/©day/data holding [day]; [before] goes ahead of moov.
Uint8List m4a(String? day, {List<int> before = const []}) =>
    Uint8List.fromList([
      ...atom('ftyp', [...'M4A '.codeUnits, 0, 0, 0, 0]),
      ...before,
      ...atom('moov', [
        ...atom('mvhd', List.filled(20, 0)),
        ...atom('udta', [
          ...atom('meta', [
            0, 0, 0, 0, // version and flags
            ...atom('hdlr', List.filled(25, 0)),
            ...atom('ilst', [
              ...atom(
                '©nam',
                atom('data', [0, 0, 0, 1, 0, 0, 0, 0, ...'T'.codeUnits]),
              ),
              if (day != null)
                ...atom(
                  '©day',
                  atom('data', [0, 0, 0, 1, 0, 0, 0, 0, ...utf8.encode(day)]),
                ),
            ]),
          ]),
        ]),
      ]),
      ...atom('mdat', [1, 2, 3]),
    ]);

Track track({int? year}) => Track(
  id: 'a' * 64,
  fileName: '${'a' * 64}.mp3',
  originalFileName: 'x.mp3',
  title: 'T',
  year: year,
  duration: 1,
  hasArtwork: false,
  dateAdded: DateTime.utc(2026),
  customOrder: 0,
);

void main() {
  group('#141/AK2 parseYear', () {
    test('four digits at the start', () {
      expect(parseYear('1937'), 1937);
      expect(parseYear(' 1937 '), 1937);
      expect(parseYear('1937-05-12'), 1937);
      expect(parseYear('1937-05-12T20:00:00Z'), 1937);
    });
    test('no year', () {
      expect(parseYear(null), isNull);
      expect(parseYear(''), isNull);
      expect(parseYear('37'), isNull);
      expect(parseYear('19370'), isNull);
      expect(parseYear('ca. 1937'), isNull);
      expect(parseYear('0000'), isNull);
      expect(parseYear('0001'), 1);
    });
  });

  group('#141/AK2 year from the tag', () {
    test('ID3v2.3 TYER', () {
      expect(readMetadata(id3(3, [('TYER', text(0, '1937'))])).year, 1937);
    });
    test('ID3v2.4 TDRC with a date', () {
      expect(
        readMetadata(id3(4, [('TDRC', text(3, '1937-05-12'))])).year,
        1937,
      );
    });
    test('ID3v2.2 TYE', () {
      expect(readMetadata(id3(2, [('TYE', text(0, '1940'))])).year, 1940);
    });
    test('the first year frame counts', () {
      final m = readMetadata(
        id3(3, [('TYER', text(0, '1937')), ('TDRC', text(0, '1999'))]),
      );
      expect(m.year, 1937);
    });
    test('ID3v1 without ID3v2', () {
      final file = Uint8List.fromList([
        0xff,
        0xfb,
        0x90,
        0,
        ...id3v1(year: '1928'),
      ]);
      expect(readMetadata(file).year, 1928);
    });
    test('ID3v1 fills a year missing in ID3v2, ID3v2 wins otherwise', () {
      final v1 = id3v1(year: '1928');
      expect(
        readMetadata(
          Uint8List.fromList([
            ...id3(3, [('TIT2', text(0, 'T'))]),
            ...v1,
          ]),
        ).year,
        1928,
      );
      expect(
        readMetadata(
          Uint8List.fromList([
            ...id3(3, [('TYER', text(0, '1937'))]),
            ...v1,
          ]),
        ).year,
        1937,
      );
    });
    test('ID3v1 with an empty or invalid year', () {
      expect(readMetadata(Uint8List.fromList(id3v1())).year, isNull);
      expect(
        readMetadata(Uint8List.fromList(id3v1(year: 'abcd'))).year,
        isNull,
      );
    });
    test('FLAC DATE and YEAR', () {
      expect(
        readMetadata(flac(comments: ['TITLE=T', 'DATE=1937-05-12'])).year,
        1937,
      );
      expect(readMetadata(flac(comments: ['year=1941'])).year, 1941);
    });
    test('M4A ©day', () {
      expect(readMetadata(m4a('1937')).year, 1937);
      expect(readMetadata(m4a('1937-05-12T00:00:00Z')).year, 1937);
    });
    test('M4A with a broken UTF-8 byte after the year', () {
      final file = Uint8List.fromList([
        ...atom('ftyp', 'M4A '.codeUnits),
        ...atom(
          'moov',
          atom(
            'udta',
            atom('meta', [
              0, 0, 0, 0, //
              ...atom(
                'ilst',
                atom(
                  '\u00a9day',
                  atom('data', [
                    0,
                    0,
                    0,
                    1,
                    0,
                    0,
                    0,
                    0,
                    ...'1937'.codeUnits,
                    0xff,
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ]);
      expect(readMetadata(file).year, 1937);
    });
    test('M4A: an atom of size 0 reaches to the end of its parent', () {
      final whole = m4a('1966');
      final mdat = atom('mdat', [1, 2, 3]);
      // moov (after ftyp, 16 bytes) is last and has size 0: it reaches to the end of the file
      final file = Uint8List.fromList(
        whole.sublist(0, whole.length - mdat.length),
      );
      file.setRange(16, 20, [0, 0, 0, 0]);
      expect(readMetadata(file).year, 1966);
    });
    test('M4A: an empty atom (only its header) before moov is skipped', () {
      expect(readMetadata(m4a('1971', before: atom('free', []))).year, 1971);
    });
    test('M4A without ©day, or with a free atom before moov', () {
      expect(readMetadata(m4a(null)).year, isNull);
      expect(
        readMetadata(m4a('1950', before: atom('free', [0, 0]))).year,
        1950,
      );
    });
    test('damaged M4A gives no year and no exception', () {
      final whole = m4a('1937');
      for (var n = 0; n < whole.length; n += 7) {
        expect(
          () => readMetadata(Uint8List.sublistView(whole, 0, n)),
          returnsNormally,
        );
      }
      // an atom claiming more than the file
      final broken = Uint8List.fromList(whole)..[3 + 16] = 0xff;
      expect(readMetadata(broken).year, isNull);
    });
    test('M4A with a 64-bit atom size', () {
      final day = atom(
        '©day',
        atom('data', [0, 0, 0, 1, 0, 0, 0, 0, ...'1960'.codeUnits]),
      );
      final ilst = [
        ...be(1, 4),
        ...'ilst'.codeUnits,
        ...be(16 + day.length, 8),
        ...day,
      ];
      final file = Uint8List.fromList([
        ...atom('ftyp', 'M4A '.codeUnits),
        ...atom('moov', atom('udta', atom('meta', [0, 0, 0, 0, ...ilst]))),
      ]);
      expect(readMetadata(file).year, 1960);
    });
  });

  group('#141/AK1 year of a track', () {
    test('is shared and read back', () {
      final t = track(year: 1937);
      expect(t.toShared()['year'], 1937);
      expect(Track.fromShared(t.id, t.toShared()).year, 1937);
    });
    test('an unknown year is not a shared field (no stamp that wins over another device)', () {
      expect(track().toShared().containsKey('year'), isFalse);
      expect(Track.fromShared('a' * 64, track().toShared()).year, isNull);
    });
    test('an older record without year or with a wrong value', () {
      final shared = track().toShared();
      expect(
        Track.fromShared('a' * 64, {...shared, 'year': '1937'}).year,
        isNull,
      );
      expect(Track.fromShared('a' * 64, {...shared, 'year': 0}).year, isNull);
      expect(
        Track.fromShared('a' * 64, {...shared, 'year': 10000}).year,
        isNull,
      );
      expect(Track.fromShared('a' * 64, {...shared, 'year': 9999}).year, 9999);
    });
    test('copyWith keeps, sets and clears the year', () {
      final t = track(year: 1937);
      expect(t.copyWith(title: 'U').year, 1937);
      expect(t.copyWith(year: () => 1940).year, 1940);
      expect(t.copyWith(year: () => null).year, isNull);
    });
    test('a trimmed track keeps its year', () {
      final t = track(year: 1937).trimmed(
        id: 'b' * 64,
        fileName: 'b.mp3',
        start: 0,
        duration: 1,
        hasArtwork: false,
      );
      expect(t.year, 1937);
    });
  });

  test('#141/AK3 device.json reads yearsRead back', () async {
    final dir = Directory.systemTemp.createTempSync('wp_years');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = IoFileStore(dir);
    Future<bool> load(Object? value) async {
      File('${dir.path}/device.json').writeAsStringSync(
        jsonEncode({'deviceId': '0123456789abcdef', 'yearsRead': ?value}),
      );
      return (await DeviceSettings.load(store)).yearsRead;
    }

    expect(await load(true), isTrue);
    expect(await load(null), isFalse);
    expect(await load(false), isFalse);
    expect(await load('true'), isFalse);
  });

  test('#141/AK3 device.json keeps yearsRead', () {
    const d = DeviceSettings(deviceId: '0123456789abcdef');
    expect(d.toJson().containsKey('yearsRead'), isFalse);
    expect(d.copyWith(yearsRead: true).toJson()['yearsRead'], isTrue);
    expect(d.copyWith(yearsRead: true).copyWith(area: 'x').yearsRead, isTrue);
  });
}
