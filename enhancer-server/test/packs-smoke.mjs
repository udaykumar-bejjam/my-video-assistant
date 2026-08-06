#!/usr/bin/env node
/**
 * Smoke-test Shorts Pack heuristic biases + opening hook.
 */
import { enhanceWithCursor } from "../src/enhance.js";
import { getPack, loadPacks } from "../src/packs.js";

const packs = loadPacks();
if (!packs.items?.length) {
  console.error("FAIL: no packs loaded");
  process.exit(1);
}

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

let failures = 0;

for (const pack of packs.items) {
  const plan = await enhanceWithCursor({
    captions,
    duration: 8,
    forceHeuristic: true,
    language: "en-US",
    packId: pack.id,
    videoSize: { width: 1080, height: 1920 },
  });

  const bias = new Set(pack.effectBias || []);
  const hits = plan.wordHits || [];
  const early = hits.some((h) => h.startTime < (pack.requireHookInFirstSeconds || 3));
  const earlySfx = (plan.placements || []).some((p) => p.kind === "sfx" && p.startTime < 3);
  const effectsOk =
    hits.length === 0 || hits.every((h) => !bias.size || bias.has(h.effectId));

  const ok =
    plan.packId === pack.id &&
    early &&
    earlySfx &&
    hits.length > 0 &&
    effectsOk;

  console.log(
    `${ok ? "PASS" : "FAIL"} pack=${pack.id} hits=${hits.length} earlyHit=${early} earlySfx=${earlySfx} effectsInBias=${effectsOk} packId=${plan.packId}`
  );
  if (!ok) {
    failures += 1;
    console.log("  effects:", hits.map((h) => h.effectId).join(", "));
    console.log("  hook:", plan.hook);
  }
}

// Unknown pack should still return a plan
const loose = await enhanceWithCursor({
  captions,
  duration: 8,
  forceHeuristic: true,
  packId: null,
});
console.log(`${loose.wordHits?.length ? "PASS" : "FAIL"} no-pack baseline hits=${loose.wordHits?.length || 0}`);
if (!loose.wordHits?.length) failures += 1;

console.log(`\nPacks available: ${packs.items.map((p) => p.id).join(", ")}`);
console.log(`getPack(hype)=${getPack("hype")?.name}`);

process.exit(failures ? 1 : 0);
