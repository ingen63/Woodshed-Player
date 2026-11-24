// Feasibility test K0 (#52): can two devices exchange data directly? Test points (docs/KONZEPT-SYNC-OHNE-
// REGISTRIERUNG.md, K0): (1) installed web app on iPhone <-> Mac in the same Wi-Fi, (2) Android likewise,
// (3) phone on mobile data <-> desktop at home, (4) setup over three public relays, daily for a week,
// (5) 100 MB with abort and resume, (6) screen lock, (7) key still there after 7 days. Plus the extension stage
// from #56: the web app reaches the Mac in the Wi-Fi without relays and STUN (manual direct code).
//
// Signalling: hello / offer / answer, sealed with the pairing key (k0.mjs), over public Nostr relays or as a
// direct code. The lower device id makes the offer. Non-trickle ICE (the SDP carries all candidates).
// Data channel: JSON control messages and binary chunks (4-byte big-endian index + 64 KiB test data). The receiver
// checks every chunk against the generator and keeps its position, so a transfer resumes after any abort.
// Nothing leaves the device before pairing; the log holds no addresses, only their kind.
import * as K from './k0.mjs';

const CFG = window.K0_CONFIG || { relays: [], stun: [] };
const TOTAL = 100 * 1024 * 1024;
const HELLO_EVERY_MS = 15000;
const ATTEMPT_MS = 25000;
// A direct code is copied by hand: the offer waits as long as the code is valid, the answer a minute.
const DIRECT_OFFER_MS = 10 * 60 * 1000;
const DIRECT_ANSWER_MS = 60000;
const STALE_MS = 10 * 60 * 1000;
const LOG_MAX = 3000;

const $ = (id) => document.getElementById(id);

// ---- Storage: one IndexedDB object store as key-value store ----

let dbPromise;
function openDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open('k0', 1);
    req.onupgradeneeded = () => req.result.createObjectStore('kv');
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}
async function kv(mode, fn) {
  const db = await (dbPromise || (dbPromise = openDb()));
  return new Promise((resolve, reject) => {
    const tx = db.transaction('kv', mode);
    const req = fn(tx.objectStore('kv'));
    tx.oncomplete = () => resolve(req.result);
    tx.onerror = () => reject(tx.error);
  });
}
const get = (key) => kv('readonly', (s) => s.get(key));
const put = (key, value) => kv('readwrite', (s) => s.put(value, key));
const del = (key) => kv('readwrite', (s) => s.delete(key));

// ---- Helpers ----

function standalone() {
  return matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
}
function platform() {
  const ua = navigator.userAgent;
  if (/iPhone/.test(ua)) return 'iPhone';
  if (/iPad/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) return 'iPad';
  if (/Android/.test(ua)) return 'Android';
  if (/Macintosh/.test(ua)) return 'Mac';
  if (/Windows/.test(ua)) return 'Windows';
  return 'Linux';
}
const where = () => `${platform()} ${standalone() ? 'Web-App' : 'Browser'}`;

function stamp(t) {
  const d = new Date(t);
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}
const today = () => stamp(Date.now()).slice(0, 10);
const days = (ms) => Math.floor(ms / 86400000);
const mb = (bytes) => (bytes / 1048576).toFixed(1);
const randomHex = (n) => K.hex(crypto.getRandomValues(new Uint8Array(n)));

// ---- Log ----

let log = [];
async function note(text) {
  log.push({ t: Date.now(), text });
  if (log.length > LOG_MAX) log = log.slice(-LOG_MAX);
  renderLog();
  await put('log', log);
}
function renderLog() {
  $('log').textContent = log
    .slice(-300)
    .reverse()
    .map((e) => `${stamp(e.t)}  ${e.text}`)
    .join('\n');
}

// ---- State ----

const S = {
  device: null, // { id, created }
  pair: null, // { key: Uint8Array, created }
  keys: null, // K.deriveKeys(pair.key)
  persisted: null,
  pool: null,
  helloTimer: 0,
  pc: null,
  dc: null,
  sid: null,
  peer: null, // { id, name }
  attemptTimer: 0,
  via: '',
  rx: null, // { id, seed, size, next, bytes, ms }
  tx: null, // { id, seed, size, done }
  pumpToken: 0,
  wakeLock: null,
  rxSession: null, // { t0, n0 }
  probing: false,
  offering: false,
};

function useStun() {
  return $('stun').checked;
}

// ---- Relays (Nostr, NIP-01) ----

class RelayPool {
  constructor(urls, keys, onMessage) {
    this.urls = urls;
    this.keys = keys;
    this.onMessage = onMessage;
    this.sockets = new Map();
    this.seen = new Set();
    this.failures = new Map(); // failed attempts in a row per relay: back off, log the first only
    this.running = false;
  }
  start() {
    this.running = true;
    for (const url of this.urls) this.connect(url);
  }
  stop() {
    this.running = false;
    for (const ws of this.sockets.values()) ws.close();
    this.sockets.clear();
  }
  openCount() {
    let n = 0;
    for (const ws of this.sockets.values()) if (ws.readyState === WebSocket.OPEN) n++;
    return n;
  }
  connect(url) {
    let ws;
    try {
      ws = new WebSocket(url);
    } catch (e) {
      note(`Relay ${host(url)}: ${e.message}`);
      return;
    }
    this.sockets.set(url, ws);
    const since = Math.floor(Date.now() / 1000) - 60;
    ws.onopen = () => {
      this.failures.delete(url);
      ws.send(JSON.stringify(['REQ', 'k0', { kinds: [K.NOSTR_KIND], authors: [this.keys.pubkey], since }]));
      note(`Relay ${host(url)} offen`);
      render();
    };
    ws.onmessage = async (e) => {
      let m;
      try {
        m = JSON.parse(e.data);
      } catch {
        return;
      }
      if (m[0] === 'EVENT' && m[2] && typeof m[2].content === 'string') {
        if (this.seen.has(m[2].id)) return;
        this.seen.add(m[2].id);
        const msg = await K.open(this.keys, m[2].content);
        if (msg) this.onMessage(msg, host(url));
      } else if (m[0] === 'OK' && m[2] === false) {
        note(`Relay ${host(url)} lehnt ab: ${m[3]}`);
      } else if (m[0] === 'NOTICE' || m[0] === 'CLOSED') {
        note(`Relay ${host(url)}: ${m[0]} ${m[m.length - 1]}`);
      }
    };
    ws.onclose = () => {
      if (this.sockets.get(url) !== ws) return;
      this.sockets.delete(url);
      render();
      const n = this.failures.get(url) || 0;
      this.failures.set(url, n + 1);
      const wait = Math.min(60000, 5000 * 2 ** n);
      if (this.running) setTimeout(() => this.running && !this.sockets.has(url) && this.connect(url), wait);
    };
    ws.onerror = () => {
      if (!this.failures.has(url)) note(`Relay ${host(url)}: keine Verbindung`);
    };
  }
  async send(msg) {
    const ev = await K.nostrEvent(this.keys, await K.seal(this.keys, msg));
    const frame = JSON.stringify(['EVENT', ev]);
    let n = 0;
    for (const ws of this.sockets.values()) {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(frame);
        n++;
      }
    }
    return n;
  }
}

const host = (url) => url.replace(/^wss?:\/\//, '').replace(/\/.*$/, '');

/** One relay alone: open, subscribe, publish a probe, wait for OK and for the echo. */
function probeRelay(url, keys) {
  return new Promise((resolve) => {
    const t0 = performance.now();
    const result = { url: host(url), ok: false, openMs: null, okMs: null, echoMs: null, error: '' };
    let ws;
    let id = '';
    const finish = (error) => {
      if (error) result.error = error;
      result.ok = result.okMs !== null && result.echoMs !== null;
      clearTimeout(timer);
      try {
        ws.close();
      } catch {
        /* closed */
      }
      resolve(result);
    };
    const timer = setTimeout(() => finish(result.openMs === null ? 'keine Verbindung' : 'Zeitüberschreitung'), 10000);
    try {
      ws = new WebSocket(url);
    } catch (e) {
      finish(e.message);
      return;
    }
    ws.onopen = async () => {
      result.openMs = Math.round(performance.now() - t0);
      const since = Math.floor(Date.now() / 1000) - 5;
      ws.send(JSON.stringify(['REQ', 'probe', { kinds: [K.NOSTR_KIND], authors: [keys.pubkey], since }]));
      const ev = await K.nostrEvent(keys, await K.seal(keys, { t: 'probe', from: S.device.id, ts: Date.now() }));
      id = ev.id;
      ws.send(JSON.stringify(['EVENT', ev]));
    };
    ws.onmessage = (e) => {
      let m;
      try {
        m = JSON.parse(e.data);
      } catch {
        return;
      }
      if (m[0] === 'OK' && m[1] === id) {
        if (m[2] === false) finish(`abgelehnt: ${m[3]}`);
        else result.okMs = Math.round(performance.now() - t0);
      } else if (m[0] === 'EVENT' && m[2] && m[2].id === id) {
        result.echoMs = Math.round(performance.now() - t0);
      }
      if (result.okMs !== null && result.echoMs !== null) finish('');
    };
    ws.onerror = () => {
      if (result.openMs === null) finish('keine Verbindung');
    };
  });
}

async function probeAll(reason) {
  if (!S.keys || S.probing) return;
  S.probing = true;
  render();
  await note(`Relays prüfen (${reason})`);
  const results = await Promise.all(CFG.relays.map((u) => probeRelay(u, S.keys)));
  const checks = (await get('checks')) || [];
  for (const r of results) {
    checks.push({ day: today(), t: Date.now(), relay: r.url, ok: r.ok, ms: r.echoMs });
    await note(
      r.ok
        ? `  ${r.url}: ok, offen ${r.openMs} ms, bestätigt ${r.okMs} ms, Echo ${r.echoMs} ms`
        : `  ${r.url}: FEHLER ${r.error}${r.openMs !== null ? ` (offen nach ${r.openMs} ms)` : ''}`,
    );
  }
  await put('checks', checks);
  S.probing = false;
  render();
}

// ---- Signalling ----

async function signal(msg) {
  const full = { ...msg, from: S.device.id, name: where(), ts: Date.now() };
  return S.pool ? S.pool.send(full) : 0;
}

async function startRelays(reason) {
  if (!S.keys) {
    await note('Erst koppeln');
    return;
  }
  stopRelays();
  S.pool = new RelayPool(CFG.relays, S.keys, onSignal);
  S.pool.start();
  await note(`Verbinden über Relays (${reason}), STUN ${useStun() ? 'an' : 'aus'}`);
  const hello = async () => {
    if (!S.pool) return;
    if (!connected()) {
      const n = await signal({ t: 'hello' });
      if (n === 0) await note('Hallo: noch kein Relay offen');
    }
  };
  setTimeout(hello, 1500);
  S.helloTimer = setInterval(hello, HELLO_EVERY_MS);
  render();
}

function stopRelays() {
  clearInterval(S.helloTimer);
  if (S.pool) S.pool.stop();
  S.pool = null;
}

async function onSignal(msg, via) {
  if (msg.from === S.device.id || (msg.to && msg.to !== S.device.id)) return;
  if (typeof msg.ts !== 'number' || Math.abs(Date.now() - msg.ts) > STALE_MS) {
    await note(`Veraltete Nachricht verworfen (${msg.t})`);
    return;
  }
  if (msg.t === 'hello') {
    if (!S.peer || S.peer.id !== msg.from) await note(`Gegenstelle gefunden über ${via}: ${msg.name}`);
    S.peer = { id: msg.from, name: msg.name };
    if (connected()) return;
    if (!msg.reply) await signal({ t: 'hello', reply: true, to: msg.from });
    // Two hellos can arrive together (reply and periodic one): only one offer.
    if (S.device.id < msg.from && !S.attemptTimer && !S.offering) {
      S.offering = true;
      try {
        await offerVia('relay', msg.from);
      } finally {
        S.offering = false;
      }
    }
  } else if (msg.t === 'offer') {
    S.peer = { id: msg.from, name: msg.name };
    await note(`Angebot erhalten über ${via}`);
    const sdp = await takeOffer(msg.sdp, useStun(), 'relay');
    await signal({ t: 'answer', to: msg.from, sid: msg.sid, sdp });
  } else if (msg.t === 'answer' && msg.sid === S.sid) {
    await note(`Antwort erhalten über ${via}`);
    await S.pc.setRemoteDescription({ type: 'answer', sdp: msg.sdp });
  }
}

async function offerVia(kind, peerId) {
  const sdp = await makeOffer(kind === 'direct' ? false : useStun(), kind);
  const msg = { t: 'offer', sid: S.sid, sdp };
  if (kind === 'relay') {
    await signal({ ...msg, to: peerId });
    await note('Angebot gesendet');
  }
  return msg;
}

// ---- WebRTC ----

const connected = () => !!S.dc && S.dc.readyState === 'open';

function closePc() {
  clearTimeout(S.attemptTimer);
  S.attemptTimer = 0;
  S.pumpToken++;
  if (S.dc) S.dc.onclose = null;
  if (S.pc) S.pc.close();
  S.pc = null;
  S.dc = null;
  render();
}

function newPc(stun, kind, waitMs = ATTEMPT_MS) {
  closePc();
  const pc = new RTCPeerConnection({ iceServers: stun ? CFG.stun.map((urls) => ({ urls })) : [] });
  S.pc = pc;
  S.via = kind;
  const t0 = performance.now();
  pc.onconnectionstatechange = async () => {
    if (S.pc !== pc) return;
    await note(`Verbindung: ${pc.connectionState} (${Math.round(performance.now() - t0)} ms)`);
    if (pc.connectionState === 'failed') {
      await note('Keine Verbindung zustande gekommen. Im selben WLAN erneut versuchen, ggf. mit STUN.');
      closePc();
    }
    render();
  };
  S.attemptTimer = setTimeout(async () => {
    S.attemptTimer = 0;
    if (S.pc === pc && !connected()) {
      await note(`Zeitüberschreitung nach ${waitMs / 1000} s (ICE ${pc.iceConnectionState})${kind === 'relay' ? ', neuer Versuch beim nächsten Hallo' : ''}`);
      closePc();
    }
  }, waitMs);
  render();
  return pc;
}

function gathered(pc) {
  return new Promise((resolve) => {
    const done = () => resolve(pc.localDescription.sdp);
    if (pc.iceGatheringState === 'complete') return done();
    pc.addEventListener('icegatheringstatechange', () => pc.iceGatheringState === 'complete' && done());
    setTimeout(done, 5000);
  });
}

async function makeOffer(stun, kind) {
  const pc = newPc(stun, kind, kind === 'direct' ? DIRECT_OFFER_MS : ATTEMPT_MS);
  S.sid = randomHex(8);
  setupDc(pc.createDataChannel('k0', { ordered: true }));
  await pc.setLocalDescription(await pc.createOffer());
  return gathered(pc);
}

async function takeOffer(sdp, stun, kind) {
  const pc = newPc(stun, kind, kind === 'direct' ? DIRECT_ANSWER_MS : ATTEMPT_MS);
  pc.ondatachannel = (e) => setupDc(e.channel);
  await pc.setRemoteDescription({ type: 'offer', sdp });
  await pc.setLocalDescription(await pc.createAnswer());
  return gathered(pc);
}

function setupDc(dc) {
  S.dc = dc;
  dc.binaryType = 'arraybuffer';
  dc.bufferedAmountLowThreshold = 1 << 20;
  dc.onopen = async () => {
    clearTimeout(S.attemptTimer);
    S.attemptTimer = 0;
    await note(`Datenkanal offen (${S.via === 'direct' ? 'Direktcode, ohne Relays' : 'über Relays'})`);
    dc.send(JSON.stringify({ t: 'info', name: where() }));
    await describePath();
    render();
    if (S.tx && !S.tx.done) await offerTransfer('Fortsetzen');
  };
  dc.onclose = async () => {
    if (S.dc !== dc) return;
    await note('Datenkanal geschlossen');
    S.pumpToken++;
    S.dc = null;
    releaseWake();
    render();
  };
  dc.onmessage = (e) => (typeof e.data === 'string' ? onControl(JSON.parse(e.data)) : onChunk(e.data));
}

/** Logs which way the connection took: candidate types and kinds of address (never the address itself). */
async function describePath() {
  const pc = S.pc;
  if (!pc) return;
  const stats = await pc.getStats();
  let pair;
  stats.forEach((r) => {
    if (r.type === 'transport' && r.selectedCandidatePairId) pair = stats.get(r.selectedCandidatePairId);
  });
  if (!pair) {
    stats.forEach((r) => {
      if (r.type === 'candidate-pair' && r.state === 'succeeded' && (r.nominated || r.selected)) pair = r;
    });
  }
  if (!pair) {
    await note('Weg: unbekannt (keine Statistik)');
    return;
  }
  const l = stats.get(pair.localCandidateId) || {};
  const r = stats.get(pair.remoteCandidateId) || {};
  const lk = K.addressKind(l.address || l.ip);
  const rk = K.addressKind(r.address || r.ip);
  const types = [l.candidateType, r.candidateType];
  const way = types.includes('relay')
    ? 'über TURN'
    : types.includes('srflx') || lk === 'öffentlich' || rk === 'öffentlich'
      ? 'über das Internet (STUN)'
      : 'direkt im WLAN';
  const rtt = pair.currentRoundTripTime !== undefined ? `, RTT ${Math.round(pair.currentRoundTripTime * 1000)} ms` : '';
  await note(
    `Weg: ${way}; hier ${l.candidateType}/${l.protocol} (${lk}), Gegenstelle ${r.candidateType}/${r.protocol} (${rk})${rtt}`,
  );
}

// ---- Transfer ----

async function onControl(m) {
  if (m.t === 'info') {
    await note(`Gegenstelle: ${m.name}`);
  } else if (m.t === 'ping') {
    S.dc.send(JSON.stringify({ t: 'pong', ts: m.ts }));
  } else if (m.t === 'pong') {
    await note(`Ping ${Math.round(performance.now() - m.ts)} ms`);
  } else if (m.t === 'xfer') {
    if (!S.rx || S.rx.id !== m.id) {
      S.rx = { id: m.id, seed: m.seed, size: m.size, next: 0, bytes: 0, ms: 0, errors: 0 };
      await put('rx', S.rx);
    }
    const n = K.chunkCount(S.rx.size);
    if (S.rx.next >= n) {
      S.dc.send(JSON.stringify({ t: 'done', id: m.id, ms: S.rx.ms, errors: S.rx.errors }));
      return;
    }
    S.rxSession = { t0: performance.now(), n0: S.rx.next };
    await note(`Empfang ${m.id.slice(0, 6)}: ab ${mb(S.rx.next * K.CHUNK)} MB von ${mb(S.rx.size)} MB`);
    await holdWake();
    S.dc.send(JSON.stringify({ t: 'want', id: m.id, from: S.rx.next }));
  } else if (m.t === 'want') {
    if (S.tx && S.tx.id === m.id) pump(m.from);
  } else if (m.t === 'done') {
    if (S.tx && S.tx.id === m.id && !S.tx.done) {
      S.tx.done = true;
      await put('tx', S.tx);
      await note(`Gegenstelle hat alles (${mb(S.tx.size)} MB), Prüffehler: ${m.errors}`);
      releaseWake();
      render();
    }
  }
}

const verifyWords = new Uint32Array(K.CHUNK / 4);
async function onChunk(buf) {
  const rx = S.rx;
  if (!rx) return;
  const index = new DataView(buf).getUint32(0);
  if (index !== rx.next) {
    await note(`Stück ${index} statt ${rx.next}, verworfen`);
    return;
  }
  const len = Math.min(K.CHUNK, rx.size - index * K.CHUNK);
  K.fillChunk(rx.seed, index, verifyWords);
  const got = new Uint8Array(buf, 4);
  const want = new Uint8Array(verifyWords.buffer, 0, len);
  let same = got.length === len;
  for (let i = 0; same && i < len; i++) same = got[i] === want[i];
  if (!same) rx.errors++;
  rx.next++;
  rx.bytes += len;
  const n = K.chunkCount(rx.size);
  if (rx.next % 16 === 0 || rx.next === n) {
    await put('rx', rx);
    renderXfer();
  }
  if (rx.next === n) {
    const s = S.rxSession;
    const secs = s ? (performance.now() - s.t0) / 1000 : 0;
    const part = s ? (rx.next - s.n0) * K.CHUNK : 0;
    rx.ms += Math.round(secs * 1000);
    await put('rx', rx);
    await note(
      `Empfang fertig: ${mb(rx.size)} MB, Prüffehler ${rx.errors}; letzter Abschnitt ${mb(part)} MB in ${secs.toFixed(1)} s (${(part / 1048576 / Math.max(secs, 0.001)).toFixed(1)} MB/s)`,
    );
    S.dc.send(JSON.stringify({ t: 'done', id: rx.id, ms: rx.ms, errors: rx.errors }));
    releaseWake();
  }
}

async function offerTransfer(reason) {
  if (!connected()) return;
  await note(`${reason}: ${S.tx.id.slice(0, 6)}, ${mb(S.tx.size)} MB`);
  S.dc.send(JSON.stringify({ t: 'xfer', id: S.tx.id, seed: S.tx.seed, size: S.tx.size }));
}

async function pump(from) {
  const token = ++S.pumpToken;
  const dc = S.dc;
  const tx = S.tx;
  const n = K.chunkCount(tx.size);
  const words = new Uint32Array(K.CHUNK / 4);
  const t0 = performance.now();
  await holdWake();
  await note(`Senden ab ${mb(from * K.CHUNK)} MB`);
  for (let i = from; i < n; i++) {
    if (token !== S.pumpToken || dc.readyState !== 'open') {
      await note(`Senden unterbrochen bei ${mb(i * K.CHUNK)} MB`);
      return;
    }
    if (dc.bufferedAmount > 4 << 20) {
      await new Promise((resolve) => {
        const done = () => {
          dc.removeEventListener('bufferedamountlow', done);
          dc.removeEventListener('close', done);
          resolve();
        };
        dc.addEventListener('bufferedamountlow', done);
        dc.addEventListener('close', done);
      });
      i--;
      continue;
    }
    K.fillChunk(tx.seed, i, words);
    const len = Math.min(K.CHUNK, tx.size - i * K.CHUNK);
    const msg = new Uint8Array(4 + len);
    new DataView(msg.buffer).setUint32(0, i);
    msg.set(new Uint8Array(words.buffer, 0, len), 4);
    try {
      dc.send(msg);
    } catch (e) {
      await note(`Senden: ${e.message}`);
      return;
    }
    if (i % 16 === 0) {
      tx.sent = i + 1;
      renderXfer();
    }
  }
  tx.sent = n;
  const secs = (performance.now() - t0) / 1000;
  await note(`Alles abgeschickt: ${mb((n - from) * K.CHUNK)} MB in ${secs.toFixed(1)} s, warte auf Bestätigung`);
  renderXfer();
}

// ---- Wake lock (test point 6) ----

async function holdWake() {
  if (!$('wake').checked || S.wakeLock || !('wakeLock' in navigator)) return;
  try {
    S.wakeLock = await navigator.wakeLock.request('screen');
    S.wakeLock.addEventListener('release', () => {
      S.wakeLock = null;
    });
    await note('Bildschirm wird wach gehalten');
  } catch (e) {
    await note(`Wake Lock: ${e.message}`);
  }
}
function releaseWake() {
  if (S.wakeLock) S.wakeLock.release();
  S.wakeLock = null;
}
const transferring = () => (S.tx && !S.tx.done && connected()) || (S.rx && S.rx.next < K.chunkCount(S.rx.size) && connected());

// ---- Pairing ----

async function setKey(key, how) {
  S.pair = { key, created: Date.now() };
  await put('pair', S.pair);
  S.keys = await K.deriveKeys(key);
  S.persisted = navigator.storage && navigator.storage.persist ? await navigator.storage.persist() : null;
  await note(`Gekoppelt (${how}), Speicher dauerhaft: ${fmtPersist()}`);
  render();
}
const fmtPersist = () => (S.persisted === null ? 'unbekannt' : S.persisted ? 'ja' : 'nein');

// ---- Rendering ----

function render() {
  const pair = S.pair;
  const st = S.pc ? S.pc.connectionState : 'keine';
  const rows = [
    ['Gerät', `${where()} · ${S.device ? S.device.id.slice(0, 6) : ''}`],
    [
      'Schlüssel',
      pair
        ? `vorhanden seit ${stamp(pair.created).slice(0, 10)} (${days(Date.now() - pair.created)} Tage)`
        : 'nicht gekoppelt',
    ],
    ['Speicher dauerhaft', fmtPersist()],
    ['Relays offen', S.pool ? `${S.pool.openCount()} von ${CFG.relays.length}` : 'aus'],
    ['Verbindung', `${connected() ? 'Datenkanal offen' : st}${S.peer ? ` · ${S.peer.name}` : ''}`],
    ['Bildschirm wach', S.wakeLock ? 'ja' : 'nein'],
  ];
  fillDl($('state'), rows);
  $('connect').disabled = !S.keys || !!S.pool;
  $('disconnect').disabled = !S.pool && !S.pc;
  $('probe').disabled = !S.keys || S.probing;
  $('directOffer').disabled = !S.keys;
  $('takeDirect').disabled = !S.keys;
  $('copyKey').disabled = !S.pair;
  $('dropKey').disabled = !S.pair;
  $('send').disabled = !connected();
  $('ping').disabled = !connected();
  renderXfer();
}

function renderXfer() {
  const rows = [];
  if (S.tx) {
    const n = K.chunkCount(S.tx.size);
    rows.push([
      'Senden',
      S.tx.done ? `${mb(S.tx.size)} MB bestätigt` : `${mb(Math.min(S.tx.sent || 0, n) * K.CHUNK)} von ${mb(S.tx.size)} MB`,
    ]);
  }
  if (S.rx) {
    const n = K.chunkCount(S.rx.size);
    rows.push(['Empfangen', `${mb(Math.min(S.rx.next, n) * K.CHUNK)} von ${mb(S.rx.size)} MB, Prüffehler ${S.rx.errors}`]);
  }
  fillDl($('xfer'), rows);
}

async function renderSummary() {
  const checks = (await get('checks')) || [];
  const rows = [];
  for (const url of CFG.relays) {
    const h = host(url);
    const mine = checks.filter((c) => c.relay === h);
    const dayOk = new Set(mine.filter((c) => c.ok).map((c) => c.day));
    const allDays = new Set(mine.map((c) => c.day));
    rows.push([h, mine.length ? `an ${dayOk.size} von ${allDays.size} Tagen ok (${mine.length} Prüfungen)` : 'noch nicht geprüft']);
  }
  const starts = log.filter((e) => e.text.startsWith('Start')).length;
  rows.push(['Starts', String(starts)]);
  fillDl($('summary'), rows);
}

function fillDl(dl, rows) {
  dl.replaceChildren(
    ...rows.flatMap(([k, v]) => {
      const dt = document.createElement('dt');
      dt.textContent = k;
      const dd = document.createElement('dd');
      dd.textContent = v;
      return [dt, dd];
    }),
  );
}

async function copy(text, what) {
  try {
    await navigator.clipboard.writeText(text);
    await note(`${what} kopiert`);
  } catch {
    await note(`${what}: Kopieren nicht erlaubt, bitte von Hand markieren`);
  }
}

// ---- Buttons ----

function wire() {
  $('newKey').onclick = async () => {
    if (S.pair && !confirm('Den bestehenden Schlüssel ersetzen? Gekoppelte Geräte müssen neu koppeln.')) return;
    await setKey(crypto.getRandomValues(new Uint8Array(32)), 'neuer Schlüssel');
    $('keyIn').value = K.keyToCode(S.pair.key);
  };
  $('copyKey').onclick = () => copy(K.keyToCode(S.pair.key), 'Kopplungscode');
  $('dropKey').onclick = async () => {
    if (!confirm('Schlüssel auf diesem Gerät löschen?')) return;
    stopRelays();
    closePc();
    S.pair = null;
    S.keys = null;
    await del('pair');
    await note('Schlüssel gelöscht');
    render();
  };
  $('takeKey').onclick = async () => {
    const key = K.codeToKey($('keyIn').value);
    if (!key) {
      await note('Kopplungscode ungültig (52 Zeichen A–Z, 2–7 erwartet)');
      return;
    }
    await setKey(key, 'Code übernommen');
  };
  $('connect').onclick = () => startRelays('von Hand');
  $('disconnect').onclick = async () => {
    stopRelays();
    closePc();
    await note('Getrennt');
  };
  $('probe').onclick = () => probeAll('von Hand');
  $('directOffer').onclick = async () => {
    const msg = await offerVia('direct');
    $('directOut').value = await K.seal(S.keys, { ...msg, from: S.device.id, name: where(), ts: Date.now() });
    await note('Direktcode erzeugt (ohne STUN), warte auf Antwort der Gegenstelle');
  };
  $('copyDirect').onclick = () => copy($('directOut').value, 'Direktcode');
  $('takeDirect').onclick = async () => {
    const msg = await K.open(S.keys, $('directIn').value.trim());
    if (!msg || msg.from === S.device.id) {
      await note('Direktcode ungültig (anderer Schlüssel oder eigener Code)');
      return;
    }
    if (Math.abs(Date.now() - msg.ts) > STALE_MS) {
      await note('Direktcode älter als 10 Minuten, neu erzeugen');
      return;
    }
    S.peer = { id: msg.from, name: msg.name };
    if (msg.t === 'offer') {
      const sdp = await takeOffer(msg.sdp, false, 'direct');
      $('directOut').value = await K.seal(S.keys, {
        t: 'answer',
        sid: msg.sid,
        sdp,
        from: S.device.id,
        name: where(),
        ts: Date.now(),
      });
      await note('Direktcode übernommen, Antwort steht oben: bei der Gegenstelle einfügen');
    } else if (msg.t === 'answer' && msg.sid === S.sid && S.pc) {
      await S.pc.setRemoteDescription({ type: 'answer', sdp: msg.sdp });
      await note('Antwort übernommen, verbinde');
    } else {
      await note('Antwort passt nicht zum letzten Direktcode');
    }
  };
  $('send').onclick = async () => {
    S.tx = { id: randomHex(8), seed: crypto.getRandomValues(new Uint32Array(1))[0], size: TOTAL, done: false, sent: 0 };
    await put('tx', S.tx);
    await offerTransfer('Neue Übertragung');
  };
  $('ping').onclick = () => S.dc.send(JSON.stringify({ t: 'ping', ts: performance.now() }));
  $('resetRx').onclick = async () => {
    S.rx = null;
    await del('rx');
    await note('Empfangsstand gelöscht');
    renderXfer();
  };
  $('auto').onchange = () => put('auto', $('auto').checked);
  $('stun').onchange = () => put('stun', $('stun').checked);
  $('copyLog').onclick = () => copy(log.map((e) => `${stamp(e.t)}  ${e.text}`).join('\n'), 'Protokoll');
  $('resetLog').onclick = async () => {
    if (!confirm('Protokoll und Relay-Prüfungen löschen?')) return;
    log = [];
    await put('log', log);
    await del('checks');
    renderLog();
    renderSummary();
  };
}

// ---- Lifecycle (test point 6) ----

function watchLifecycle() {
  document.addEventListener('visibilitychange', async () => {
    await note(`Sichtbarkeit: ${document.visibilityState}${transferring() ? ' (während Übertragung)' : ''}`);
    if (document.visibilityState === 'visible') {
      if (transferring()) await holdWake();
      if ($('auto').checked && S.keys && !connected()) await startRelays('Rückkehr');
    }
  });
  window.addEventListener('pagehide', (e) => note(`pagehide (persisted=${e.persisted})`));
  window.addEventListener('pageshow', (e) => e.persisted && note('pageshow aus dem Cache'));
  document.addEventListener('freeze', () => note('freeze'));
  document.addEventListener('resume', () => note('resume'));
  window.addEventListener('online', () => note('online'));
  window.addEventListener('offline', () => note('offline'));
}

// ---- Start ----

async function main() {
  log = (await get('log')) || [];
  renderLog();
  S.device = await get('device');
  if (!S.device) {
    S.device = { id: randomHex(8), created: Date.now() };
    await put('device', S.device);
  }
  S.pair = (await get('pair')) || null;
  if (S.pair) S.keys = await K.deriveKeys(S.pair.key);
  S.rx = (await get('rx')) || null;
  S.tx = (await get('tx')) || null;
  $('auto').checked = !!(await get('auto'));
  const stun = await get('stun');
  $('stun').checked = stun === undefined ? true : stun;
  S.persisted = navigator.storage && navigator.storage.persisted ? await navigator.storage.persisted() : null;
  wire();
  watchLifecycle();
  await note(
    `Start (${where()}), Schlüssel ${S.pair ? `vorhanden, ${days(Date.now() - S.pair.created)} Tage alt` : 'fehlt'}, Speicher dauerhaft: ${fmtPersist()}, WebRTC ${'RTCPeerConnection' in window ? 'ja' : 'nein'}, Wake Lock ${'wakeLock' in navigator ? 'ja' : 'nein'}`,
  );
  render();
  await renderSummary();
  if (S.keys) {
    const checks = (await get('checks')) || [];
    if (!checks.some((c) => c.day === today())) await probeAll('erster Start heute');
    await renderSummary();
    if ($('auto').checked) await startRelays('Start');
  }
  setInterval(render, 2000);
}

main().catch((e) => note(`Fehler: ${e.message}`));
