// Worker that records in the web app (#157). It runs its own instance of wp_core_web.wasm (wp_web_rec_*: the
// same sound gate as natively, FLAC with 24 bits) and stores the file piece by piece in the Origin Private
// File System, folder WoodshedPlayerRecordings, through a synchronous access handle (only Workers have one).
// The microphone comes from the AudioWorklet processor «wp-mic» (wp_worklet.js) over a MessagePort.
// Created as new Worker('wp_recorder.js', { type: 'module' }). Messages: { id, cmd, args } in, { id, result }
// or { id, error } out, one command after the other. Commands:
//   init [module]           compiled wp_core_web.wasm (WebAssembly.Module); true if this browser can store a
//                           recording (synchronous OPFS access, only in Workers), else false
//   start [options, port]   options { name, sampleRate, channels, armed, thresholdDb, silenceSeconds,
//                           tailSeconds }; port: the MessagePort «wp-mic» sends to. 0 or WP_REC_ERR_*
//   stop []                 waits for { end } on the port (at most 1 s), finishes the file:
//                           { code, size, seconds, keptSeconds, interrupted }
// While recording it sends { status: { gate, seconds, keptSeconds, level, silent, interrupted } } about every
// 50 ms of audio. `interrupted` is 'storage' when the storage was full (#157/AK8: the file ends with what was
// stored, nothing more is recorded) or 'error' when the core or the file failed.
import { createRecordingCore, WP_OK } from './wp_core_web.mjs';

const DIR = 'WoodshedPlayerRecordings';
const WP_REC_ERR_FILE = -8;
const STATUS_EVERY = 0.05; // seconds of audio between two status messages
const END_WAIT = 1000; // ms a stop waits for the last block of the worklet

let core = null;
let job = null;

async function folder() {
  const root = await navigator.storage.getDirectory();
  return root.getDirectoryHandle(DIR, { create: true });
}

function isQuota(err) {
  return err && (err.name === 'QuotaExceededError' || err.code === 22);
}

function status(j) {
  self.postMessage({
    status: {
      name: j.name,
      gate: core.gate,
      seconds: core.seconds,
      keptSeconds: core.keptSeconds,
      level: core.takeLevel(),
      silent: core.onlySilence,
      interrupted: j.interrupted,
    },
  });
}

// Stores what the core encoded since the last call; storage full ends the file before that piece.
function store(j) {
  const piece = core.take();
  if (!piece || j.interrupted) return;
  try {
    const n = j.file.write(piece.bytes, { at: piece.offset });
    if (n !== piece.bytes.length) throw new DOMException('Short write', 'QuotaExceededError');
    j.size = piece.offset + piece.bytes.length;
  } catch (err) {
    j.interrupted = isQuota(err) ? 'storage' : 'error';
    j.size = core.cut();
    j.cutting = (async () => {
      await j.file.truncate(j.size);
      writeHeader(j);
    })();
    status(j);
  }
}

// The final stream info over the start of the file (if the file holds it).
function writeHeader(j) {
  const head = core.header();
  if (!head.length || j.size < head.length) return;
  try {
    j.file.write(head, { at: 0 });
  } catch {
    // the first bytes exist already, so this does not need more space; nothing else to do
  }
}

function onAudio(j, data) {
  if (data.end) {
    j.ended = true;
    if (j.onEnd) j.onEnd();
    return;
  }
  if (!data.frames || j.interrupted || j.stopped) return;
  const r = core.feed(data.frames);
  store(j);
  if (r !== WP_OK && !j.interrupted) {
    j.interrupted = 'error';
    status(j);
    return;
  }
  j.since += data.frames.length / j.channels;
  if (j.since >= j.every) {
    j.since = 0;
    status(j);
  }
}

async function start(options, port) {
  if (job) await stop();
  const dir = await folder();
  const handle = await dir.getFileHandle(options.name, { create: true });
  const file = await handle.createSyncAccessHandle();
  await file.truncate(0);
  const code = core.start(options);
  if (code !== WP_OK) {
    await file.close();
    await dir.removeEntry(options.name);
    return code;
  }
  const channels = options.channels || 2;
  const j = {
    name: options.name,
    file,
    port,
    channels,
    size: 0,
    since: 0,
    every: Math.round(STATUS_EVERY * options.sampleRate),
    interrupted: null,
    ended: false,
    stopped: false,
  };
  job = j;
  port.onmessage = ({ data }) => onAudio(j, data);
  store(j);
  status(j);
  return WP_OK;
}

async function stop() {
  const j = job;
  if (!j) return { code: WP_OK, size: 0, seconds: 0, keptSeconds: 0, interrupted: null };
  if (!j.ended) {
    await new Promise((resolve) => {
      const timer = setTimeout(resolve, END_WAIT);
      j.onEnd = () => {
        clearTimeout(timer);
        resolve();
      };
    });
  }
  j.stopped = true;
  j.port.onmessage = null;
  j.port.close();
  let code = WP_OK;
  if (j.cutting) await j.cutting;
  if (!j.interrupted) {
    code = core.finish();
    store(j);
    if (j.cutting) await j.cutting;
    writeHeader(j);
  }
  if (j.interrupted === 'error') code = WP_REC_ERR_FILE;
  const result = {
    code,
    size: j.size,
    seconds: core.seconds,
    keptSeconds: core.keptSeconds,
    interrupted: j.interrupted,
  };
  status(j);
  await j.file.flush();
  await j.file.close();
  core.free();
  job = null;
  return result;
}

async function run(cmd, args) {
  if (cmd === 'init') {
    const sync = typeof FileSystemFileHandle !== 'undefined' &&
      'createSyncAccessHandle' in FileSystemFileHandle.prototype && !!navigator.storage?.getDirectory;
    if (!sync) return false;
    core = await createRecordingCore(args[0]);
    return true;
  }
  if (!core) throw new Error('Recorder not initialised');
  if (cmd === 'start') return start(args[0], args[1]);
  if (cmd === 'stop') return stop();
  throw new Error(`Unknown command ${cmd}`);
}

// One command after the other: a start waits for the stop before it.
let queue = Promise.resolve();
self.onmessage = ({ data: { id, cmd, args = [] } }) => {
  queue = queue.then(async () => {
    try {
      self.postMessage({ id, result: await run(cmd, args) });
    } catch (err) {
      self.postMessage({ id, error: String(err) });
    }
  });
};
