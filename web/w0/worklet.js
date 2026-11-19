// Machbarkeitstest W0 (#32): der Audio-Kern (WebAssembly) rendert im AudioWorklet.
// Nachrichten vom Hauptthread: wasm, source, cmd, sab. Status geht über SharedArrayBuffer
// (wenn verfügbar) und zusätzlich alle ~100 ms per postMessage zurück.

const BLOCK = 128;

class W0Processor extends AudioWorkletProcessor {
  constructor() {
    super();
    this.w = null;          // Exporte der WASM-Instanz
    this.view = null;       // Float32Array auf den WASM-Speicher
    this.viewBuffer = null; // ArrayBuffer, auf dem `view` liegt (wechselt bei Speicherwachstum)
    this.status = null;     // Float64Array auf SharedArrayBuffer
    this.blocks = 0;
    this.busyMs = 0;
    this.loadPeak = 0;
    this.lastReport = 0;
    // Nachrichten der Reihe nach abarbeiten: ein Titel darf erst nach dem Laden des Kerns ankommen.
    this.queue = Promise.resolve();
    this.port.onmessage = (e) => { this.queue = this.queue.then(() => this.onMessage(e.data)); };
  }

  async onMessage(m) {
    try {
      if (m.type === 'wasm') {
        const { instance } = await WebAssembly.instantiate(m.bytes, {
          env: { emscripten_notify_memory_growth: () => {} },
        });
        this.w = instance.exports;
        this.w._initialize();
        this.w.w0_init(sampleRate);
        this.port.postMessage({ type: 'ready', sampleRate });
      } else if (m.type === 'sab') {
        this.status = new Float64Array(m.sab);
      } else if (m.type === 'source') {
        const frames = m.left.length;
        const ptr = this.w.w0_alloc_source(frames);
        const mem = new Float32Array(this.w.memory.buffer, ptr, frames * 2);
        for (let i = 0; i < frames; i++) {
          mem[2 * i] = m.left[i];
          mem[2 * i + 1] = m.right[i];
        }
        this.w.w0_commit_source();
        this.port.postMessage({ type: 'loaded', duration: this.w.w0_duration() });
      } else if (m.type === 'cmd') {
        const w = this.w;
        switch (m.name) {
          case 'play': w.w0_play(); break;
          case 'pause': w.w0_pause(); break;
          case 'seek': w.w0_seek(m.a); break;
          case 'rate': w.w0_set_rate(m.a); break;
          case 'loop': w.w0_set_loop(m.a, m.b); break;
          case 'volume': w.w0_set_volume(m.a); break;
          case 'metronome': w.w0_metronome(m.on ? 1 : 0, m.bpm, m.volume); break;
        }
      }
    } catch (err) {
      this.port.postMessage({ type: 'error', message: String(err) });
    }
  }

  process(_inputs, outputs) {
    const out = outputs[0];
    if (!this.w || out.length === 0) return true;
    const n = out[0].length || BLOCK;
    const t0 = Date.now();
    const ptr = this.w.w0_render(n);
    const buf = this.w.memory.buffer;
    if (buf !== this.viewBuffer) {
      this.viewBuffer = buf;
      this.view = new Float32Array(buf);
    }
    const base = ptr >> 2;
    const l = out[0];
    const r = out.length > 1 ? out[1] : null;
    for (let i = 0; i < n; i++) {
      l[i] = this.view[base + 2 * i];
      if (r) r[i] = this.view[base + 2 * i + 1];
    }

    // Grobe Last: Rechenzeit gegen Blockdauer, über ~1 s gemittelt (Date.now hat nur ms-Auflösung).
    this.busyMs += Date.now() - t0;
    this.blocks++;
    const blockMs = (n / sampleRate) * 1000;
    if (this.blocks >= 375) {
      const load = this.busyMs / (this.blocks * blockMs);
      if (load > this.loadPeak) this.loadPeak = load;
      this.lastLoad = load;
      this.blocks = 0;
      this.busyMs = 0;
    }

    const w = this.w;
    if (this.status) {
      const s = this.status;
      s[0] = w.w0_position();
      s[1] = w.w0_duration();
      s[2] = w.w0_playing();
      s[3] = w.w0_loop_passes();
      s[4] = w.w0_tick_deviation_ms();
      s[5] = w.w0_tick_count();
      s[6] = this.lastLoad || 0;
      s[7] = this.loadPeak;
      s[8] = currentTime;
    }
    if (currentTime - this.lastReport > 0.1) {
      this.lastReport = currentTime;
      this.port.postMessage({
        type: 'status',
        position: w.w0_position(),
        duration: w.w0_duration(),
        playing: w.w0_playing(),
        loopPasses: w.w0_loop_passes(),
        tickDevMs: w.w0_tick_deviation_ms(),
        ticks: w.w0_tick_count(),
        load: this.lastLoad || 0,
        loadPeak: this.loadPeak,
      });
    }
    return true;
  }
}

registerProcessor('w0-processor', W0Processor);
