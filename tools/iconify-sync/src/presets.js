/**
 * Mood → Iconify search queries + CaptionStudio B-roll tags.
 * Prefer collections with permissive licenses (MIT / Apache-2.0).
 */
export const PREFERRED_PREFIXES = [
  "mdi",
  "lucide",
  "ri",
  "boxicons",
  "tabler",
  "ph", // phosphor
  "mingcute",
];

/** Default color for overlays on dark video (bright yellow). */
export const DEFAULT_COLOR = "#FFEF5A";

export const MOOD_PRESETS = {
  power: {
    queries: ["fire", "bolt", "flash", "rocket", "flame"],
    tags: ["power", "impact", "hype", "energy", "hot"],
    limit: 2,
  },
  reveal: {
    queries: ["eye", "sparkles", "star", "magic", "lightbulb"],
    tags: ["reveal", "focus", "highlight", "new", "premium"],
    limit: 2,
  },
  emotion: {
    queries: ["heart", "emoji", "smile", "hand-heart"],
    tags: ["love", "emotional", "celebration", "cheer", "like"],
    limit: 2,
  },
  numbers: {
    queries: ["hash", "chart", "trophy", "medal", "target"],
    tags: ["point", "highlight", "focus", "ui", "label"],
    limit: 2,
  },
  cta: {
    queries: ["arrow-right", "hand-point", "click", "share", "bell"],
    tags: ["cta", "direction", "point", "product", "premium"],
    limit: 2,
  },
};

export function preferIcon(iconIds = []) {
  const ranked = [...iconIds].sort((a, b) => {
    const pa = a.split(":")[0];
    const pb = b.split(":")[0];
    const ia = PREFERRED_PREFIXES.indexOf(pa);
    const ib = PREFERRED_PREFIXES.indexOf(pb);
    const sa = ia === -1 ? 99 : ia;
    const sb = ib === -1 ? 99 : ib;
    return sa - sb;
  });
  return ranked[0] || null;
}
