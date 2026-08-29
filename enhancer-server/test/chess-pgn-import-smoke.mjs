#!/usr/bin/env node
/**
 * Smoke-test chess PGN import URL resolution + chess.com archive matching (P1.9).
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  chessComArchiveUrl,
  fetchPgnForResolved,
  normalizeImportInput,
  pgnFromChessComArchive,
  resolveChessImport,
} from "../src/chessPgnImport.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixtures = path.join(__dirname, "fixtures");

let failures = 0;
function assert(cond, msg) {
  if (!cond) {
    failures += 1;
    console.log(`FAIL ${msg}`);
  } else {
    console.log(`PASS ${msg}`);
  }
}

assert(normalizeImportInput("  https://x  ") === "https://x", "normalize trims");

{
  const r = resolveChessImport("https://lichess.org/q7ZvsdUF");
  assert(r.kind === "lichess" && r.gameId === "q7ZvsdUF", "lichess bare id");
  assert(
    r.exportUrl.includes("/game/export/q7ZvsdUF"),
    "lichess export URL"
  );
}
{
  const r = resolveChessImport("https://lichess.org/game/export/q7ZvsdUF");
  assert(r.kind === "lichess" && r.gameId === "q7ZvsdUF", "lichess export path");
}
{
  const r = resolveChessImport("https://www.chess.com/game/live/169227053782");
  assert(r.kind === "chesscom" && r.format === "live", "chesscom live");
  assert(r.gameId === "169227053782", "chesscom id");
  assert(r.callbackUrl.includes("/callback/live/game/169227053782"), "callback URL");
}
{
  const r = resolveChessImport("chess.com/game/daily/42");
  assert(r.kind === "chesscom" && r.format === "daily" && r.gameId === "42", "daily + no scheme");
}
{
  const r = resolveChessImport("https://example.com/game.pgn");
  assert(r.kind === "pgnUrl" && r.exportUrl.includes("game.pgn"), "direct pgn url");
}
{
  const r = resolveChessImport("https://example.com/not-a-game");
  assert(r.kind === "unknown" && r.error, "unknown host errors");
}

const callback = JSON.parse(
  fs.readFileSync(path.join(fixtures, "chesscom-callback-sample.json"), "utf8")
);
const archiveUrl = chessComArchiveUrl(callback.game.pgnHeaders);
assert(
  archiveUrl === "https://api.chess.com/pub/player/leonliur/games/2026/05",
  `archive URL (got ${archiveUrl})`
);

const fakeArchive = {
  games: [
    { url: "https://www.chess.com/game/live/111", pgn: "[Event \"x\"]\n\n1. e4 *" },
    {
      url: "https://www.chess.com/game/live/169227053782",
      pgn: fs.readFileSync(path.join(fixtures, "chesscom-game.pgn"), "utf8"),
    },
  ],
};
const matched = pgnFromChessComArchive(fakeArchive, "169227053782");
assert(matched && matched.includes("[White \"LeonLiur\"]"), "archive match returns PGN");
assert(pgnFromChessComArchive(fakeArchive, "999") == null, "missing id → null");

// Live Lichess fetch (network)
try {
  const resolved = resolveChessImport("https://lichess.org/q7ZvsdUF");
  const { pgn, source } = await fetchPgnForResolved(resolved);
  assert(source === "lichess", "live lichess source tag");
  assert(pgn.includes("[Event ") && pgn.includes("1."), "live lichess PGN body");
  const fixture = fs.readFileSync(path.join(fixtures, "lichess-game.pgn"), "utf8");
  assert(fixture.includes("[White \"Lance5500\"]"), "lichess fixture on disk");
} catch (err) {
  assert(false, `live lichess fetch (${err.message})`);
}

// Live chess.com resolve → archive (network)
try {
  const resolved = resolveChessImport("https://www.chess.com/game/live/169227053782");
  const { pgn, source } = await fetchPgnForResolved(resolved);
  assert(source === "chesscom-archive" || source === "chesscom-callback-pgn", `chesscom source (${source})`);
  assert(pgn.includes("[White \"LeonLiur\"]") || pgn.includes("1."), "chesscom PGN usable");
} catch (err) {
  assert(false, `live chess.com fetch (${err.message})`);
}

if (failures) {
  console.error(`\nchess-pgn-import-smoke: ${failures} failure(s)`);
  process.exit(1);
}
console.log("\nchess-pgn-import-smoke: all passed");
