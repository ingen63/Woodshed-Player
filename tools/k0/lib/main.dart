// K0 (#52): native test program (macOS) for the direct connection between devices. Counterpart of the test
// page web/k0/. A test tool, not part of the app: German labels like the test page, no localisation.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'protocol.dart';
import 'session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
  final session = Session(
    // K0_PROFILE: a second instance on the same Mac (own device id and key), e.g.
    // open -n --env K0_PROFILE=2 build/macos/Build/Products/Debug/woodshed_k0.app
    Directory(
      '$home/Library/Application Support/woodshed-k0${Platform.environment['K0_PROFILE'] ?? ''}',
    ),
  );
  await session.load();
  runApp(K0App(session));
}

class K0App extends StatelessWidget {
  const K0App(this.session, {super.key});

  final Session session;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Woodshed K0',
    theme: ThemeData(colorSchemeSeed: const Color(0xffb4532a)),
    darkTheme: ThemeData(
      colorSchemeSeed: const Color(0xffb4532a),
      brightness: Brightness.dark,
    ),
    home: Scaffold(
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) => _Body(session),
      ),
    ),
  );
}

class _Body extends StatefulWidget {
  const _Body(this.s);

  final Session s;

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  final _keyIn = TextEditingController();
  final _directIn = TextEditingController();

  Session get s => widget.s;

  @override
  void dispose() {
    _keyIn.dispose();
    _directIn.dispose();
    super.dispose();
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    s.note('$what kopiert');
  }

  Widget _section(String title, List<Widget> children) => Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    ),
  );

  Widget _row(List<Widget> children) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    ),
  );

  Widget _button(
    String label,
    VoidCallback? onPressed, {
    bool primary = false,
  }) => primary
      ? FilledButton(onPressed: onPressed, child: Text(label))
      : OutlinedButton(onPressed: onPressed, child: Text(label));

  @override
  Widget build(BuildContext context) {
    final paired = s.keys != null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rx = s.rx;
    final tx = s.tx;
    final mono = const TextStyle(fontFamily: 'Menlo', fontSize: 12);
    final state = <(String, String)>[
      ('Gerät', '$name · ${s.deviceId.substring(0, 6)}'),
      (
        'Schlüssel',
        s.key == null
            ? 'nicht gekoppelt'
            : 'vorhanden seit ${stamp(s.keyCreated ?? now).substring(0, 10)} (${(now - (s.keyCreated ?? now)) ~/ 86400000} Tage)',
      ),
      (
        'Relays offen',
        s.pool == null ? 'aus' : '${s.pool!.openCount} von ${relays.length}',
      ),
      ('Bonjour', s.lan == null ? 'aus' : 'an'),
      (
        'Verbindung',
        '${s.dcOpen ? 'Datenkanal offen' : s.connState}${s.peerName == null ? '' : ' · ${s.peerName}'}',
      ),
      if (tx != null)
        (
          'Senden',
          tx['done'] == true
              ? '${mb(tx['size'] as int)} MB bestätigt'
              : '${mb(((tx['sent'] as int?) ?? 0) * chunkSize)} von ${mb(tx['size'] as int)} MB',
        ),
      if (rx != null)
        (
          'Empfangen',
          '${mb((rx['next'] as int) * chunkSize)} von ${mb(rx['size'] as int)} MB, Prüffehler ${rx['errors']}',
        ),
    ];
    final days = <String, (Set<String>, Set<String>, int)>{};
    for (final c in s.checks) {
      final e = days.putIfAbsent(
        c['relay'] as String,
        () => (<String>{}, <String>{}, 0),
      );
      days[c['relay'] as String] = (
        e.$1..add(c['day'] as String),
        c['ok'] == true ? (e.$2..add(c['day'] as String)) : e.$2,
        e.$3 + 1,
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Woodshed K0 · Direkte Verbindung',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const Text(
          'Machbarkeitstest #52. Gegenstelle: die Testseite k0/ (Web-App) oder ein zweites Testprogramm. '
          'Verbindet sich erst nach dem Koppeln; Relays sehen nur verschlüsselte Verbindungsdaten.',
        ),
        _section('Stand', [for (final (k, v) in state) Text('$k: $v')]),
        _section('1 · Koppeln', [
          _row([
            _button(
              'Neuen Schlüssel erzeugen',
              s.key != null
                  ? null
                  : () => s.setKey(randomBytes(32), 'neuer Schlüssel'),
            ),
            _button(
              'Kopplungscode kopieren',
              s.key == null
                  ? null
                  : () => _copy(keyToCode(s.key!), 'Kopplungscode'),
            ),
            _button('Schlüssel löschen', s.key == null ? null : s.dropKey),
          ]),
          if (s.key != null) SelectableText(keyToCode(s.key!), style: mono),
          TextField(
            controller: _keyIn,
            decoration: const InputDecoration(
              hintText: 'Kopplungscode der Gegenstelle einfügen',
            ),
          ),
          _row([
            _button('Code übernehmen', () {
              final k = codeToKey(_keyIn.text);
              if (k == null) {
                s.note('Kopplungscode ungültig (52 Zeichen A–Z, 2–7 erwartet)');
              } else {
                s.setKey(k, 'Code übernommen');
              }
            }, primary: true),
          ]),
        ]),
        _section('2 · Verbinden', [
          _row([
            _button(
              'Über Relays verbinden',
              !paired || s.pool != null
                  ? null
                  : () => s.startRelays('von Hand'),
              primary: true,
            ),
            _button(
              'Im WLAN suchen (Bonjour)',
              !paired || s.lan != null ? null : s.startLan,
            ),
            _button(
              'Trennen',
              s.pool == null && s.lan == null && s.pc == null
                  ? null
                  : s.disconnect,
            ),
            _button(
              'Relays prüfen',
              !paired || s.probing ? null : () => s.probeAll('von Hand'),
            ),
          ]),
          Row(
            children: [
              Checkbox(value: s.stun, onChanged: (v) => s.setStun(v ?? true)),
              const Text('STUN verwenden (nur über Relays)'),
            ],
          ),
          Row(
            children: [
              Checkbox(value: s.auto, onChanged: (v) => s.setAuto(v ?? false)),
              const Text(
                'Beim Start automatisch verbinden (Relays und Bonjour)',
              ),
            ],
          ),
          const Text(
            'Bonjour findet ein zweites Testprogramm im WLAN ohne Internet und ohne Relays; '
            'die Web-App kann Bonjour nicht nutzen.',
          ),
        ]),
        _section('3 · Direkt, ohne Relays (Ausbaustufe)', [
          _row([
            _button('Direktcode erzeugen', paired ? s.makeDirectCode : null),
            _button(
              'Kopieren',
              s.directOut.isEmpty
                  ? null
                  : () => _copy(s.directOut, 'Direktcode'),
            ),
          ]),
          if (s.directOut.isNotEmpty)
            SelectableText(s.directOut, style: mono, maxLines: 4),
          TextField(
            controller: _directIn,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Code der Gegenstelle einfügen',
            ),
          ),
          _row([
            _button(
              'Code übernehmen',
              paired ? () => s.takeDirectCode(_directIn.text) : null,
              primary: true,
            ),
          ]),
        ]),
        _section('4 · Übertragen', [
          _row([
            _button(
              '100 MB senden',
              s.dcOpen ? s.startTransfer : null,
              primary: true,
            ),
            _button('Ping', s.dcOpen ? s.ping : null),
            _button('Empfang zurücksetzen', s.rx == null ? null : s.resetRx),
          ]),
        ]),
        _section('Protokoll', [
          for (final e in days.entries)
            Text(
              '${e.key}: an ${e.value.$2.length} von ${e.value.$1.length} Tagen ok (${e.value.$3} Prüfungen)',
            ),
          _row([
            _button(
              'Protokoll kopieren',
              () => _copy(s.logText(), 'Protokoll'),
            ),
            _button('Protokoll löschen', s.clearLog),
          ]),
          SelectableText(
            s.log.reversed
                .take(300)
                .map((e) => '${stamp(e.$1)}  ${e.$2}')
                .join('\n'),
            style: mono,
          ),
        ]),
      ],
    );
  }
}
