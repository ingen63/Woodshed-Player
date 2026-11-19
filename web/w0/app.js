// Machbarkeitstest W0 (#32): Hauptthread der Testseite.
'use strict';

const $ = (id) => document.getElementById(id);
const lines = [];
function log(msg) {
  const t = new Date().toLocaleTimeString('de-CH');
  lines.push(`${t}  ${msg}`);
  $('log').textContent = lines.slice(-200).join('\n');
  $('log').scrollTop = 1e9;
}
function dl(el, rows) {
  el.innerHTML = rows.map(([k, v, cls]) => `<dt>${k}</dt><dd class="${cls || ''}">${v}</dd>`).join('');
}
const yes = (b) => (b ? ['ja', 'ok'] : ['nein', 'bad']);
const mmss = (s) => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;

// ---------- Service Worker (COOP/COEP) und Umgebung ----------

async function setupServiceWorker() {
  if (!('serviceWorker' in navigator)) return log('Kein Service Worker verfügbar');
  try {
    await navigator.serviceWorker.register('sw.js', { scope: './' });
    await navigator.serviceWorker.ready;
    // Ohne Isolation einmal neu laden, damit der Service Worker die Header setzen kann.
    if (!self.crossOriginIsolated) {
      if (!sessionStorage.getItem('w0-reloaded')) {
        sessionStorage.setItem('w0-reloaded', '1');
        location.reload();
        return;
      }
      log('Nach Neuladen nicht cross-origin isolated');
    }
  } catch (err) {
    log(`Service Worker: ${err}`);
  }
}

function standalone() {
  return matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
}

function showEnv() {
  const sab = typeof SharedArrayBuffer !== 'undefined';
  const [iso, isoC] = yes(self.crossOriginIsolated);
  const [s, sC] = yes(sab);
  const [w, wC] = yes(typeof AudioWorkletNode !== 'undefined');
  const [o, oC] = yes(!!navigator.storage?.getDirectory);
  dl($('env'), [
    ['Browser', navigator.userAgent.replace(/\) .*$/, ')').slice(0, 80)],
    ['Cross-Origin isolated', iso, isoC],
    ['SharedArrayBuffer', s, sC],
    ['SAB im Worklet', sabInWorklet === null ? 'nach «Audio starten»' : yes(sabInWorklet)[0], sabInWorklet === null ? '' : yes(sabInWorklet)[1]],
    ['AudioWorklet', w, wC],
    ['OPFS', o, oC],
    ['audioSession', navigator.audioSession ? 'ja' : 'nein'],
    ['Installiert (standalone)', standalone() ? 'ja' : 'nein'],
  ]);
}

// ---------- Audio ----------

let ctx = null;
let node = null;
let streamDest = null;
let sab = null;
let sabInWorklet = null;
let st = {};
let rate = 1;

function makeTestSignal(sr) {
  // 30 s, 120 BPM: gezupfte Töne je Schlag (mit Obertönen) über einem Grundton 110 Hz.
  // Der Grundton hat in jedem ganzen Takt (2 s) eine ganze Zahl Perioden, ein Loop auf
  // Taktgrenzen ist im Signal also nahtlos; jedes Knacken kommt vom Kern.
  const seconds = 30, n = sr * seconds;
  const L = new Float32Array(n), R = new Float32Array(n);
  const scale = [220, 247.5, 275, 293.3, 330, 366.7, 412.5, 440];
  for (let i = 0; i < n; i++) {
    const t = i / sr;
    const drone = 0.12 * Math.sin(2 * Math.PI * 110 * t);
    const beat = Math.floor(t * 2), tb = t - beat / 2;
    const f = scale[(beat * 3) % scale.length];
    const env = Math.exp(-tb * 6);
    let note = 0;
    for (let h = 1; h <= 4; h++) note += Math.sin(2 * Math.PI * f * h * tb) / (h * h);
    note *= 0.3 * env * Math.min(1, tb * 400);
    L[i] = drone + note * 0.9;
    R[i] = drone + note * 0.7;
  }
  return [L, R];
}

// Startet Audio einmal; das Versprechen erfüllt sich, wenn der Kern im Worklet bereit ist.
let starting = null;
let coreReady = null;
let userFile = false;
let titleName = 'Testsignal';  // nur auf der Seite angezeigt, nie im Protokoll
function startAudio() {
  starting = starting || doStartAudio().catch((err) => { starting = null; throw err; });
  return starting;
}

async function doStartAudio() {
  const ready = new Promise((resolve) => { coreReady = resolve; });
  ctx = new AudioContext({ latencyHint: 'playback' });
  ctx.onstatechange = () => log(`AudioContext: ${ctx.state}`);
  applySession();
  await ctx.audioWorklet.addModule('worklet.js');
  node = new AudioWorkletNode(ctx, 'w0-processor', { numberOfInputs: 0, outputChannelCount: [2] });
  node.port.onmessage = (e) => onWorklet(e.data);
  const bytes = await (await fetch('w0.wasm')).arrayBuffer();
  node.port.postMessage({ type: 'wasm', bytes }, [bytes]);

  if (typeof SharedArrayBuffer !== 'undefined' && self.crossOriginIsolated) {
    try {
      sab = new SharedArrayBuffer(16 * 8);
      node.port.postMessage({ type: 'sab', sab });
    } catch (err) {
      log(`SAB an Worklet: ${err}`);
      sab = null;
    }
  }
  connectRoute();
  setupMediaSession();
  await ready;
  // Sichtbar machen, dass Audio läuft und es mit «Abspielen» weitergeht.
  $('start').disabled = true;
  $('start').textContent = 'Audio bereit';
  $('start').classList.remove('primary');
  $('play').classList.add('primary');
}

function onWorklet(m) {
  if (m.type === 'ready') {
    log(`Kern bereit, ${m.sampleRate} Hz, Latenz base ${ms(ctx.baseLatency)}, output ${ms(ctx.outputLatency)}`);
    if (!userFile) {
      const [L, R] = makeTestSignal(m.sampleRate);
      node.port.postMessage({ type: 'source', left: L, right: R }, [L.buffer, R.buffer]);
    }
    coreReady();
  } else if (m.type === 'loaded') {
    log(`Titel geladen, ${m.duration.toFixed(1)} s`);
    for (const b of ['play', 'pause', 'seek0']) $(b).disabled = false;
    sendLoop();
    sendRate();
  } else if (m.type === 'status') {
    st = m;
    if (sab) {
      const s = new Float64Array(sab);
      sabInWorklet = s[8] > 0;  // der Worklet schreibt currentTime hinein
    }
  } else if (m.type === 'error') {
    log(`Fehler im Worklet: ${m.message}`);
  }
}

const ms = (s) => (typeof s === 'number' ? `${(s * 1000).toFixed(1)} ms` : 'unbekannt');
const cmd = (name, extra = {}) => node && node.port.postMessage({ type: 'cmd', name, ...extra });

function connectRoute() {
  if (!node) return;
  node.disconnect();
  const sink = $('sink');
  if ($('route').value === 'element') {
    streamDest = streamDest || ctx.createMediaStreamDestination();
    node.connect(streamDest);
    sink.srcObject = streamDest.stream;
    sink.play().catch((err) => log(`<audio>.play: ${err}`));
    log('Ausgabe über <audio>-Element');
  } else {
    sink.pause();
    sink.srcObject = null;
    node.connect(ctx.destination);
    log('Ausgabe Web Audio direkt');
  }
}

function applySession() {
  if (!navigator.audioSession) return;
  navigator.audioSession.type = $('session').checked ? 'playback' : 'auto';
  log(`audioSession.type = ${navigator.audioSession.type}`);
}

function setupMediaSession() {
  if (!('mediaSession' in navigator)) return;
  navigator.mediaSession.metadata = new MediaMetadata({ title: 'Testsignal', artist: 'Woodshed W0' });
  navigator.mediaSession.setActionHandler('play', () => play());
  navigator.mediaSession.setActionHandler('pause', () => pause());
}

async function play() {
  await startAudio();
  await ctx.resume();
  if ($('route').value === 'element') $('sink').play().catch(() => {});
  cmd('play');
  if ('mediaSession' in navigator) navigator.mediaSession.playbackState = 'playing';
}

function pause() {
  cmd('pause');
  // Pause hält auch das Metronom an, sonst klickt es nach dem Test weiter.
  if ($('metOn').checked) {
    $('metOn').checked = false;
    sendMetronome();
  }
  if ('mediaSession' in navigator) navigator.mediaSession.playbackState = 'paused';
}

function sendRate() {
  cmd('rate', { a: rate });
  document.querySelectorAll('.rate').forEach((b) => b.setAttribute('aria-pressed', String(Number(b.dataset.rate) === rate)));
}

function sendLoop() {
  const on = $('loopOn').checked;
  cmd('loop', on ? { a: Number($('loopA').value), b: Number($('loopB').value) } : { a: 0, b: 0 });
}

function sendMetronome() {
  cmd('metronome', { on: $('metOn').checked, bpm: Number($('bpm').value) || 120, volume: 0.7 });
}

async function loadFile(file) {
  userFile = true;
  titleName = file.name;
  log(`Datei gewählt: ${(file.size / 1e6).toFixed(1)} MB, Typ «${file.type || 'unbekannt'}»`);
  await startAudio();
  let buf;
  try {
    buf = await ctx.decodeAudioData(await file.arrayBuffer());
  } catch (err) {
    throw new Error(`Dekodieren fehlgeschlagen (${err && err.name ? err.name : err}). Format vom Browser nicht unterstützt?`);
  }
  log(`Dekodiert: ${buf.duration.toFixed(1)} s, ${buf.numberOfChannels} Kanäle, ${buf.sampleRate} Hz`);
  const L = new Float32Array(buf.getChannelData(0));
  const R = new Float32Array(buf.numberOfChannels > 1 ? buf.getChannelData(1) : buf.getChannelData(0));
  node.port.postMessage({ type: 'source', left: L, right: R }, [L.buffer, R.buffer]);
  log('Eigene Datei geladen (bleibt auf dem Gerät)');
}

function showStatus() {
  const s = st;
  const devOk = s.ticks > 1 ? (s.tickDevMs < 20 ? 'ok' : 'bad') : '';
  const loadCls = s.loadPeak > 0.8 ? 'bad' : s.loadPeak > 0 ? 'ok' : '';
  dl($('status'), [
    ['Titel', titleName],
    ['Position', s.duration ? `${mmss(s.position)} / ${mmss(s.duration)}` : '–'],
    ['Läuft', s.playing ? 'ja' : 'nein'],
    ['Loop-Durchgänge', s.loopPasses ?? '–'],
    ['Metronom-Klicks', s.ticks ?? '–'],
    ['Klick-Abweichung max', s.ticks > 1 ? `${s.tickDevMs.toFixed(3)} ms` : '–', devOk],
    ['Ausgabelatenz', ctx ? `${ms(ctx.baseLatency)} + ${ms(ctx.outputLatency)}` : '–'],
    ['Last (1 s / Spitze)', s.load !== undefined ? `${(s.load * 100).toFixed(0)} % / ${(s.loadPeak * 100).toFixed(0)} %` : '–', loadCls],
  ]);
}

// ---------- Sperrbildschirm und Hintergrund ----------

let hiddenAt = null;
const life = { checks: [] };

function onVisibility() {
  if (document.visibilityState === 'hidden') {
    hiddenAt = { wall: performance.now(), pos: st.position || 0, playing: !!st.playing, ctxTime: ctx ? ctx.currentTime : 0 };
    log('Seite verborgen');
    return;
  }
  log('Seite wieder sichtbar');
  if (!hiddenAt || !hiddenAt.playing || !ctx) return;
  // Kurz warten, bis frischer Status vom Worklet da ist.
  setTimeout(() => {
    const away = (performance.now() - hiddenAt.wall) / 1000;
    const audioRan = ctx.currentTime - hiddenAt.ctxTime;
    const ratio = away > 0 ? audioRan / away : 0;
    const route = $('route').value === 'element' ? '<audio>' : 'direkt';
    const result = { route, away, audioRan, ok: ratio > 0.9 };
    life.checks.push(result);
    log(`Hintergrund ${away.toFixed(0)} s (${route}): Audio lief ${audioRan.toFixed(0)} s → ${result.ok ? 'durchgespielt' : 'unterbrochen'}`);
    showLife();
  }, 300);
}

function showLife() {
  const rows = [['AudioContext', ctx ? ctx.state : '–']];
  life.checks.slice(-4).forEach((c, i) => rows.push([
    `Hintergrund ${i + 1} (${c.route})`,
    `${c.away.toFixed(0)} s weg, ${c.audioRan.toFixed(0)} s gespielt`,
    c.ok ? 'ok' : 'bad',
  ]));
  dl($('life'), rows);
}

// ---------- OPFS ----------

let opfs = null;
function opfsWorker() {
  if (opfs) return opfs;
  opfs = new Worker('opfs-worker.js');
  opfs.onmessage = (e) => onOpfs(e.data);
  return opfs;
}

async function storageInfo() {
  const rows = [];
  if (navigator.storage?.persisted) rows.push(['Dauerhaft (persist)', (await navigator.storage.persisted()) ? 'ja' : 'nein']);
  if (navigator.storage?.estimate) {
    const e = await navigator.storage.estimate();
    rows.push(['Belegt / Kontingent', `${(e.usage / 1e6).toFixed(0)} MB / ${(e.quota / 1e6).toFixed(0)} MB`]);
  }
  return rows;
}

let storeRows = [];
async function showStore(extra) {
  if (extra) storeRows = extra;
  dl($('store'), [...storeRows, ...(await storageInfo())]);
}

function onOpfs(m) {
  if (m.type === 'progress') {
    $('prog').max = m.total;
    $('prog').value = m.done;
  } else if (m.type === 'written') {
    log(`OPFS: ${m.meta.mb} MB geschrieben`);
    showStore([['Geschrieben', `${m.meta.mb} MB am ${new Date(m.meta.writtenAt).toLocaleString('de-CH')}`]]);
  } else if (m.type === 'verified') {
    if (!m.present) {
      log('OPFS: Testdatei fehlt');
      showStore([['Testdatei', 'fehlt', 'bad']]);
      return;
    }
    const days = m.meta ? (Date.now() - Date.parse(m.meta.writtenAt)) / 864e5 : NaN;
    const complete = m.meta && m.mb === m.meta.mb && m.bad === 0;
    log(`OPFS: ${m.mb} MB vorhanden, ${m.bad} fehlerhafte MB, Alter ${days.toFixed(1)} Tage`);
    showStore([
      ['Testdatei', `${m.mb} MB, ${m.bad} fehlerhaft`, complete ? 'ok' : 'bad'],
      ['Alter', `${days.toFixed(1)} Tage${days >= 7 ? '' : ' (Ziel 7)'}`, days >= 7 && complete ? 'ok' : ''],
    ]);
  } else if (m.type === 'removed') {
    log('OPFS: gelöscht');
    showStore([['Testdatei', 'gelöscht']]);
  } else if (m.type === 'error') {
    log(`OPFS-Fehler: ${m.message}`);
  }
}

// ---------- Oberfläche ----------

function wire() {
  $('start').onclick = () => startAudio().catch((err) => log(`Start: ${err}`));
  $('play').onclick = () => play();
  $('pause').onclick = () => pause();
  $('seek0').onclick = () => cmd('seek', { a: 0 });
  document.querySelectorAll('.rate').forEach((b) => (b.onclick = () => { rate = Number(b.dataset.rate); sendRate(); }));
  for (const id of ['loopOn', 'loopA', 'loopB']) $(id).onchange = sendLoop;
  for (const id of ['metOn', 'bpm']) $(id).onchange = sendMetronome;
  $('route').onchange = connectRoute;
  $('session').onchange = applySession;
  // Erst beim Öffnen der Auswahl leeren: der Name bleibt sichtbar, dieselbe Datei lässt sich erneut wählen.
  $('file').onclick = (e) => { e.target.value = ''; };
  $('file').onchange = (e) => {
    const f = e.target.files[0];
    if (f) loadFile(f).catch((err) => log(`Datei: ${err.message || err}`));
  };
  $('write').onclick = async () => {
    if (navigator.storage?.persist) log(`persist(): ${await navigator.storage.persist()}`);
    opfsWorker().postMessage({ type: 'write', mb: Number($('mb').value) || 500 });
  };
  $('verify').onclick = () => opfsWorker().postMessage({ type: 'verify' });
  $('remove').onclick = () => opfsWorker().postMessage({ type: 'remove' });
  $('copy').onclick = () => {
    // Ohne die Zeile «Titel»: der Dateiname bleibt auf dem Gerät.
    const status = $('status').innerText.split('\n').slice(2).join('\n');
    const text = [$('env').innerText, status, $('life').innerText, $('store').innerText, '', ...lines].join('\n');
    navigator.clipboard.writeText(text).then(() => log('In die Zwischenablage kopiert'), (err) => log(`Kopieren: ${err}`));
  };
  document.addEventListener('visibilitychange', onVisibility);
  $('sink').onpause = () => log('<audio> pausiert');
  setInterval(() => { showStatus(); showEnv(); if (ctx) showLife(); }, 250);
}

(async () => {
  wire();
  showEnv();
  showStatus();
  showStore([]);
  await setupServiceWorker();
  showEnv();
  log(`Bereit. Isoliert: ${self.crossOriginIsolated}, installiert: ${standalone()}`);
})();
