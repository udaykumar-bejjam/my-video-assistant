import { Agent } from "@cursor/sdk";
import {
  LIBRARIES_ROOT,
  buildPrompt,
  extractJson,
  heuristicPlan,
  loadLibraries,
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
  const videoDuration = Number(duration) || 10;
  const lang = language || "en-US";
  const payload = {
    captions: normalizedCaptions,
    duration: videoDuration,
    libraries,
    videoSize,
    language: lang,
  };

  if (forceHeuristic || !process.env.CURSOR_API_KEY) {
    return {
      ...heuristicPlan(payload),
      model: null,
      note: forceHeuristic
        ? "Forced heuristic (word hits + fonts/effects/SFX)"
        : "CURSOR_API_KEY missing — heuristic chose significant words, fonts, effects, SFX",
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
      { ...parsed, language: parsed.language || lang, source: "cursor-sdk" },
      libraries,
      normalizedCaptions,
      videoDuration
    );
    return {
      ...plan,
      model: result.model?.id || "composer-2.5",
      usage: result.usage,
      durationMs: result.durationMs,
      note: "Cursor SDK response applied precisely (wordHits + placements)",
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
