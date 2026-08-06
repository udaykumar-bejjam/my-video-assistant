import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = path.resolve(__dirname, "../..");
export const LIBRARIES_ROOT = path.join(REPO_ROOT, "AssetLibraries");

const LIBS = ["text-styles", "gifs", "pngs", "sfx"];

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
  };
}

function indexAssets(libraries) {
  return {
    text: Object.fromEntries(libraries["text-styles"].items.map((i) => [i.id, i])),
    gif: Object.fromEntries(libraries.gifs.items.map((i) => [i.id, i])),
    png: Object.fromEntries(libraries.pngs.items.map((i) => [i.id, i])),
    sfx: Object.fromEntries(libraries.sfx.items.map((i) => [i.id, i])),
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
 * Build the Cursor agent prompt with FULL resource timing/size metadata.
 */
export function buildPrompt({ captions, duration, libraries, videoSize }) {
  const canvas = canvasForVideoSize(videoSize);
  const catalog = compactCatalog(libraries, canvas);
  const aspect = aspectLabel(canvas);

  const captionWindows = captions.map((c, index) => ({
    index,
    text: c.text,
    startTime: c.startTime,
    endTime: c.endTime,
    lengthSeconds: round3(Math.max(0, (c.endTime || 0) - (c.startTime || 0))),
  }));

  return `You are the timing director for CaptionStudio.

You place library resources onto a video timeline. Each resource has a MEASURED length and size.
Your startTime/endTime MUST respect those lengths and the caption windows that are playing.

VIDEO
- durationSeconds: ${duration}
- aspect: ${aspect}
- canvasPixels: ${canvas.width}x${canvas.height}
- coordinateSystem: x,y normalized 0–1 on this canvas (0,0 = top-left). Resource normalizedWidth/Height are fractions of THIS canvas at scale=1.

CAPTION WINDOWS (spoken content currently playing)
${JSON.stringify(captionWindows, null, 2)}

RESOURCE LIBRARIES (ids only from here)
Each item includes:
- lengthSeconds / durationSeconds = how long the resource plays (GIF cycle, SFX audio, text on-screen, PNG hold)
- pixelWidth/pixelHeight = intrinsic asset size
- normalizedWidth/normalizedHeight = on-canvas size at scale 1
${JSON.stringify(catalog, null, 2)}

TIMING RULES (mandatory)
1. Only use assetId values from the libraries. Never invent ids.
2. Return ONLY valid JSON (no markdown).
3. Prefer 6–14 placements; do not overlap too many visuals at once.
4. Set captionIndex to the caption window this resource supports.
5. startTime should equal that caption's startTime (hit with the spoken line).
6. endTime MUST be derived from the asset length:
   - sfx: endTime = startTime + asset.lengthSeconds (exact audio length)
   - gif: endTime = startTime + N * asset.lengthSeconds where N is whole loops that fit in the caption window (at least 1)
   - png: endTime = min(caption.endTime, startTime + asset.lengthSeconds)
   - text: endTime = min(caption.endTime, startTime + asset.lengthSeconds)
7. Never schedule past video durationSeconds.
8. Choose x,y so the resource's normalized size stays fully on-screen (account for scale).
9. For text, "text" is 2–5 punchy words from the caption.
10. Match mood tags: hype→neon-punch/confetti/bass-hit; calm→soft-serif/heart; tech→mint-glow/sparkle/glitch; reveal→outline-impact/pop-burst/ding.

OUTPUT SCHEMA (JSON only):
{
  "summary": "one sentence creative + timing plan",
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
      "reason": "why this moment + how length fits the caption"
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

export function validatePlacements(plan, libraries, captions = [], videoDuration = 10) {
  const assets = indexAssets(libraries);
  const placements = Array.isArray(plan?.placements) ? plan.placements : [];
  const cleaned = [];

  for (const p of placements) {
    const asset = assets[p?.kind]?.[p?.assetId];
    if (!asset) continue;
    cleaned.push(alignPlacement(p, asset, captions, videoDuration));
  }

  return {
    summary: typeof plan?.summary === "string" ? plan.summary : "Enhancement plan",
    placements: cleaned,
    source: plan?.source || "cursor-sdk",
    canvas: REFERENCE_CANVAS,
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

/** Offline heuristic — still aligns to measured asset lengths + caption windows. */
export function heuristicPlan({ captions, duration, libraries }) {
  const placements = [];
  const textLib = libraries["text-styles"].items;
  const gifLib = libraries.gifs.items;
  const pngLib = libraries.pngs.items;
  const sfxLib = libraries.sfx.items;

  const pick = (items, tags) =>
    items.find((i) => i.tags?.some((t) => tags.includes(t))) || items[0];

  captions.slice(0, 8).forEach((cap, index) => {
    const lower = (cap.text || "").toLowerCase();
    const mood =
      /(let'?s go|fire|crazy|insane|wow|hype)/.test(lower)
        ? "hype"
        : /(love|heart|feel|miss)/.test(lower)
          ? "emotional"
          : /(ai|tech|code|app|build)/.test(lower)
            ? "tech"
            : /(tip|how|secret|watch)/.test(lower)
              ? "reveal"
              : "default";

    const textAsset =
      mood === "hype"
        ? pick(textLib, ["hype", "energy"])
        : mood === "emotional"
          ? pick(textLib, ["emotional", "calm"])
          : mood === "tech"
            ? pick(textLib, ["ai", "tech", "modern"])
            : mood === "reveal"
              ? pick(textLib, ["impact", "reveal", "cta"])
              : textLib[index % textLib.length];

    const words = (cap.text || "Wow").split(/\s+/).slice(0, 4).join(" ");
    placements.push({
      kind: "text",
      assetId: textAsset.id,
      captionIndex: index,
      startTime: cap.startTime,
      endTime: cap.startTime + (textAsset.lengthSeconds || 1.8),
      x: index % 2 === 0 ? 0.5 : 0.48,
      y: index % 3 === 0 ? 0.26 : 0.32,
      scale: 1,
      rotation: index % 2 === 0 ? -3 : 2,
      text: words,
      reason: `Text length ${textAsset.lengthSeconds}s aligned to caption ${index}`,
    });

    if (index % 2 === 0) {
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
        reason: `GIF cycle ${gif.lengthSeconds}s (${gif.pixelWidth}x${gif.pixelHeight}) on caption ${index}`,
      });
    }

    if (index % 3 === 0) {
      const png =
        mood === "emotional"
          ? pick(pngLib, ["love", "emotional"])
          : mood === "tech"
            ? pick(pngLib, ["magic", "ai"])
            : pngLib[index % pngLib.length];
      placements.push({
        kind: "png",
        assetId: png.id,
        captionIndex: index,
        startTime: cap.startTime,
        endTime: cap.startTime + (png.lengthSeconds || 2),
        x: 0.18,
        y: 0.28 + (index % 2) * 0.1,
        scale: png.defaultScale || 1,
        rotation: -8,
        reason: `PNG ${png.pixelWidth}x${png.pixelHeight}, hold ${png.lengthSeconds}s`,
      });
    }

    const sfx =
      mood === "hype"
        ? pick(sfxLib, ["impact", "hype"])
        : mood === "reveal"
          ? pick(sfxLib, ["reveal", "success"])
          : mood === "tech"
            ? pick(sfxLib, ["tech", "glitch"])
            : sfxLib[index % sfxLib.length];
    placements.push({
      kind: "sfx",
      assetId: sfx.id,
      captionIndex: index,
      startTime: cap.startTime,
      endTime: cap.startTime + (sfx.lengthSeconds || 0.3),
      x: 0.5,
      y: 0.5,
      scale: 1,
      rotation: 0,
      reason: `SFX exact length ${sfx.lengthSeconds}s at caption ${index}`,
    });
  });

  if (duration > 1.5) {
    const riser = sfxLib.find((i) => i.id === "riser") || sfxLib[0];
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

  return validatePlacements(
    {
      summary:
        "Heuristic placements snapped to measured asset lengths and caption windows (Cursor SDK offline fallback).",
      placements,
      source: "heuristic-fallback",
    },
    libraries,
    captions,
    duration
  );
}
