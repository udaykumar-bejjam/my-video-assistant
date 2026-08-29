/**
 * Timeline snap helpers — keep in sync with CaptionStudio/Services/TimelineSnap.swift
 */
export const DEFAULT_SNAP_THRESHOLD_SECONDS = 0.08;

/**
 * Snap a moving interval [start, end] to the nearest anchor.
 * Prefers snapping the leading edge (start); if end is closer, shifts by the same delta.
 * @returns {{ start: number, end: number, guide: number|null, snapped: boolean }}
 */
export function snapInterval(start, end, anchors = [], threshold = DEFAULT_SNAP_THRESHOLD_SECONDS) {
  const length = Math.max(0.05, Number(end) - Number(start));
  let s = Number(start);
  let best = null;
  let bestDist = Infinity;

  for (const raw of anchors) {
    const a = Number(raw);
    if (!Number.isFinite(a)) continue;
    const dStart = Math.abs(s - a);
    if (dStart < bestDist) {
      bestDist = dStart;
      best = { guide: a, via: "start" };
    }
    const e = s + length;
    const dEnd = Math.abs(e - a);
    if (dEnd < bestDist) {
      bestDist = dEnd;
      best = { guide: a, via: "end" };
    }
  }

  if (!best || bestDist > threshold + 1e-9) {
    return { start: s, end: s + length, guide: null, snapped: false };
  }

  if (best.via === "start") {
    s = best.guide;
  } else {
    s = best.guide - length;
  }
  return {
    start: s,
    end: s + length,
    guide: best.guide,
    snapped: true,
  };
}

/** Collect snap anchors from clip edges + playhead + media bounds. */
export function collectSnapAnchors({
  clips = [],
  excludeIds = new Set(),
  playhead = null,
  mediaDuration = null,
  includeZero = true,
} = {}) {
  const anchors = [];
  if (includeZero) anchors.push(0);
  if (Number.isFinite(playhead)) anchors.push(Number(playhead));
  if (Number.isFinite(mediaDuration) && mediaDuration > 0) {
    anchors.push(Number(mediaDuration));
  }
  for (const c of clips) {
    const id = c?.id;
    if (id != null && excludeIds.has(id)) continue;
    if (Number.isFinite(c?.start)) anchors.push(Number(c.start));
    if (Number.isFinite(c?.end)) anchors.push(Number(c.end));
  }
  return anchors;
}

/** Pixel-aware threshold: at least `minSeconds`, or `pixelSlop / pps`. */
export function snapThresholdSeconds(pixelsPerSecond, pixelSlop = 8, minSeconds = 0.04) {
  const pps = Math.max(Number(pixelsPerSecond) || 0, 0.001);
  return Math.max(minSeconds, pixelSlop / pps);
}
