// Feasibility test M0 (#52): does the Google sign-in hold in the installed web app (P1), and how often does a
// renewal need a tap (P2)?
//
// Browser only, no server: Google's token endpoint wants the client secret for "Web application" clients even
// with PKCE, so a public page uses the token response (response_type=token, about 1 h, no refresh token).
// Renewal is a full-page redirect with prompt=none (Safari blocks the hidden-iframe variant). Token and log stay
// in IndexedDB of this origin; nothing is sent anywhere except to Google after «Anmelden».
'use strict';

const SCOPE = 'https://www.googleapis.com/auth/drive.file';
const AUTH_URL = 'https://accounts.google.com/o/oauth2/v2/auth';
const REVOKE_URL = 'https://oauth2.googleapis.com/revoke';
const DRIVE = 'https://www.googleapis.com/drive/v3';
const UPLOAD = 'https://www.googleapis.com/upload/drive/v3';
const FOLDER = 'WoodshedPlayer-M0';
const CLIENT_ID = (window.M0_CONFIG && window.M0_CONFIG.googleClientId) || '';
// Must match an authorised redirect URI in the Google Cloud console exactly (trailing slash included).
const REDIRECT_URI = new URL('./', location.href).href;
// Treat a token as expired a minute early, so a request never starts with a token about to lapse.
const MARGIN_MS = 60 * 1000;
// After a failed silent renewal, do not try again on start for this long (no redirect loop).
const RETRY_AFTER_MS = 10 * 60 * 1000;

const $ = (id) => document.getElementById(id);

// ---- Storage: one IndexedDB object store as key-value store ----

let dbPromise;
function openDb() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open('m0', 1);
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

function randomHex(bytes) {
  const a = crypto.getRandomValues(new Uint8Array(bytes));
  return Array.from(a, (b) => b.toString(16).padStart(2, '0')).join('');
}

function standalone() {
  return matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
}
const where = () => (standalone() ? 'App' : 'Browser');

const valid = (token) => !!token && token.expiresAt - MARGIN_MS > Date.now();

function minutesLeft(token) {
  return Math.max(0, Math.round((token.expiresAt - Date.now()) / 60000));
}

function stamp(t) {
  const d = new Date(t);
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}:${p(d.getSeconds())}`;
}

function tokenText(token) {
  if (!token) return 'kein Token';
  return valid(token) ? `Token gültig, noch ${minutesLeft(token)} min` : 'Token abgelaufen';
}

// ---- Log ----

const KIND = {
  start: 'Start',
  'login-ok': 'Anmeldung erfolgreich',
  'silent-ok': 'still erneuert',
  'needs-tap': 'stille Erneuerung abgelehnt, Tippen nötig',
  'login-fail': 'Anmeldung fehlgeschlagen',
  'state-mismatch': 'Rückkehr ohne passenden Start',
  'token-401': 'Token von Google abgelehnt',
  'drive-ok': 'Drive-Test erfolgreich',
  'drive-fail': 'Drive-Test fehlgeschlagen',
  logout: 'abgemeldet',
};

async function log(kind, detail = '') {
  const entries = (await get('log')) || [];
  entries.push({ t: Date.now(), kind, where: where(), detail });
  await put('log', entries);
}

function lineOf(e) {
  return `${stamp(e.t)}  ${e.where.padEnd(7)} ${KIND[e.kind] || e.kind}${e.detail ? ' · ' + e.detail : ''}`;
}

// ---- Sign-in ----

async function authorize(silent) {
  if (!CLIENT_ID) return;
  const state = randomHex(16);
  await put('pending', { state, silent, t: Date.now() });
  const params = new URLSearchParams({
    client_id: CLIENT_ID,
    redirect_uri: REDIRECT_URI,
    response_type: 'token',
    scope: SCOPE,
    state,
    include_granted_scopes: 'true',
  });
  if (silent) params.set('prompt', 'none');
  location.assign(`${AUTH_URL}?${params}`);
}

/** Handles the return from Google (#access_token=… or #error=…). Returns true if there was one. */
async function handleReturn() {
  const hash = location.hash.slice(1);
  if (!/(^|&)(state|error|access_token)=/.test(hash)) return false;
  const p = new URLSearchParams(hash);
  history.replaceState(null, '', location.pathname + location.search);

  const pending = await get('pending');
  await del('pending');
  if (!pending || pending.state !== p.get('state')) {
    // Typical for P1: the sign-in started in the installed app but came back in Safari (other storage).
    await log('state-mismatch', 'Start in anderem Speicher (App oder Safari?)');
    return true;
  }
  const took = `${Math.round((Date.now() - pending.t) / 1000)} s`;
  const error = p.get('error');
  if (error) {
    await log(pending.silent ? 'needs-tap' : 'login-fail', `${error}, ${took}`);
    return true;
  }
  const accessToken = p.get('access_token');
  if (!accessToken) {
    await log('login-fail', `kein Token in der Antwort, ${took}`);
    return true;
  }
  const expiresIn = Number(p.get('expires_in')) || 3600;
  const scope = p.get('scope') || '';
  await put('token', { accessToken, expiresAt: Date.now() + expiresIn * 1000, scope });
  const extra = scope.split(' ').filter((s) => s && s !== SCOPE);
  await log(
    pending.silent ? 'silent-ok' : 'login-ok',
    `${took}, gültig ${Math.round(expiresIn / 60)} min` + (extra.length ? `, weitere Rechte: ${extra.join(' ')}` : ''),
  );
  return true;
}

async function logout() {
  const token = await get('token');
  if (token) {
    // The revoke endpoint sends no CORS headers; the opaque response is enough.
    try {
      await fetch(REVOKE_URL, {
        method: 'POST',
        mode: 'no-cors',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ token: token.accessToken }),
      });
    } catch (_) {
      // Offline: the token lapses on its own within the hour.
    }
  }
  await del('token');
  await log('logout');
  await render();
}

// ---- Drive ----

async function api(url, options = {}) {
  const token = await get('token');
  if (!valid(token)) throw new Error('kein gültiges Token');
  const r = await fetch(url, {
    ...options,
    headers: { Authorization: `Bearer ${token.accessToken}`, ...(options.headers || {}) },
  });
  if (r.status === 401) {
    await del('token');
    await log('token-401', new URL(url).pathname);
    throw new Error('401: Token abgelehnt');
  }
  if (!r.ok) throw new Error(`${r.status}: ${(await r.text()).slice(0, 300)}`);
  return r.json();
}

async function driveTest() {
  const out = $('driveOut');
  out.innerHTML = '<dt>Lauf</dt><dd>…</dd>';
  try {
    const q = `name='${FOLDER}' and mimeType='application/vnd.google-apps.folder' and trashed=false`;
    const found = await api(`${DRIVE}/files?${new URLSearchParams({ q, fields: 'files(id,name,createdTime)' })}`);
    let folder = found.files[0];
    const created = !folder;
    if (created) {
      folder = await api(`${DRIVE}/files?fields=id,name,createdTime`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name: FOLDER, mimeType: 'application/vnd.google-apps.folder' }),
      });
    }
    const boundary = `m0${randomHex(8)}`;
    const meta = { name: `probe-${stamp(Date.now()).replace(/[: ]/g, '-')}.json`, parents: [folder.id] };
    const content = JSON.stringify({ written: new Date().toISOString(), where: where() });
    const body =
      `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${JSON.stringify(meta)}\r\n` +
      `--${boundary}\r\nContent-Type: application/json\r\n\r\n${content}\r\n--${boundary}--`;
    await api(`${UPLOAD}/files?uploadType=multipart&fields=id`, {
      method: 'POST',
      headers: { 'Content-Type': `multipart/related; boundary=${boundary}` },
      body,
    });
    const listed = await api(
      `${DRIVE}/files?${new URLSearchParams({ q: `'${folder.id}' in parents and trashed=false`, fields: 'files(name)', pageSize: '1000' })}`,
    );
    const detail = `Ordner ${created ? 'angelegt' : 'gefunden'}, ${listed.files.length} Dateien`;
    await log('drive-ok', detail);
    out.innerHTML = '';
    addRow(out, 'Ergebnis', detail, 'ok');
    addRow(out, 'Ordner seit', stamp(Date.parse(folder.createdTime)));
  } catch (e) {
    await log('drive-fail', e.message);
    out.innerHTML = '';
    addRow(out, 'Fehler', e.message, 'bad');
  }
  await render();
}

// ---- View ----

function addRow(dl, term, text, cls) {
  const dt = document.createElement('dt');
  dt.textContent = term;
  const dd = document.createElement('dd');
  dd.textContent = text;
  if (cls) dd.className = cls;
  dl.append(dt, dd);
}

async function render() {
  const token = await get('token');
  const entries = (await get('log')) || [];

  const state = $('state');
  state.innerHTML = '';
  addRow(state, 'Ansicht', standalone() ? 'installierte App' : 'Browser (nicht installiert)', standalone() ? 'ok' : '');
  addRow(state, 'Anmeldung', tokenText(token), valid(token) ? 'ok' : 'bad');
  if (token) addRow(state, 'gültig bis', stamp(token.expiresAt));
  addRow(state, 'Weiterleitung', REDIRECT_URI);
  addRow(state, 'Client-ID', CLIENT_ID ? `${CLIENT_ID.slice(0, 12)}…` : 'fehlt', CLIENT_ID ? '' : 'bad');

  const count = (kind) => entries.filter((e) => e.kind === kind).length;
  const summary = $('summary');
  summary.innerHTML = '';
  if (entries.length) {
    const days = Math.floor((Date.now() - entries[0].t) / 86400000);
    const startDays = new Set(entries.filter((e) => e.kind === 'start').map((e) => stamp(e.t).slice(0, 10)));
    addRow(summary, 'seit', `${stamp(entries[0].t).slice(0, 10)} (${days} Tage, an ${startDays.size} Tagen geöffnet)`);
  }
  addRow(summary, 'Starts', String(count('start')));
  addRow(summary, 'still erneuert', String(count('silent-ok')));
  addRow(summary, 'Tippen nötig', String(count('needs-tap')));
  addRow(summary, 'Anmeldungen', String(count('login-ok')));
  addRow(summary, 'falscher Speicher', String(count('state-mismatch')), count('state-mismatch') ? 'bad' : '');

  $('log').textContent = entries.slice().reverse().map(lineOf).join('\n');
  $('auto').checked = (await get('auto')) !== false;
  for (const id of ['login', 'silent', 'drive']) $(id).disabled = !CLIENT_ID;
}

async function copyLog() {
  const entries = (await get('log')) || [];
  const text = entries.map(lineOf).join('\n');
  try {
    await navigator.clipboard.writeText(text);
    $('copy').textContent = 'Kopiert';
  } catch (_) {
    getSelection().selectAllChildren($('log'));
  }
}

async function resetLog() {
  if (!confirm('Protokoll löschen? Das Token bleibt.')) return;
  await del('log');
  await render();
}

// ---- Start ----

async function main() {
  $('login').onclick = () => authorize(false);
  $('silent').onclick = () => authorize(true);
  $('logout').onclick = logout;
  $('drive').onclick = driveTest;
  $('copy').onclick = copyLog;
  $('reset').onclick = resetLog;
  $('auto').onchange = async (e) => put('auto', e.target.checked);
  if (!CLIENT_ID) $('banner').textContent = 'Client-ID fehlt: in config.js eintragen.';

  const returned = await handleReturn();
  if (!returned) {
    const token = await get('token');
    await log('start', tokenText(token));
    const entries = (await get('log')) || [];
    const lastFail = entries.filter((e) => e.kind === 'needs-tap').pop();
    const failedRecently = lastFail && Date.now() - lastFail.t < RETRY_AFTER_MS;
    const auto = (await get('auto')) !== false;
    if (CLIENT_ID && auto && token && !valid(token) && !failedRecently) {
      await authorize(true);
      return;
    }
  }
  await render();
}

main().catch((e) => {
  $('banner').textContent = `Fehler: ${e.message}`;
});
