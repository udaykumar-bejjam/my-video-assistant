#!/usr/bin/env node
/**
 * Smoke-test LUFS metering + gain (P1.14).
 * Mirrors CaptionStudio AudioNormalizeService LUFS path.
 */
import {
  PEAK_CEILING,
  TARGET_LUFS,
  gainForTargetLUFS,
  integratedLUFS,
  makeSine,
  samplePeak,
  sfxGainScale,
} from "../src/lufs.js";

let failures = 0;
function assert(cond, msg) {
  if (!cond) {
    failures += 1;
    console.log(`FAIL ${msg}`);
  } else {
    console.log(`PASS ${msg}`);
  }
}
const near = (a, b, eps = 0.6) => Math.abs(a - b) < eps;

const sr = 48000;
const quiet = makeSine({ seconds: 2, sampleRate: sr, amplitude: 0.05 });
const loud = makeSine({ seconds: 2, sampleRate: sr, amplitude: 0.2 }); // +12 dB vs quiet

const q = integratedLUFS(quiet, sr);
const l = integratedLUFS(loud, sr);
assert(Number.isFinite(q.lufs) && Number.isFinite(l.lufs), "LUFS finite");
assert(l.lufs > q.lufs + 10, `louder sine ≫ quieter (Δ=${(l.lufs - q.lufs).toFixed(2)} LU)`);
// Amplitude ×4 = +12 dB; LUFS delta should be ~12
assert(near(l.lufs - q.lufs, 12, 1.0), `ΔLUFS ≈ 12 (got ${(l.lufs - q.lufs).toFixed(2)})`);

const gQuiet = gainForTargetLUFS(quiet, sr, TARGET_LUFS, PEAK_CEILING);
const gLoud = gainForTargetLUFS(loud, sr, TARGET_LUFS, PEAK_CEILING);
assert(gQuiet.gain > gLoud.gain, "quieter needs more gain than louder");
assert(gQuiet.gain >= 0.25 && gQuiet.gain <= 4, `quiet gain in range (got ${gQuiet.gain})`);
assert(gLoud.gain >= 0.25 && gLoud.gain <= 4, `loud gain in range (got ${gLoud.gain})`);

// After applying gain, peak must stay ≤ ceiling (within float slop)
const peakAfter = samplePeak(loud) * gLoud.gain;
assert(peakAfter <= PEAK_CEILING + 1e-4, `peak after gain ≤ ceiling (got ${peakAfter.toFixed(3)})`);

// Hot signal should be peak-limited when aiming high
const hot = makeSine({ seconds: 2, sampleRate: sr, amplitude: 0.95 });
const gHot = gainForTargetLUFS(hot, sr, -6, PEAK_CEILING);
assert(gHot.limitedByPeak, "hot signal limited by peak ceiling");
assert(samplePeak(hot) * gHot.gain <= PEAK_CEILING + 1e-3, "hot peak clamped");

const scale = sfxGainScale(gLoud.gain, gLoud.measuredPeak, 0.85);
assert(scale >= 0.15 && scale <= 1.2, `sfx scale in range (got ${scale})`);

// 44.1k path still works
const q441 = integratedLUFS(
  makeSine({ seconds: 1.5, sampleRate: 44100, amplitude: 0.1 }),
  44100
);
assert(Number.isFinite(q441.lufs), "44.1k LUFS finite");

assert(TARGET_LUFS === -14, "default target -14 LUFS");

if (failures) {
  console.error(`\nlufs-smoke: ${failures} failure(s)`);
  process.exit(1);
}
console.log("\nlufs-smoke: all passed");
console.log(
  JSON.stringify(
    {
      quietLUFS: +q.lufs.toFixed(2),
      loudLUFS: +l.lufs.toFixed(2),
      delta: +(l.lufs - q.lufs).toFixed(2),
      quietGain: +gQuiet.gain.toFixed(3),
      loudGain: +gLoud.gain.toFixed(3),
      targetLUFS: TARGET_LUFS,
    },
    null,
    2
  )
);
