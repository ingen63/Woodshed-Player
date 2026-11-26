// Prüft wp_core_web.wasm (#33), den Kern fürs AudioWorklet, in Node.js über die JS-Hülle wp_core_web.mjs.
// Gleiche Fälle wie player_tests.cpp nativ: Dekodieren, Seek, Loop-Grenzen, Dateiende, Tempo; dazu der
// Weg für AAC/M4A (PCM, wie es decodeAudioData liefert).
// Aufruf: node core/web/wp_core_web_test.mjs <wp_core_web.wasm> <core/tests/audio>
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  createCore, createDecoder, createRecordingCore, loadFile, WP_OK, WP_ERR_UNSUPPORTED_FORMAT, WP_ERR_INVALID_ARGUMENT,
  WP_ERR_OUT_OF_MEMORY,
} from './wp_core_web.mjs';

const [wasmPath, audioDir] = process.argv.slice(2);
const wasm = new WebAssembly.Module(readFileSync(wasmPath));
const SR = 48000;
let checks = 0, failures = 0, testFailed = false;
function check(cond, what) {
  checks++;
  if (!cond) { failures++; testFailed = true; console.log(`  FAILED: ${what}`); }
}
const near = (a, b, tol, what) => check(Math.abs(a - b) <= tol, `${what}: ${a} instead of ${b} ± ${tol}`);

// 16-Bit-Stereo-WAV mit Frame-Index als Inhalt (wie writeIndexWav in player_tests.cpp).
function indexWav(frames, sr = SR) {
  const buf = new DataView(new ArrayBuffer(44 + frames * 4));
  const str = (o, s) => [...s].forEach((c, i) => buf.setUint8(o + i, c.charCodeAt(0)));
  str(0, 'RIFF'); buf.setUint32(4, 36 + frames * 4, true); str(8, 'WAVE');
  str(12, 'fmt '); buf.setUint32(16, 16, true); buf.setUint16(20, 1, true); buf.setUint16(22, 2, true);
  buf.setUint32(24, sr, true); buf.setUint32(28, sr * 4, true); buf.setUint16(32, 4, true); buf.setUint16(34, 16, true);
  str(36, 'data'); buf.setUint32(40, frames * 4, true);
  for (let i = 0; i < frames; i++) {
    buf.setUint16(44 + i * 4, i & 0x7fff, true);
    buf.setUint16(46 + i * 4, (i >> 15) & 0x7fff, true);
  }
  return new Uint8Array(buf.buffer);
}
const frameIndex = (l, r) => Math.round(l * 32768) + Math.round(r * 32768) * 32768;

// Rendert `frames` Frames in Blöcken (wie das Worklet, 128 Frames) und liefert links und rechts.
function render(core, frames, block = 128) {
  const L = new Float32Array(frames), R = new Float32Array(frames);
  for (let done = 0; done < frames; done += block) {
    const n = Math.min(block, frames - done);
    core.render(L.subarray(done, done + n), R.subarray(done, done + n));
  }
  return { L, R };
}
const zeroCrossingFreq = (v, from, count) => {
  let c = 0;
  for (let i = from + 1; i < from + count; i++) if (v[i - 1] < 0 && v[i] >= 0) c++;
  return (c * SR) / count;
};
const rms = (v, from, count) => {
  let s = 0;
  for (let i = from; i < from + count; i++) s += v[i] * v[i];
  return Math.sqrt(s / count);
};

async function sineChecks(core, what) {
  near(core.duration, 1.0, 0.06, `${what} duration`);
  core.play();
  const { L, R } = render(core, SR / 2);
  near(zeroCrossingFreq(L, SR / 10, SR / 4), 440, 8, `${what} frequency`);
  near(rms(L, SR / 10, SR / 4), 0.5 / Math.SQRT2, 0.05, `${what} level`);
  check(L.every((x, i) => x === R[i]), `${what} mono on both channels`);
}

const tests = {
  async decodesMp3AndFlac() { // #33/AK3
    for (const f of ['sine440.mp3', 'sine440.flac']) {
      const core = await createCore(wasm, SR);
      check(core.loadEncoded(readFileSync(join(audioDir, f))) === WP_OK, `${f} loaded`);
      await sineChecks(core, f);
    }
  },
  async wavSeekSampleExact() { // #33/AK2 Seek, #33/AK3 WAV
    const core = await createCore(wasm, SR);
    check(core.loadEncoded(indexWav(2 * SR)) === WP_OK, 'WAV loaded');
    near(core.duration, 2.0, 1e-9, 'WAV duration');
    core.seek(1.25);
    core.play();
    const { L, R } = render(core, 2, 2);
    check(frameIndex(L[0], R[0]) === 60000 && frameIndex(L[1], R[1]) === 60001, 'seek sample-exact');
  },
  async loopBounds() { // #33/AK2 Loop-Grenzen (wie loopBoundsWithLoadedFile)
    const core = await createCore(wasm, SR);
    check(core.loadEncoded(indexWav(3 * SR)) === WP_OK, 'WAV loaded');
    core.setLoop(0.5, 1.75);
    core.seek(1.7);
    core.play();
    const { L, R } = render(core, 4 * SR, 128);
    let expected = Math.trunc(1.7 * SR), ok = true;
    for (let i = 0; i < 4 * SR && ok; i++) {
      ok = frameIndex(L[i], R[i]) === expected;
      if (++expected >= 1.75 * SR) expected = SR / 2;
    }
    check(ok, 'loop gapless and sample-exact');
    check(core.loopPasses === 4, `loop passes ${core.loopPasses} instead of 4`);
    check(core.playing, 'keeps playing in the loop');
  },
  async endOfFile() { // Dateiende
    const core = await createCore(wasm, SR);
    core.loadEncoded(indexWav(SR));
    core.seek(0.99);
    core.play();
    const { L, R } = render(core, SR / 50, SR / 50);
    check(frameIndex(L[SR / 100 - 1], R[SR / 100 - 1]) === SR - 1, 'last frame');
    check(L[SR / 100] === 0 && R[SR / 100] === 0, 'silence afterwards');
    check(!core.playing, 'stops at the end');
    near(core.position, 1.0, 1e-9, 'position at the end');
  },
  async tempoKeepsPitch() { // #33/AK2 Tempo
    const core = await createCore(wasm, SR);
    core.loadEncoded(readFileSync(join(audioDir, 'sine440.flac')));
    for (const rate of [0.5, 0.25]) {
      core.seek(0);
      core.setRate(rate);
      core.play();
      const { L } = render(core, SR / 2);
      near(core.position, 0.5 * rate, 0.01, `position at ${rate}x`);
      near(zeroCrossingFreq(L, SR / 5, SR / 4), 440, 10, `pitch at ${rate}x`);
      core.pause();
    }
  },
  async aacViaBrowserPcm() { // #33/AK4: PCM wie von decodeAudioData (44,1 kHz mono)
    const core = await createCore(wasm, SR);
    const mono = new Float32Array(44100).map((_, i) => 0.5 * Math.sin((2 * Math.PI * 440 * i) / 44100));
    const fakeDecode = async () => ({ numberOfChannels: 1, sampleRate: 44100, getChannelData: () => mono });
    const m4a = readFileSync(join(audioDir, 'sine440.m4a'));
    check(core.loadEncoded(m4a) === WP_ERR_UNSUPPORTED_FORMAT, 'M4A not in the core');
    check(await loadFile(core, m4a, fakeDecode) === WP_OK, 'M4A via decodeAudioData');
    await sineChecks(core, 'PCM from the browser');
    const stereo = [new Float32Array(SR).fill(0.25), new Float32Array(SR).fill(-0.25)];
    check(core.loadPcm(stereo, SR) === WP_OK, 'stereo PCM');
    core.play();
    const { L, R } = render(core, 256);
    check(L.every((x) => x === 0.25) && R.every((x) => x === -0.25), 'stereo PCM unchanged');
    check(core.loadPcm([], SR) === WP_ERR_INVALID_ARGUMENT, 'empty PCM rejected');
  },
  async errorsKeepTitle() {
    const core = await createCore(wasm, SR);
    core.loadEncoded(indexWav(2 * SR));
    check(core.loadEncoded(new TextEncoder().encode('no audio')) === WP_ERR_UNSUPPORTED_FORMAT, 'no audio');
    check(await loadFile(core, new Uint8Array(4), async () => { throw new Error('x'); }) === WP_ERR_UNSUPPORTED_FORMAT,
      'browser cannot decode it either');
    check(core.errorMessage(WP_ERR_UNSUPPORTED_FORMAT) === 'Unsupported format or corrupt file', 'error text');
    near(core.duration, 2.0, 1e-9, 'previous title stays');
  },
  async waveformAndMetronome() {
    const core = await createCore(wasm, SR);
    check(core.waveform(0, 1, 10) === null, 'no waveform without a title');
    core.loadEncoded(readFileSync(join(audioDir, 'sine440.flac')));
    const w = core.waveform(0, 1, 10);
    near(w.maxs[5], 0.5, 0.01, 'waveform maximum');
    near(w.mins[5], -0.5, 0.01, 'waveform minimum');
    core.pause();
    core.metroSetBpm(120);
    core.metroStart();
    check(core.metroRunning && core.metroBpm === 120, 'metronome running');
    const { L } = render(core, SR);
    let clicks = 0;
    for (let i = 1; i < SR; i++) if (L[i - 1] === 0 && L[i] !== 0) clicks++;
    check(clicks === 2, `${clicks} clicks in 1 s at 120 BPM instead of 2`);
  },
  async decoderInWorkerTakenOverInPieces() { // #42/AK1, #42/AK2: decode elsewhere, old title plays on
    const decoder = await createDecoder(wasm);
    const d = decoder.decode(indexWav(3 * SR), SR);
    check(d.code === WP_OK && d.pcm.length === 3 * SR * 2, `decoded ${d.code}, ${d.pcm?.length} samples`);
    near(d.duration, 3.0, 1e-9, 'decoder duration');
    check(d.mins.length === 600 && d.maxs.length === 600, `waveform ${d.mins.length} sections for 3 s`);
    const core = await createCore(wasm, SR);
    core.loadEncoded(indexWav(2 * SR));
    core.seek(0.5);
    core.play();
    check(core.beginPcm(d.pcm) === WP_OK, 'begin');
    let expected = SR / 2, continuous = true, result = null, pumps = 0;
    while (result === null) {
      const { L, R } = render(core, 128, 128);
      for (let i = 0; i < 128; i++) continuous = continuous && frameIndex(L[i], R[i]) === expected++;
      result = core.pumpPcm(SR / 4);
      pumps++;
    }
    check(continuous, 'old title plays on without a jump while the new one is taken over');
    check(result === WP_OK && pumps === 12, `commit ${result} after ${pumps} pieces`);
    near(core.duration, 3.0, 1e-9, 'new title in place');
    check(!core.playing && core.position === 0, 'new title at the start, paused');
    check(core.waveform(0, 1, 10) === null, 'worklet keeps no stale waveform');
    core.seek(2.5);
    core.play();
    const { L, R } = render(core, 2, 2);
    check(frameIndex(L[0], R[0]) === 2.5 * SR && frameIndex(L[1], R[1]) === 2.5 * SR + 1, 'new title sample-exact');
  },
  async decoderFormatsAndErrors() { // #42/AK3
    const decoder = await createDecoder(wasm);
    for (const f of ['sine440.mp3', 'sine440.flac']) {
      const d = decoder.decode(readFileSync(join(audioDir, f)), SR);
      check(d.code === WP_OK, `${f} decoded`);
      near(d.maxs[100], 0.5, 0.04, `${f} waveform`);
      const core = await createCore(wasm, SR);
      core.beginPcm(d.pcm);
      let r = null;
      while (r === null) r = core.pumpPcm();
      check(r === WP_OK, `${f} taken over`);
      await sineChecks(core, `${f} via decoder`);
    }
    const m4a = decoder.decode(readFileSync(join(audioDir, 'sine440.m4a')), SR);
    check(m4a.code === WP_ERR_UNSUPPORTED_FORMAT && !m4a.pcm, 'M4A goes to decodeAudioData');
    const mono = new Float32Array(44100).map((_, i) => 0.5 * Math.sin((2 * Math.PI * 440 * i) / 44100));
    const c = decoder.convert([mono], 44100, SR);
    check(c.code === WP_OK && Math.abs(c.pcm.length / 2 - SR) <= 2, 'PCM from the browser converted');
    near(c.duration, 1.0, 1e-3, 'converted duration');
    check(decoder.convert([], 44100, SR).code === WP_ERR_INVALID_ARGUMENT, 'empty PCM rejected');
    check(decoder.decode(new TextEncoder().encode('no audio'), SR).code === WP_ERR_UNSUPPORTED_FORMAT, 'no audio');

    const core = await createCore(wasm, SR);
    core.loadEncoded(indexWav(2 * SR));
    check(core.beginPcm(new Float32Array(0)) === WP_ERR_INVALID_ARGUMENT, 'empty title rejected');
    check(core.pumpPcm() === WP_ERR_INVALID_ARGUMENT, 'nothing to take over');
    core.beginPcm(c.pcm);
    core.pumpPcm(100);
    check(core.beginPcm(new Float32Array(0)) === WP_ERR_INVALID_ARGUMENT, 'newer load replaces the unfinished one');
    check(core.pumpPcm() === WP_ERR_INVALID_ARGUMENT, 'unfinished one discarded');
    near(core.duration, 2.0, 1e-9, 'previous title stays playable');
  },
  // #116/AK4: the browser trims in the core too, AAC in ADTS included (the browser only decodes it).
  async trimInTheCore() {
    const decoder = await createDecoder(wasm);
    const mp3 = decoder.trim(readFileSync(join(audioDir, 'clicks3.mp3')), 0.7, 2.2);
    check(mp3.code === WP_OK && mp3.bytes.length > 0, 'MP3 trimmed');
    near(mp3.start, 0.7, 1 / 44100, 'MP3 start');
    near(mp3.end, 2.2, 1 / 44100, 'MP3 end');
    const d = decoder.decode(mp3.bytes, 44100);
    check(d.code === WP_OK && Math.abs(d.pcm.length / 2 - 66150) <= 1, 'MP3 is 1.5 s long');
    // ADTS: frames of 1024 samples, 0.7 s → frame 30, 2.2 s → frame 95
    const aac = decoder.trim(readFileSync(join(audioDir, 'clicks3.aac')), 0.7, 2.2);
    check(aac.code === WP_OK && aac.bytes[0] === 0xff && (aac.bytes[1] & 0xf6) === 0xf0, 'ADTS stays ADTS');
    near(aac.start, (30 * 1024) / 44100, 1e-9, 'ADTS start at a frame boundary');
    near(aac.end, (95 * 1024) / 44100, 1e-9, 'ADTS end at a frame boundary');
    const flac = decoder.trim(readFileSync(join(audioDir, 'clicks3.flac')), 0.7, 2.2);
    check(flac.code === WP_OK && new TextDecoder().decode(flac.bytes.subarray(0, 4)) === 'fLaC', 'FLAC stays FLAC');
    const short = decoder.trim(readFileSync(join(audioDir, 'clicks3.mp3')), 1.0, 1.5);
    check(short.code === WP_ERR_INVALID_ARGUMENT && !short.bytes, 'less than 1 s refused');
    // #120/AK4: M4A (AAC and ALAC) is cut by the core as well, with the same result as natively
    // (trim_mp4_tests): AAC frame 32 minus the priming of 2112 samples, ALAC packet 8
    const m4a = decoder.trim(readFileSync(join(audioDir, 'clicks3.m4a')), 0.7, 2.2);
    check(m4a.code === WP_OK && new TextDecoder().decode(m4a.bytes.subarray(4, 8)) === 'ftyp', 'M4A stays M4A');
    near(m4a.start, (32 * 1024 - 2112) / 44100, 1e-9, 'M4A start at a frame boundary');
    near(m4a.end, (97 * 1024 - 2112) / 44100, 1e-9, 'M4A end at a frame boundary');
    const alac = decoder.trim(readFileSync(join(audioDir, 'clicks3_alac.m4a')), 0.7, 2.2);
    check(alac.code === WP_OK, 'ALAC trimmed');
    near(alac.start, (8 * 4096) / 44100, 1e-9, 'ALAC start at a packet boundary');
  },
  // #93: running out of memory reports WP_ERR_OUT_OF_MEMORY instead of aborting the WASM core (it is
  // built with -fwasm-exceptions); the previous title stays playable and loading works again.
  async outOfMemoryIsReported() {
    const core = await createCore(wasm, SR);
    core.loadEncoded(indexWav(2 * SR));
    const begin = (frames) => core.x.wp_web_pcm_begin(core.p, frames);
    check(begin(300_000_000) === WP_ERR_OUT_OF_MEMORY, '2.4 GB title: out of memory'); // above 2 GB
    check(begin(2 ** 31 - 1) === WP_ERR_OUT_OF_MEMORY, 'more samples than a vector holds: out of memory');
    near(core.duration, 2.0, 1e-9, 'previous title stays playable');
    check(core.loadPcm([new Float32Array(SR).fill(0.25)], SR) === WP_OK, 'loading works again');
    near(core.duration, 1.0, 1e-9, 'new title loaded');
  },
  // #157/AK5: the recording through the JS wrapper as the worker uses it: armed (lead-in 1 s, pause kept, tail
  // 1 s, end after the pause), the file put together from its pieces and decoded by the core; plain and the
  // storage running full (cut) as well.
  async recordingCore() {
    const rec = await createRecordingCore(wasm);
    const decoder = await createDecoder(wasm);
    const mono = [];
    const part = (seconds, amp) => {
      for (let i = 0; i < seconds * SR; i++) mono.push(amp * Math.cos((2 * Math.PI * 440 * i) / SR));
    };
    part(1.5, 0); part(0.5, 0.5); part(0.8, 0); part(0.5, 0.5); part(2.5, 0); part(0.5, 0.5);
    const record = (samples, channels, store = (p, file) => file.set(p.bytes, p.offset)) => {
      const file = new Uint8Array(2 * 1024 * 1024);
      let size = 0;
      for (let done = 0; done < samples.length; done += 2048) {
        const n = Math.min(2048, samples.length - done);
        const block = new Float32Array(n * channels);
        for (let i = 0; i < n; i++) for (let c = 0; c < channels; c++) block[i * channels + c] = samples[done + i];
        check(rec.feed(block) === WP_OK, 'block fed');
        const p = rec.take();
        if (p && store(p, file) !== false) size = p.offset + p.bytes.length;
        else if (p) return { file, size: rec.cut(), cut: true };
      }
      check(rec.finish() === WP_OK, 'finished');
      const p = rec.take();
      if (p) { file.set(p.bytes, p.offset); size = p.offset + p.bytes.length; }
      file.set(rec.header(), 0);
      return { file, size };
    };
    check(rec.start({ sampleRate: SR, channels: 2, armed: true, thresholdDb: -30, silenceSeconds: 2, tailSeconds: 1 })
      === WP_OK, 'armed start');
    check(rec.gate === 1, 'armed');
    const armed = record(mono, 2);
    check(rec.gate === 3, 'done after the pause');
    near(rec.keptSeconds, 3.8, 0.01, 'kept: lead-in, tone, pause, tone, tail');
    near(rec.seconds, mono.length / SR, 1e-9, 'seconds fed');
    near(rec.takeLevel(), 0.5, 1e-6, 'peak level');
    check(rec.takeLevel() === 0, 'level taken');
    check(!rec.onlySilence, 'sound came');
    const d = decoder.decode(armed.file.subarray(0, armed.size), SR);
    check(d.code === WP_OK, 'FLAC decodes');
    near(d.duration, 3.8, 0.01, 'file length');
    let first = -1;
    for (let i = 0; i < d.pcm.length / 2 && first < 0; i++) if (Math.abs(d.pcm[2 * i]) > 0.0316) first = i;
    near(first, SR, SR / 100, 'first sound 1 s into the file');

    check(rec.start({ sampleRate: SR, channels: 1 }) === WP_OK, 'plain start');
    check(rec.gate === 0, 'not armed');
    const plain = record(mono.slice(0, SR), 1);
    near(decoder.decode(plain.file.subarray(0, plain.size), SR).duration, 1.0, 1e-9, 'every frame kept');

    check(rec.start({ sampleRate: SR, channels: 2 }) === WP_OK, 'start again');
    let pieces = 0;
    const full = record(mono, 2, (p, file) => {
      if (++pieces >= 4) return false; // the fourth piece does not fit any more
      file.set(p.bytes, p.offset);
      return true;
    });
    check(full.cut && full.size > 0, 'cut before the piece that did not fit');
    full.file.set(rec.header(), 0);
    const kept = decoder.decode(full.file.subarray(0, full.size), SR);
    check(kept.code === WP_OK && kept.duration > 0 && kept.duration < 1, 'what was stored plays');
    check(rec.start({ sampleRate: SR, channels: 2, armed: true, silenceSeconds: 0 }) === -12, 'bad settings');
    rec.free();
  },
};

for (const [name, fn] of Object.entries(tests)) {
  testFailed = false;
  try { await fn(); } catch (e) { failures++; testFailed = true; console.log(`  EXCEPTION: ${e.stack}`); }
  console.log(`${testFailed ? 'FAIL' : 'ok  '} ${name}`);
}
console.log(`${checks} checks, ${failures} failures`);
process.exit(failures ? 1 : 0);
