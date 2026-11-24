// Feasibility test K0 (#52): pure protocol and crypto helpers of the test page, shared with the Node test
// (tools/k0/test/web_k0_test.mjs). The native test program (tools/k0/lib/protocol.dart) implements the same
// functions; tools/k0/test/vectors.json pins both to the same bytes.
//
// Pairing key: 32 random bytes, shown as base32 (RFC 4648, 52 characters). Derived with HKDF-SHA256 (empty salt):
//   info "woodshed-k0/enc"   AES-256-GCM key for every signalling message (relay, Bonjour, direct code)
//   info "woodshed-k0/nostr" secret key of the Nostr identity both devices share (rendezvous id = its public key)
//   info "woodshed-k0/lan"   8-byte tag in the Bonjour TXT record, so only devices with the same key talk
// Envelope: base64(nonce(12) || AES-GCM(JSON) || tag(16)), additional data "woodshed-k0".
// Test data: 64 KiB chunks of xorshift32 words (little endian), seeded per transfer and chunk index.
'use strict';

export const NOSTR_KIND = 25052; // ephemeral range (NIP-01): relays forward, never store
export const CHUNK = 64 * 1024;
const AAD = new TextEncoder().encode('woodshed-k0');
const subtle = globalThis.crypto.subtle;

// ---- Encodings ----

export const hex = (bytes) => Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('');
export function unhex(s) {
  if (s.length % 2 !== 0 || /[^0-9a-f]/i.test(s)) throw new Error('bad hex');
  const out = new Uint8Array(s.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(s.slice(2 * i, 2 * i + 2), 16);
  return out;
}

export function b64(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}
export function unb64(s) {
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

const B32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/** Base32 (RFC 4648, no padding) in groups of four, e.g. "ABCD-EFGH-...". */
export function keyToCode(key) {
  let bits = 0;
  let value = 0;
  let out = '';
  for (const b of key) {
    value = (value << 8) | b;
    bits += 8;
    while (bits >= 5) {
      out += B32[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += B32[(value << (5 - bits)) & 31];
  return out.match(/.{1,4}/g).join('-');
}

/** Parses a pairing code; spaces, dashes and case do not matter. Returns null unless it holds 32 bytes. */
export function codeToKey(code) {
  const s = code.toUpperCase().replace(/[\s-]/g, '');
  if (s.length !== 52 || /[^A-Z2-7]/.test(s)) return null;
  let bits = 0;
  let value = 0;
  const out = [];
  for (const c of s) {
    value = ((value << 5) | B32.indexOf(c)) & 0xffff;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }
  return new Uint8Array(out.slice(0, 32));
}

// ---- Hashes and key derivation ----

export async function sha256(bytes) {
  return new Uint8Array(await subtle.digest('SHA-256', bytes));
}

async function hkdf(key, info, length) {
  const base = await subtle.importKey('raw', key, 'HKDF', false, ['deriveBits']);
  const bits = await subtle.deriveBits(
    { name: 'HKDF', hash: 'SHA-256', salt: new Uint8Array(0), info: new TextEncoder().encode(info) },
    base,
    length * 8,
  );
  return new Uint8Array(bits);
}

/** All keys of one pairing key. */
export async function deriveKeys(key) {
  const encRaw = await hkdf(key, 'woodshed-k0/enc', 32);
  const nostrRaw = await hkdf(key, 'woodshed-k0/nostr', 32);
  const lan = await hkdf(key, 'woodshed-k0/lan', 8);
  const sk = (bytesToBig(nostrRaw) % (N - 1n)) + 1n;
  const enc = await subtle.importKey('raw', encRaw, 'AES-GCM', false, ['encrypt', 'decrypt']);
  return { enc, encRaw, sk, pubkey: hex(xOnly(sk)), lanTag: hex(lan) };
}

// ---- Envelope ----

export async function seal(keys, message, nonce = globalThis.crypto.getRandomValues(new Uint8Array(12))) {
  const plain = new TextEncoder().encode(JSON.stringify(message));
  const ct = new Uint8Array(await subtle.encrypt({ name: 'AES-GCM', iv: nonce, additionalData: AAD }, keys.enc, plain));
  const out = new Uint8Array(12 + ct.length);
  out.set(nonce);
  out.set(ct, 12);
  return b64(out);
}

/** Decrypts an envelope; null if it is not one of ours (wrong key, damaged, not JSON). */
export async function open(keys, text) {
  try {
    const raw = unb64(text);
    if (raw.length < 12 + 16) return null;
    const plain = await subtle.decrypt(
      { name: 'AES-GCM', iv: raw.subarray(0, 12), additionalData: AAD },
      keys.enc,
      raw.subarray(12),
    );
    const message = JSON.parse(new TextDecoder().decode(plain));
    return message && typeof message === 'object' && typeof message.t === 'string' ? message : null;
  } catch {
    return null;
  }
}

// ---- secp256k1 and BIP-340 Schnorr signatures (Nostr events, NIP-01) ----

const P = 2n ** 256n - 2n ** 32n - 977n;
const N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;
const G = [
  0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798n,
  0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8n,
];

const mod = (a, m = P) => ((a % m) + m) % m;
function pow(b, e, m = P) {
  let r = 1n;
  b = mod(b, m);
  while (e > 0n) {
    if (e & 1n) r = (r * b) % m;
    b = (b * b) % m;
    e >>= 1n;
  }
  return r;
}
const inv = (a, m = P) => pow(a, m - 2n, m);

export function bytesToBig(bytes) {
  let n = 0n;
  for (const b of bytes) n = (n << 8n) | BigInt(b);
  return n;
}
export function bigToBytes(n) {
  const out = new Uint8Array(32);
  for (let i = 31; i >= 0; i--) {
    out[i] = Number(n & 0xffn);
    n >>= 8n;
  }
  return out;
}

// Jacobian coordinates [X, Y, Z]; Z = 0 is the point at infinity.
function jDouble([x, y, z]) {
  if (z === 0n || y === 0n) return [0n, 1n, 0n];
  const s = mod(4n * x * y * y);
  const m = mod(3n * x * x);
  const x2 = mod(m * m - 2n * s);
  return [x2, mod(m * (s - x2) - 8n * y * y * y * y), mod(2n * y * z)];
}
function jAdd(p, q) {
  if (p[2] === 0n) return q;
  if (q[2] === 0n) return p;
  const z1z1 = mod(p[2] * p[2]);
  const z2z2 = mod(q[2] * q[2]);
  const u1 = mod(p[0] * z2z2);
  const u2 = mod(q[0] * z1z1);
  const s1 = mod(p[1] * q[2] * z2z2);
  const s2 = mod(q[1] * p[2] * z1z1);
  if (u1 === u2) return s1 === s2 ? jDouble(p) : [0n, 1n, 0n];
  const h = mod(u2 - u1);
  const r = mod(s2 - s1);
  const hh = mod(h * h);
  const hhh = mod(h * hh);
  const x3 = mod(r * r - hhh - 2n * u1 * hh);
  return [x3, mod(r * (u1 * hh - x3) - s1 * hhh), mod(h * p[2] * q[2])];
}
function mul(k, [x, y]) {
  let r = [0n, 1n, 0n];
  let a = [x, y, 1n];
  while (k > 0n) {
    if (k & 1n) r = jAdd(r, a);
    a = jDouble(a);
    k >>= 1n;
  }
  return r;
}
function affine([x, y, z]) {
  if (z === 0n) return null;
  const zi = inv(z);
  const zi2 = mod(zi * zi);
  return [mod(x * zi2), mod(y * zi2 * zi)];
}

function xOnly(sk) {
  return bigToBytes(affine(mul(sk, G))[0]);
}

async function taggedHash(tag, ...parts) {
  const t = await sha256(new TextEncoder().encode(tag));
  const len = parts.reduce((n, p) => n + p.length, 0);
  const buf = new Uint8Array(64 + len);
  buf.set(t);
  buf.set(t, 32);
  let o = 64;
  for (const p of parts) {
    buf.set(p, o);
    o += p.length;
  }
  return sha256(buf);
}

/** BIP-340 signature of a 32-byte message. */
export async function schnorrSign(msg, sk, aux = globalThis.crypto.getRandomValues(new Uint8Array(32))) {
  const pub = affine(mul(sk, G));
  const d = pub[1] % 2n === 0n ? sk : N - sk;
  const px = bigToBytes(pub[0]);
  const auxHash = await taggedHash('BIP0340/aux', aux);
  const t = bigToBytes(d).map((b, i) => b ^ auxHash[i]);
  const k0 = bytesToBig(await taggedHash('BIP0340/nonce', t, px, msg)) % N;
  if (k0 === 0n) throw new Error('nonce is zero');
  const r = affine(mul(k0, G));
  const k = r[1] % 2n === 0n ? k0 : N - k0;
  const rx = bigToBytes(r[0]);
  const e = bytesToBig(await taggedHash('BIP0340/challenge', rx, px, msg)) % N;
  const sig = new Uint8Array(64);
  sig.set(rx);
  sig.set(bigToBytes(mod(k + e * d, N)), 32);
  return sig;
}

/** BIP-340 verification (for the tests). */
export async function schnorrVerify(msg, pubkey, sig) {
  const x = bytesToBig(pubkey);
  if (x >= P) return false;
  const c = mod(x * x * x + 7n);
  let y = pow(c, (P + 1n) / 4n);
  if (mod(y * y) !== c) return false;
  if (y % 2n !== 0n) y = P - y;
  const r = bytesToBig(sig.subarray(0, 32));
  const s = bytesToBig(sig.subarray(32));
  if (r >= P || s >= N) return false;
  const e = bytesToBig(await taggedHash('BIP0340/challenge', sig.subarray(0, 32), pubkey, msg)) % N;
  const point = affine(jAdd(mul(s, G), mul(N - e, [x, y])));
  return point !== null && point[1] % 2n === 0n && point[0] === r;
}

/** A signed ephemeral Nostr event (NIP-01) with the sealed message as content. */
export async function nostrEvent(keys, content, createdAt = Math.floor(Date.now() / 1000), aux = undefined) {
  const ev = { pubkey: keys.pubkey, created_at: createdAt, kind: NOSTR_KIND, tags: [], content };
  const id = await sha256(
    new TextEncoder().encode(JSON.stringify([0, ev.pubkey, ev.created_at, ev.kind, ev.tags, ev.content])),
  );
  ev.id = hex(id);
  ev.sig = hex(await schnorrSign(id, keys.sk, aux));
  return ev;
}

// ---- Test data for the transfer ----

/** Fills [words] (one 64 KiB chunk as 32-bit words) with the test data of chunk [index] of transfer [seed]. */
export function fillChunk(seed, index, words) {
  let x = (seed ^ Math.imul(index + 1, 0x9e3779b9)) >>> 0 || 1;
  for (let i = 0; i < words.length; i++) {
    x ^= x << 13;
    x ^= x >>> 17;
    x ^= x << 5;
    x >>>= 0;
    words[i] = x;
  }
  return words;
}

/** Number of chunks for [size] bytes. */
export const chunkCount = (size) => Math.ceil(size / CHUNK);

/** Classifies an ICE candidate address without revealing it: mDNS name, private (LAN) or public. */
export function addressKind(address) {
  if (!address) return 'unbekannt';
  if (address.endsWith('.local')) return 'mDNS';
  if (/^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.|127\.)/.test(address)) return 'privat';
  if (/^(fe80:|fc|fd|::1$)/i.test(address)) return 'privat';
  return 'öffentlich';
}
