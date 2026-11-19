// Erzeugt die App-Symbole der Testseite W0 (#32): dunkle Fläche, Kreis in Akzentfarbe, drei Balken.
// Aufruf: node core/web/make_w0_icons.mjs [ausgabeordner]   (Standard: web/w0)
import { writeFileSync } from 'node:fs';
import { deflateSync } from 'node:zlib';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const out = process.argv[2] ?? join(dirname(fileURLToPath(import.meta.url)), '../../web/w0');

function crc32(buf) {
  let c, crc = 0xffffffff;
  for (const b of buf) {
    c = (crc ^ b) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = (crc >>> 8) ^ c;
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}

function png(size) {
  const bg = [0x1d, 0x1b, 0x19], accent = [0xe0, 0x7a, 0x4b], light = [0xf1, 0xec, 0xe4];
  const rows = [];
  const c = size / 2, r = size * 0.36;
  for (let y = 0; y < size; y++) {
    const row = [0];
    for (let x = 0; x < size; x++) {
      const d = Math.hypot(x + 0.5 - c, y + 0.5 - c);
      let px = d < r ? accent : bg;
      // drei senkrechte Balken (Pegel) im Kreis
      const u = (x - c) / r, v = (y - c) / r;
      const bars = [[-0.4, 0.35], [0, 0.55], [0.4, 0.25]];
      for (const [bx, h] of bars) if (Math.abs(u - bx) < 0.1 && Math.abs(v) < h) px = light;
      row.push(...px);
    }
    rows.push(Buffer.from(row));
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0); ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; ihdr[9] = 2;  // 8 Bit, RGB
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(Buffer.concat(rows))),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

for (const size of [192, 512]) writeFileSync(join(out, `icon-${size}.png`), png(size));
console.log(`Symbole in ${out}`);
