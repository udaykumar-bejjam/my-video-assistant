#!/usr/bin/env node
/**
 * Lock offline heuristic parity contract — Node must honor
 * AssetLibraries/heuristic/parity-contract.json (Swift mirrors the same).
 */
import {
  appendMissingCaptionWordHits,
  fillerWordsSet,
  heuristicParityVersion,
  loadParityContract,
  significantWordsFromCaption,
} from "../src/heuristicCore.js";
import { heuristicPlan, loadLibraries, thinWordHits } from "../src/libraries.js";
import { maxWordHitsPer15s, wordHitSfxEveryN } from "../src/packs.js";

let failures = 0;
function assert(cond, msg) {
  if (!cond) {
    failures += 1;
    console.log(`FAIL ${msg}`);
  } else {
    console.log(`PASS ${msg}`);
  }
}

const contract = loadParityContract();
assert(contract.version === "1", `parity contract version is 1 (got ${contract.version})`);
assert(heuristicParityVersion() === "1", "heuristicParityVersion() === 1");
assert(
  Array.isArray(contract.fillerWords) && contract.fillerWords.includes("the"),
  "filler words include English 'the'"
);
assert(
  fillerWordsSet().has("the") && fillerWordsSet().has("और") && fillerWordsSet().has("మరియు"),
  "filler set covers EN/HI/TE samples"
);
assert(
  Array.isArray(contract.punchyEffectIds) && contract.punchyEffectIds.includes("punch"),
  "punchy effects include punch"
);

const captions = [
  {
    text: "Hey welcome to CaptionStudio",
    startTime: 0,
    endTime: 1.6,
    words: [
      { text: "Hey", startTime: 0, endTime: 0.3 },
      { text: "welcome", startTime: 0.3, endTime: 0.7 },
      { text: "to", startTime: 0.7, endTime: 0.9 },
      { text: "CaptionStudio", startTime: 0.9, endTime: 1.6 },
    ],
  },
  {
    text: "AI captions in one tap",
    startTime: 1.6,
    endTime: 3.2,
  },
  {
    text: "Pick a style that pops fire",
    startTime: 3.2,
    endTime: 4.8,
    words: [
      { text: "Pick", startTime: 3.2, endTime: 3.4 },
      { text: "a", startTime: 3.4, endTime: 3.5 },
      { text: "style", startTime: 3.5, endTime: 3.8 },
      { text: "that", startTime: 3.8, endTime: 4.0 },
      { text: "pops", startTime: 4.0, endTime: 4.3 },
      { text: "fire", startTime: 4.3, endTime: 4.8 },
    ],
  },
  {
    text: "Add overlays and emojis",
    startTime: 4.8,
    endTime: 6.4,
  },
  {
    text: "Export ready for social",
    startTime: 6.4,
    endTime: 8.0,
  },
];

const sig = significantWordsFromCaption(captions[0], "en-US", 2);
assert(sig.length >= 1, `significant words from first caption (got ${sig.length})`);
assert(
  !sig.some((w) => w.text.toLowerCase() === "to"),
  "filler 'to' excluded from significant words"
);
assert(
  significantWordsFromCaption(captions[2], "en-US", 1)[0]?.text === "fire",
  "lexicon prefers 'fire' over weaker tokens"
);

const libraries = loadLibraries();
const seedHits = [];
const added = appendMissingCaptionWordHits({
  wordHits: seedHits,
  captions,
  libraries,
  language: "en-US",
  pack: null,
});
const stride = Number(contract.rules.captionStride) || 2;
const expectedSlots = captions.filter((_, i) => i % stride === 0).length;
assert(added >= 2, `sparse fill adds ≥2 hits (got ${added})`);
assert(seedHits.length <= expectedSlots, `hits ≤ even-caption slots (${seedHits.length}≤${expectedSlots})`);
assert(
  seedHits.every((h) => h.kind === "wordHit" && h.effectId && h.fontId),
  "seed hits have kind/effect/font"
);
assert(
  seedHits.every((h, i, arr) => {
    if (i === 0) return true;
    // Only one hit per even caption index
    return arr.filter((x) => x.captionIndex === h.captionIndex).length === 1;
  }),
  "max one word per filled caption"
);

const plan = heuristicPlan({
  captions,
  duration: 8,
  libraries,
  language: "en-US",
  packId: "hype",
  videoSize: { width: 1080, height: 1920 },
});

assert(plan.source === "heuristic-fallback", `source is heuristic-fallback (got ${plan.source})`);
assert(
  plan.heuristicParityVersion === "1",
  `plan carries heuristicParityVersion 1 (got ${plan.heuristicParityVersion})`
);
assert(Array.isArray(plan.wordHits) && plan.wordHits.length >= 1, "plan has wordHits");
assert(
  (plan.placements || []).some((p) => p.kind === "sfx" && Number(p.startTime) < 0.35),
  "cold-open SFX present"
);
assert(
  (plan.placements || []).filter((p) => p.kind === "text").every((p) => {
    const words = String(p.text || "").split(/\s+/).filter(Boolean);
    return words.length <= (Number(contract.rules.textPrefixWords) || 3);
  }),
  "support text ≤ textPrefixWords tokens"
);

const thinned = thinWordHits(plan.wordHits, 8, maxWordHitsPer15s({ gifDensity: "medium" }));
assert(thinned.length <= plan.wordHits.length, "thinWordHits does not grow");
const sfxEvery = wordHitSfxEveryN({ gifDensity: "high" });
assert(sfxEvery === 2, `hype/high sfx every N === 2 (got ${sfxEvery})`);

if (failures) {
  console.error(`\nheuristic-parity-smoke: ${failures} failure(s)`);
  process.exit(1);
}
console.log("\nheuristic-parity-smoke: all passed");
