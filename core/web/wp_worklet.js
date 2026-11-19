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
import { createCoreSync, MAX_BLOCK } from './wp_core_web.mjs';

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
    this.initResults = init.map(({ cmd, args }) => this.run(cmd, args));
    this.port.onmessage = (e) => this.handle(e.data);
  }

  run(cmd, args = []) {
    if (cmd === 'state') return Object.fromEntries(QUERIES.map((q) => [q, this.core[q]]));
    if (cmd === 'initResults') return this.initResults;
    if (typeof this.core[cmd] === 'function' && cmd !== 'render') return this.core[cmd](...args);
    throw new Error(`Unbekannter Befehl ${cmd}`);
  }

  handle({ id, cmd, args = [] }) {
    if (typeof id === 'number' && id > this.ack) this.ack = id;
    try {
      this.port.postMessage({ id, result: this.run(cmd, args) });
    } catch (err) {
      this.port.postMessage({ id, error: String(err) });
    }
  }

  process(_inputs, outputs) {
    const out = outputs[0];
    if (out.length < 2) return true;
    for (let done = 0; done < out[0].length; done += MAX_BLOCK) {
      const end = Math.min(out[0].length, done + MAX_BLOCK);
      this.core.render(out[0].subarray(done, end), out[1].subarray(done, end));
    }
    if (this.stateFrames > 0) this.pushState(out);
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
    this.port.postMessage({ state: { ...this.run('state'), peak, ack: this.ack, time: currentTime } });
    this.sinceState = 0;
    this.peak = 0;
  }
}

registerProcessor('wp-core', WpCoreProcessor);
