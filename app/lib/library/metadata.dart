// Liest Titel, Künstler, Album und Cover aus Audiodateien (#16), ohne Abhängigkeiten:
// MP3 (ID3v2.2/2.3/2.4, ID3v1), FLAC (Vorbis-Kommentare, PICTURE) und WAV (LIST/INFO, id3-Block).
// Fehlerhafte oder fehlende Angaben ergeben leere Felder, nie eine Ausnahme.
// A damaged WAV chunk or FLAC block keeps the fields read before it (#91).
// A damaged ID3v2 tag keeps its earlier frames, FLAC blocks and ID3v1 (#96).
import 'dart:convert';
import 'dart:typed_data';

class TrackMetadata {
  const TrackMetadata({this.title, this.artist, this.album, this.artwork});
  final String? title, artist, album;
  final Uint8List? artwork;

  bool get isEmpty =>
      title == null && artist == null && album == null && artwork == null;

  /// Ergänzt fehlende Felder aus [other].
  TrackMetadata fillFrom(TrackMetadata other) => TrackMetadata(
    title: title ?? other.title,
    artist: artist ?? other.artist,
    album: album ?? other.album,
    artwork: artwork ?? other.artwork,
  );
}

TrackMetadata readMetadata(Uint8List bytes) {
  try {
    if (_starts(bytes, 0, 'fLaC') ||
        (_starts(bytes, 0, 'ID3') && _flacAfterId3(bytes))) {
      final start = _starts(bytes, 0, 'ID3') ? 10 + _syncsafe(bytes, 6) : 0;
      return _readFlac(bytes, start).fillFrom(
        _starts(bytes, 0, 'ID3') ? _readId3v2(bytes, 0) : const TrackMetadata(),
      );
    }
    if (_starts(bytes, 0, 'RIFF') && _starts(bytes, 8, 'WAVE')) {
      return _readWav(bytes);
    }
    var meta = const TrackMetadata();
    if (_starts(bytes, 0, 'ID3')) meta = _readId3v2(bytes, 0);
    return meta.fillFrom(_readId3v1(bytes));
  } catch (_) {
    return const TrackMetadata();
  }
}

// ---------------------------------------------------------------------------
// Hilfen

bool _starts(Uint8List b, int at, String s) {
  if (b.length < at + s.length) return false;
  for (var i = 0; i < s.length; i++) {
    if (b[at + i] != s.codeUnitAt(i)) return false;
  }
  return true;
}

int _syncsafe(Uint8List b, int at) =>
    (b[at] & 0x7f) << 21 |
    (b[at + 1] & 0x7f) << 14 |
    (b[at + 2] & 0x7f) << 7 |
    (b[at + 3] & 0x7f);

int _be(Uint8List b, int at, int n) {
  var v = 0;
  for (var i = 0; i < n; i++) {
    v = v << 8 | b[at + i];
  }
  return v;
}

int _le32(Uint8List b, int at) =>
    b[at] | b[at + 1] << 8 | b[at + 2] << 16 | b[at + 3] << 24;

bool _flacAfterId3(Uint8List b) {
  if (b.length < 14) return false;
  return _starts(b, 10 + _syncsafe(b, 6), 'fLaC');
}

String? _clean(String? s) {
  if (s == null) return null;
  final t = s.replaceAll('\u0000', '').trim();
  return t.isEmpty ? null : t;
}

/// Entfernt die ID3-«Unsynchronisation» (0xFF 0x00 -> 0xFF).
Uint8List _deunsync(Uint8List b) {
  final out = BytesBuilder(copy: false);
  for (var i = 0; i < b.length; i++) {
    out.addByte(b[i]);
    if (b[i] == 0xff && i + 1 < b.length && b[i + 1] == 0x00) i++;
  }
  return out.toBytes();
}

/// Text in ID3-Kodierung 0 (Latin-1), 1 (UTF-16 mit BOM), 2 (UTF-16BE), 3 (UTF-8).
String _decode(int encoding, Uint8List b) {
  switch (encoding) {
    case 1:
    case 2:
      var bigEndian = encoding == 2;
      var start = 0;
      if (b.length >= 2 && b[0] == 0xff && b[1] == 0xfe) {
        bigEndian = false;
        start = 2;
      } else if (b.length >= 2 && b[0] == 0xfe && b[1] == 0xff) {
        bigEndian = true;
        start = 2;
      }
      final units = <int>[];
      for (var i = start; i + 1 < b.length; i += 2) {
        units.add(bigEndian ? b[i] << 8 | b[i + 1] : b[i + 1] << 8 | b[i]);
      }
      return String.fromCharCodes(units);
    case 3:
      return utf8.decode(b, allowMalformed: true);
    default:
      return latin1.decode(b);
  }
}

/// Ende eines nullterminierten Texts ab [at] in Kodierung [encoding] (Index des Terminators).
int _terminator(Uint8List b, int at, int encoding) {
  if (encoding == 1 || encoding == 2) {
    for (var i = at; i + 1 < b.length; i += 2) {
      if (b[i] == 0 && b[i + 1] == 0) return i;
    }
    return b.length;
  }
  for (var i = at; i < b.length; i++) {
    if (b[i] == 0) return i;
  }
  return b.length;
}

// ---------------------------------------------------------------------------
// ID3v2

TrackMetadata _readId3v2(Uint8List bytes, int at) {
  final major = bytes[at + 3];
  final flags = bytes[at + 5];
  final size = _syncsafe(bytes, at + 6);
  if (major < 2 || major > 4) return const TrackMetadata();
  var tag = Uint8List.sublistView(
    bytes,
    at + 10,
    (at + 10 + size).clamp(0, bytes.length),
  );
  if (flags & 0x80 != 0 && major < 4) tag = _deunsync(tag);

  String? title, artist, album;
  Uint8List? artwork;
  var artworkIsFront = false;
  final idLen = major == 2 ? 3 : 4;
  final headerLen = major == 2 ? 6 : 10;
  // A damaged extended header or frame ends the tag (#96): the fields read
  // so far stay, and the caller still reads FLAC blocks or the ID3v1 tag.
  try {
    var pos = 0;
    if (flags & 0x40 != 0 && major >= 3) {
      pos = major == 3 ? 4 + _be(tag, 0, 4) : _syncsafe(tag, 0);
    }
    while (pos + headerLen <= tag.length) {
      final id = String.fromCharCodes(tag.sublist(pos, pos + idLen));
      if (id.codeUnitAt(0) == 0) break; // padding
      final frameSize = switch (major) {
        2 => _be(tag, pos + 3, 3),
        3 => _be(tag, pos + 4, 4),
        _ => _syncsafe(tag, pos + 4),
      };
      final formatFlags = major == 2 ? 0 : tag[pos + 9];
      final dataStart = pos + headerLen;
      final dataEnd = dataStart + frameSize;
      if (frameSize <= 0 || dataEnd > tag.length) break;
      pos = dataEnd;

      var data = Uint8List.sublistView(tag, dataStart, dataEnd);
      if (major == 4) {
        if (formatFlags & 0x0c != 0) continue; // compressed or encrypted
        if (formatFlags & 0x01 != 0) {
          data = Uint8List.sublistView(data, 4); // data length indicator
        }
        if (formatFlags & 0x02 != 0) data = _deunsync(data);
      } else if (major == 3 && formatFlags & 0xc0 != 0) {
        continue; // compressed or encrypted
      }
      if (data.isEmpty) continue;

      switch (id) {
        case 'TIT2' || 'TT2':
          title ??= _text(data);
        case 'TPE1' || 'TP1':
          artist ??= _text(data);
        case 'TALB' || 'TAL':
          album ??= _text(data);
        case 'APIC' || 'PIC':
          final pic = _picture(data, id == 'PIC');
          if (pic != null &&
              (artwork == null || (!artworkIsFront && pic.$2 == 3))) {
            artwork = pic.$1;
            artworkIsFront = pic.$2 == 3;
          }
      }
    }
  } catch (_) {
    // keep the fields read before the damaged part
  }
  return TrackMetadata(
    title: title,
    artist: artist,
    album: album,
    artwork: artwork,
  );
}

/// Erster Wert eines Textframes (v2.4 trennt mehrere Werte mit Null).
String? _text(Uint8List data) {
  final enc = data[0];
  final body = Uint8List.sublistView(data, 1);
  final end = _terminator(body, 0, enc);
  return _clean(_decode(enc, Uint8List.sublistView(body, 0, end)));
}

/// (Bilddaten, Bildart) aus APIC bzw. PIC (v2.2).
(Uint8List, int)? _picture(Uint8List d, bool v22) {
  final enc = d[0];
  var p = 1;
  if (v22) {
    p += 3; // Format, z. B. "JPG"
  } else {
    while (p < d.length && d[p] != 0) {
      p++;
    }
    p++; // MIME-Typ
  }
  if (p >= d.length) return null;
  final type = d[p++];
  final descEnd = _terminator(d, p, enc);
  p = descEnd + ((enc == 1 || enc == 2) ? 2 : 1);
  if (p >= d.length) return null;
  return (Uint8List.fromList(d.sublist(p)), type);
}

TrackMetadata _readId3v1(Uint8List b) {
  if (b.length < 128 || !_starts(b, b.length - 128, 'TAG')) {
    return const TrackMetadata();
  }
  String? field(int off) => _clean(
    latin1.decode(b.sublist(b.length - 128 + off, b.length - 128 + off + 30)),
  );
  return TrackMetadata(title: field(3), artist: field(33), album: field(63));
}

// ---------------------------------------------------------------------------
// FLAC

TrackMetadata _readFlac(Uint8List b, int at) {
  var p = at + 4;
  String? title, artist, album;
  Uint8List? artwork;
  var artworkIsFront = false;
  while (p + 4 <= b.length) {
    final header = b[p];
    final last = header & 0x80 != 0;
    final type = header & 0x7f;
    final len = _be(b, p + 1, 3);
    final start = p + 4;
    if (start + len > b.length) break;
    try {
      if (type == 4) {
        var q = start;
        q += 4 + _le32(b, q); // Hersteller
        final count = _le32(b, q);
        q += 4;
        for (var i = 0; i < count && q + 4 <= start + len; i++) {
          final l = _le32(b, q);
          q += 4;
          final entry = utf8.decode(b.sublist(q, q + l), allowMalformed: true);
          q += l;
          final eq = entry.indexOf('=');
          if (eq < 0) continue;
          final value = _clean(entry.substring(eq + 1));
          switch (entry.substring(0, eq).toUpperCase()) {
            case 'TITLE':
              title ??= value;
            case 'ARTIST':
              artist ??= value;
            case 'ALBUM':
              album ??= value;
          }
        }
      } else if (type == 6) {
        var q = start;
        final picType = _be(b, q, 4);
        q += 4;
        q += 4 + _be(b, q, 4); // MIME
        q += 4 + _be(b, q, 4); // Beschreibung
        q += 16; // Breite, Höhe, Farbtiefe, Farben
        final dataLen = _be(b, q, 4);
        q += 4;
        if (q + dataLen <= start + len &&
            (artwork == null || (!artworkIsFront && picType == 3))) {
          artwork = Uint8List.fromList(b.sublist(q, q + dataLen));
          artworkIsFront = picType == 3;
        }
      }
    } catch (_) {
      break; // damaged block (#91): keep the fields read so far
    }
    p = start + len;
    if (last) break;
  }
  return TrackMetadata(
    title: title,
    artist: artist,
    album: album,
    artwork: artwork,
  );
}

// ---------------------------------------------------------------------------
// WAV

TrackMetadata _readWav(Uint8List b) {
  var meta = const TrackMetadata();
  var p = 12;
  while (p + 8 <= b.length) {
    final id = String.fromCharCodes(b.sublist(p, p + 4));
    final len = _le32(b, p + 4);
    final start = p + 8;
    final end = (start + len).clamp(0, b.length);
    if (id == 'LIST' && _starts(b, start, 'INFO')) {
      String? title, artist, album;
      var q = start + 4;
      while (q + 8 <= end) {
        final sub = String.fromCharCodes(b.sublist(q, q + 4));
        final l = _le32(b, q + 4);
        final v = q + 8 + l <= end
            ? _clean(
                utf8.decode(b.sublist(q + 8, q + 8 + l), allowMalformed: true),
              )
            : null;
        switch (sub) {
          case 'INAM':
            title ??= v;
          case 'IART':
            artist ??= v;
          case 'IPRD':
            album ??= v;
        }
        q += 8 + l + (l & 1);
      }
      meta = meta.fillFrom(
        TrackMetadata(title: title, artist: artist, album: album),
      );
    } else if ((id == 'id3 ' || id == 'ID3 ') && _starts(b, start, 'ID3')) {
      try {
        meta = _readId3v2(
          Uint8List.sublistView(b, start, end),
          0,
        ).fillFrom(meta);
      } catch (_) {
        // Damaged or cut ID3 tag (#91): keep the fields from LIST/INFO.
      }
    }
    p = start + len + (len & 1);
  }
  return meta;
}
