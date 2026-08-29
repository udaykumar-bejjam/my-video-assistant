/**
 * Smoke: chess VO clock fit-range + fixed pace.
 */
import {
  moveStartTimes,
  effectivePace,
  endTime,
  boardIndex,
} from "../src/chessVOClock.js";

function assert(cond, msg) {
  if (!cond) {
    console.error("FAIL:", msg);
    process.exit(1);
  }
}

const fixed = moveStartTimes({
  mode: "fixed",
  startOffset: 10,
  moveCount: 4,
  secondsPerMove: 1.5,
});
assert(fixed.length === 4, "fixed length");
assert(Math.abs(fixed[0] - 10) < 1e-9, "fixed[0]");
assert(Math.abs(fixed[3] - 14.5) < 1e-9, `fixed[3]=${fixed[3]}`);

const fit = moveStartTimes({
  mode: "fit",
  startOffset: 10,
  endOffset: 20,
  moveCount: 5,
  secondsPerMove: 1.35,
});
assert(fit.length === 5, "fit length");
assert(Math.abs(fit[0] - 10) < 1e-9, "fit start");
assert(Math.abs(fit[4] - 18) < 1e-9, `fit last start ${fit[4]}`); // pace=2 → 10,12,14,16,18
assert(Math.abs(effectivePace({ mode: "fit", startOffset: 10, endOffset: 20, moveCount: 5 }) - 2) < 1e-9, "fit pace");
assert(Math.abs(endTime({ mode: "fit", startOffset: 10, endOffset: 20, moveCount: 5 }) - 20) < 1e-9, "fit end");

assert(boardIndex({ time: 9.9, mode: "fit", startOffset: 10, endOffset: 20, moveCount: 5 }) === 0, "before start");
assert(boardIndex({ time: 10.0, mode: "fit", startOffset: 10, endOffset: 20, moveCount: 5 }) === 1, "first ply");
assert(boardIndex({ time: 14.0, mode: "fit", startOffset: 10, endOffset: 20, moveCount: 5 }) === 3, "mid");
assert(boardIndex({ time: 19.5, mode: "fit", startOffset: 10, endOffset: 20, moveCount: 5 }) === 5, "last");

console.log("chess-vo-clock-smoke: ok");
