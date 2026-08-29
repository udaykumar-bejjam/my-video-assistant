/**
 * Chess VO / video clock helpers (mirrors Swift ChessVOClock).
 */

export function moveStartTimes({
  mode = "fixed",
  startOffset = 0,
  endOffset = null,
  moveCount = 0,
  secondsPerMove = 1.35,
}) {
  const n = Math.max(0, moveCount | 0);
  if (n === 0) return [];
  const start = Math.max(0, startOffset);
  if (mode === "fit") {
    const end = Math.max(
      start + n * 0.05,
      endOffset == null ? start + n * Math.max(0.05, secondsPerMove) : endOffset
    );
    const span = Math.max(0.05 * n, end - start);
    const pace = span / n;
    return Array.from({ length: n }, (_, i) => start + i * pace);
  }
  const pace = Math.max(0.05, secondsPerMove);
  return Array.from({ length: n }, (_, i) => start + i * pace);
}

export function effectivePace(args) {
  const n = Math.max(1, args.moveCount | 0);
  if (args.mode === "fit") {
    const start = Math.max(0, args.startOffset ?? 0);
    const end = Math.max(
      start + n * 0.05,
      args.endOffset == null
        ? start + n * Math.max(0.05, args.secondsPerMove ?? 1.35)
        : args.endOffset
    );
    return Math.max(0.05, (end - start) / n);
  }
  return Math.max(0.05, args.secondsPerMove ?? 1.35);
}

export function endTime(args) {
  const n = Math.max(0, args.moveCount | 0);
  if (n === 0) return Math.max(0, args.startOffset ?? 0);
  const starts = moveStartTimes(args);
  const pace = effectivePace(args);
  return (starts[starts.length - 1] ?? args.startOffset ?? 0) + pace;
}

export function boardIndex({ time, ...args }) {
  const n = Math.max(0, args.moveCount | 0);
  if (n === 0) return 0;
  const starts = moveStartTimes(args);
  if (time < starts[0]) return 0;
  let idx = 0;
  for (let i = 0; i < n; i++) {
    if (starts[i] <= time) idx = i + 1;
  }
  return Math.min(n, idx);
}
