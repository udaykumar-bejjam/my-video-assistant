/**
 * Editor keyboard nudge / JKL rate helpers (parity with Swift EditorShortcuts).
 */
export const NUDGE_FINE = 1 / 30;
export const NUDGE_COARSE = 1;
export const RATE_LADDER = [1, 2, 4, 8];

export function nextRate(current, forward) {
  const ladder = RATE_LADDER;
  if (forward) {
    if (current <= 0) return ladder[0];
    const absCurrent = Math.abs(current);
    const i = ladder.findIndex((v) => Math.abs(v - absCurrent) < 0.01);
    if (i >= 0 && i + 1 < ladder.length) return ladder[i + 1];
    if (absCurrent < ladder[0]) return ladder[0];
    return ladder[ladder.length - 1];
  }
  if (current >= 0) return -ladder[0];
  const absCurrent = Math.abs(current);
  const i = ladder.findIndex((v) => Math.abs(v - absCurrent) < 0.01);
  if (i >= 0 && i + 1 < ladder.length) return -ladder[i + 1];
  if (absCurrent < ladder[0]) return -ladder[0];
  return -ladder[ladder.length - 1];
}

export function nudgeDelta(shift) {
  return shift ? NUDGE_COARSE : NUDGE_FINE;
}
