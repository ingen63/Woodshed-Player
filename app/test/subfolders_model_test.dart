// #146: the parent link of a folder in the shared fields and the closed folders in device.json. Plain
// values only, no library.
import 'package:flutter_test/flutter_test.dart';
import 'package:woodshed_player/library/device_settings.dart';
import 'package:woodshed_player/library/track.dart';

void main() {
  group('#146/AK7 shared fields of a folder', () {
    test('a folder on the top level is written as before, a subfolder with its parent', () {
      const top = TrackFolder(id: 'a', name: 'A');
      expect(top.toShared(), {'name': 'A', 'sync': true});
      const sub = TrackFolder(id: 'b', name: 'B', sync: false, parentId: 'a');
      expect(sub.toShared(), {'name': 'B', 'sync': false, 'parent': 'a'});
      expect(TrackFolder.parentField, 'parent');
    });

    test('read back: without the field on the top level, with it inside', () {
      final old = TrackFolder.fromShared('a', {'name': 'A', 'sync': true});
      expect(old.parentId, isNull);
      expect(old.name, 'A');
      final sub = TrackFolder.fromShared('b', {
        'name': 'B',
        'sync': false,
        'parent': 'a',
      });
      expect(
        (sub.id, sub.name, sub.sync, sub.parentId),
        ('b', 'B', false, 'a'),
      );
      final none = TrackFolder.fromShared('c', {'name': 'C', 'parent': null});
      expect(none.parentId, isNull);
    });

    test('a parent that is not text makes the record unreadable', () {
      expect(
        () => TrackFolder.fromShared('x', {'name': 'x', 'parent': 7}),
        throwsA(isA<TypeError>()),
      );
    });

    test('copyWith keeps or changes the parent', () {
      const f = TrackFolder(id: 'b', name: 'B', sync: false, parentId: 'a');
      final renamed = f.copyWith(name: 'C');
      expect((renamed.name, renamed.sync, renamed.parentId), ('C', false, 'a'));
      expect(f.copyWith(parentId: () => null).parentId, isNull);
      expect(f.copyWith(parentId: () => 'z').parentId, 'z');
      expect(f.copyWith(sync: true).parentId, 'a');
    });

    test('a folder of the former format 1 lies on the top level', () {
      final f = TrackFolder.fromLegacyJson({'id': 'ab', 'name': 'X'});
      expect((f.id, f.name, f.parentId), ('AB', 'X', null));
    });
  });

  group('#146/AK2 closed folders in device.json', () {
    test('sorted, none when all are open, kept by copyWith', () {
      const d = DeviceSettings(deviceId: '0123456789abcdef');
      expect(d.closedFolders, isEmpty);
      expect(d.toJson().containsKey('closedFolders'), isFalse);
      final c = d.copyWith(closedFolders: {'b', 'a'});
      expect(c.toJson()['closedFolders'], ['a', 'b']);
      expect(c.copyWith(libraryOpen: true).closedFolders, {'a', 'b'});
    });
  });
}
