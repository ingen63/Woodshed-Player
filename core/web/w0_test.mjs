// Prüft den WASM-Kern des Machbarkeitstests W0 (#32) offline in Node.js:
// #32/AK3 Tempo 0,5x und 0,25x ohne Sprünge, Loop lückenlos, Metronom-Abweichung unter 20 ms,
// dazu die Rechenzeit (muss deutlich schneller als Echtzeit sein, sonst knackt es im Browser).
// Aufruf: node core/web/w0_test.mjs [pfad/zu/w0.wasm]
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const wasmPath = process.argv[2] ?? join(dirname(fileURLToPath(import.meta.url)), '../../web/w0/w0.wasm');
const SR = 48000, BLOCK = 128;
let failed = 0;
function check(name, ok, detail) {
  console.log(`${ok ? 'ok  ' : 'FEHL'} ${name}${detail ? ` (${detail})` : ''}`);
  if (!ok) failed++;
}

async function core() {
  const { instance } = await WebAssembly.instantiate(readFileSync(wasmPath), {
    env: { emscripten_notify_memory_growth: () => {} },
  });
  const w = instance.exports;
  w._initialize();
  w.w0_init(SR);
  return w;
}

// 20 s Sinus 110 Hz: in jeder ganzen Sekunde ganze Perioden, ein Loop 4–8 s ist im Signal nahtlos.
function load(w, seconds = 20, freq = 110, amp = 0.5) {
  const frames = SR * seconds;
  const ptr = w.w0_alloc_source(frames);
  const mem = new Float32Array(w.memory.buffer, ptr, frames * 2);
  for (let i = 0; i < frames; i++) mem[2 * i] = mem[2 * i + 1] = amp * Math.sin((2 * Math.PI * freq * i) / SR);
  w.w0_commit_source();
}

// Rendert `seconds` Sekunden und liefert grössten Sprung zwischen zwei Samples (links) und Rechenzeit.
function run(w, seconds, skipSeconds = 1) {
  const blocks = Math.ceil((seconds * SR) / BLOCK);
  const skip = Math.ceil((skipSeconds * SR) / BLOCK);
  let prev = null, maxJump = 0;
  const t0 = performance.now();
  for (let b = 0; b < blocks; b++) {
    const ptr = w.w0_render(BLOCK);
    if (b < skip) continue;  // Einschwingen des Time-Stretch nicht werten
    const out = new Float32Array(w.memory.buffer, ptr, BLOCK * 2);
    for (let i = 0; i < BLOCK; i++) {
      const x = out[2 * i];
      if (prev !== null) maxJump = Math.max(maxJump, Math.abs(x - prev));
      prev = x;
    }
  }
  return { maxJump, realtime: (seconds * 1000) / (performance.now() - t0) };
}

// Grösster Sprung eines sauberen 110-Hz-Sinus mit Amplitude 0,5: 2π·110/48000·0,5 ≈ 0,0072.
const JUMP_LIMIT = 0.03;

for (const rate of [0.5, 0.25]) {
  const w = await core();
  load(w);
  w.w0_set_rate(rate);
  w.w0_play();
  const r = run(w, 15);
  check(`#32/AK3 Tempo ${rate}x ohne Sprünge`, r.maxJump < JUMP_LIMIT, `max ${r.maxJump.toFixed(4)}`);
  check(`#32/AK3 Tempo ${rate}x schneller als Echtzeit`, r.realtime > 3, `${r.realtime.toFixed(0)}x Echtzeit`);
}

for (const rate of [1, 0.5]) {
  const w = await core();
  load(w);
  w.w0_set_rate(rate);
  w.w0_set_loop(4, 8);
  w.w0_seek(4);
  w.w0_play();
  const r = run(w, 4 / rate * 3.5);
  const passes = w.w0_loop_passes();
  check(`#32/AK3 Loop lückenlos bei ${rate}x`, r.maxJump < JUMP_LIMIT && passes >= 3, `max ${r.maxJump.toFixed(4)}, ${passes} Durchgänge`);
}

{
  const w = await core();
  load(w);
  w.w0_metronome(1, 137, 0.7);  // Tempo mit nicht ganzzahligem Klickabstand in Frames
  run(w, 60, 0);
  const ticks = w.w0_tick_count(), dev = w.w0_tick_deviation_ms();
  check('#32/AK3 Metronom-Abweichung unter 20 ms', ticks >= 130 && dev < 20, `${ticks} Klicks, max ${dev.toFixed(3)} ms`);
}

if (failed) {
  console.log(`${failed} Prüfung(en) fehlgeschlagen`);
  process.exit(1);
}
console.log('Alle Prüfungen bestanden');
