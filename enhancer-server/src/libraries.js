import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import {
  effectPoolForPack,
  getPack,
  hookWindowSeconds,
  loadPacks,
  maxWordHitsPer15s,
  sfxPoolForPack,
  wordHitSfxEveryN,
} from "./packs.js";
import { ensureBrollStickers } from "./broll.js";
import {
  appendMissingCaptionWordHits,
  heuristicParityVersion,
  punchyEffectIds,
  wordHitColors,
  parityRules,
} from "./heuristicCore.js";
import {
  clampToSafeZone,
  heuristicDistribution,
  normalizeDistribution,
  normalizeSafeZone,
} from "./safezone.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = path.resolve(__dirname, "../..");
export const LIBRARIES_ROOT = path.join(REPO_ROOT, "AssetLibraries");

const LIBS = ["text-styles", "fonts", "effects", "gifs", "pngs", "sfx"];

export const REFERENCE_CANVAS = { width: 1080, height: 1920 };

export function canvasForVideoSize(videoSize) {
  if (videoSize?.width && videoSize?.height) {
    return { width: Number(videoSize.width), height: Number(videoSize.height) };
  }
  return REFERENCE_CANVAS;
}

export function aspectLabel(size) {
  const r = size.width / size.height;
  if (Math.abs(r - 16 / 9) < 0.08) return "16:9";
  if (Math.abs(r - 9 / 16) < 0.08) return "9:16";
  return `${size.width}x${size.height}`;
}

export function loadLibraries() {
  const libraries = {};
  for (const name of LIBS) {
    const catalogPath = path.join(LIBRARIES_ROOT, name, "catalog.json");
    const catalog = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
    catalog.items = catalog.items.map((item) => enrichItem(name, item));
    libraries[name] = catalog;
  }
  libraries.packs = loadPacks();
  return libraries;
}

/**
 * Ensure every library item exposes duration + size so Cursor can time it.
 * Catalog JSON is the source of truth; we fill gaps by probing files.
 */
function enrichItem(library, item) {
  const out = { ...item };
  const folder = path.join(LIBRARIES_ROOT, library);

  if (library === "gifs" && out.file) {
    const filePath = path.join(folder, out.file);
    if (!out.durationSeconds || !out.width) {
      Object.assign(out, probeGif(filePath));
    }
    out.lengthSeconds = out.durationSeconds;
    out.pixelWidth = out.width;
    out.pixelHeight = out.height;
    out.normalizedWidth = round4((out.width * (out.defaultScale || 1)) / REFERENCE_CANVAS.width);
    out.normalizedHeight = round4((out.height * (out.defaultScale || 1)) / REFERENCE_CANVAS.height);
  }

  if (library === "pngs" && out.file) {
    const filePath = path.join(folder, out.file);
    if (!out.width) Object.assign(out, probeImageSize(filePath));
    out.lengthSeconds = out.defaultDuration ?? 2;
    out.durationSeconds = out.lengthSeconds;
    out.pixelWidth = out.width;
    out.pixelHeight = out.height;
    out.normalizedWidth = round4((out.width * (out.defaultScale || 1)) / REFERENCE_CANVAS.width);
    out.normalizedHeight = round4((out.height * (out.defaultScale || 1)) / REFERENCE_CANVAS.height);
  }

  if (library === "sfx") {
    const fileName = out.wav || out.file;
    if (fileName && !out.durationSeconds) {
      Object.assign(out, probeAudioDuration(path.join(folder, fileName)));
    }
    out.lengthSeconds = out.durationSeconds;
    out.pixelWidth = 0;
    out.pixelHeight = 0;
    out.normalizedWidth = 0;
    out.normalizedHeight = 0;
  }

  if (library === "text-styles") {
    const fsPx = out.fontSize || 36;
    const text = out.previewText || out.name || "Text";
    out.estimatedWidth = out.estimatedWidth ?? Math.round(Math.min(900, Math.max(120, text.length * fsPx * 0.55)));
    out.estimatedHeight = out.estimatedHeight ?? Math.round(fsPx * 1.35);
    out.lengthSeconds = out.defaultDuration ?? 2;
    out.durationSeconds = out.lengthSeconds;
    out.pixelWidth = out.estimatedWidth;
    out.pixelHeight = out.estimatedHeight;
    out.normalizedWidth = round4(out.estimatedWidth / REFERENCE_CANVAS.width);
    out.normalizedHeight = round4(out.estimatedHeight / REFERENCE_CANVAS.height);
  }

  if (library === "fonts") {
    const text = out.previewText || out.name || "Aa";
    out.lengthSeconds = out.defaultDuration ?? 1.5;
    out.durationSeconds = out.lengthSeconds;
    out.pixelWidth = Math.round(Math.min(700, Math.max(80, text.length * 42 * 0.6)));
    out.pixelHeight = 64;
    out.normalizedWidth = round4(out.pixelWidth / REFERENCE_CANVAS.width);
    out.normalizedHeight = round4(out.pixelHeight / REFERENCE_CANVAS.height);
  }

  if (library === "effects") {
    out.lengthSeconds = out.defaultDuration ?? 1.0;
    out.durationSeconds = out.lengthSeconds;
    out.pixelWidth = 0;
    out.pixelHeight = 0;
    out.normalizedWidth = 0;
    out.normalizedHeight = 0;
  }

  return out;
}

function probeGif(filePath) {
  try {
    // Prefer catalog values; lightweight ffprobe for duration when needed.
    const duration = Number(
      execFileSync(
        "ffprobe",
        ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", filePath],
        { encoding: "utf8" }
      ).trim()
    );
    const wh = execFileSync(
      "ffprobe",
      ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", filePath],
      { encoding: "utf8" }
    )
      .trim()
      .split(",");
    return {
      durationSeconds: round3(duration || 0.84),
      width: Number(wh[0]) || 192,
      height: Number(wh[1]) || 192,
    };
  } catch {
    return { durationSeconds: 0.84, width: 192, height: 192 };
  }
}

function probeImageSize(filePath) {
  try {
    const wh = execFileSync(
      "ffprobe",
      ["-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height", "-of", "csv=p=0", filePath],
      { encoding: "utf8" }
    )
      .trim()
      .split(",");
    return { width: Number(wh[0]) || 256, height: Number(wh[1]) || 256 };
  } catch {
    return { width: 256, height: 256 };
  }
}

function probeAudioDuration(filePath) {
  try {
    const duration = Number(
      execFileSync(
        "ffprobe",
        ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", filePath],
        { encoding: "utf8" }
      ).trim()
    );
    return { durationSeconds: round3(duration || 0.3) };
  } catch {
    return { durationSeconds: 0.3 };
  }
}

/** Compact but COMPLETE resource metadata for the Cursor prompt. */
export function compactCatalog(libraries, canvas = REFERENCE_CANVAS) {
  const norm = (w, h, scale = 1) => ({
    normalizedWidth: round4(((w || 128) * scale) / canvas.width),
    normalizedHeight: round4(((h || 128) * scale) / canvas.height),
  });

  return {
    "text-styles": libraries["text-styles"].items.map((i) => ({
      id: i.id,
      name: i.name,
      tags: i.tags,
      previewText: i.previewText,
      lengthSeconds: i.lengthSeconds,
      durationSeconds: i.durationSeconds,
      pixelWidth: i.pixelWidth,
      pixelHeight: i.pixelHeight,
      ...norm(i.pixelWidth, i.pixelHeight, 1),
      fontSize: i.fontSize,
    })),
    gifs: libraries.gifs.items.map((i) => ({
      id: i.id,
      name: i.name,
      tags: i.tags,
      lengthSeconds: i.lengthSeconds,
      durationSeconds: i.durationSeconds,
      frameCount: i.frameCount,
      pixelWidth: i.pixelWidth,
      pixelHeight: i.pixelHeight,
      ...norm(i.pixelWidth, i.pixelHeight, i.defaultScale || 1),
      defaultScale: i.defaultScale || 1,
    })),
    pngs: libraries.pngs.items.map((i) => ({
      id: i.id,
      name: i.name,
      tags: i.tags,
      lengthSeconds: i.lengthSeconds,
      durationSeconds: i.durationSeconds,
      pixelWidth: i.pixelWidth,
      pixelHeight: i.pixelHeight,
      ...norm(i.pixelWidth, i.pixelHeight, i.defaultScale || 1),
      defaultScale: i.defaultScale || 1,
    })),
    sfx: libraries.sfx.items.map((i) => ({
      id: i.id,
      name: i.name,
      tags: i.tags,
      lengthSeconds: i.lengthSeconds,
      durationSeconds: i.durationSeconds,
      defaultGain: i.defaultGain,
    })),
    fonts: libraries.fonts.items.map((i) => ({
      id: i.id,
      name: i.name,
      fontName: i.fontName,
      scripts: i.scripts,
      tags: i.tags,
      previewText: i.previewText,
      lengthSeconds: i.lengthSeconds,
      pixelWidth: i.pixelWidth,
      pixelHeight: i.pixelHeight,
      ...norm(i.pixelWidth, i.pixelHeight, 1),
    })),
    effects: libraries.effects.items.map((i) => ({
      id: i.id,
      name: i.name,
      tags: i.tags,
      animation: i.animation,
      lengthSeconds: i.lengthSeconds,
      preferredSfx: i.preferredSfx || [],
      colors: i.colors || ["#FFEF5A", "#FF2D2D"],
      description: i.description,
    })),
  };
}

function indexAssets(libraries) {
  return {
    text: Object.fromEntries(libraries["text-styles"].items.map((i) => [i.id, i])),
    gif: Object.fromEntries(libraries.gifs.items.map((i) => [i.id, i])),
    png: Object.fromEntries(libraries.pngs.items.map((i) => [i.id, i])),
    sfx: Object.fromEntries(libraries.sfx.items.map((i) => [i.id, i])),
    font: Object.fromEntries(libraries.fonts.items.map((i) => [i.id, i])),
    effect: Object.fromEntries(libraries.effects.items.map((i) => [i.id, i])),
    wordHit: Object.fromEntries(libraries.fonts.items.map((i) => [i.id, i])),
  };
}

/**
 * Snap a placement's start/end to the asset's real length and the caption window.
 */
export function alignPlacement(placement, asset, captions, videoDuration, safeZone = null) {
  const length = Number(asset?.lengthSeconds ?? asset?.durationSeconds ?? 1.2) || 1.2;
  const caps = Array.isArray(captions) ? captions : [];

  let caption = null;
  if (Number.isInteger(placement.captionIndex) && caps[placement.captionIndex]) {
    caption = caps[placement.captionIndex];
  } else if (placement.alignToCaptionText) {
    caption = caps.find((c) => c.text === placement.alignToCaptionText) || null;
  } else {
    const t = Number(placement.startTime) || 0;
    caption =
      caps.find((c) => t >= c.startTime - 0.05 && t < c.endTime + 0.05) ||
      caps.find((c) => Math.abs((c.startTime || 0) - t) < 0.35) ||
      null;
  }

  let start = Number(placement.startTime);
  if (!Number.isFinite(start)) start = caption?.startTime ?? 0;

  // Prefer locking to the caption's start so the resource hits with the spoken line.
  if (caption && (placement.snapToCaption !== false)) {
    start = caption.startTime;
  }

  start = clamp(start, 0, Math.max(0, videoDuration - 0.05));

  let end;
  if (placement.kind === "sfx") {
    // Audio must play for exactly its measured length (clipped by video end).
    end = Math.min(videoDuration, start + length);
  } else if (placement.kind === "gif") {
    // One full GIF cycle by default; may fill the caption window with whole loops.
    const captionSpan = caption ? Math.max(0.1, caption.endTime - start) : length;
    const loops = Math.max(1, Math.floor(captionSpan / length));
    const playFor = Math.min(captionSpan, loops * length);
    end = Math.min(videoDuration, start + Math.max(length, playFor));
    // If caption is shorter than one cycle, still show one cycle clipped to video.
    if (caption && captionSpan < length) {
      end = Math.min(videoDuration, Math.min(caption.endTime, start + length));
    }
  } else if (placement.kind === "png") {
    // Still image: stay for min(asset default, remaining caption).
    const span = caption ? caption.endTime - start : length;
    end = Math.min(videoDuration, start + clamp(span, 0.4, length));
  } else {
    // Stylish text: ride the caption window, capped by style length.
    if (caption) {
      end = Math.min(videoDuration, Math.min(caption.endTime, start + length));
      if (end - start < 0.35) end = Math.min(videoDuration, start + Math.min(length, 0.8));
    } else {
      end = Math.min(videoDuration, start + length);
    }
  }

  if (end <= start) end = Math.min(videoDuration, start + Math.min(length, 0.5));

  // Keep overlays inside the frame given their measured normalized size.
  const nw = Number(asset?.normalizedWidth || 0.15) * (Number(placement.scale) || asset?.defaultScale || 1);
  const nh = Number(asset?.normalizedHeight || 0.1) * (Number(placement.scale) || asset?.defaultScale || 1);
  let x = Number(placement.x);
  let y = Number(placement.y);
  if (!Number.isFinite(x)) x = 0.5;
  if (!Number.isFinite(y)) y = 0.3;
  x = clamp(x, nw / 2 + 0.02, 1 - nw / 2 - 0.02);
  y = clamp(y, nh / 2 + 0.02, 1 - nh / 2 - 0.02);
  if (placement.kind !== "sfx" && safeZone) {
    ({ x, y } = clampToSafeZone(x, y, safeZone));
  }

  return {
    kind: placement.kind,
    assetId: placement.assetId,
    startTime: round3(start),
    endTime: round3(end),
    lengthSeconds: round3(length),
    x: round4(x),
    y: round4(y),
    scale: clamp(Number(placement.scale) || asset?.defaultScale || 1, 0.4, 2.5),
    rotation: Number(placement.rotation) || 0,
    text: typeof placement.text === "string" ? placement.text.slice(0, 48) : undefined,
    reason: typeof placement.reason === "string" ? placement.reason : undefined,
    captionIndex: caption ? caps.indexOf(caption) : undefined,
    pairedWord: typeof placement.pairedWord === "string" ? placement.pairedWord : undefined,
    mood: typeof placement.mood === "string" ? placement.mood : undefined,
    assetPixelSize:
      asset?.pixelWidth && asset?.pixelHeight
        ? { width: asset.pixelWidth, height: asset.pixelHeight }
        : undefined,
    assetNormalizedSize:
      asset?.normalizedWidth != null
        ? { width: asset.normalizedWidth, height: asset.normalizedHeight }
        : undefined,
  };
}

/**
 * Build the Cursor agent prompt with FULL resource timing/size metadata + significant word hits.
 */
export function buildPrompt({
  captions,
  duration,
  libraries,
  videoSize,
  language = "en-US",
  packId = null,
  brandKit = null,
  safeZone = null,
}) {
  const canvas = canvasForVideoSize(videoSize);
  const catalog = compactCatalog(libraries, canvas);
  const aspect = aspectLabel(canvas);
  const pack = getPack(packId) || null;
  const hookWindow = hookWindowSeconds(pack);
  const zone = normalizeSafeZone(safeZone, videoSize);

  const captionWindows = captions.map((c, index) => ({
    index,
    text: c.text,
    startTime: c.startTime,
    endTime: c.endTime,
    lengthSeconds: round3(Math.max(0, (c.endTime || 0) - (c.startTime || 0))),
    words: Array.isArray(c.words)
      ? c.words.map((w, wi) => ({
          index: wi,
          text: w.text,
          startTime: w.startTime,
          endTime: w.endTime,
        }))
      : undefined,
  }));

  const scriptHint =
    language.startsWith("hi")
      ? "Hindi/Devanagari — prefer hindi-* fonts"
      : language.startsWith("te")
        ? "Telugu — prefer telugu-* fonts"
        : "English/Latin — prefer latin-* fonts";

  const packBlock = pack
    ? `
SHORTS PACK (must honor)
- packId: ${pack.id}
- name: ${pack.name}
- effectBias (prefer these effectIds): ${JSON.stringify(pack.effectBias || [])}
- sfxBias (prefer these sfxIds): ${JSON.stringify(pack.sfxBias || [])}
- gifTags: ${JSON.stringify(pack.gifTags || [])}
- wordHitsPerCaption: ${wordHitsPerCaption(pack)}
- requireHookInFirstSeconds: ${hookWindow}
- gifDensity: ${pack.gifDensity || "medium"}
- captionStyle hint: ${pack.captionStyle || "upperPunch"}
`
    : `
SHORTS PACK
- none selected — use default punchy effects
`;

  const brandBlock = brandKit
    ? `
BRAND KIT (soft constraints — prefer when choosing fonts/colors)
- primaryFontId: ${brandKit.primaryFontId || ""}
- hindiFontId: ${brandKit.hindiFontId || ""}
- teluguFontId: ${brandKit.teluguFontId || ""}
- primaryColor: ${brandKit.primaryColor || "#FFEF5A"}
- secondaryColor: ${brandKit.secondaryColor || "#FF2D2D"}
`
    : "";

  return `You are the creative timing director for CaptionStudio.

Decide PRECISELY:
1) which SIGNIFICANT words to punch on screen
2) which font, randomised effect, and sound effect each word gets
3) where (x,y) and when (start/end) every asset plays

Language: ${language} (${scriptHint})
${packBlock}${brandBlock}
VIDEO
- durationSeconds: ${duration}
- aspect: ${aspect}
- canvasPixels: ${canvas.width}x${canvas.height}
- coordinateSystem: x,y normalized 0–1 on this canvas (0,0 = top-left)
- safeZone (keep wordHit/gif/png/text centers inside): ${JSON.stringify(zone)}

CAPTION WINDOWS + WORD TIMINGS
${JSON.stringify(captionWindows, null, 2)}

LIBRARIES (ids only from here)
${JSON.stringify(catalog, null, 2)}

SIGNIFICANT WORD RULES
1. Pick ${pack ? wordHitsPerCaption(pack) : "1–2"} high-impact words per caption (names, verbs of power, emotion, numbers, CTAs). Skip filler.
2. For each wordHit use the word's OWN startTime; hold endTime for ≥1.8s (or through most of the caption) so hits don't flash ahead of audio.
3. Prefer PUNCHY colourful effects${pack?.effectBias?.length ? ` from effectBias ${JSON.stringify(pack.effectBias)}` : " — punch, color-pulse, fire-pulse, stomp, slam, shake, neon-pulse"} — not plain bold.
4. Randomise effectId within the allowed pool; do not reuse the same effect for every word.
5. Set color to the effect's first palette colour (or brand kit primary/secondary when provided). Optionally set secondaryColor.
6. Pair each effect with an sfxId — prefer pack sfxBias then that effect's preferredSfx list.
7. fontId MUST match the language script (${scriptHint})${brandKit ? "; prefer brand kit font ids when they match the script" : ""}.
8. assetId for wordHit = fontId (required for validation).
9. endTime for wordHit = min(caption.end, max(word.end, start + max(1.8, effect.lengthSeconds))).
10. HOOK: guarantee ≥1 wordHit (or stylish text + sfx) with startTime < ${hookWindow}s. Prefer riser/bass-hit for the opening.
11. Also emit supporting placements (gif/png/text/sfx) when helpful — gif density = ${pack?.gifDensity || "medium"}.
12. B-ROLL: for every strong wordHit (power / reveal / emotion / numbers / CTA lexicon), also emit a gif OR png timed to that word's startTime, placed in a safe corner (x≈0.18/0.72, y≈0.2/0.55), tags matching the mood. Prefer gif (animated) over png for power / emotion / reveal when a matching gif exists. Cap ≈3 stickers per 15s. Pair sticker with sfx (wordHit.sfxId counts).
13. Keep x,y centers inside safeZone for all visual placements.
14. Also return distribution { title, coverText, hashtags[], hookLine } for social posting.
15. FULL DURATION: place wordHits across EVERY caption window from start to end — not only the opening ~10s. Sparse early-only plans are invalid.

GENERAL TIMING RULES
1. Never invent library ids.
2. Return ONLY valid JSON (no markdown).
3. Never schedule past durationSeconds.
4. Keep resources fully on-screen given normalized size × scale AND safeZone.
5. sfx endTime = startTime + sfx.lengthSeconds exactly.
6. Sticker placements for wordHits must use snapToCaption:false semantics — start at the word, not the caption start.
7. Cover the full timeline: the last wordHit should fall near the final captions (within the last ~20% of durationSeconds when captions exist there).

OUTPUT SCHEMA (JSON only) — the app applies this response precisely:
{
  "summary": "one sentence creative plan",
  "language": "${language}",
  "packId": ${pack ? `"${pack.id}"` : "null"},
  "hook": {
    "word": "opening word",
    "startTime": 0.4,
    "endTime": 1.1,
    "effectId": "punch",
    "sfxId": "riser",
    "fontId": "font id",
    "reason": "Opening retention hook"
  },
  "distribution": {
    "title": "short social title",
    "coverText": "COVER",
    "hashtags": ["#shorts", "#reels"],
    "hookLine": "opening line"
  },
  "wordHits": [
    {
      "kind": "wordHit",
      "assetId": "font id",
      "fontId": "font id",
      "effectId": "effect id",
      "sfxId": "sfx id",
      "word": "exact word text",
      "text": "exact word text",
      "captionIndex": 0,
      "wordIndex": 0,
      "startTime": 0.0,
      "endTime": 0.8,
      "x": 0.5,
      "y": 0.42,
      "scale": 1.35,
      "rotation": -4,
      "color": "#FFEF5A",
      "secondaryColor": "#FF2D2D",
      "reason": "punchy yellow/red pulse on this word"
    }
  ],
  "placements": [
    {
      "kind": "text" | "gif" | "png" | "sfx",
      "assetId": "string from library",
      "captionIndex": 0,
      "startTime": 0.0,
      "endTime": 1.0,
      "x": 0.5,
      "y": 0.28,
      "scale": 1.0,
      "rotation": 0,
      "text": "only for kind=text",
      "reason": "why"
    }
  ]
}`;
}

export function extractJson(text) {
  if (!text) throw new Error("Empty agent response");
  const trimmed = text.trim();
  const fence = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const candidate = fence ? fence[1].trim() : trimmed;
  const start = candidate.indexOf("{");
  const end = candidate.lastIndexOf("}");
  if (start === -1 || end === -1) throw new Error("No JSON object in agent response");
  return JSON.parse(candidate.slice(start, end + 1));
}

const WORD_HIT_COLORS = wordHitColors();
const PUNCHY_EFFECT_IDS = punchyEffectIds().length
  ? punchyEffectIds()
  : [
  "punch", "color-pulse", "fire-pulse", "stomp", "slam", "shake", "neon-pulse", "pulse", "glitch",
];

function punchColor(hex, fallback = "#FFEF5A") {
  if (typeof hex !== "string" || !hex.startsWith("#")) return fallback;
  const u = hex.toUpperCase();
  if (u === "#FFFFFF" || u === "#FFF" || u === "#FFFFFFFF") return fallback;
  return hex;
}

/** Keep word-hit density under control across long videos. */
export function thinWordHits(hits, videoDuration, maxPer15 = 2) {
  if (!Array.isArray(hits) || !hits.length) return [];
  const sorted = [...hits].sort((a, b) => Number(a.startTime) - Number(b.startTime));
  const kept = [];
  for (const hit of sorted) {
    const t = Number(hit.startTime) || 0;
    const inWindow = kept.filter((k) => {
      const kt = Number(k.startTime) || 0;
      return Math.abs(kt - t) <= 15;
    }).length;
    if (inWindow < maxPer15) kept.push(hit);
  }
  return kept;
}

/**
 * Resolve timeline length without the `Number(x) || 10` trap (0 is falsy and
 * used to clamp all word hits into the first 10s while phrase captions continued).
 */
export function resolveVideoDuration(duration, captions = []) {
  const raw = Number(duration);
  const fromCaptions = (captions || []).reduce((max, c) => {
    const end = Number(c?.endTime);
    return Number.isFinite(end) ? Math.max(max, end) : max;
  }, 0);
  if (Number.isFinite(raw) && raw > 0.05) {
    return Math.max(raw, fromCaptions);
  }
  if (fromCaptions > 0.05) return fromCaptions;
  return 10;
}

export function validatePlacements(
  plan,
  libraries,
  captions = [],
  videoDuration = 10,
  packId = null,
  videoSize = null,
  safeZone = null
) {
  const assets = indexAssets(libraries);
  const fonts = Object.fromEntries(libraries.fonts.items.map((i) => [i.id, i]));
  const effects = Object.fromEntries(libraries.effects.items.map((i) => [i.id, i]));
  const sfx = Object.fromEntries(libraries.sfx.items.map((i) => [i.id, i]));
  const pack = getPack(packId || plan?.packId) || null;
  const resolvedPackId = pack?.id || packId || plan?.packId || null;
  const zone = normalizeSafeZone(safeZone || plan?.safeZone, videoSize);
  const duration = resolveVideoDuration(videoDuration, captions);

  const placements = [];
  const wordHits = [];

  const incoming = [
    ...(Array.isArray(plan?.placements) ? plan.placements : []),
    ...(Array.isArray(plan?.wordHits) ? plan.wordHits : []),
  ];

  for (const p of incoming) {
    if (!p) continue;
    if (p.kind === "wordHit") {
      const hit = alignWordHit(p, fonts, effects, sfx, captions, duration, pack, zone);
      if (hit) wordHits.push(hit);
      continue;
    }
    const asset = assets[p.kind]?.[p.assetId];
    if (!asset) continue;
    placements.push(alignPlacement(p, asset, captions, duration, zone));
  }

  const hook = ensureOpeningHook({
    plan,
    wordHits,
    placements,
    fonts: libraries.fonts.items,
    effects: libraries.effects.items,
    sfxLib: libraries.sfx.items,
    captions,
    videoDuration: duration,
    pack,
    language: plan?.language || "en-US",
    safeZone: zone,
  });

  const language = plan?.language || "en-US";
  // Fill captions the model/heuristic skipped so AI Place spans the full video.
  const beforeFill = wordHits.length;
  appendMissingCaptionWordHits({
    wordHits,
    captions,
    libraries,
    language,
    pack,
  });
  for (let i = beforeFill; i < wordHits.length; i++) {
    const hit = alignWordHit(wordHits[i], fonts, effects, sfx, captions, duration, pack, zone);
    if (hit) {
      wordHits[i] = hit;
    } else {
      wordHits.splice(i, 1);
      i -= 1;
    }
  }
  // Density cap — avoid wall-of-hits on long clips.
  const thinned = thinWordHits(wordHits, duration, maxWordHitsPer15s(pack));
  wordHits.length = 0;
  wordHits.push(...thinned);
  // SFX only on every Nth surviving hit so audio stays sparse.
  const sfxEvery = wordHitSfxEveryN(pack);
  wordHits.forEach((h, i) => {
    if (i % sfxEvery !== 0) h.sfxId = null;
  });
  const beforeBroll = placements.length;
  ensureBrollStickers({
    wordHits,
    placements,
    gifLib: libraries.gifs.items,
    pngLib: libraries.pngs.items,
    sfxLib: libraries.sfx.items,
    language,
    pack,
    videoDuration: duration,
    options: plan?.options || {},
  });
  for (let i = beforeBroll; i < placements.length; i++) {
    const p = placements[i];
    const asset = assets[p.kind]?.[p.assetId];
    if (!asset) {
      placements.splice(i, 1);
      i -= 1;
      continue;
    }
    placements[i] = alignPlacement(
      { ...p, snapToCaption: false },
      asset,
      captions,
      duration,
      zone
    );
  }

  // Thin standalone SFX placements so audio stays sparse (keep opening hook).
  const standaloneSfx = placements
    .map((p, i) => ({ p, i }))
    .filter(({ p }) => p.kind === "sfx");
  const dropSfx = new Set();
  standaloneSfx.forEach(({ p, i }, n) => {
    if (Number(p.startTime) < 0.35) return; // keep cold-open
    if (n % 2 === 1) dropSfx.add(i);
  });
  if (dropSfx.size) {
    for (let i = placements.length - 1; i >= 0; i--) {
      if (dropSfx.has(i)) placements.splice(i, 1);
    }
  }

  const distribution = normalizeDistribution(
    plan?.distribution,
    captions,
    language,
    resolvedPackId
  );

  return {
    summary: typeof plan?.summary === "string" ? plan.summary : "Enhancement plan",
    placements,
    wordHits,
    hook: hook || plan?.hook || null,
    packId: resolvedPackId,
    distribution,
    safeZone: zone,
    language,
    source: plan?.source || "cursor-sdk",
    canvas: REFERENCE_CANVAS,
  };
}

/** Guarantee a visual+audio hook inside the pack's opening window. */
export function ensureOpeningHook({
  plan,
  wordHits,
  placements,
  fonts,
  effects,
  sfxLib,
  captions,
  videoDuration,
  pack,
  language = "en-US",
  safeZone = null,
}) {
  const windowSec = hookWindowSeconds(pack);
  const hasEarlyHit = wordHits.some((h) => h.startTime < windowSec);
  const hasEarlySfx = placements.some(
    (p) => p.kind === "sfx" && p.startTime < windowSec
  );

  let hookMeta = plan?.hook && typeof plan.hook === "object" ? { ...plan.hook } : null;

  if (hasEarlyHit && hasEarlySfx) {
    const early = wordHits.find((h) => h.startTime < windowSec);
    return (
      hookMeta || {
        word: early?.word,
        startTime: early?.startTime,
        endTime: early?.endTime,
        effectId: early?.effectId,
        sfxId: early?.sfxId,
        fontId: early?.fontId,
        reason: "Opening retention hook",
      }
    );
  }

  // Prefer an early spoken word; else synthesize a localized WAIT sticker.
  const earlyWords = [];
  captions.forEach((cap, captionIndex) => {
    const parts =
      Array.isArray(cap.words) && cap.words.length
        ? cap.words.map((w, i) => ({ ...w, index: i, captionIndex }))
        : String(cap.text || "")
            .split(/\s+/)
            .filter(Boolean)
            .map((text, i, arr) => {
              const span = (cap.endTime - cap.startTime) / Math.max(arr.length, 1);
              return {
                text,
                index: i,
                captionIndex,
                startTime: cap.startTime + i * span,
                endTime: cap.startTime + (i + 1) * span,
              };
            });
    for (const w of parts) {
      if (w.startTime < windowSec) earlyWords.push(w);
    }
  });

  const scriptFonts = fonts.filter((f) => {
    const scripts = f.scripts || [];
    // Code-switched TE/HI also needs Latin fonts for English inserts.
    if (language.startsWith("hi")) {
      return scripts.some((s) => ["hi", "hindi", "devanagari", "en", "latin"].includes(s));
    }
    if (language.startsWith("te")) {
      return scripts.some((s) => ["te", "telugu", "en", "latin"].includes(s));
    }
    return scripts.some((s) => ["en", "latin"].includes(s));
  });
  const fontPool = scriptFonts.length ? scriptFonts : fonts;
  const effectPool = effectPoolForPack(effects, pack);
  const sfxPool = sfxPoolForPack(sfxLib, pack);
  const riser =
    sfxPool.find((s) => s.id === "riser") ||
    sfxPool.find((s) => s.id === "bass-hit") ||
    sfxPool[0];
  const effect =
    effectPool.find((e) => e.id === "punch") ||
    effectPool.find((e) => (pack?.effectBias || []).includes(e.id)) ||
    effectPool[0];
  const font = fontPool[0];

  if (!hasEarlyHit && earlyWords.length && font && effect) {
    const w = earlyWords.sort((a, b) => String(b.text).length - String(a.text).length)[0];
    const palette = effect.colors || WORD_HIT_COLORS;
    const raw = {
      kind: "wordHit",
      assetId: font.id,
      fontId: font.id,
      effectId: effect.id,
      sfxId: riser?.id,
      word: w.text,
      text: w.text,
      captionIndex: w.captionIndex,
      wordIndex: w.index,
      startTime: w.startTime,
      endTime: w.endTime,
      x: 0.5,
      y: 0.38,
      scale: 1.45,
      rotation: -4,
      color: palette[0],
      secondaryColor: palette[1] || palette[0],
      reason: `Pack hook on "${w.text}"`,
    };
    const fontsMap = Object.fromEntries(fonts.map((i) => [i.id, i]));
    const effectsMap = Object.fromEntries(effects.map((i) => [i.id, i]));
    const sfxMap = Object.fromEntries(sfxLib.map((i) => [i.id, i]));
    const hit = alignWordHit(raw, fontsMap, effectsMap, sfxMap, captions, videoDuration, pack, safeZone);
    if (hit) wordHits.unshift(hit);
    hookMeta = {
      word: hit?.word || w.text,
      startTime: hit?.startTime ?? w.startTime,
      endTime: hit?.endTime ?? w.endTime,
      effectId: hit?.effectId || effect.id,
      sfxId: hit?.sfxId || riser?.id,
      fontId: hit?.fontId || font.id,
      reason: "Opening retention hook",
    };
  } else if (!hasEarlyHit && font && effect) {
    // Fallback stylish WAIT word-hit in the opening window
    const waitWord = language.startsWith("hi")
      ? "रुको"
      : language.startsWith("te")
        ? "ఆగు"
        : "WAIT";
    const palette = effect.colors || WORD_HIT_COLORS;
    const fontsMap = Object.fromEntries(fonts.map((i) => [i.id, i]));
    const effectsMap = Object.fromEntries(effects.map((i) => [i.id, i]));
    const sfxMap = Object.fromEntries(sfxLib.map((i) => [i.id, i]));
    const hit = alignWordHit(
      {
        kind: "wordHit",
        assetId: font.id,
        fontId: font.id,
        effectId: effect.id,
        sfxId: riser?.id,
        word: waitWord,
        text: waitWord,
        captionIndex: 0,
        startTime: 0.2,
        endTime: Math.min(videoDuration, 1.2),
        x: 0.5,
        y: 0.36,
        scale: 1.5,
        rotation: -5,
        color: palette[0],
        secondaryColor: palette[1] || palette[0],
        reason: "Synthetic WAIT hook",
      },
      fontsMap,
      effectsMap,
      sfxMap,
      captions,
      videoDuration,
      pack,
      safeZone
    );
    if (hit) {
      wordHits.unshift(hit);
      hookMeta = {
        word: waitWord,
        startTime: hit.startTime,
        endTime: hit.endTime,
        effectId: hit.effectId,
        sfxId: hit.sfxId,
        fontId: hit.fontId,
        reason: "Synthetic opening retention hook",
      };
    }
  }

  if (!hasEarlySfx && riser) {
    placements.unshift({
      kind: "sfx",
      assetId: riser.id,
      captionIndex: 0,
      snapToCaption: false,
      startTime: 0,
      endTime: riser.lengthSeconds || 0.8,
      x: 0.5,
      y: 0.5,
      scale: 1,
      rotation: 0,
      reason: `Pack opening ${riser.id} ${riser.lengthSeconds || 0.8}s`,
      lengthSeconds: riser.lengthSeconds,
    });
    // Re-align through alignPlacement path for consistency
    const aligned = alignPlacement(
      placements[0],
      riser,
      captions,
      videoDuration,
      safeZone
    );
    placements[0] = aligned;
  }

  return hookMeta;
}

export function alignWordHit(
  placement,
  fonts,
  effects,
  sfxMap,
  captions,
  videoDuration,
  pack = null,
  safeZone = null
) {
  const fontId = placement.fontId || placement.assetId;
  const font = fonts[fontId];
  if (!font) return null;

  const effectIds = Object.keys(effects);
  const bias = (pack?.effectBias || []).filter((id) => effects[id]);
  let effectId = placement.effectId;
  if (!effects[effectId]) {
    const punchy = PUNCHY_EFFECT_IDS.filter((id) => effects[id]);
    const pool = bias.length ? bias : punchy.length ? punchy : effectIds;
    effectId = pool[Math.floor(Math.random() * pool.length)];
  }
  const effect = effects[effectId];

  const sfxBias = (pack?.sfxBias || []).filter((id) => sfxMap[id]);
  let sfxId = placement.sfxId;
  if (!sfxMap[sfxId]) {
    const preferred = effect.preferredSfx || [];
    sfxId =
      sfxBias[0] ||
      preferred.find((id) => sfxMap[id]) ||
      Object.keys(sfxMap)[0];
  }
  const sfx = sfxMap[sfxId];

  const caps = Array.isArray(captions) ? captions : [];
  let caption = null;
  if (Number.isInteger(placement.captionIndex) && caps[placement.captionIndex]) {
    caption = caps[placement.captionIndex];
  }

  let start = Number(placement.startTime);
  let end = Number(placement.endTime);
  const words = caption?.words;

  if (Number.isInteger(placement.wordIndex) && Array.isArray(words) && words[placement.wordIndex]) {
    const w = words[placement.wordIndex];
    start = w.startTime;
    end = w.endTime;
  } else if (caption && (!Number.isFinite(start) || start < caption.startTime)) {
    start = caption.startTime;
  }

  if (!Number.isFinite(start)) start = 0;
  const effectLen = effect.lengthSeconds || 1;
  const sfxLen = sfx?.lengthSeconds || 0.3;
  if (!Number.isFinite(end) || end <= start) {
    end = start + effectLen;
  }
  end = Math.min(videoDuration, start + Math.max(end - start, Math.min(effectLen, 1.4)));
  if (caption) end = Math.min(end, caption.endTime + 0.15);

  const wordText = placement.word || placement.text || font.previewText || "!";
  const palette = Array.isArray(effect.colors) && effect.colors.length ? effect.colors : WORD_HIT_COLORS;
  const color = punchColor(
    typeof placement.color === "string" && placement.color.startsWith("#")
      ? placement.color
      : palette[0]
  );
  const secondaryColor = punchColor(palette[1] || palette[0], "#FF2D2D");

  // Inflate glyph extents so large punch text stays inside the frame / safe zone.
  const scale = clamp(Number(placement.scale) || 1.25, 0.8, 1.45);
  const charFactor = Math.min(1.8, 0.55 + String(wordText).length * 0.08);
  const nw = (font.normalizedWidth || 0.22) * scale * charFactor;
  const nh = (font.normalizedHeight || 0.1) * scale * 1.35;
  let x = Number(placement.x);
  let y = Number(placement.y);
  if (!Number.isFinite(x)) x = 0.5;
  if (!Number.isFinite(y)) y = 0.38;
  // Keep hits in the upper/mid band — below chrome, above caption lane (~0.82).
  const yMaxHit = safeZone ? Math.min(safeZone.yMax ?? 0.78, 0.58) : 0.58;
  const yMinHit = safeZone ? Math.max(safeZone.yMin ?? 0.12, 0.14) : 0.14;
  x = clamp(x, nw / 2 + 0.04, 1 - nw / 2 - 0.04);
  y = clamp(y, Math.max(nh / 2 + 0.04, yMinHit), Math.min(1 - nh / 2 - 0.04, yMaxHit));
  if (safeZone) {
    const z = {
      xMin: safeZone.xMin,
      xMax: safeZone.xMax,
      yMin: yMinHit,
      yMax: yMaxHit,
    };
    ({ x, y } = clampToSafeZone(x, y, z));
  }

  return {
    kind: "wordHit",
    assetId: fontId,
    fontId,
    effectId,
    sfxId,
    word: wordText,
    text: wordText,
    captionIndex: caption ? caps.indexOf(caption) : placement.captionIndex,
    wordIndex: placement.wordIndex,
    startTime: round3(Math.max(0, start)),
    endTime: round3(Math.max(0, end)),
    lengthSeconds: round3(effectLen),
    x: round4(x),
    y: round4(y),
    scale,
    rotation: Number.isFinite(Number(placement.rotation))
      ? clamp(Number(placement.rotation), -8, 8)
      : (Math.random() * 10 - 5),
    color,
    secondaryColor,
    reason: placement.reason || `Punchy "${wordText}" → ${effectId} (${color}) + ${sfxId || "no-sfx"}`,
    assetPixelSize: { width: font.pixelWidth || 200, height: font.pixelHeight || 64 },
    sfxLengthSeconds: sfxLen,
  };
}

function clamp(n, lo, hi) {
  return Math.min(hi, Math.max(lo, n));
}
function round3(n) {
  return Math.round(n * 1000) / 1000;
}
function round4(n) {
  return Math.round(n * 10000) / 10000;
}

/** Offline heuristic — significant word hits + measured asset lengths. */
export function heuristicPlan({
  captions,
  duration,
  libraries,
  language = "en-US",
  packId = null,
  videoSize = null,
  safeZone = null,
}) {
  const placements = [];
  const wordHits = [];
  const textLib = libraries["text-styles"].items;
  const sfxLib = libraries.sfx.items;
  const pack = getPack(packId);
  const sfxPoolBase = sfxPoolForPack(sfxLib, pack);
  const rules = parityRules();
  const textMod = Number(rules.textPlacementCaptionModulo) || 3;
  const textPrefix = Number(rules.textPrefixWords) || 3;
  const textX = Number(rules.textX) || 0.5;
  const textY = Number(rules.textY) || 0.28;
  const textRot = Number(rules.textRotation) || 0;
  const openMin = Number(rules.openingSfxMinDuration) || 1.5;
  const preferredOpen = rules.openingSfxPreferredIds || ["riser", "bass-hit"];
  const sourceTag = rules.sourceTag || "heuristic-fallback";

  // Seed from all captions — validatePlacements also fills any gaps.
  appendMissingCaptionWordHits({
    wordHits,
    captions,
    libraries,
    language,
    pack,
  });

  (captions || []).forEach((cap, index) => {
    if (index % textMod === 0 && textLib.length) {
      const textAsset = textLib[index % textLib.length];
      placements.push({
        kind: "text",
        assetId: textAsset.id,
        captionIndex: index,
        startTime: cap.startTime,
        endTime: cap.startTime + (textAsset.lengthSeconds || 1.8),
        x: textX,
        y: textY,
        scale: 1,
        rotation: textRot,
        text: String(cap.text || "").split(/\s+/).slice(0, textPrefix).join(" "),
        reason: `Support text on caption ${index}`,
      });
    }
  });

  // Opening SFX — prefer pack bias (ensureOpeningHook also enforces)
  if (duration > openMin) {
    let riser = null;
    for (const id of preferredOpen) {
      riser = sfxPoolBase.find((i) => i.id === id) || sfxLib.find((i) => i.id === id);
      if (riser) break;
    }
    if (!riser) riser = sfxLib[0];
    if (riser) {
      placements.unshift({
        kind: "sfx",
        assetId: riser.id,
        captionIndex: 0,
        snapToCaption: false,
        startTime: 0,
        endTime: riser.lengthSeconds || 0.8,
        x: 0.5,
        y: 0.5,
        scale: 1,
        rotation: 0,
        reason: `Cold-open ${riser.id} exact ${riser.lengthSeconds}s`,
      });
    }
  }

  const validated = validatePlacements(
    {
      summary: pack
        ? `Heuristic pack "${pack.name}": word hits + B-roll stickers snapped to timings.`
        : "Heuristic: significant words with fonts/effects/SFX + auto B-roll stickers.",
      language,
      packId: pack?.id || null,
      placements,
      wordHits,
      distribution: heuristicDistribution(captions, language, pack?.id || null),
      source: sourceTag,
    },
    libraries,
    captions,
    duration,
    pack?.id || null,
    videoSize,
    safeZone
  );
  return {
    ...validated,
    heuristicParityVersion: heuristicParityVersion(),
  };
}
