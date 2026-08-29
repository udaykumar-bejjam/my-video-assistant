import assert from "node:assert/strict";
import {
  NUDGE_FINE,
  NUDGE_COARSE,
  nextRate,
  nudgeDelta,
} from "../src/editorShortcuts.js";

assert.ok(Math.abs(NUDGE_FINE - 1 / 30) < 1e-9);
assert.equal(NUDGE_COARSE, 1);
assert.equal(nudgeDelta(false), NUDGE_FINE);
assert.equal(nudgeDelta(true), NUDGE_COARSE);

assert.equal(nextRate(0, true), 1);
assert.equal(nextRate(1, true), 2);
assert.equal(nextRate(2, true), 4);
assert.equal(nextRate(4, true), 8);
assert.equal(nextRate(8, true), 8);
assert.equal(nextRate(-2, true), 1);

assert.equal(nextRate(0, false), -1);
assert.equal(nextRate(1, false), -1);
assert.equal(nextRate(-1, false), -2);
assert.equal(nextRate(-2, false), -4);
assert.equal(nextRate(-8, false), -8);

console.log("editor-shortcuts-smoke: ok");
