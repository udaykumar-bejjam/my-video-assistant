/**
 * Shared offline enhance heuristic core (parity contract v1).
 * Keep in sync with AssetLibraries/heuristic/parity-contract.json and
 * CaptionStudio HeuristicParity / CursorEnhancerClient.localHeuristicPlan.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  effectPoolForPack,
  sfxPoolForPack,
  wordHitsPerCaption,
} from "./packs.js";
import { scoreWordSignificance } from "./lexicon.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const CONTRACT_PATH = path.resolve(
  __dirname,
  "../../AssetLibraries/heuristic/parity-contract.json"
);

let cachedContract = null;

export function loadParityContract() {
  if (cachedContract) return cachedContract;
  cachedContract = JSON.parse(fs.readFileSync(CONTRACT_PATH, "utf8"));
  return cachedContract;
}

export function clearParityContractCache() {
  cachedContract = null;
}

export function heuristicParityVersion() {
  return String(loadParityContract().version || "1");
}

export function fillerWordsSet() {
  return new Set(loadParityContract().fillerWords || []);
}

export function punchyEffectIds() {
  return loadParityContract().punchyEffectIds || [];
}

export function wordHitColors() {
  return loadParityContract().wordHitColors || ["#FFEF5A", "#FF2D2D"];
}

export function parityRules() {
  return loadParityContract().rules || {};
}

export function captionTokens(cap) {
  if (Array.isArray(cap.words) && cap.words.length) {
    return cap.words.map((w, i) => ({ ...w, index: i }));
  }
  return String(cap.text || "")
    .split(/\s+/)
    .filter(Boolean)
    .map((text, i, arr) => {
      const span = (cap.endTime - cap.startTime) / Math.max(arr.length, 1);
      return {
        text,
        index: i,
        startTime: cap.startTime + i * span,
        endTime: cap.startTime + (i + 1) * span,
      };
    });
}

export function significantWordsFromCaption(cap, language, limit) {
  const lang = String(language || "en-US");
  const rules = parityRules();
  const minLen = lang.startsWith("en")
    ? Number(rules.minTokenLengthEn) || 3
    : Number(rules.minTokenLengthOther) || 2;
  const filler = fillerWordsSet();
  return captionTokens(cap)
    .filter(
      (w) =>
        w.text &&
        !filler.has(String(w.text).toLowerCase()) &&
        String(w.text).length >= minLen
    )
    .sort(
      (a, b) =>
        scoreWordSignificance(b.text, language) -
        scoreWordSignificance(a.text, language)
    )
    .slice(0, limit);
}

export function captionHasWordHit(wordHits, cap) {
  const start = Number(cap.startTime) || 0;
  const end = Number(cap.endTime) || start;
  return wordHits.some((h) => {
    const t = Number(h.startTime) || 0;
    return t >= start - 0.05 && t <= end + 0.05;
  });
}

function punchColor(hex, fallback = "#FFEF5A") {
  if (typeof hex !== "string" || !hex.startsWith("#")) return fallback;
  const u = hex.toUpperCase();
  if (u === "#FFFFFF" || u === "#FFF" || u === "#FFFFFFFF") return fallback;
  return hex;
}

/**
 * Build pack-biased wordHits for even captions that still have none.
 * Ensures AI Place covers the full video sparsely.
 */
export function appendMissingCaptionWordHits({
  wordHits,
  captions = [],
  libraries,
  language = "en-US",
  pack = null,
}) {
  if (!Array.isArray(captions) || !captions.length) return 0;
  const rules = parityRules();
  const stride = Number(rules.captionStride) || 2;
  const fontLib = libraries.fonts.items;
  const effectLib = libraries.effects.items;
  const sfxLib = libraries.sfx.items;
  const hitsPerCap = wordHitsPerCaption(pack);
  const effectPoolBase = effectPoolForPack(effectLib, pack);
  const sfxPoolBase = sfxPoolForPack(sfxLib, pack);
  const punchyIds = punchyEffectIds();
  const colors = wordHitColors();
  const scale = Number(rules.wordHitScale) || 1.2;
  const xBase = Number(rules.wordHitXBase) || 0.42;
  const xStep = Number(rules.wordHitXStep) || 0.16;
  const yBase = Number(rules.wordHitYBase) || 0.34;
  const yStep = Number(rules.wordHitYStep) || 0.05;

  const scriptFonts = fontLib.filter((f) => {
    const scripts = f.scripts || [];
    if (language.startsWith("hi")) {
      return scripts.some((s) =>
        ["hi", "hindi", "devanagari", "en", "latin"].includes(s)
      );
    }
    if (language.startsWith("te")) {
      return scripts.some((s) => ["te", "telugu", "en", "latin"].includes(s));
    }
    return scripts.some((s) => ["en", "latin"].includes(s));
  });
  const fonts = scriptFonts.length ? scriptFonts : fontLib;
  let added = 0;

  captions.forEach((cap, index) => {
    if (index % stride !== 0) return;
    if (captionHasWordHit(wordHits, cap)) return;
    const sig = significantWordsFromCaption(cap, language, hitsPerCap);
    if (!sig.length) return;
    // One strong word max per filled caption (parity contract).
    const word = sig[0];
    const font = fonts[index % fonts.length];
    if (!font) return;
    const punchy = effectPoolBase.filter((e) => punchyIds.includes(e.id));
    const effectPool = punchy.length ? punchy : effectPoolBase;
    const effect = effectPool[(index * 3) % effectPool.length];
    if (!effect) return;
    const preferred = (effect.preferredSfx || [])
      .map(
        (id) =>
          sfxPoolBase.find((s) => s.id === id) ||
          sfxLib.find((s) => s.id === id)
      )
      .filter(Boolean);
    const sfx =
      preferred[0] ||
      sfxPoolBase[index % sfxPoolBase.length] ||
      sfxLib[index % sfxLib.length];
    const palette = effect.colors || colors;
    wordHits.push({
      kind: "wordHit",
      assetId: font.id,
      fontId: font.id,
      effectId: effect.id,
      sfxId: sfx?.id,
      word: word.text,
      text: word.text,
      captionIndex: index,
      wordIndex: word.index,
      startTime: word.startTime,
      endTime: word.endTime,
      x: xBase + (index % 2) * xStep,
      y: yBase + (index % 3) * yStep,
      scale,
      rotation: index % 2 === 0 ? -4 : 4,
      color: punchColor(palette[0]),
      secondaryColor: punchColor(palette[1] || "#FF2D2D", "#FF2D2D"),
      reason: `Sparse fill "${word.text}" → ${effect.id}`,
    });
    added += 1;
  });
  return added;
}
