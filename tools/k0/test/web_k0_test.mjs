// K0 (#52): tests of the test page's protocol (web/k0/k0.mjs) under Node.js. Pins the bytes in vectors.json,
// which the native test program checks as well (protocol_test.dart), so both sides speak the same protocol.
// Usage: node tools/k0/test/web_k0_test.mjs [--write]   (--write regenerates vectors.json from k0.mjs)
import assert from 'node:assert/strict';
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as K from '../../../web/k0/k0.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const vectorFile = join(here, 'vectors.json');

// Official BIP-340 test vectors 0 and 1 (github.com/bitcoin/bips, bip-0340/test-vectors.csv).
const bip340 = [
  {
    sk: '0000000000000000000000000000000000000000000000000000000000000003',
    pk: 'F9308A019258C31049344F85F89D5229B531C845836F99B08601F113BCE036F9',
    aux: '0000000000000000000000000000000000000000000000000000000000000000',
    msg: '0000000000000000000000000000000000000000000000000000000000000000',
    sig: 'E907831F80848D1069A5371B402410364BDF1C5F8307B0084C55F1CE2DCA821525F66A4A85EA8B71E482A74F382D2CE5EBEEE8FDB2172F477DF4900D310536C0',
  },
  {
    sk: 'B7E151628AED2A6ABF7158809CF4F3C762E7160F38B4DA56A784D9045190CFEF',
    pk: 'DFF1D77F2A671C5F36183726DB2341BE58FEAE1DA2DECED843240F7B502BA659',
    aux: '0000000000000000000000000000000000000000000000000000000000000001',
    msg: '243F6A8885A308D313198A2E03707344A4093822299F31D0082EFA98EC4E6C89',
    sig: '6896BD60EEAE296DB48A229FF71DFE071BDE413E6D43F917DC8DCF8C78DE33418906D11AC976ABCCB20B091292BFF4EA897EFCB639EA871CFA95F6DE339E4B0A',
  },
];

async function compute() {
  const key = Uint8Array.from({ length: 32 }, (_, i) => i);
  const keys = await K.deriveKeys(key);
  const message = { t: 'hello', from: '0011223344556677', name: 'Test', ts: 1700000000000 };
  const nonce = Uint8Array.from({ length: 12 }, (_, i) => i);
  const event = await K.nostrEvent(keys, 'abc', 1700000000, new Uint8Array(32));
  const words = K.fillChunk(123456789, 5, new Uint32Array(K.CHUNK / 4));
  return {
    key: K.hex(key),
    code: K.keyToCode(key),
    enc: K.hex(keys.encRaw),
    pubkey: keys.pubkey,
    lanTag: keys.lanTag,
    message,
    envelope: await K.seal(keys, message, nonce),
    event: { id: event.id, sig: event.sig },
    chunk: {
      seed: 123456789,
      index: 5,
      first: Array.from(words.subarray(0, 4)),
      sha256: K.hex(await K.sha256(new Uint8Array(words.buffer))),
    },
    bip340,
  };
}

const actual = await compute();
if (process.argv.includes('--write')) {
  writeFileSync(vectorFile, `${JSON.stringify(actual, null, 2)}\n`);
  console.log(`wrote ${vectorFile}`);
}
const expected = JSON.parse(readFileSync(vectorFile, 'utf8'));
let failures = 0;
async function test(name, fn) {
  try {
    await fn();
    console.log(`ok   ${name}`);
  } catch (e) {
    failures++;
    console.log(`FAIL ${name}: ${e.message}`);
  }
}

await test('#52/K0 BIP-340 official vectors sign and verify', async () => {
  for (const v of bip340) {
    const sig = await K.schnorrSign(K.unhex(v.msg), BigInt(`0x${v.sk}`), K.unhex(v.aux));
    assert.equal(K.hex(sig).toUpperCase(), v.sig);
    assert.equal(await K.schnorrVerify(K.unhex(v.msg), K.unhex(v.pk), sig), true);
    sig[5] ^= 1;
    assert.equal(await K.schnorrVerify(K.unhex(v.msg), K.unhex(v.pk), sig), false);
  }
});

await test('#52/K0 derived keys, envelope, event and test data match vectors.json', async () => {
  assert.deepEqual(actual, expected);
});

await test('#52/K0 pairing code round trip, tolerant input, wrong length rejected', async () => {
  for (let i = 0; i < 20; i++) {
    const key = crypto.getRandomValues(new Uint8Array(32));
    const code = K.keyToCode(key);
    assert.equal(code.length, 52 + 12);
    assert.deepEqual(K.codeToKey(` ${code.toLowerCase().replaceAll('-', ' ')} `), key);
  }
  assert.equal(K.codeToKey('ABCD'), null);
  assert.equal(K.codeToKey(`${expected.code}A`), null);
  assert.equal(K.codeToKey(expected.code.replace(/^./, '1')), null);
});

await test('#52/K0 envelope opens with the same key only', async () => {
  const a = await K.deriveKeys(new Uint8Array(32).fill(1));
  const b = await K.deriveKeys(new Uint8Array(32).fill(2));
  const sealed = await K.seal(a, { t: 'offer', sdp: 'v=0' });
  assert.deepEqual(await K.open(a, sealed), { t: 'offer', sdp: 'v=0' });
  assert.equal(await K.open(b, sealed), null);
  assert.equal(await K.open(a, 'not base64!'), null);
  assert.equal(await K.open(a, K.b64(new Uint8Array(20))), null);
  const raw = K.unb64(sealed);
  raw[raw.length - 1] ^= 1;
  assert.equal(await K.open(a, K.b64(raw)), null);
  assert.equal(await K.open(a, await K.seal(a, { no: 'type' })), null);
});

await test('#52/K0 event id and signature verify, pubkey is the shared identity', async () => {
  const keys = await K.deriveKeys(new Uint8Array(32).fill(9));
  const ev = await K.nostrEvent(keys, 'x');
  assert.equal(ev.kind, K.NOSTR_KIND);
  assert.equal(ev.pubkey, keys.pubkey);
  assert.equal(await K.schnorrVerify(K.unhex(ev.id), K.unhex(ev.pubkey), K.unhex(ev.sig)), true);
});

await test('#52/K0 address kinds never show the address', async () => {
  assert.equal(K.addressKind('abc.local'), 'mDNS');
  assert.equal(K.addressKind('192.168.1.2'), 'privat');
  assert.equal(K.addressKind('172.20.0.1'), 'privat');
  assert.equal(K.addressKind('172.40.0.1'), 'öffentlich');
  assert.equal(K.addressKind('fe80::1'), 'privat');
  assert.equal(K.addressKind('8.8.8.8'), 'öffentlich');
  assert.equal(K.addressKind(undefined), 'unbekannt');
  assert.equal(K.chunkCount(100 * 1024 * 1024), 1600);
  assert.equal(K.chunkCount(1), 1);
});

if (failures) {
  console.log(`${failures} failed`);
  process.exit(1);
}
