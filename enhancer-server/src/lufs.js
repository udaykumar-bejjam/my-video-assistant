/**
 * ITU-R BS.1770-4 style integrated loudness (LUFS) helpers.
 * Keep in sync with CaptionStudio/Services/AudioNormalizeService.swift (LUFS path).
 *
 * Shorts / social target: -14 LUFS with a sample-peak ceiling so exports don't clip.
 */

/** Typical short-form / YouTube-ish dialogue target. */
export const TARGET_LUFS = -14;

/** Sample-peak linear ceiling after LUFS gain (~−3 dBFS). */
export const PEAK_CEILING = 0.7;

export const MAX_GAIN = 4.0;
export const MIN_GAIN = 0.25;

/** Absolute gate (LUFS). */
const ABS_GATE = -70;
/** Relative gate offset (LU). */
const REL_GATE = -10;
/** Block length (seconds) and overlap fraction. */
const BLOCK_SEC = 0.4;
const OVERLAP = 0.75;

/**
 * Biquad K-weighting coeffs for common rates (pre-filter + RLB).
 * Sourced from BS.1770 / libebur128 tables.
 */
function kWeightFilters(sampleRate) {
  const sr = Number(sampleRate) || 48000;
  // Prefer exact 48k / 44.1k tables; otherwise scale 48k as approximation.
  if (Math.abs(sr - 48000) < 50) {
    return {
      pre: {
        b: [1.53512485958697, -2.69169618940638, 1.19839281085285],
        a: [1.0, -1.69065929318241, 0.73248077421585],
      },
      rlb: {
        b: [1.0, -2.0, 1.0],
        a: [1.0, -1.99004745483398, 0.99007225036621],
      },
    };
  }
  if (Math.abs(sr - 44100) < 50) {
    return {
      pre: {
        b: [1.5308412300503478, -2.6509799950757456, 1.1690790799215877],
        a: [1.0, -1.6636551132567342, 0.7125954263059514],
      },
      rlb: {
        b: [1.0, -2.0, 1.0],
        a: [1.0, -1.9891845679314284, 0.9892245165138008],
      },
    };
  }
  // Fallback: 48k coeffs (docs note reduced accuracy off-rate).
  return kWeightFilters(48000);
}

function applyBiquad(samples, b, a) {
  const out = new Float64Array(samples.length);
  let x1 = 0;
  let x2 = 0;
  let y1 = 0;
  let y2 = 0;
  for (let i = 0; i < samples.length; i++) {
    const x0 = samples[i];
    const y0 = b[0] * x0 + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2;
    out[i] = y0;
    x2 = x1;
    x1 = x0;
    y2 = y1;
    y1 = y0;
  }
  return out;
}

function kWeight(samples, sampleRate) {
  const { pre, rlb } = kWeightFilters(sampleRate);
  const stage1 = applyBiquad(samples, pre.b, pre.a);
  return applyBiquad(stage1, rlb.b, rlb.a);
}

function meanSquare(block) {
  let sum = 0;
  for (let i = 0; i < block.length; i++) sum += block[i] * block[i];
  return sum / Math.max(1, block.length);
}

function lufsFromMS(ms) {
  if (!(ms > 0)) return -120;
  return -0.691 + 10 * Math.log10(ms);
}

/**
 * Integrated LUFS for a mono float buffer in [-1, 1].
 * @param {Float32Array|number[]} samples
 * @param {number} sampleRate
 * @returns {{ lufs: number, ungatedLUFS: number, blockCount: number, gatedBlocks: number }}
 */
export function integratedLUFS(samples, sampleRate = 48000) {
  const sr = Math.max(8000, Number(sampleRate) || 48000);
  const input = samples instanceof Float32Array ? samples : Float32Array.from(samples);
  if (input.length < Math.floor(sr * 0.4)) {
    // Too short for a full block — ungated whole-buffer estimate.
    const weighted = kWeight(input, sr);
    const ms = meanSquare(weighted);
    const lufs = lufsFromMS(ms);
    return { lufs, ungatedLUFS: lufs, blockCount: 1, gatedBlocks: ms > 0 ? 1 : 0 };
  }

  const weighted = kWeight(input, sr);
  const blockSize = Math.max(1, Math.round(sr * BLOCK_SEC));
  const hop = Math.max(1, Math.round(blockSize * (1 - OVERLAP)));
  const blockMS = [];
  for (let start = 0; start + blockSize <= weighted.length; start += hop) {
    blockMS.push(meanSquare(weighted.subarray(start, start + blockSize)));
  }
  if (!blockMS.length) {
    const ms = meanSquare(weighted);
    const lufs = lufsFromMS(ms);
    return { lufs, ungatedLUFS: lufs, blockCount: 0, gatedBlocks: 0 };
  }

  const ungatedMS =
    blockMS.reduce((a, b) => a + b, 0) / blockMS.length;
  const ungatedLUFS = lufsFromMS(ungatedMS);

  // Absolute gate
  const afterAbs = blockMS.filter((ms) => lufsFromMS(ms) > ABS_GATE);
  if (!afterAbs.length) {
    return { lufs: -70, ungatedLUFS, blockCount: blockMS.length, gatedBlocks: 0 };
  }
  const absMean = afterAbs.reduce((a, b) => a + b, 0) / afterAbs.length;
  const relativeThresh = lufsFromMS(absMean) - REL_GATE;
  const gated = afterAbs.filter((ms) => lufsFromMS(ms) > relativeThresh);
  const gatedMS =
    (gated.length ? gated : afterAbs).reduce((a, b) => a + b, 0) /
    Math.max(1, gated.length || afterAbs.length);
  return {
    lufs: lufsFromMS(gatedMS),
    ungatedLUFS,
    blockCount: blockMS.length,
    gatedBlocks: gated.length || afterAbs.length,
  };
}

/** Sample peak (max abs). */
export function samplePeak(samples) {
  let peak = 1e-4;
  for (let i = 0; i < samples.length; i++) {
    const a = Math.abs(samples[i]);
    if (a > peak) peak = a;
  }
  return peak;
}

/**
 * Linear gain to hit target LUFS, clamped by peak ceiling + min/max gain.
 * @returns {{ gain: number, measuredLUFS: number, measuredPeak: number, limitedByPeak: boolean }}
 */
export function gainForTargetLUFS(
  samples,
  sampleRate = 48000,
  targetLUFS = TARGET_LUFS,
  peakCeiling = PEAK_CEILING
) {
  const measured = integratedLUFS(samples, sampleRate);
  const peak = samplePeak(samples);
  let gain = Math.pow(10, (targetLUFS - measured.lufs) / 20);
  gain = Math.min(MAX_GAIN, Math.max(MIN_GAIN, gain));
  let limitedByPeak = false;
  if (peak * gain > peakCeiling) {
    gain = peakCeiling / Math.max(peak, 1e-4);
    gain = Math.min(MAX_GAIN, Math.max(MIN_GAIN, gain));
    limitedByPeak = true;
  }
  return {
    gain,
    measuredLUFS: measured.lufs,
    measuredPeak: peak,
    limitedByPeak,
    ungatedLUFS: measured.ungatedLUFS,
  };
}

/** SFX scale under dialogue after LUFS/peak normalize (mirrors Swift). */
export function sfxGainScale(dialogueGain, measuredPeak, brandSfxGain, peakCeiling = PEAK_CEILING) {
  const peak = Math.max(measuredPeak, 1e-4);
  const after = peak * dialogueGain;
  const scale =
    Math.min(1.0, brandSfxGain) * Math.min(1.0, peakCeiling / Math.max(after, 1e-4));
  return Math.max(0.15, Math.min(1.2, scale));
}

/** Generate mono sine for tests. */
export function makeSine({
  seconds = 2,
  sampleRate = 48000,
  hz = 1000,
  amplitude = 0.25,
} = {}) {
  const n = Math.floor(seconds * sampleRate);
  const out = new Float32Array(n);
  const w = (2 * Math.PI * hz) / sampleRate;
  for (let i = 0; i < n; i++) out[i] = amplitude * Math.sin(w * i);
  return out;
}
