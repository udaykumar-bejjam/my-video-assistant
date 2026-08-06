/**
 * Safe-zone helpers for Reels/TikTok chrome.
 */
export const DEFAULT_SAFE_ZONE = { xMin: 0.08, xMax: 0.82, yMin: 0.12, yMax: 0.78 };
export const LANDSCAPE_SAFE_ZONE = { xMin: 0.06, xMax: 0.94, yMin: 0.1, yMax: 0.88 };

export function normalizeSafeZone(raw, videoSize = null) {
  if (raw && Number.isFinite(raw.xMin) && Number.isFinite(raw.xMax)) {
    return {
      xMin: Number(raw.xMin),
      xMax: Number(raw.xMax),
      yMin: Number(raw.yMin),
      yMax: Number(raw.yMax),
    };
  }
  if (videoSize?.width && videoSize?.height && videoSize.width > videoSize.height) {
    return { ...LANDSCAPE_SAFE_ZONE };
  }
  return { ...DEFAULT_SAFE_ZONE };
}

export function clampToSafeZone(x, y, safeZone) {
  if (!safeZone) return { x, y };
  return {
    x: Math.min(safeZone.xMax, Math.max(safeZone.xMin, x)),
    y: Math.min(safeZone.yMax, Math.max(safeZone.yMin, y)),
  };
}

/** Build distribution copy heuristically from caption text. */
export function heuristicDistribution(captions = [], language = "en-US", packId = null) {
  const text = captions.map((c) => c.text || "").join(" ");
  const words = text
    .split(/[\s.,!?;:]+/)
    .map((w) => w.trim())
    .filter((w) => w.length > 2);
  const significant = words.slice(0, 6);
  const hook =
    significant[0] ||
    (language.startsWith("hi") ? "देखो" : language.startsWith("te") ? "చూడండి" : "Watch this");
  const titleBase = significant.slice(0, 4).join(" ");
  const title = (titleBase || (packId ? `${packId} short` : "New short")).slice(0, 60);
  const coverText = String(significant[0] || hook).toUpperCase().slice(0, 24);

  let hashtags = ["#shorts", "#reels", "#fyp"];
  if (language.startsWith("hi")) hashtags = ["#शॉर्ट्स", "#reels", "#fyp"];
  if (language.startsWith("te")) hashtags = ["#shorts", "#reels", "#తెలుగు"];
  if (packId) hashtags.push(`#${packId}`);
  if (significant[0]) hashtags.push(`#${significant[0].toLowerCase()}`);

  return {
    title,
    coverText,
    hashtags: hashtags.slice(0, 6),
    hookLine: hook,
  };
}

export function normalizeDistribution(raw, captions, language, packId) {
  if (raw && typeof raw === "object" && typeof raw.title === "string" && raw.title.trim()) {
    const hashtags = Array.isArray(raw.hashtags)
      ? raw.hashtags.map(String).filter(Boolean).slice(0, 8)
      : [];
    return {
      title: String(raw.title).slice(0, 80),
      coverText: String(raw.coverText || raw.title).slice(0, 32),
      hashtags,
      hookLine: raw.hookLine ? String(raw.hookLine).slice(0, 60) : undefined,
    };
  }
  return heuristicDistribution(captions, language, packId);
}
