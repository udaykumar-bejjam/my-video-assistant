#!/usr/bin/env node
/**
 * Smoke-test A3 auto B-roll: strong words get sticker (+ SFX) ≥70%.
 */
import { enhanceWithCursor } from "../src/enhance.js";
import { brollPairingRate } from "../src/broll.js";
import { classifyStrongWord } from "../src/lexicon.js";

const captions = [
  {
    text: "Wait for this fire energy secret",
    startTime: 0.0,
    endTime: 3.0,
    words: [
      { text: "Wait", startTime: 0.1, endTime: 0.5 },
      { text: "for", startTime: 0.5, endTime: 0.7 },
      { text: "this", startTime: 0.7, endTime: 0.9 },
      { text: "fire", startTime: 0.9, endTime: 1.3 },
      { text: "energy", startTime: 1.3, endTime: 1.8 },
      { text: "secret", startTime: 1.8, endTime: 2.5 },
    ],
  },
  {
    text: "Love this tip then follow and share",
    startTime: 3.0,
    endTime: 6.0,
    words: [
      { text: "Love", startTime: 3.0, endTime: 3.4 },
      { text: "this", startTime: 3.4, endTime: 3.6 },
      { text: "tip", startTime: 3.6, endTime: 4.0 },
      { text: "then", startTime: 4.0, endTime: 4.2 },
      { text: "follow", startTime: 4.2, endTime: 4.8 },
      { text: "and", startTime: 4.8, endTime: 5.0 },
      { text: "share", startTime: 5.0, endTime: 5.6 },
    ],
  },
  {
    text: "One hundred percent wow crazy",
    startTime: 6.0,
    endTime: 8.5,
    words: [
      { text: "One", startTime: 6.0, endTime: 6.3 },
      { text: "hundred", startTime: 6.3, endTime: 6.8 },
      { text: "percent", startTime: 6.8, endTime: 7.3 },
      { text: "wow", startTime: 7.3, endTime: 7.7 },
      { text: "crazy", startTime: 7.7, endTime: 8.4 },
    ],
  },
];

let failures = 0;
function assert(cond, msg) {
  if (!cond) {
    failures += 1;
    console.log(`FAIL ${msg}`);
  } else {
    console.log(`PASS ${msg}`);
  }
}

assert(classifyStrongWord("fire", "en-US") === "power", "lexicon fire→power");
assert(classifyStrongWord("प्यार", "hi-IN") === "emotion", "lexicon hi emotion");
assert(classifyStrongWord("100%", "en-US") === "numbers", "lexicon number");

const plan = await enhanceWithCursor({
  captions,
  duration: 10,
  forceHeuristic: true,
  language: "en-US",
  packId: "hype",
  videoSize: { width: 1080, height: 1920 },
});

const stickers = (plan.placements || []).filter((p) => p.kind === "gif" || p.kind === "png");
const rate = brollPairingRate(plan.wordHits || [], plan.placements || [], "en-US");
const strongHits = (plan.wordHits || []).filter((h) =>
  classifyStrongWord(h.word || h.text || "", "en-US")
);

assert(strongHits.length >= 2, `strong wordHits ≥2 (got ${strongHits.length})`);
assert(stickers.length >= 2, `stickers ≥2 (got ${stickers.length})`);
assert(rate >= 0.7, `pairing rate ≥70% (got ${(rate * 100).toFixed(0)}%)`);

// Stickers should sit near word times (not only caption starts)
const nearWord = stickers.filter((s) =>
  strongHits.some((h) => Math.abs(Number(s.startTime) - Number(h.startTime)) <= 0.5)
);
assert(
  nearWord.length / Math.max(stickers.length, 1) >= 0.7,
  `≥70% stickers near strong words (got ${nearWord.length}/${stickers.length})`
);

// Density cap: ≤4 stickers in any 15s window for high pack (hype is usually medium → 3)
const times = stickers.map((s) => Number(s.startTime)).sort((a, b) => a - b);
let maxInWindow = 0;
for (const t of times) {
  const n = times.filter((x) => x >= t - 7.5 && x <= t + 7.5).length;
  maxInWindow = Math.max(maxInWindow, n);
}
assert(maxInWindow <= 4, `density ≤4 per ~15s (got ${maxInWindow})`);

// Phase 2: power / emotion / reveal stickers should mostly be animated GIFs.
const gifBiasMoods = new Set(["power", "emotion", "reveal"]);
const moodStickers = stickers.filter((s) => gifBiasMoods.has(s.mood));
const gifMoodStickers = moodStickers.filter((s) => s.kind === "gif");
const gifBiasRate =
  moodStickers.length === 0 ? 1 : gifMoodStickers.length / moodStickers.length;
assert(
  moodStickers.length >= 2,
  `power/emotion/reveal stickers ≥2 (got ${moodStickers.length})`
);
assert(
  gifBiasRate >= 0.7,
  `GIF bias ≥70% for power/emotion/reveal (got ${(gifBiasRate * 100).toFixed(0)}% = ${gifMoodStickers.length}/${moodStickers.length})`
);

console.log(
  `\nstrongHits=${strongHits.map((h) => h.word || h.text).join(",")} stickers=${stickers.length} rate=${(rate * 100).toFixed(0)}% gifBias=${(gifBiasRate * 100).toFixed(0)}%`
);
console.log(`${failures ? "FAILED" : "OK"} — ${failures} failure(s)`);
process.exit(failures ? 1 : 0);
