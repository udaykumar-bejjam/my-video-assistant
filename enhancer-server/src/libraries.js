import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

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
export function alignPlacement(placement, asset, captions, videoDuration) {
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
export function buildPrompt({ captions, duration, libraries, videoSize, language = "en-US" }) {
  const canvas = canvasForVideoSize(videoSize);
  const catalog = compactCatalog(libraries, canvas);
  const aspect = aspectLabel(canvas);

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

  return `You are the creative timing director for CaptionStudio.

Decide PRECISELY:
1) which SIGNIFICANT words to punch on screen
2) which font, randomised effect, and sound effect each word gets
3) where (x,y) and when (start/end) every asset plays

Language: ${language} (${scriptHint})

VIDEO
- durationSeconds: ${duration}
- aspect: ${aspect}
- canvasPixels: ${canvas.width}x${canvas.height}
- coordinateSystem: x,y normalized 0–1 on this canvas (0,0 = top-left)

CAPTION WINDOWS + WORD TIMINGS
${JSON.stringify(captionWindows, null, 2)}

LIBRARIES (ids only from here)
${JSON.stringify(catalog, null, 2)}

SIGNIFICANT WORD RULES
1. Pick 1–2 high-impact words per caption (names, verbs of power, emotion, numbers, CTAs). Skip filler.
2. For each wordHit use the word's OWN startTime/endTime when words[] is present; else use caption start + short span.
3. Randomise effectId across the effects library (do not reuse the same effect for every word).
4. Pair each effect with an sfxId — prefer that effect's preferredSfx list.
5. fontId MUST match the language script (${scriptHint}).
6. assetId for wordHit = fontId (required for validation).
7. endTime for wordHit = min(word.end, start + effect.lengthSeconds, caption.end).
8. Also emit supporting placements (gif/png/text/sfx) as before when helpful — keep total visual clutter low.

GENERAL TIMING RULES
1. Never invent library ids.
2. Return ONLY valid JSON (no markdown).
3. Never schedule past durationSeconds.
4. Keep resources fully on-screen given normalized size × scale.
5. sfx endTime = startTime + sfx.lengthSeconds exactly.

OUTPUT SCHEMA (JSON only) — the app applies this response precisely:
{
  "summary": "one sentence creative plan",
  "language": "${language}",
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
      "reason": "why this word + effect"
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

const WORD_HIT_COLORS = ["#FFEF5A", "#33F2CF", "#FF6B6B", "#FFFFFF", "#FF9F1C", "#C77DFF"];

export function validatePlacements(plan, libraries, captions = [], videoDuration = 10) {
  const assets = indexAssets(libraries);
  const fonts = Object.fromEntries(libraries.fonts.items.map((i) => [i.id, i]));
  const effects = Object.fromEntries(libraries.effects.items.map((i) => [i.id, i]));
  const sfx = Object.fromEntries(libraries.sfx.items.map((i) => [i.id, i]));

  const placements = [];
  const wordHits = [];

  const incoming = [
    ...(Array.isArray(plan?.placements) ? plan.placements : []),
    ...(Array.isArray(plan?.wordHits) ? plan.wordHits : []),
  ];

  for (const p of incoming) {
    if (!p) continue;
    if (p.kind === "wordHit") {
      const hit = alignWordHit(p, fonts, effects, sfx, captions, videoDuration);
      if (hit) wordHits.push(hit);
      continue;
    }
    const asset = assets[p.kind]?.[p.assetId];
    if (!asset) continue;
    placements.push(alignPlacement(p, asset, captions, videoDuration));
  }

  return {
    summary: typeof plan?.summary === "string" ? plan.summary : "Enhancement plan",
    placements,
    wordHits,
    language: plan?.language,
    source: plan?.source || "cursor-sdk",
    canvas: REFERENCE_CANVAS,
  };
}

export function alignWordHit(placement, fonts, effects, sfxMap, captions, videoDuration) {
  const fontId = placement.fontId || placement.assetId;
  const font = fonts[fontId];
  if (!font) return null;

  const effectIds = Object.keys(effects);
  let effectId = placement.effectId;
  if (!effects[effectId]) {
    effectId = effectIds[Math.floor(Math.random() * effectIds.length)];
  }
  const effect = effects[effectId];

  let sfxId = placement.sfxId;
  if (!sfxMap[sfxId]) {
    const preferred = effect.preferredSfx || [];
    sfxId = preferred.find((id) => sfxMap[id]) || Object.keys(sfxMap)[0];
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
  const color =
    typeof placement.color === "string" && placement.color.startsWith("#")
      ? placement.color
      : WORD_HIT_COLORS[Math.floor(Math.random() * WORD_HIT_COLORS.length)];

  const nw = (font.normalizedWidth || 0.2) * (Number(placement.scale) || 1.3);
  const nh = (font.normalizedHeight || 0.08) * (Number(placement.scale) || 1.3);
  let x = Number(placement.x);
  let y = Number(placement.y);
  if (!Number.isFinite(x)) x = 0.5;
  if (!Number.isFinite(y)) y = 0.4;
  x = clamp(x, nw / 2 + 0.02, 1 - nw / 2 - 0.02);
  y = clamp(y, nh / 2 + 0.05, 1 - nh / 2 - 0.05);

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
    scale: clamp(Number(placement.scale) || 1.3, 0.8, 2.6),
    rotation: Number.isFinite(Number(placement.rotation))
      ? Number(placement.rotation)
      : (Math.random() * 16 - 8),
    color,
    reason: placement.reason || `Significant word "${wordText}" with ${effectId}+${sfxId}`,
    assetPixelSize: { width: font.pixelWidth || 200, height: font.pixelHeight || 64 },
    // paired SFX cue length for the client
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
export function heuristicPlan({ captions, duration, libraries, language = "en-US" }) {
  const placements = [];
  const wordHits = [];
  const textLib = libraries["text-styles"].items;
  const gifLib = libraries.gifs.items;
  const pngLib = libraries.pngs.items;
  const sfxLib = libraries.sfx.items;
  const fontLib = libraries.fonts.items;
  const effectLib = libraries.effects.items;

  const pick = (items, tags) =>
    items.find((i) => (i.tags || []).some((t) => tags.includes(t))) || items[0];

  const scriptFonts = fontLib.filter((f) => {
    const scripts = f.scripts || [];
    if (language.startsWith("hi")) return scripts.some((s) => ["hi", "hindi", "devanagari"].includes(s));
    if (language.startsWith("te")) return scripts.some((s) => ["te", "telugu"].includes(s));
    return scripts.some((s) => ["en", "latin"].includes(s));
  });
  const fonts = scriptFonts.length ? scriptFonts : fontLib;

  const significantFrom = (cap) => {
    const parts = Array.isArray(cap.words) && cap.words.length
      ? cap.words.map((w, i) => ({ ...w, index: i }))
      : String(cap.text || "")
          .split(/\s+/)
          .filter(Boolean)
          .map((text, i, arr) => {
            const span = (cap.endTime - cap.startTime) / arr.length;
            return {
              text,
              index: i,
              startTime: cap.startTime + i * span,
              endTime: cap.startTime + (i + 1) * span,
            };
          });
    // Prefer longer / non-filler tokens
    const filler = new Set([
      "a","an","the","to","of","and","or","in","on","is","are","for","with","this","that",
      "एक","और","की","के","को","में","से","है","हैं","का","कि",
      "ఒక","మరియు","లో","కి","నుంచి","ఉంది","అని"
    ]);
    return parts
      .filter((w) => w.text && !filler.has(String(w.text).toLowerCase()) && String(w.text).length > 2)
      .sort((a, b) => String(b.text).length - String(a.text).length)
      .slice(0, 2);
  };

  captions.slice(0, 8).forEach((cap, index) => {
    const lower = (cap.text || "").toLowerCase();
    const mood =
      /(let'?s go|fire|crazy|insane|wow|hype|धमाका|ज़ोर|గొప్ప)/.test(lower)
        ? "hype"
        : /(love|heart|feel|miss|प्यार|ప్రేమ)/.test(lower)
          ? "emotional"
          : /(ai|tech|code|app|build|एआई)/.test(lower)
            ? "tech"
            : /(tip|how|secret|watch|टिप)/.test(lower)
              ? "reveal"
              : "default";

    // Significant word hits with randomised effects + sfx
    const sig = significantFrom(cap);
    sig.forEach((word, wi) => {
      const font = fonts[(index + wi) % fonts.length];
      const effect = effectLib[(index * 3 + wi * 2) % effectLib.length];
      const preferred = (effect.preferredSfx || []).map((id) => sfxLib.find((s) => s.id === id)).filter(Boolean);
      const sfx = preferred[0] || sfxLib[(index + wi) % sfxLib.length];
      wordHits.push({
        kind: "wordHit",
        assetId: font.id,
        fontId: font.id,
        effectId: effect.id,
        sfxId: sfx.id,
        word: word.text,
        text: word.text,
        captionIndex: index,
        wordIndex: word.index,
        startTime: word.startTime,
        endTime: word.endTime,
        x: 0.35 + (wi % 2) * 0.3,
        y: 0.36 + (index % 3) * 0.06,
        scale: 1.25 + (wi % 2) * 0.15,
        rotation: wi % 2 === 0 ? -5 : 6,
        color: WORD_HIT_COLORS[(index + wi) % WORD_HIT_COLORS.length],
        reason: `Significant "${word.text}" → ${effect.id} + ${sfx.id}`,
      });
    });

    if (index % 2 === 0 && gifLib.length) {
      const gif =
        mood === "hype"
          ? pick(gifLib, ["hype", "celebration"])
          : mood === "tech"
            ? pick(gifLib, ["tech", "focus"])
            : gifLib[index % gifLib.length];
      placements.push({
        kind: "gif",
        assetId: gif.id,
        captionIndex: index,
        startTime: cap.startTime,
        endTime: cap.startTime + (gif.lengthSeconds || 0.84),
        x: 0.82,
        y: 0.22 + (index % 3) * 0.08,
        scale: gif.defaultScale || 1,
        rotation: 0,
        reason: `GIF support for caption ${index}`,
      });
    }

    if (index % 3 === 0 && textLib.length) {
      const textAsset = textLib[index % textLib.length];
      placements.push({
        kind: "text",
        assetId: textAsset.id,
        captionIndex: index,
        startTime: cap.startTime,
        endTime: cap.startTime + (textAsset.lengthSeconds || 1.8),
        x: 0.5,
        y: 0.78,
        scale: 1,
        rotation: 0,
        text: String(cap.text || "").split(/\s+/).slice(0, 3).join(" "),
        reason: `Support text on caption ${index}`,
      });
    }
  });

  if (duration > 1.5) {
    const riser = sfxLib.find((i) => i.id === "riser") || sfxLib[0];
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
        reason: `Cold-open riser exact ${riser.lengthSeconds}s`,
      });
    }
  }

  return validatePlacements(
    {
      summary:
        "Heuristic: significant words with randomised fonts/effects/SFX, snapped to word timings.",
      language,
      placements,
      wordHits,
      source: "heuristic-fallback",
    },
    libraries,
    captions,
    duration
  );
}
