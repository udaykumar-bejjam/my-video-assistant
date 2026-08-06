#!/usr/bin/env node
/**
 * Smoke-test distribution package + safe-zone clamping on heuristic enhance.
 */
import { enhanceWithCursor } from "../src/enhance.js";
import { DEFAULT_SAFE_ZONE, clampToSafeZone } from "../src/safezone.js";

const captions = [
  {
    text: "Welcome to CaptionStudio fire energy",
    startTime: 0.0,
    endTime: 2.0,
    words: [
      { text: "Welcome", startTime: 0.0, endTime: 0.5 },
      { text: "to", startTime: 0.5, endTime: 0.7 },
      { text: "CaptionStudio", startTime: 0.7, endTime: 1.3 },
      { text: "fire", startTime: 1.3, endTime: 1.6 },
      { text: "energy", startTime: 1.6, endTime: 2.0 },
    ],
  },
  {
    text: "This tip will change everything",
    startTime: 2.0,
    endTime: 4.0,
  },
];

const tightZone = { xMin: 0.2, xMax: 0.7, yMin: 0.2, yMax: 0.65 };

let failures = 0;

const plan = await enhanceWithCursor({
  captions,
  duration: 8,
  forceHeuristic: true,
  language: "en-US",
  packId: "hype",
  videoSize: { width: 1080, height: 1920 },
  safeZone: tightZone,
});

function assert(cond, msg) {
  if (!cond) {
    failures += 1;
    console.log(`FAIL ${msg}`);
  } else {
    console.log(`PASS ${msg}`);
  }
}

const dist = plan.distribution;
assert(!!dist?.title, `distribution.title present (${dist?.title || "missing"})`);
assert(!!dist?.coverText, `distribution.coverText present (${dist?.coverText || "missing"})`);
assert(Array.isArray(dist?.hashtags) && dist.hashtags.length > 0, `hashtags=${dist?.hashtags?.length || 0}`);
assert(!!plan.safeZone, "plan.safeZone present");

const visuals = [
  ...(plan.wordHits || []),
  ...(plan.placements || []).filter((p) => p.kind !== "sfx"),
];

let allInside = visuals.length > 0;
for (const p of visuals) {
  const x = Number(p.x);
  const y = Number(p.y);
  if (!(x >= tightZone.xMin - 1e-6 && x <= tightZone.xMax + 1e-6 && y >= tightZone.yMin - 1e-6 && y <= tightZone.yMax + 1e-6)) {
    allInside = false;
    console.log(`  out of zone: kind=${p.kind} x=${x} y=${y}`);
  }
}
assert(allInside, `all ${visuals.length} visual placements inside safe zone`);

const clamped = clampToSafeZone(0.01, 0.99, DEFAULT_SAFE_ZONE);
assert(
  clamped.x >= DEFAULT_SAFE_ZONE.xMin &&
    clamped.x <= DEFAULT_SAFE_ZONE.xMax &&
    clamped.y >= DEFAULT_SAFE_ZONE.yMin &&
    clamped.y <= DEFAULT_SAFE_ZONE.yMax,
  `clampToSafeZone helper (${clamped.x.toFixed(2)}, ${clamped.y.toFixed(2)})`
);

console.log(`\n${failures ? "FAILED" : "OK"} — ${failures} failure(s)`);
process.exit(failures ? 1 : 0);
