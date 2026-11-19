// Machbarkeitstest W0 (#32), Punkt 4: grosse Datei im Origin Private File System (OPFS).
// Schreibt N MB mit einem prüfbaren Muster und prüft sie später Byte für Byte.
// Synchrone Zugriffe (createSyncAccessHandle) gibt es nur in einem Worker, dafür in Safari und Chrome.

const FILE = 'w0-test.bin';
const META = 'w0-meta.json';
const CHUNK = 1024 * 1024;

function fill(chunk, index) {
  const u = new Uint32Array(chunk.buffer);
  let x = (index + 1) * 2654435761 >>> 0;
  for (let i = 0; i < u.length; i++) {
    x ^= x << 13; x >>>= 0;
    x ^= x >>> 17;
    x ^= x << 5; x >>>= 0;
    u[i] = x;
  }
}

async function root() {
  return navigator.storage.getDirectory();
}

async function readMeta(dir) {
  try {
    const f = await (await dir.getFileHandle(META)).getFile();
    return JSON.parse(await f.text());
  } catch {
    return null;
  }
}

async function writeMeta(dir, meta) {
  const h = await dir.getFileHandle(META, { create: true });
  const a = await h.createSyncAccessHandle();
  const bytes = new TextEncoder().encode(JSON.stringify(meta));
  a.truncate(0);
  a.write(bytes, { at: 0 });
  a.flush();
  a.close();
}

async function write(mb) {
  const dir = await root();
  const h = await dir.getFileHandle(FILE, { create: true });
  const a = await h.createSyncAccessHandle();
  a.truncate(0);
  const chunk = new Uint8Array(CHUNK);
  for (let i = 0; i < mb; i++) {
    fill(chunk, i);
    a.write(chunk, { at: i * CHUNK });
    if (i % 10 === 9) postMessage({ type: 'progress', done: i + 1, total: mb });
  }
  a.flush();
  a.close();
  const meta = { writtenAt: new Date().toISOString(), mb };
  await writeMeta(dir, meta);
  postMessage({ type: 'written', meta });
}

async function verify() {
  const dir = await root();
  const meta = await readMeta(dir);
  let h;
  try {
    h = await dir.getFileHandle(FILE);
  } catch {
    postMessage({ type: 'verified', meta, present: false });
    return;
  }
  const a = await h.createSyncAccessHandle();
  const size = a.getSize();
  const mb = Math.floor(size / CHUNK);
  const expect = new Uint8Array(CHUNK);
  const got = new Uint8Array(CHUNK);
  let bad = 0;
  for (let i = 0; i < mb; i++) {
    fill(expect, i);
    a.read(got, { at: i * CHUNK });
    const e = new Uint32Array(expect.buffer), g = new Uint32Array(got.buffer);
    for (let j = 0; j < e.length; j++) if (e[j] !== g[j]) { bad++; break; }
    if (i % 10 === 9) postMessage({ type: 'progress', done: i + 1, total: mb });
  }
  a.close();
  postMessage({ type: 'verified', meta, present: true, mb, bad });
}

async function remove() {
  const dir = await root();
  for (const name of [FILE, META]) {
    try { await dir.removeEntry(name); } catch { /* fehlt schon */ }
  }
  postMessage({ type: 'removed' });
}

onmessage = async (e) => {
  try {
    if (e.data.type === 'write') await write(e.data.mb);
    else if (e.data.type === 'verify') await verify();
    else if (e.data.type === 'remove') await remove();
  } catch (err) {
    postMessage({ type: 'error', message: String(err) });
  }
};
