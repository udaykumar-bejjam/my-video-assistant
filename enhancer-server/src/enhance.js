import { Agent } from "@cursor/sdk";
import {
  LIBRARIES_ROOT,
  buildPrompt,
  extractJson,
  heuristicPlan,
  loadLibraries,
  resolveVideoDuration,
  validatePlacements,
} from "./libraries.js";

/**
 * Ask Cursor SDK which significant words / fonts / effects / SFX to place.
 * Falls back to a deterministic heuristic if CURSOR_API_KEY is missing.
 */
export async function enhanceWithCursor({
  captions,
  duration,
  forceHeuristic = false,
  videoSize = null,
  language = "en-US",
  packId = null,
  brandKit = null,
  safeZone = null,
}) {
  const libraries = loadLibraries();
  const normalizedCaptions = (captions || []).map((c) => ({
    text: String(c.text ?? ""),
    startTime: Number(c.startTime) || 0,
    endTime: Number(c.endTime) || 0,
    words: Array.isArray(c.words)
      ? c.words.map((w) => ({
          text: String(w.text ?? ""),
          startTime: Number(w.startTime) || 0,
          endTime: Number(w.endTime) || 0,
        }))
      : undefined,
  }));
  // Never coerce 0 → 10 (Number(0) is falsy). Prefer explicit duration, else caption span.
  const videoDuration = resolveVideoDuration(duration, normalizedCaptions);
  const lang = language || "en-US";
  const pack = packId || brandKit?.defaultPackId || null;
  const payload = {
    captions: normalizedCaptions,
    duration: videoDuration,
    libraries,
    videoSize,
    language: lang,
    packId: pack,
    brandKit,
    safeZone,
  };

  if (forceHeuristic || !process.env.CURSOR_API_KEY) {
    const plan = heuristicPlan(payload);
    return {
      ...plan,
      model: null,
      note: forceHeuristic
        ? `Forced heuristic${pack ? ` (pack:${pack})` : ""} parity v${plan.heuristicParityVersion || "1"}`
        : `CURSOR_API_KEY missing — heuristic${pack ? ` pack:${pack}` : ""} parity v${plan.heuristicParityVersion || "1"}`,
    };
  }

  const prompt = buildPrompt(payload);

  try {
    const result = await Agent.prompt(prompt, {
      apiKey: process.env.CURSOR_API_KEY,
      model: { id: "composer-2.5" },
      local: {
        cwd: LIBRARIES_ROOT,
      },
    });

    if (result.status !== "finished" || !result.result) {
      throw new Error(result.error?.message || `Agent status: ${result.status}`);
    }

    const parsed = extractJson(result.result);
    const plan = validatePlacements(
      {
        ...parsed,
        language: parsed.language || lang,
        packId: parsed.packId || pack,
        source: "cursor-sdk",
      },
      libraries,
      normalizedCaptions,
      videoDuration,
      pack,
      videoSize,
      safeZone
    );
    return {
      ...plan,
      model: result.model?.id || "composer-2.5",
      usage: result.usage,
      durationMs: result.durationMs,
      note: `Cursor SDK response applied precisely (wordHits + placements${pack ? `, pack:${pack}` : ""})`,
    };
  } catch (error) {
    const fallback = heuristicPlan(payload);
    return {
      ...fallback,
      model: null,
      note: `Cursor SDK failed (${error.message}); heuristic word-hit plan used`,
    };
  }
}
