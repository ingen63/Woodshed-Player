// Worker that decodes titles for the AudioWorklet (#42). It runs its own instance of wp_core_web.wasm, so
// decoding never blocks the audio thread: the worklet only takes over the finished PCM (cmd 'beginPcm').
// Created as new Worker('wp_loader.js', { type: 'module' }). Messages: { id, cmd, args } in,
// { id, result } or { id, error } out. Commands:
//   init [module]                                   compiled wp_core_web.wasm (WebAssembly.Module)
//   decode [bytes, sampleRate, bins]                MP3, WAV, FLAC (ArrayBuffer)
//   convert [channels, srcRate, sampleRate, bins]   PCM from decodeAudioData (AAC/M4A)
//   trim [bytes, start, end]                        #116: the file cut to [start, end] seconds
// Results as WpDecoder in wp_core_web.mjs: { code, pcm, duration, mins, maxs } or (trim) { code, bytes,
// start, end }; the buffers are transferred.
import { createDecoder } from './wp_core_web.mjs';

let decoder = null;

async function run(cmd, args) {
  if (cmd === 'init') {
    decoder = await createDecoder(args[0]);
    return true;
  }
  if (!decoder) throw new Error('Decoder not initialised');
  if (cmd === 'decode') return decoder.decode(new Uint8Array(args[0]), args[1], args[2]);
  if (cmd === 'convert') return decoder.convert(args[0], args[1], args[2], args[3]);
  if (cmd === 'trim') return decoder.trim(new Uint8Array(args[0]), args[1], args[2]);
  throw new Error(`Unknown command ${cmd}`);
}

self.onmessage = async ({ data: { id, cmd, args = [] } }) => {
  try {
    const result = await run(cmd, args);
    const transfer = result && result.pcm ? [result.pcm.buffer, result.mins.buffer, result.maxs.buffer]
      : result && result.bytes ? [result.bytes.buffer] : [];
    self.postMessage({ id, result }, transfer);
  } catch (err) {
    self.postMessage({ id, error: String(err) });
  }
};
