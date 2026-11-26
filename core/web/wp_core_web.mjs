// JS-Hülle um wp_core_web.wasm (#33). Läuft im AudioWorklet, in Workern, im Hauptthread und in Node.js.
// Der Kern braucht keine Emscripten-Laufzeit; die wenigen Importe (Dateizugriff) werden hier abgelehnt,
// weil es im Browser keine Dateipfade gibt.

export const WP_OK = 0;
export const WP_ERR_INVALID_ARGUMENT = -1;
export const WP_ERR_UNSUPPORTED_FORMAT = -3;
export const WP_ERR_OUT_OF_MEMORY = -5;
export const MAX_BLOCK = 4096;
// Frames the worklet copies per render block while taking over a title (#42): about 0.2 ms of work.
export const PCM_CHUNK = 32768;

const ENOSYS = 52;
const imports = {
  env: { emscripten_notify_memory_growth: () => {} },
  wasi_snapshot_preview1: {
    fd_write: () => ENOSYS,
    fd_read: () => ENOSYS,
    fd_close: () => ENOSYS,
    fd_seek: () => ENOSYS,
  },
};

// `wasm`: Bytes (ArrayBuffer/Uint8Array) oder ein bereits kompiliertes WebAssembly.Module.
export async function createCore(wasm, sampleRate) {
  const module = wasm instanceof WebAssembly.Module ? wasm : await WebAssembly.compile(wasm);
  const instance = await WebAssembly.instantiate(module, imports);
  instance.exports._initialize();
  return new WpCore(instance.exports, sampleRate);
}

// Wie createCore, aber synchron (für den Konstruktor des AudioWorklets, damit der erste Block schon
// rendert). `module`: WebAssembly.Module.
export function createCoreSync(module, sampleRate) {
  const instance = new WebAssembly.Instance(module, imports);
  instance.exports._initialize();
  return new WpCore(instance.exports, sampleRate);
}

export class WpCore {
  constructor(x, sampleRate) {
    this.x = x;
    this.p = x.wp_web_create(sampleRate);
    if (!this.p) throw new Error('Out of memory for the audio core');
    this.sampleRate = sampleRate;
  }

  get #heap() { return this.x.memory.buffer; }

  #withCopy(typed, fn) {
    const ptr = this.x.wp_web_alloc(typed.byteLength);
    if (!ptr) return WP_ERR_OUT_OF_MEMORY;
    try {
      new Uint8Array(this.#heap, ptr, typed.byteLength)
        .set(new Uint8Array(typed.buffer, typed.byteOffset, typed.byteLength));
      return fn(ptr);
    } finally {
      this.x.wp_web_free(ptr);
    }
  }

  errorMessage(code) {
    const ptr = this.x.wp_error_message(code);
    const mem = new Uint8Array(this.#heap);
    let end = ptr;
    while (mem[end]) end++;
    return new TextDecoder().decode(mem.subarray(ptr, end));
  }

  // MP3, WAV oder FLAC als Bytes. WP_OK oder Fehlercode (WP_ERR_UNSUPPORTED_FORMAT: z. B. AAC/M4A).
  loadEncoded(bytes) {
    const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
    return this.#withCopy(u8, (ptr) => this.x.wp_web_load_encoded(this.p, ptr, u8.byteLength));
  }

  // Dekodiertes PCM, ein Float32Array je Kanal (wie AudioBuffer.getChannelData), beliebige Samplerate.
  loadPcm(channels, sampleRate) {
    const n = channels.length;
    const frames = n ? channels[0].length : 0;
    if (!n || !frames || channels.some((c) => c.length !== frames)) return WP_ERR_INVALID_ARGUMENT;
    const inter = new Float32Array(frames * n);
    for (let c = 0; c < n; c++) {
      const src = channels[c];
      for (let i = 0; i < frames; i++) inter[i * n + c] = src[i];
    }
    return this.#withCopy(inter, (ptr) => this.x.wp_web_load_pcm(this.p, ptr, n, frames, sampleRate));
  }

  // Takes over a title decoded elsewhere (#42): interleaved stereo at this core's rate. Returns WP_OK or an
  // error code; then pumpPcm() moves it into the core piece by piece while the old title keeps playing.
  beginPcm(stereo) {
    this.pending = null;
    const frames = Math.floor(stereo.length / 2);
    const r = this.x.wp_web_pcm_begin(this.p, frames);
    if (r === WP_OK) this.pending = { stereo, frames, done: 0 };
    return r;
  }

  // Copies up to maxFrames of the pending title; null while there is more, else the result of the commit.
  pumpPcm(maxFrames = PCM_CHUNK) {
    const job = this.pending;
    if (!job) return WP_ERR_INVALID_ARGUMENT;
    const n = Math.min(maxFrames, job.frames - job.done);
    if (n > 0) {
      const part = job.stereo.subarray(job.done * 2, (job.done + n) * 2);
      const r = this.#withCopy(part, (ptr) => this.x.wp_web_pcm_append(this.p, ptr, n));
      if (r !== WP_OK) {
        this.pending = null;
        return r;
      }
      job.done += n;
      if (job.done < job.frames) return null;
    }
    this.pending = null;
    return this.x.wp_web_pcm_commit(this.p);
  }

  // Rendert left.length Frames (höchstens MAX_BLOCK) nach left und right, z. B. die Ausgänge des Worklets.
  render(left, right) {
    const frames = left.length;
    const ptr = this.x.wp_web_render(this.p, frames);
    const out = new Float32Array(this.#heap, ptr, frames * 2);
    for (let i = 0; i < frames; i++) {
      left[i] = out[2 * i];
      right[i] = out[2 * i + 1];
    }
  }

  play() { this.x.wp_play(this.p); }
  pause() { this.x.wp_pause(this.p); }
  get playing() { return this.x.wp_is_playing(this.p) !== 0; }
  seek(seconds) { this.x.wp_seek(this.p, seconds); }
  setRate(rate) { this.x.wp_set_rate(this.p, rate); }
  setLoop(a, b) { this.x.wp_set_loop(this.p, a, b); }
  setVolume(v) { this.x.wp_set_volume(this.p, v); }
  get position() { return this.x.wp_position(this.p); }
  get duration() { return this.x.wp_duration(this.p); }
  get loopPasses() { return Number(this.x.wp_loop_passes(this.p)); }

  waveform(start, end, count) {
    const ptr = this.x.wp_web_alloc(count * 8);
    try {
      const r = this.x.wp_waveform(this.p, start, end, count, ptr, ptr + count * 4);
      if (r !== WP_OK) return null;
      const all = new Float32Array(this.#heap, ptr, count * 2);
      return { mins: all.slice(0, count), maxs: all.slice(count) };
    } finally {
      this.x.wp_web_free(ptr);
    }
  }

  metroStart() { this.x.wp_metro_start(this.p); }
  metroStop() { this.x.wp_metro_stop(this.p); }
  get metroRunning() { return this.x.wp_metro_is_running(this.p) !== 0; }
  metroSetBpm(bpm) { this.x.wp_metro_set_bpm(this.p, bpm); }
  get metroBpm() { return this.x.wp_metro_bpm(this.p); }
  metroSetMeter(beats) { this.x.wp_metro_set_meter(this.p, beats); }
  metroSetSubdivision(clicks) { this.x.wp_metro_set_subdivision(this.p, clicks); }
  metroSetVolume(v) { this.x.wp_metro_set_volume(this.p, v); }
  // Steigerung nach Takten bzw. nach Zeit (#34, wie wp_metro_set_ramp und wp_metro_set_ramp_timed).
  metroSetRamp(enabled, start, target, step, every) {
    this.x.wp_metro_set_ramp(this.p, enabled ? 1 : 0, start, target, step, every);
  }
  metroSetTimedRamp(enabled, start, target, seconds) {
    this.x.wp_metro_set_ramp_timed(this.p, enabled ? 1 : 0, start, target, seconds);
  }
}

// Decoding without a player (#42), e.g. in a Worker next to the AudioWorklet. Each result holds the PCM
// (interleaved stereo at `sampleRate`, own buffer, transferable), the duration and the waveform
// (`bins` sections over the whole title, see WaveformSummary in the app), or only `code` on failure.
export async function createDecoder(wasm) {
  const module = wasm instanceof WebAssembly.Module ? wasm : await WebAssembly.compile(wasm);
  const instance = await WebAssembly.instantiate(module, imports);
  instance.exports._initialize();
  return new WpDecoder(instance.exports);
}

export class WpDecoder {
  constructor(x) { this.x = x; }

  #copyIn(typed, fn) {
    const ptr = this.x.wp_web_alloc(typed.byteLength);
    if (!ptr) return { code: WP_ERR_OUT_OF_MEMORY };
    try {
      new Uint8Array(this.x.memory.buffer, ptr, typed.byteLength)
        .set(new Uint8Array(typed.buffer, typed.byteOffset, typed.byteLength));
      return fn(ptr);
    } finally {
      this.x.wp_web_free(ptr);
    }
  }

  #result(make, bins) {
    const err = this.x.wp_web_alloc(4);
    try {
      const t = make(err);
      if (!t) return { code: new Int32Array(this.x.memory.buffer, err, 1)[0] || WP_ERR_UNSUPPORTED_FORMAT };
      try {
        const frames = this.x.wp_web_track_frames(t);
        const duration = this.x.wp_web_track_duration(t);
        const pcm = new Float32Array(this.x.memory.buffer, this.x.wp_web_track_data(t), frames * 2).slice();
        const count = Math.max(1, Math.min(bins.max, Math.ceil(duration * bins.perSecond)));
        const w = this.x.wp_web_alloc(count * 8);
        try {
          if (this.x.wp_web_track_waveform(t, 0, duration, count, w, w + count * 4) !== WP_OK) {
            return { code: WP_ERR_INVALID_ARGUMENT };
          }
          const all = new Float32Array(this.x.memory.buffer, w, count * 2);
          return { code: WP_OK, pcm, duration, mins: all.slice(0, count), maxs: all.slice(count) };
        } finally {
          this.x.wp_web_free(w);
        }
      } finally {
        this.x.wp_web_track_free(t);
      }
    } finally {
      this.x.wp_web_free(err);
    }
  }

  // MP3, WAV or FLAC. code WP_ERR_UNSUPPORTED_FORMAT: try decodeAudioData (AAC/M4A).
  decode(bytes, sampleRate, bins = { perSecond: 200, max: 400000 }) {
    const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
    return this.#copyIn(u8, (ptr) =>
      this.#result((err) => this.x.wp_web_track_decode(ptr, u8.byteLength, sampleRate, err), bins));
  }

  // #116: keeps [start, end] seconds of the file `bytes` (MP3, WAV, FLAC or AAC in ADTS; the same core
  // code as natively, so the browser cuts alike). { code, bytes, start, end }: the new file (own
  // buffer, transferable) and where it starts and ends in the old one, or only `code` on failure.
  trim(bytes, start, end) {
    const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
    return this.#copyIn(u8, (ptr) => {
      const out = this.x.wp_web_alloc(4);
      if (!out) return { code: WP_ERR_OUT_OF_MEMORY };
      try {
        const code = this.x.wp_trim(ptr, u8.byteLength, start, end, out);
        if (code !== WP_OK) return { code };
        const r = new Uint32Array(this.x.memory.buffer, out, 1)[0];
        try {
          const data = new Uint8Array(this.x.memory.buffer, this.x.wp_trim_data(r), this.x.wp_trim_size(r)).slice();
          return { code: WP_OK, bytes: data, start: this.x.wp_trim_start(r), end: this.x.wp_trim_end(r) };
        } finally {
          this.x.wp_trim_free(r);
        }
      } finally {
        this.x.wp_web_free(out);
      }
    });
  }

  // PCM as decodeAudioData returns it (one Float32Array per channel, any rate).
  convert(channels, srcRate, sampleRate, bins = { perSecond: 200, max: 400000 }) {
    const n = channels.length;
    const frames = n ? channels[0].length : 0;
    if (!n || !frames || channels.some((c) => c.length !== frames)) return { code: WP_ERR_INVALID_ARGUMENT };
    const inter = new Float32Array(frames * n);
    for (let c = 0; c < n; c++) {
      const src = channels[c];
      for (let i = 0; i < frames; i++) inter[i * n + c] = src[i];
    }
    return this.#copyIn(inter, (ptr) =>
      this.#result((err) => this.x.wp_web_track_convert(ptr, n, frames, srcRate, sampleRate, err), bins));
  }
}

// Recording without a player (#157), e.g. in a Worker next to the AudioWorklet that delivers the microphone.
export async function createRecordingCore(wasm) {
  const module = wasm instanceof WebAssembly.Module ? wasm : await WebAssembly.compile(wasm);
  const instance = await WebAssembly.instantiate(module, imports);
  instance.exports._initialize();
  return new WpRecordingCore(instance.exports);
}

// One recording at a time through wp_web_rec_* (wp_core_web.h): feed interleaved frames, take the encoded
// FLAC in pieces { offset, bytes }, finally write header() over the start of the file.
export class WpRecordingCore {
  constructor(x) {
    this.x = x;
    this.r = 0;
    this.channels = 0;
  }

  // { sampleRate, channels, armed, thresholdDb, silenceSeconds, tailSeconds }. 0 or WP_REC_ERR_*; ends a
  // recording still open here.
  start({ sampleRate, channels = 2, armed = false, thresholdDb = 0, silenceSeconds = 0, tailSeconds = 0 }) {
    this.free();
    const err = this.x.wp_web_alloc(4);
    try {
      this.r = this.x.wp_web_rec_create(sampleRate, channels, armed ? 1 : 0, thresholdDb, silenceSeconds,
        tailSeconds, err);
      this.channels = this.r ? channels : 0;
      return this.r ? WP_OK : new Int32Array(this.x.memory.buffer, err, 1)[0];
    } finally {
      this.x.wp_web_free(err);
    }
  }

  // Feeds interleaved frames (Float32Array of channels × frames). 0 or WP_REC_ERR_*.
  feed(interleaved) {
    const ch = this.channels;
    const frames = Math.floor(interleaved.length / ch);
    for (let done = 0; done < frames;) {
      const n = Math.min(MAX_BLOCK, frames - done);
      new Float32Array(this.x.memory.buffer, this.x.wp_web_rec_input(this.r), n * ch)
        .set(interleaved.subarray(done * ch, (done + n) * ch));
      const r = this.x.wp_web_rec_feed(this.r, n);
      if (r !== WP_OK) return r;
      done += n;
    }
    return WP_OK;
  }

  // The encoded bytes not taken yet (own buffer) and their offset in the file; null if there are none.
  // They count as taken: if storing them fails, call cut().
  take() {
    const size = this.x.wp_web_rec_out_size(this.r);
    if (!size) return null;
    const offset = this.x.wp_web_rec_out_offset(this.r);
    const bytes = new Uint8Array(this.x.memory.buffer, this.x.wp_web_rec_out(this.r), size).slice();
    this.x.wp_web_rec_take(this.r);
    return { offset, bytes };
  }

  finish() { return this.x.wp_web_rec_finish(this.r); }
  // The last piece of take() was not stored: returns the length the file must be cut to.
  cut() { return this.x.wp_web_rec_cut(this.r); }
  header() {
    return new Uint8Array(this.x.memory.buffer, this.x.wp_web_rec_header(this.r),
      this.x.wp_web_rec_header_size(this.r)).slice();
  }

  get gate() { return this.x.wp_web_rec_gate(this.r); }
  get seconds() { return this.x.wp_web_rec_seconds(this.r); }
  get keptSeconds() { return this.x.wp_web_rec_kept_seconds(this.r); }
  // Peak since the last call.
  takeLevel() { return this.x.wp_web_rec_level(this.r); }
  get onlySilence() { return this.x.wp_web_rec_only_silence(this.r) !== 0; }

  free() {
    if (this.r) this.x.wp_web_rec_free(this.r);
    this.r = 0;
    this.channels = 0;
  }
}

// Lädt eine Datei: zuerst der Kern (MP3, WAV, FLAC), sonst der Browser (AAC/M4A u. a.) über
// `decodeAudioData` (z. B. ctx.decodeAudioData.bind(ctx); im Worklet nicht verfügbar, dort übernimmt
// der Hauptthread diesen Schritt und schickt das PCM). WP_OK oder Fehlercode.
export async function loadFile(core, bytes, decodeAudioData) {
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  const r = core.loadEncoded(u8);
  if (r !== WP_ERR_UNSUPPORTED_FORMAT || !decodeAudioData) return r;
  let buffer;
  try {
    // decodeAudioData übernimmt den Puffer, darum eine Kopie.
    buffer = await decodeAudioData(u8.slice().buffer);
  } catch {
    return WP_ERR_UNSUPPORTED_FORMAT;
  }
  const channels = [];
  for (let c = 0; c < buffer.numberOfChannels; c++) channels.push(buffer.getChannelData(c));
  return core.loadPcm(channels, buffer.sampleRate);
}
