/**
 * Smoke: playhead SFX crossing + dialogue duck math.
 */
import {
  cuesToTrigger,
  dialogueVolume,
  extendDuck,
  PLAYBACK_LOOKBACK,
} from "../src/timelineSfxPreview.js";

function assert(cond, msg) {
  if (!cond) {
    console.error("FAIL:", msg);
    process.exit(1);
  }
}

const a = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const b = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const c = "cccccccc-cccc-cccc-cccc-cccccccccccc";

const cues = [
  { id: a, startTime: 1.0, isMuted: false },
  { id: b, startTime: 2.5, isMuted: true },
  { id: c, startTime: 3.0, isMuted: false },
];

// Cross one cue
let fired = cuesToTrigger({ cues, from: 0.9, to: 1.05, alreadyTriggered: new Set() });
assert(fired.length === 1 && fired[0] === a, `cross a got ${fired}`);

// Already triggered → skip
fired = cuesToTrigger({ cues, from: 0.9, to: 1.05, alreadyTriggered: new Set([a]) });
assert(fired.length === 0, "skip already triggered");

// Muted skipped; later cue fires
fired = cuesToTrigger({ cues, from: 2.4, to: 3.1, alreadyTriggered: new Set([a]) });
assert(fired.length === 1 && fired[0] === c, `cross c got ${fired}`);

// Scrub back resets blocked to past cues only — future can fire again
fired = cuesToTrigger({
  cues,
  from: 3.5,
  to: 0.5,
  alreadyTriggered: new Set([a, c]),
});
assert(fired.length === 0, "scrub back to before all cues fires none");
fired = cuesToTrigger({
  cues,
  from: 0.5,
  to: 1.1,
  alreadyTriggered: new Set(), // after scrub handler resets
});
assert(fired[0] === a, "after scrub, a fires again");

// Duck volume
assert(
  Math.abs(dialogueVolume({ baseGain: 1, duckEnabled: true, duckAmount: 0.5, now: 1, duckUntil: 2 }) - 0.5) < 1e-6,
  "duck 50%"
);
assert(
  dialogueVolume({ baseGain: 1, duckEnabled: true, duckAmount: 0.5, now: 2.1, duckUntil: 2 }) === 1,
  "duck expired"
);
assert(
  dialogueVolume({ baseGain: 1, duckEnabled: false, duckAmount: 0.5, now: 1, duckUntil: 2 }) === 1,
  "duck off"
);

const until = extendDuck({ currentUntil: null, fireTime: 1, cueLength: 0.4 });
assert(until === 1.4, `extendDuck ${until}`);
assert(extendDuck({ currentUntil: 1.5, fireTime: 1, cueLength: 0.2 }) === 1.5, "keep longer duck");

assert(PLAYBACK_LOOKBACK === 0.08, "lookback");

console.log("timeline-sfx-preview-smoke: ok");
