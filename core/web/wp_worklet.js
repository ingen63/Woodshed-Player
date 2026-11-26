// AudioWorklet-Prozessor «wp-core» (#33): der Audio-Kern im Browser. Wird mit
//   new AudioWorkletNode(ctx, 'wp-core', { outputChannelCount: [2], processorOptions: { module } })
// angelegt, `module` ist das kompilierte wp_core_web.wasm (WebAssembly.Module). Befehle kommen über
// node.port als { id, cmd, args }, Antworten als { id, result } bzw. { id, error } zurück.
// processorOptions.init: Befehle [{ cmd, args }], die vor dem ersten Block ausgeführt werden.
// processorOptions.stateEvery (Sekunden, #34): schickt so oft unaufgefordert { state } mit dem Zustand
// wie cmd 'state', dazu `peak` (Spitzenpegel der Ausgabe seit dem letzten Mal, 0–1), `time` (Audiozeit
// am Ende des Blocks, Sekunden) und `ack` (id des zuletzt ausgeführten Befehls, damit der Hauptthread
// veraltete Zustände erkennt).
// MP3, WAV und FLAC dekodiert der Kern hier selbst (cmd 'loadEncoded'). AAC/M4A meldet er als
// WP_ERR_UNSUPPORTED_FORMAT; dann dekodiert der Hauptthread mit decodeAudioData und schickt das PCM
// (cmd 'loadPcm'), siehe loadFile in wp_core_web.mjs.
// #42: the app decodes in a Worker (wp_loader.js) and only sends the finished PCM (cmd 'beginPcm', interleaved
// stereo at this rate). The worklet takes it over in small pieces after each render block, so playback and
// metronome go on; the reply comes once the new title is in place. A newer 'beginPcm' cancels an older one.
// The state also carries `wall` (Date.now() when it was sent) to measure gaps against the wall clock and
// `busy` (longest single command or render block since the last state, milliseconds).
import { createCoreSync, MAX_BLOCK, WP_OK } from './wp_core_web.mjs';

const WP_ERR_CANCELLED = -7;

const QUERIES = ['playing', 'position', 'duration', 'loopPasses', 'metroRunning', 'metroBpm'];

class WpCoreProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const { module, init = [], stateEvery = 0 } = options.processorOptions;
    this.core = createCoreSync(module, sampleRate);
    this.stateFrames = Math.round(stateEvery * sampleRate);
    this.sinceState = 0;
    this.peak = 0;
    this.ack = 0;
    this.busy = 0;
    this.initResults = init.map(({ cmd, args }) => this.run(cmd, args));
    this.port.onmessage = (e) => this.handle(e.data);
  }

  run(cmd, args = []) {
    if (cmd === 'state') return Object.fromEntries(QUERIES.map((q) => [q, this.core[q]]));
    if (cmd === 'initResults') return this.initResults;
    if (typeof this.core[cmd] === 'function' && cmd !== 'render') return this.core[cmd](...args);
    throw new Error(`Unbekannter Befehl ${cmd}`);
  }

  handle(msg) {
    const t0 = Date.now();
    this.dispatch(msg);
    this.busy = Math.max(this.busy, Date.now() - t0);
  }

  dispatch({ id, cmd, args = [] }) {
    if (typeof id === 'number' && id > this.ack) this.ack = id;
    if (cmd === 'beginPcm') {
      this.beginPcm(id, args[0]);
      return;
    }
    try {
      this.port.postMessage({ id, result: this.run(cmd, args) });
    } catch (err) {
      this.port.postMessage({ id, error: String(err) });
    }
  }

  beginPcm(id, stereo) {
    if (this.pcmId !== undefined) this.port.postMessage({ id: this.pcmId, result: WP_ERR_CANCELLED });
    this.pcmId = undefined;
    const r = this.core.beginPcm(stereo);
    if (r === WP_OK) this.pcmId = id;
    else this.port.postMessage({ id, result: r });
  }

  pumpPcm() {
    const r = this.core.pumpPcm();
    if (r === null) return;
    this.port.postMessage({ id: this.pcmId, result: r });
    this.pcmId = undefined;
  }

  process(_inputs, outputs) {
    const t0 = Date.now();
    const r = this.renderBlock(outputs);
    this.busy = Math.max(this.busy, Date.now() - t0);
    return r;
  }

  renderBlock(outputs) {
    const out = outputs[0];
    if (out.length < 2) return true;
    for (let done = 0; done < out[0].length; done += MAX_BLOCK) {
      const end = Math.min(out[0].length, done + MAX_BLOCK);
      this.core.render(out[0].subarray(done, end), out[1].subarray(done, end));
    }
    if (this.stateFrames > 0) this.pushState(out);
    if (this.pcmId !== undefined) this.pumpPcm();
    return true;
  }

  pushState(out) {
    let peak = this.peak;
    for (const ch of out) {
      for (let i = 0; i < ch.length; i++) {
        const v = Math.abs(ch[i]);
        if (v > peak) peak = v;
      }
    }
    this.peak = peak;
    this.sinceState += out[0].length;
    if (this.sinceState < this.stateFrames) return;
    this.port.postMessage({ state: { ...this.run('state'), peak, ack: this.ack, time: currentTime, wall: Date.now(), busy: this.busy } });
    this.busy = 0;
    this.sinceState = 0;
    this.peak = 0;
  }
}

registerProcessor('wp-core', WpCoreProcessor);

// #157: processor «wp-mic»: hands the microphone (its input) to the recording worker (wp_recorder.js). The
// main thread sends { port } (a MessagePort to the worker); from then on the input goes there as interleaved
// Float32Array blocks of `block` frames (processorOptions, default 2048), transferred. { end: true } on the
// port answers { stop: true }: the rest of the block first, then nothing more until the next port.
// Its single output stays silent; it is connected only so every browser keeps calling process().
class WpMicProcessor extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const { channels = 2, block = 2048 } = options.processorOptions || {};
    this.channels = channels;
    this.block = block;
    this.out = null;
    this.fresh();
    this.port.onmessage = ({ data }) => {
      if (data.port) {
        this.out = data.port;
        this.fresh();
      } else if (data.stop && this.out) {
        this.flush();
        this.out.postMessage({ end: true });
        this.out = null;
      }
    };
  }

  fresh() {
    this.buf = new Float32Array(this.block * this.channels);
    this.n = 0;
  }

  flush() {
    if (!this.n) return;
    const part = this.buf.slice(0, this.n * this.channels);
    this.out.postMessage({ frames: part }, [part.buffer]);
    this.fresh();
  }

  process(inputs) {
    const input = inputs[0];
    if (!this.out || !input || input.length === 0) return true;
    const ch = this.channels;
    const frames = input[0].length;
    for (let i = 0; i < frames; i++) {
      for (let c = 0; c < ch; c++) this.buf[this.n * ch + c] = input[Math.min(c, input.length - 1)][i];
      if (++this.n === this.block) {
        const full = this.buf;
        this.out.postMessage({ frames: full }, [full.buffer]);
        this.fresh();
      }
    }
    return true;
  }
}

registerProcessor('wp-mic', WpMicProcessor);
