/**
 * Shorts Pack helpers — load recipes and bias heuristic / Cursor prompts.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const LIBRARIES_ROOT = path.resolve(__dirname, "../../AssetLibraries");

let cachedPacks = null;

export function loadPacks() {
  if (cachedPacks) return cachedPacks;
  const catalogPath = path.join(LIBRARIES_ROOT, "packs", "catalog.json");
  if (!fs.existsSync(catalogPath)) {
    cachedPacks = { version: 1, library: "packs", items: [] };
    return cachedPacks;
  }
  cachedPacks = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
  return cachedPacks;
}

export function getPack(packId) {
  if (!packId) return null;
  const packs = loadPacks();
  return packs.items.find((p) => p.id === packId) || null;
}

export function clearPackCache() {
  cachedPacks = null;
}

/** Filter effect list to pack bias when possible. */
export function effectPoolForPack(effectLib, pack) {
  if (!pack?.effectBias?.length) return effectLib;
  const biased = pack.effectBias
    .map((id) => effectLib.find((e) => e.id === id))
    .filter(Boolean);
  return biased.length ? biased : effectLib;
}

/** Filter SFX list to pack bias when possible. */
export function sfxPoolForPack(sfxLib, pack) {
  if (!pack?.sfxBias?.length) return sfxLib;
  const biased = pack.sfxBias
    .map((id) => sfxLib.find((s) => s.id === id))
    .filter(Boolean);
  return biased.length ? biased : sfxLib;
}

export function pickGifForPack(gifLib, pack, moodTags = []) {
  if (!gifLib?.length) return null;
  const tags = [...(pack?.gifTags || []), ...moodTags];
  if (!tags.length) return gifLib[0];
  const hit = gifLib.find((g) => (g.tags || []).some((t) => tags.includes(t)));
  return hit || gifLib[0];
}

export function gifEveryN(pack) {
  const density = pack?.gifDensity || "medium";
  if (density === "high") return 1;
  if (density === "low") return 3;
  return 2;
}

export function wordHitsPerCaption(pack) {
  const n = Number(pack?.wordHitsPerCaption);
  // Default 1, hard max 2 — dense hits crowd the frame and steal focus.
  return Number.isFinite(n) && n > 0 ? Math.min(2, Math.floor(n)) : 1;
}

/** Max floating word hits in any rolling 15s window. */
export function maxWordHitsPer15s(pack) {
  const density = pack?.gifDensity || "medium";
  if (density === "high") return 3;
  if (density === "low") return 1;
  return 2;
}

/** Attach SFX to every Nth word hit (1 = all, 3 = every third). */
export function wordHitSfxEveryN(pack) {
  const density = pack?.gifDensity || "medium";
  if (density === "high") return 2;
  if (density === "low") return 4;
  return 3;
}

export function hookWindowSeconds(pack) {
  const n = Number(pack?.requireHookInFirstSeconds);
  return Number.isFinite(n) && n > 0 ? n : 3;
}
