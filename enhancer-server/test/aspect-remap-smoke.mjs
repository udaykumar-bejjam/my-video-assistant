/**
 * Smoke: aspect remap 9:16 ↔ 16:9 ↔ 1:1 keeps points inside target safe zones.
 */
import {
  remapPoint,
  safeZoneForAspect,
  SQUARE_SAFE_ZONE,
  DEFAULT_SAFE_ZONE,
  LANDSCAPE_SAFE_ZONE,
} from "../src/safezone.js";

function assert(cond, msg) {
  if (!cond) {
    console.error("FAIL:", msg);
    process.exit(1);
  }
}

function inZone(p, z) {
  return p.x >= z.xMin - 1e-9 && p.x <= z.xMax + 1e-9 && p.y >= z.yMin - 1e-9 && p.y <= z.yMax + 1e-9;
}

const samples = [
  { x: 0.5, y: 0.28 },
  { x: 0.12, y: 0.15 },
  { x: 0.78, y: 0.72 },
  { x: 0.5, y: 0.5 },
];

const pairs = [
  ["9:16", "16:9"],
  ["9:16", "1:1"],
  ["16:9", "1:1"],
  ["1:1", "9:16"],
  ["16:9", "9:16"],
];

for (const [from, to] of pairs) {
  const dst = safeZoneForAspect(to);
  for (const s of samples) {
    const p = remapPoint(s.x, s.y, from, to);
    assert(inZone(p, dst), `${from}→${to} (${s.x},${s.y}) → (${p.x},${p.y}) outside ${JSON.stringify(dst)}`);
  }
}

// Identity
const id = remapPoint(0.4, 0.4, "9:16", "9:16");
assert(id.x === 0.4 && id.y === 0.4, "identity remap");

// Portrait mid maps near landscape mid-ish
const mid = remapPoint(0.5, 0.45, "9:16", "16:9");
assert(mid.y > LANDSCAPE_SAFE_ZONE.yMin && mid.y < LANDSCAPE_SAFE_ZONE.yMax, "landscape mid y");

assert(safeZoneForAspect("1:1").xMax === SQUARE_SAFE_ZONE.xMax, "square zone");
assert(safeZoneForAspect("9:16").yMax === DEFAULT_SAFE_ZONE.yMax, "portrait zone");

console.log("aspect-remap-smoke: ok");
