#!/usr/bin/env node
/**
 * AI Place must cover the full video — not only the first ~8 captions / ~10s.
 */
import { enhanceWithCursor } from "../src/enhance.js";

function makeCaptions(count, span = 2) {
  const captions = [];
  for (let i = 0; i < count; i++) {
    const start = i * span;
    const end = start + span * 0.9;
    const words = [
      { text: "Watch", startTime: start, endTime: start + 0.4 },
      { text: "this", startTime: start + 0.4, endTime: start + 0.7 },
      { text: i % 3 === 0 ? "fire" : i % 3 === 1 ? "energy" : "secret", startTime: start + 0.7, endTime: start + 1.2 },
      { text: "moment", startTime: start + 1.2, endTime: end },
    ];
    captions.push({
      text: words.map((w) => w.text).join(" "),
      startTime: start,
      endTime: end,
      words,
    });
  }
  return captions;
}

let failures = 0;
function assert(cond, msg) {
  if (!cond) {
    failures += 1;
    console.log(`FAIL ${msg}`);
  } else {
    console.log(`PASS ${msg}`);
  }
}

const captions = makeCaptions(15, 2); // 0–30s
const duration = 30;
const plan = await enhanceWithCursor({
  captions,
  duration,
  forceHeuristic: true,
  language: "en-US",
  packId: "hype",
  videoSize: { width: 1080, height: 1920 },
});

const hits = plan.wordHits || [];
const maxHit = hits.reduce((m, h) => Math.max(m, Number(h.startTime) || 0), 0);
const lateHits = hits.filter((h) => Number(h.startTime) >= 20);
const midHits = hits.filter((h) => Number(h.startTime) >= 10 && Number(h.startTime) < 20);

assert(hits.length >= 15, `wordHits ≥15 across 15 captions (got ${hits.length})`);
assert(maxHit >= 20, `last wordHit ≥20s (got ${maxHit.toFixed(1)}s)`);
assert(midHits.length >= 3, `hits in 10–20s ≥3 (got ${midHits.length})`);
assert(lateHits.length >= 3, `hits in ≥20s ≥3 (got ${lateHits.length})`);

// Sparse early-only plan must be filled by validatePlacements coverage.
const { validatePlacements, loadLibraries } = await import("../src/libraries.js");
const libraries = loadLibraries();
const sparse = validatePlacements(
  {
    summary: "sparse",
    language: "en-US",
    packId: "hype",
    wordHits: [
      {
        kind: "wordHit",
        assetId: libraries.fonts.items[0].id,
        fontId: libraries.fonts.items[0].id,
        effectId: libraries.effects.items[0].id,
        word: "fire",
        text: "fire",
        startTime: 0.5,
        endTime: 1.2,
        x: 0.5,
        y: 0.4,
        scale: 1.3,
        rotation: 0,
      },
    ],
    placements: [],
  },
  libraries,
  captions,
  duration,
  "hype",
  { width: 1080, height: 1920 }
);
const filledMax = (sparse.wordHits || []).reduce(
  (m, h) => Math.max(m, Number(h.startTime) || 0),
  0
);
assert(
  filledMax >= 20,
  `sparse plan filled to ≥20s (got ${filledMax.toFixed(1)}s, hits=${(sparse.wordHits || []).length})`
);

// duration=0 must NOT clamp hits into the first 10s (old Number(0)||10 trap).
const { resolveVideoDuration } = await import("../src/libraries.js");
assert(resolveVideoDuration(0, captions) >= 28, `resolveVideoDuration(0) uses caption span (got ${resolveVideoDuration(0, captions)})`);
assert(resolveVideoDuration(30, captions) === 30, `resolveVideoDuration(30) keeps explicit duration`);
const zeroDurPlan = await enhanceWithCursor({
  captions,
  duration: 0,
  forceHeuristic: true,
  language: "en-US",
  packId: "hype",
  videoSize: { width: 1080, height: 1920 },
});
const zeroMax = (zeroDurPlan.wordHits || []).reduce(
  (m, h) => Math.max(m, Number(h.startTime) || 0),
  0
);
assert(zeroMax >= 20, `duration:0 still covers ≥20s (got ${zeroMax.toFixed(1)}s)`);

// Support text must sit above phrase captions (not stacked at y≈0.78).
const supportY = (zeroDurPlan.placements || [])
  .filter((p) => p.kind === "text")
  .map((p) => Number(p.y) || 0);
if (supportY.length) {
  assert(
    supportY.every((y) => y < 0.55),
    `support text y < 0.55 so it doesn't sit on captions (got [${supportY.join(",")}])`
  );
}

console.log(`\nhits=${hits.length} max=${maxHit.toFixed(1)}s mid=${midHits.length} late=${lateHits.length}`);
console.log(`${failures ? "FAILED" : "OK"} — ${failures} failure(s)`);
process.exit(failures ? 1 : 0);
