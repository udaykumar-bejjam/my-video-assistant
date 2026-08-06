import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
export const REPO_ROOT = path.resolve(__dirname, "../..");
export const LIBRARIES_ROOT = path.join(REPO_ROOT, "AssetLibraries");

const LIBS = ["text-styles", "gifs", "pngs", "sfx"];

export function loadLibraries() {
  const libraries = {};
  for (const name of LIBS) {
    const catalogPath = path.join(LIBRARIES_ROOT, name, "catalog.json");
    libraries[name] = JSON.parse(fs.readFileSync(catalogPath, "utf8"));
  }
  return libraries;
}

export function compactCatalog(libraries) {
  return {
    "text-styles": libraries["text-styles"].items.map((i) => ({
      id: i.id,
      name: i.name,
      tags: i.tags,
      previewText: i.previewText,
      defaultDuration: i.defaultDuration,
    })),
    gifs: libraries.gifs.items.map((i) => ({
      id: i.id,
      name: i.name,
      tags: i.tags,
      defaultDuration: i.defaultDuration,
    })),
    pngs: libraries.pngs.items.map((i) => ({
      id: i.id,
      name: i.name,
      tags: i.tags,
      defaultDuration: i.defaultDuration,
    })),
    sfx: libraries.sfx.items.map((i) => ({
      id: i.id,
      name: i.name,
      tags: i.tags,
    })),
  };
}

/**
 * @typedef {object} CaptionInput
 * @property {string} text
 * @property {number} startTime
 * @property {number} endTime
 */

/**
 * Build the Cursor agent prompt. Asks for STRICT JSON placements from catalogs.
 */
export function buildPrompt({ captions, duration, libraries }) {
  const catalog = compactCatalog(libraries);
  return `You are the creative director for CaptionStudio, a short-form video editor.

Given a timed transcript and four asset libraries, decide PRECISELY where to place overlays.

RULES:
1. Only use asset ids from the libraries below. Never invent ids.
2. Return ONLY valid JSON (no markdown fences, no commentary).
3. Prefer 6–14 total placements for a short clip; do not overcrowd.
4. Times must fall within [0, duration]. Prefer aligning to caption startTimes.
5. x and y are normalized video coordinates (0–1). Keep stylish text near y=0.22–0.38 or y=0.70–0.78; stickers in corners/edges.
6. For text placements, set "text" to a short punchy phrase (2–5 words) derived from the nearby caption.
7. Match tags/mood: hype words → neon-punch / confetti / bass-hit; calm → soft-serif / heart; tech/AI → mint-glow / sparkle / glitch; reveals → outline-impact / pop-burst / ding.

VIDEO
- durationSeconds: ${duration}

CAPTIONS (timed transcript)
${JSON.stringify(captions, null, 2)}

LIBRARIES
${JSON.stringify(catalog, null, 2)}

OUTPUT SCHEMA (JSON only):
{
  "summary": "one sentence creative plan",
  "placements": [
    {
      "kind": "text" | "gif" | "png" | "sfx",
      "assetId": "string from library",
      "startTime": 0.0,
      "endTime": 1.0,
      "x": 0.5,
      "y": 0.28,
      "scale": 1.0,
      "rotation": 0,
      "text": "only for kind=text",
      "reason": "why this moment"
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

export function validatePlacements(plan, libraries) {
  const ids = {
    text: new Set(libraries["text-styles"].items.map((i) => i.id)),
    gif: new Set(libraries.gifs.items.map((i) => i.id)),
    png: new Set(libraries.pngs.items.map((i) => i.id)),
    sfx: new Set(libraries.sfx.items.map((i) => i.id)),
  };

  const placements = Array.isArray(plan?.placements) ? plan.placements : [];
  const cleaned = [];
  for (const p of placements) {
    if (!p || !ids[p.kind]?.has(p.assetId)) continue;
    const start = Number(p.startTime) || 0;
    let end = Number(p.endTime);
    if (!Number.isFinite(end) || end <= start) end = start + 1.2;
    cleaned.push({
      kind: p.kind,
      assetId: p.assetId,
      startTime: Math.max(0, start),
      endTime: Math.max(0, end),
      x: clamp01(Number(p.x) || 0.5),
      y: clamp01(Number(p.y) || 0.3),
      scale: Math.min(2.5, Math.max(0.4, Number(p.scale) || 1)),
      rotation: Number(p.rotation) || 0,
      text: typeof p.text === "string" ? p.text.slice(0, 48) : undefined,
      reason: typeof p.reason === "string" ? p.reason : undefined,
    });
  }
  return {
    summary: typeof plan?.summary === "string" ? plan.summary : "Enhancement plan",
    placements: cleaned,
    source: plan?.source || "cursor-sdk",
  };
}

function clamp01(n) {
  return Math.min(1, Math.max(0, n));
}

/** Offline heuristic when CURSOR_API_KEY is missing — still returns the same schema. */
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
      startTime: cap.startTime,
      endTime: Math.min(cap.endTime, cap.startTime + (textAsset.defaultDuration || 1.8)),
      x: index % 2 === 0 ? 0.5 : 0.48,
      y: index % 3 === 0 ? 0.26 : 0.32,
      scale: 1,
      rotation: index % 2 === 0 ? -3 : 2,
      text: words,
      reason: `Accent caption ${index + 1} (${mood})`,
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
        startTime: cap.startTime,
        endTime: cap.startTime + (gif.defaultDuration || 1.2),
        x: 0.82,
        y: 0.22 + (index % 3) * 0.08,
        scale: gif.defaultScale || 1,
        rotation: 0,
        reason: `GIF hit on beat ${index + 1}`,
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
        startTime: cap.startTime + 0.15,
        endTime: cap.startTime + (png.defaultDuration || 2),
        x: 0.18,
        y: 0.28 + (index % 2) * 0.1,
        scale: png.defaultScale || 1,
        rotation: -8,
        reason: `PNG sticker near caption ${index + 1}`,
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
      startTime: cap.startTime,
      endTime: cap.startTime + 0.5,
      x: 0.5,
      y: 0.5,
      scale: 1,
      rotation: 0,
      reason: `SFX for caption ${index + 1}`,
    });
  });

  // Opening riser if duration allows
  if (duration > 1.5) {
    const riser = sfxLib.find((i) => i.id === "riser") || sfxLib[0];
    placements.unshift({
      kind: "sfx",
      assetId: riser.id,
      startTime: 0,
      endTime: Math.min(0.8, duration),
      x: 0.5,
      y: 0.5,
      scale: 1,
      rotation: 0,
      reason: "Cold-open riser",
    });
  }

  return validatePlacements(
    {
      summary: "Heuristic enhancement from caption mood tags (Cursor SDK offline fallback).",
      placements,
      source: "heuristic-fallback",
    },
    libraries
  );
}
