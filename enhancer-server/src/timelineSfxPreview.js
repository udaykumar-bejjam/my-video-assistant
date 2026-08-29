/**
 * Pure playhead-crossing SFX helpers (mirrors Swift TimelineSFXPreview).
 */

export const PLAYBACK_LOOKBACK = 0.08;

export function cuesToTrigger({
  cues,
  from,
  to,
  alreadyTriggered = new Set(),
  landOnEpsilon = 0.05,
}) {
  const scrubbedBack = to < from - 0.02;
  let blocked = new Set(alreadyTriggered);
  if (scrubbedBack) {
    blocked = new Set(cues.filter((c) => c.startTime <= to + 0.001).map((c) => c.id));
  }

  const fired = [];
  for (const cue of cues) {
    if (cue.isMuted) continue;
    if (blocked.has(cue.id)) continue;
    const crossed = cue.startTime > from && cue.startTime <= to + 0.001;
    const landedOn = from < 0 && Math.abs(cue.startTime - to) <= landOnEpsilon;
    if (crossed || landedOn) {
      fired.push(cue.id);
      blocked.add(cue.id);
    }
  }
  return fired;
}

export function dialogueVolume({ baseGain, duckEnabled, duckAmount, now, duckUntil }) {
  const base = Math.min(2.0, Math.max(0.05, baseGain));
  if (!duckEnabled || duckUntil == null || now >= duckUntil) return base;
  const amount = Math.min(0.85, Math.max(0, duckAmount));
  return Math.max(0.05, base * (1 - amount));
}

export function extendDuck({ currentUntil, fireTime, cueLength }) {
  const end = fireTime + Math.max(0.05, cueLength);
  if (currentUntil == null) return end;
  return Math.max(currentUntil, end);
}
