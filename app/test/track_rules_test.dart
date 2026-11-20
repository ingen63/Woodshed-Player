// #61: rules of the track model (track.dart), one per test; found by mutation testing (make mutants).
// Imports the library like the other tests of the model, so the mutation tool picks them all.
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/library.dart';

const _hash =
    '0000000000000000000000000000000000000000000000000000000000000001';

Track _track({String? loopId, Map<String, LoopRange?> loops = const {}}) =>
    Track(
      id: _hash,
      fileName: '$_hash.mp3',
      originalFileName: 'a.mp3',
      title: 'A',
      duration: 60,
      hasArtwork: false,
      dateAdded: DateTime.utc(2026),
      customOrder: 0,
      loopId: loopId,
      loops: loops,
    );

void main() {
  group('#37/AK4 loops of a track', () {
    test('moving the bounds of the active loop keeps its ID', () {
      final t = _track(loopId: '0', loops: {'0': const LoopRange(1, 5)});
      final n = t.withSettings(
        const PlaybackSettings(loopEnabled: true, loopStart: 2, loopEnd: 8),
        () => 'neu',
      );
      expect(n.loopId, '0');
      expect(n.loops.keys, ['0']);
    });

    test('setting a loop where there was none creates one with a new ID', () {
      final n = _track().withSettings(
        const PlaybackSettings(loopEnabled: true, loopStart: 2, loopEnd: 8),
        () => 'neu',
      );
      expect(n.loopId, 'neu');
      expect(n.loops, {'neu': const LoopRange(2, 8)});
    });

    test('a loop range needs a number for start and for end', () {
      expect(LoopRange.fromJson({'start': 1, 'end': 2}), const LoopRange(1, 2));
      expect(LoopRange.fromJson({'start': 1, 'end': 'x'}), isNull);
      expect(LoopRange.fromJson({'start': 'x', 'end': 2}), isNull);
      expect(LoopRange.fromJson(null), isNull);
    });
  });

  group('#36/AK3 entries of the former library.json', () {
    Map<String, Object?> legacy([Map<String, Object?> extra = const {}]) => {
      'id': 'a1b2',
      'fileName': 'x.mp3',
      'title': 'Alt',
      ...extra,
    };

    test('without hasArtwork there is no artwork', () {
      expect(Track.fromLegacyJson(legacy()).hasArtwork, isFalse);
      expect(
        Track.fromLegacyJson(legacy({'hasArtwork': true})).hasArtwork,
        isTrue,
      );
    });

    test('a track without loop (end 0) gets no loop ID', () {
      final t = Track.fromLegacyJson(
        legacy({
          'settings': {'loopStart': 0, 'loopEnd': 0},
        }),
      );
      expect(t.loopId, isNull);
      expect(t.loops, isEmpty);
    });
  });

  group('#36/AK1 shared fields: defaults when a field is missing', () {
    test('artwork, loop, tempo and «don\'t upload» are off', () {
      final t = Track.fromShared(_hash, {'fileName': '$_hash.mp3'});
      expect(t.hasArtwork, isFalse);
      expect(t.settings.loopEnabled, isFalse);
      expect(t.settings.speedEnabled, isFalse);
      expect(t.noUpload, isFalse);
    });

    test('the set values are read', () {
      final t = Track.fromShared(_hash, {
        'fileName': '$_hash.mp3',
        'hasArtwork': true,
        'loopEnabled': true,
        'speedEnabled': true,
      });
      expect(t.hasArtwork, isTrue);
      expect(t.settings.loopEnabled, isTrue);
      expect(t.settings.speedEnabled, isTrue);
    });

    test('a loop of the format before #37 without «enabled» is off', () {
      final t = Track.fromShared(_hash, {
        'fileName': '$_hash.mp3',
        'loopEnabled': true,
        'loop': {'start': 1, 'end': 4},
      });
      expect(t.settings.loopEnabled, isFalse);
      expect(t.loopId, '0');
      expect(t.settings.loopEnd, 4);
    });
  });
}
