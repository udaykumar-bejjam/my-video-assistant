/**
 * Auto B-roll / sticker moments — pair strong wordHits with GIF/PNG (+ SFX).
 */
import { gifEveryN } from "./packs.js";
import {
  classifyStrongWord,
  tagsForCategory,
} from "./lexicon.js";

/** Safe corners inside default Reels chrome (normalized). */
export const SAFE_CORNERS = [
  { x: 0.18, y: 0.2 },
  { x: 0.72, y: 0.2 },
  { x: 0.18, y: 0.58 },
  { x: 0.72, y: 0.55 },
];

export function maxStickersPer15s(pack, options = {}) {
  const fromOpt = Number(options.maxStickersPer15s);
  if (Number.isFinite(fromOpt) && fromOpt > 0) return Math.min(8, Math.floor(fromOpt));
  const density = pack?.gifDensity || "medium";
  if (density === "high") return 4;
  if (density === "low") return 2;
  return 3;
}

function stickerPlacements(placements = []) {
  return placements.filter((p) => p.kind === "gif" || p.kind === "png");
}

function hasNearbySticker(placements, at, windowSec = 0.45) {
  return stickerPlacements(placements).some(
    (p) => Math.abs(Number(p.startTime) - at) <= windowSec
  );
}

function stickersInWindow(placements, center, halfWindow = 7.5) {
  return stickerPlacements(placements).filter((p) => {
    const t = Number(p.startTime);
    return t >= center - halfWindow && t <= center + halfWindow;
  }).length;
}

function pickByTags(lib, tags) {
  if (!lib?.length) return null;
  if (!tags?.length) return lib[0];
  const hit = lib.find((item) => (item.tags || []).some((t) => tags.includes(t)));
  return hit || lib[0];
}

/** Prefer animated GIFs for punchy moods when a tagged GIF exists. */
function prefersAnimatedGif(category) {
  return category === "power" || category === "emotion" || category === "reveal";
}

function pickStickerAssets(gifLib, pngLib, category, index) {
  const tags = tagsForCategory(category);
  // Phase 2: power / emotion / reveal → GIF first; numbers / CTA still alternate.
  if (prefersAnimatedGif(category)) {
    const gif = pickByTags(gifLib, tags);
    if (gif) return { kind: "gif", asset: gif };
    const png = pickByTags(pngLib, tags);
    if (png) return { kind: "png", asset: png };
    return null;
  }
  if (index % 2 === 0) {
    const gif = pickByTags(gifLib, tags);
    if (gif) return { kind: "gif", asset: gif };
    const png = pickByTags(pngLib, tags);
    if (png) return { kind: "png", asset: png };
  } else {
    const png = pickByTags(pngLib, tags);
    if (png) return { kind: "png", asset: png };
    const gif = pickByTags(gifLib, tags);
    if (gif) return { kind: "gif", asset: gif };
  }
  return null;
}

function pickPopSfx(sfxLib, pack) {
  if (!sfxLib?.length) return null;
  const preferred = [...(pack?.sfxBias || []), "pop", "whoosh", "ding", "bass-hit"];
  for (const id of preferred) {
    const hit = sfxLib.find((s) => s.id === id);
    if (hit) return hit;
  }
  return sfxLib[0];
}

/**
 * Ensure strong wordHits get a timed sticker (+ SFX if missing nearby).
 * Mutates placements array; returns count of stickers added.
 */
export function ensureBrollStickers({
  wordHits = [],
  placements,
  gifLib = [],
  pngLib = [],
  sfxLib = [],
  language = "en-US",
  pack = null,
  videoDuration = 60,
  options = {},
}) {
  if (!placements) return 0;
  const maxPer = maxStickersPer15s(pack, options);
  let added = 0;
  let cornerIdx = stickerPlacements(placements).length;

  const strong = wordHits
    .map((hit, i) => {
      const word = hit.word || hit.text || "";
      const category = classifyStrongWord(word, language);
      return category
        ? { hit, category, index: i, at: Number(hit.startTime) || 0 }
        : null;
    })
    .filter(Boolean)
    .sort((a, b) => a.at - b.at);

  for (const { hit, category, index, at } of strong) {
    if (at > videoDuration) continue;
    if (hasNearbySticker(placements, at)) continue;
    if (stickersInWindow(placements, at) >= maxPer) continue;

    const picked = pickStickerAssets(gifLib, pngLib, category, index);
    if (!picked) continue;

    const { kind, asset } = picked;
    const length =
      Number(asset.lengthSeconds || asset.durationSeconds || asset.defaultDuration) ||
      (kind === "gif" ? 0.84 : 1.8);
    const corner = SAFE_CORNERS[cornerIdx % SAFE_CORNERS.length];
    cornerIdx += 1;

    placements.push({
      kind,
      assetId: asset.id,
      captionIndex: hit.captionIndex ?? 0,
      wordIndex: hit.wordIndex,
      snapToCaption: false,
      startTime: at,
      endTime: Math.min(videoDuration, at + length),
      x: corner.x,
      y: corner.y,
      scale: asset.defaultScale || 1,
      rotation: index % 2 === 0 ? -4 : 5,
      reason: `B-roll sticker for "${hit.word || hit.text}" (${category})`,
      lengthSeconds: length,
      pairedWord: hit.word || hit.text,
      mood: category,
    });
    added += 1;

    // Ensure audible punch near the sticker if no SFX already in that window.
    const hasSfx =
      Boolean(hit.sfxId) ||
      placements.some(
        (p) => p.kind === "sfx" && Math.abs(Number(p.startTime) - at) <= 0.4
      );
    if (!hasSfx) {
      const sfx = pickPopSfx(sfxLib, pack);
      if (sfx) {
        placements.push({
          kind: "sfx",
          assetId: sfx.id,
          captionIndex: hit.captionIndex ?? 0,
          snapToCaption: false,
          startTime: at,
          endTime: Math.min(videoDuration, at + (sfx.lengthSeconds || 0.35)),
          x: 0.5,
          y: 0.5,
          scale: 1,
          rotation: 0,
          reason: `B-roll SFX for "${hit.word || hit.text}"`,
          lengthSeconds: sfx.lengthSeconds || 0.35,
        });
      }
    }
  }

  // Sparse caption-level GIF fill when pack density is high and few stickers exist.
  const everyN = gifEveryN(pack);
  if (everyN === 1 && stickerPlacements(placements).length === 0 && gifLib.length) {
    const gif = gifLib[0];
    placements.push({
      kind: "gif",
      assetId: gif.id,
      captionIndex: 0,
      startTime: 0.5,
      endTime: Math.min(videoDuration, 0.5 + (gif.lengthSeconds || 0.84)),
      x: SAFE_CORNERS[0].x,
      y: SAFE_CORNERS[0].y,
      scale: gif.defaultScale || 1,
      rotation: 0,
      reason: "Density fill GIF",
    });
    added += 1;
  }

  return added;
}

/**
 * Pairing rate: fraction of strong wordHits that have a sticker within 0.5s.
 */
export function brollPairingRate(wordHits, placements, language = "en-US") {
  const strong = (wordHits || []).filter((h) =>
    classifyStrongWord(h.word || h.text || "", language)
  );
  if (!strong.length) return 1;
  const paired = strong.filter((h) =>
    hasNearbySticker(placements, Number(h.startTime) || 0, 0.5)
  );
  return paired.length / strong.length;
}
