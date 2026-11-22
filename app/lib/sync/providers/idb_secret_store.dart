// IndexedDB as key-value store for the browser sign-in (#54/AK1): one object store «kv» in the database
// «woodshed-sync» of this origin. Not part of the library (OPFS), so the token never goes into the sync.
import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../secret_store.dart';

class IdbSecretStore implements SecretStore {
  IdbSecretStore({this.database = 'woodshed-sync'});

  final String database;
  static const _store = 'kv';
  Future<web.IDBDatabase>? _db;

  Future<web.IDBDatabase> _open() => _db ??= () {
    final done = Completer<web.IDBDatabase>();
    final req = web.window.indexedDB.open(database, 1);
    req.onupgradeneeded = ((web.Event _) {
      (req.result as web.IDBDatabase).createObjectStore(_store);
    }).toJS;
    req.onsuccess = ((web.Event _) {
      done.complete(req.result as web.IDBDatabase);
    }).toJS;
    req.onerror = ((web.Event _) {
      done.completeError(StateError('IndexedDB: ${req.error?.message}'));
    }).toJS;
    return done.future;
  }();

  Future<JSAny?> _run(
    web.IDBTransactionMode mode,
    web.IDBRequest Function(web.IDBObjectStore s) op,
  ) async {
    final db = await _open();
    final tx = db.transaction(_store.toJS, mode);
    final req = op(tx.objectStore(_store));
    final done = Completer<JSAny?>();
    tx.oncomplete = ((web.Event _) => done.complete(req.result)).toJS;
    tx.onerror = ((web.Event _) {
      if (!done.isCompleted) {
        done.completeError(StateError('IndexedDB: ${tx.error?.message}'));
      }
    }).toJS;
    tx.onabort = tx.onerror;
    return done.future;
  }

  @override
  Future<String?> read(String key) async {
    final v = await _run('readonly', (s) => s.get(key.toJS));
    return v.isA<JSString>() ? (v as JSString).toDart : null;
  }

  @override
  Future<void> write(String key, String value) =>
      _run('readwrite', (s) => s.put(value.toJS, key.toJS));

  @override
  Future<void> delete(String key) =>
      _run('readwrite', (s) => s.delete(key.toJS));
}
