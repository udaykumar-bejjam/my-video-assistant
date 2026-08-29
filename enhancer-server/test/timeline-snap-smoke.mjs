#!/usr/bin/env node
/**
 * Smoke-test timeline snap / multi-retime helpers (P1.2).
 * Mirrors CaptionStudio TimelineSnap.swift.
 */
import {
  collectSnapAnchors,
  snapInterval,
  snapThresholdSeconds,
} from "../src/timelineSnap.js";

let failures = 0;
function assert(cond, msg) {
  if (!cond) {
    failures += 1;
    console.log(`FAIL ${msg}`);
  } else {
    console.log(`PASS ${msg}`);
  }
}

const near = (a, b, eps = 1e-6) => Math.abs(a - b) < eps;

// Snap start to playhead
{
  const r = snapInterval(1.97, 2.97, [0, 2.0, 8], 0.08);
  assert(r.snapped, "snaps near playhead");
  assert(near(r.start, 2.0), `start→2 (got ${r.start})`);
  assert(near(r.end, 3.0), `end keeps length (got ${r.end})`);
  assert(r.guide === 2.0, "guide at playhead");
}

// Snap end to clip edge
{
  const r = snapInterval(0.92, 1.92, [2.0], 0.08);
  assert(r.snapped, "snaps end to 2.0");
  assert(near(r.end, 2.0), `end→2 (got ${r.end})`);
  assert(near(r.start, 1.0), `start = end-len (got ${r.start})`);
  assert(r.guide === 2.0, "guide at end anchor");
}

// Outside threshold — no snap
{
  const r = snapInterval(1.0, 2.0, [3.0], 0.08);
  assert(!r.snapped, "no snap when far");
  assert(r.guide == null, "no guide when unsnapped");
  assert(near(r.start, 1.0) && near(r.end, 2.0), "unchanged when far");
}

// collectSnapAnchors excludes moving clips
{
  const anchors = collectSnapAnchors({
    clips: [
      { id: "a", start: 1, end: 2 },
      { id: "b", start: 3, end: 4 },
    ],
    excludeIds: new Set(["a"]),
    playhead: 1.5,
    mediaDuration: 10,
  });
  assert(anchors.includes(0), "includes zero");
  assert(anchors.includes(1.5), "includes playhead");
  assert(anchors.includes(10), "includes media end");
  assert(anchors.includes(3) && anchors.includes(4), "includes other clip edges");
  assert(!anchors.includes(1) && !anchors.includes(2), "excludes moving clip edges");
}

// Pixel threshold grows when zoomed out
{
  const tight = snapThresholdSeconds(200, 8, 0.04);
  const loose = snapThresholdSeconds(20, 8, 0.04);
  assert(tight === 0.04, `zoomed-in uses min (got ${tight})`);
  assert(near(loose, 0.4), `zoomed-out uses pixel slop (got ${loose})`);
}

// Multi-retime: same delta applied to a set (documented contract for Swift)
{
  const clips = [
    { id: "1", start: 1, end: 2 },
    { id: "2", start: 3, end: 3.5 },
  ];
  const delta = 0.25;
  const moved = clips.map((c) => ({
    ...c,
    start: c.start + delta,
    end: c.end + delta,
  }));
  assert(near(moved[0].start, 1.25) && near(moved[1].start, 3.25), "multi-retime shares delta");
  assert(
    near(moved[0].end - moved[0].start, 1) && near(moved[1].end - moved[1].start, 0.5),
    "multi-retime preserves lengths"
  );
}

if (failures) {
  console.error(`\ntimeline-snap-smoke: ${failures} failure(s)`);
  process.exit(1);
}
console.log("\ntimeline-snap-smoke: all passed");
