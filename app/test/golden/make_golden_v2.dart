// Writes the golden file of the current `library.json` (format 2 with loops per ID, #37) with the data
// model of the app (#10/AK5). All titles, names and IDs are invented. Call from app/:
//   dart run test/golden/make_golden_v2.dart test/golden/library_v2.json
// The golden file of format 2 as of #36 (one `loop` field per track, library_v2_36.json) was written once
// with the same data and the code of commit 8f9fb22; it stays as it is. A changed format gets a new golden
// file (README.md in this folder), the old ones stay.
import 'dart:convert';
import 'dart:io';

import 'package:woodshed_player/library/stamps.dart';
import 'package:woodshed_player/library/track.dart';

const d1 = '3f2a9c1e5b7d4a60';
const d2 = 'b07c0ffee0000001';
final t1 = 'a1' * 32;
final t2 = 'b2' * 32;
final t3 = 'c3' * 32;
const f1 = '11111111-2222-3333-4444-555555555555';
const f2 = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE';

Hlc at(String iso, String device, [int counter = 0]) =>
    Hlc(DateTime.parse(iso).millisecondsSinceEpoch, counter, device);

SharedState goldenState() {
  final created = at('2026-11-10T09:00:00Z', d1);
  final edited = at('2026-11-11T18:30:00Z', d2);
  final deleted = at('2026-11-12T07:15:00Z', d2, 1);
  final track1 = Track(
    id: t1,
    fileName: '$t1.mp3',
    originalFileName: 'Übung in G.mp3',
    title: 'Übung in G',
    artist: 'Testband',
    album: 'Testalbum',
    duration: 183.5,
    hasArtwork: true,
    dateAdded: DateTime.utc(2026, 11, 10, 9),
    customOrder: 1,
    folderId: f1,
    loopId: '5e1f0a2b',
    loops: const {'5e1f0a2b': LoopRange(12.5, 47), '0f0f0f0f': null},
    settings: const PlaybackSettings(
      speedEnabled: true,
      speed: 0.75,
      loopEnabled: true,
      loopStart: 12.5,
      loopEnd: 47,
      rampEnabled: true,
      rampStart: 60,
      rampTarget: 90,
      rampPasses: 4,
    ),
  );
  final track2 = Track(
    id: t2,
    fileName: '$t2.flac',
    originalFileName: 'tonleiter.flac',
    title: 'Tonleiter',
    duration: 1,
    hasArtwork: false,
    dateAdded: DateTime.utc(2026, 11, 10, 9, 5),
    customOrder: 0,
    noUpload: true,
  );
  final track3 = Track(
    id: t3,
    fileName: '$t3.mp3',
    originalFileName: 'weg.mp3',
    title: 'Gelöscht',
    duration: 30,
    hasArtwork: false,
    dateAdded: DateTime.utc(2026, 11, 10, 9, 10),
    customOrder: 2,
  );
  return SharedState(
    tracks: {
      // the title was changed later on the second device
      t1: StampedRecord.create(
        track1.toShared(),
        created,
      ).update({...track1.toShared(), 'title': 'Übung in G (langsam)'}, edited),
      t2: StampedRecord.create(track2.toShared(), created),
      t3: StampedRecord.create(track3.toShared(), created).delete(deleted),
    },
    folders: {
      f1: StampedRecord.create(
        const TrackFolder(id: f1, name: 'Etüden', sync: false).toShared(),
        created,
      ),
      f2: StampedRecord.create(
        const TrackFolder(id: f2, name: 'Alt').toShared(),
        created,
      ).delete(deleted),
    },
    settings: StampedRecord.create({
      'sortOrder': 'custom',
      'appearance': 'dark',
      'metronome.meter': 3,
      'metronome.subdivision': 2,
      'metronome.volume': 0.8,
      'metronome.rampEnabled': false,
      'metronome.rampStart': 80,
      'metronome.rampTarget': 120,
      'metronome.rampStep': 5,
      'metronome.rampEveryBars': 4,
      'metronome.rampByTime': false,
      'metronome.rampMinutes': 10,
    }, created),
  );
}

void main(List<String> args) {
  final json = const JsonEncoder.withIndent('  ')
      .convert(goldenState().toJson());
  File(args.single).writeAsStringSync(json);
}
