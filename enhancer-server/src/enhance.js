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
 * Ask Cursor SDK (composer-2.5) where to place library assets on the timeline.
 * Falls back to a deterministic heuristic if CURSOR_API_KEY is missing or the call fails.
 */
export async function enhanceWithCursor({
  captions,
  duration,
  forceHeuristic = false,
  videoSize = null,
}) {
  const libraries = loadLibraries();
  const normalizedCaptions = (captions || []).map((c) => ({
    text: String(c.text ?? ""),
    startTime: Number(c.startTime) || 0,
    endTime: Number(c.endTime) || 0,
  }));
  const videoDuration = Number(duration) || 10;
  const payload = {
    captions: normalizedCaptions,
    duration: videoDuration,
    libraries,
    videoSize,
  };

  if (forceHeuristic || !process.env.CURSOR_API_KEY) {
    return {
      ...heuristicPlan(payload),
      model: null,
      note: forceHeuristic
        ? "Forced heuristic mode (asset lengths + caption windows)"
        : "CURSOR_API_KEY missing — heuristic used measured asset lengths/sizes",
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
      { ...parsed, source: "cursor-sdk" },
      libraries,
      normalizedCaptions,
      videoDuration
    );
    return {
      ...plan,
      model: result.model?.id || "composer-2.5",
      usage: result.usage,
      durationMs: result.durationMs,
      note: "Placements from Cursor SDK, snapped to each asset's measured length/size",
    };
  } catch (error) {
    const fallback = heuristicPlan(payload);
    return {
      ...fallback,
      model: null,
      note: `Cursor SDK failed (${error.message}); heuristic used measured asset lengths`,
    };
  }
}
