#!/usr/bin/env node
/** Pure logic checks mirroring TrimService keep/map behavior. */

function mergeOverlapping(items) {
  if (!items.length) return [];
  const sorted = [...items].sort((a, b) => a.startTime - b.startTime);
  const merged = [];
  let current = { ...sorted[0] };
  for (const next of sorted.slice(1)) {
    if (next.startTime <= current.endTime + 0.02) {
      current.endTime = Math.max(current.endTime, next.endTime);
    } else {
      merged.push(current);
      current = { ...next };
    }
  }
  merged.push(current);
  return merged;
}

function keepRanges(duration, cuts) {
  const merged = mergeOverlapping(cuts).sort((a, b) => a.startTime - b.startTime);
  const keeps = [];
  let cursor = 0;
  for (const cut of merged) {
    const start = Math.max(0, Math.min(duration, cut.startTime));
    const end = Math.max(start, Math.min(duration, cut.endTime));
    if (start > cursor + 0.001) keeps.push([cursor, start]);
    cursor = Math.max(cursor, end);
  }
  if (cursor < duration - 0.001) keeps.push([cursor, duration]);
  return keeps.filter(([a, b]) => b - a > 0.01);
}

function mapTime(time, keeps) {
  let offset = 0;
  for (const [start, end] of keeps) {
    if (time < start) return null;
    if (time <= end) return offset + (time - start);
    offset += end - start;
  }
  return null;
}

let fail = 0;
const duration = 10;
const cuts = [
  { startTime: 1, endTime: 2, reason: "silence" },
  { startTime: 4.5, endTime: 5.2, reason: "filler" },
];
const keeps = keepRanges(duration, cuts);
const expected = [
  [0, 1],
  [2, 4.5],
  [5.2, 10],
];
const keepsOk = JSON.stringify(keeps) === JSON.stringify(expected);
console.log(`${keepsOk ? "PASS" : "FAIL"} keepRanges`, keeps);
if (!keepsOk) fail++;

const mapped = mapTime(3, keeps);
const mapOk = Math.abs(mapped - 2) < 0.001; // 0-1 keep (1s) + 1s into second keep
console.log(`${mapOk ? "PASS" : "FAIL"} mapTime(3) -> ${mapped} (expect 2)`);
if (!mapOk) fail++;

const removed = mapTime(1.5, keeps);
console.log(`${removed === null ? "PASS" : "FAIL"} mapTime inside cut -> ${removed}`);
if (removed !== null) fail++;

const newDur = keeps.reduce((s, [a, b]) => s + (b - a), 0);
console.log(`${Math.abs(newDur - 8.3) < 0.001 ? "PASS" : "FAIL"} trimmed duration ${newDur}`);
if (Math.abs(newDur - 8.3) >= 0.001) fail++;

process.exit(fail ? 1 : 0);
