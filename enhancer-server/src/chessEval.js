/**
 * Chess move quality from material / hanging-piece deltas.
 * Mirrors CaptionStudio HeuristicChessEval category mapping for CI.
 */

export const PIECE_CP = {
  p: 100,
  n: 320,
  b: 330,
  r: 500,
  q: 900,
  k: 0,
};

/** @param {number} deltaCp change for the side that just moved (positive = gained) */
export function categoryFromDeltaCp(deltaCp, { gaveCheck = false, isCapture = false } = {}) {
  if (deltaCp <= -500) return "blunder";
  if (deltaCp <= -200) return "mistake";
  if (deltaCp <= -80) return "inaccuracy";
  if (deltaCp >= 500 && !isCapture) return "brilliant";
  if (deltaCp >= 300) return "great";
  if (deltaCp >= 120) return "good";
  if (gaveCheck) return "critical";
  if (deltaCp >= 40) return "interesting";
  return "normal";
}

/**
 * Prefer annotation categories; fill .normal with eval.
 * @param {{ category: string, deltaCp?: number, gaveCheck?: boolean, isCapture?: boolean }[]} moves
 */
export function enrichCategories(moves) {
  return moves.map((m) => {
    if (m.category && m.category !== "normal") {
      return { ...m, evalSource: "annotation" };
    }
    const category = categoryFromDeltaCp(m.deltaCp ?? 0, {
      gaveCheck: Boolean(m.gaveCheck),
      isCapture: Boolean(m.isCapture),
    });
    return { ...m, category, evalSource: "heuristic" };
  });
}
