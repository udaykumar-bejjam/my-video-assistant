/**
 * Chess PGN import helpers — URL resolution for Lichess / chess.com / raw .pgn.
 * Keep in sync with CaptionStudio/Services/ChessPGNImportService.swift
 */

export const CHESS_IMPORT_USER_AGENT =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 CaptionStudio/1.0";

/**
 * @typedef {'lichess'|'chesscom'|'pgnUrl'|'unknown'} ChessImportKind
 * @typedef {{
 *   kind: ChessImportKind,
 *   input: string,
 *   gameId?: string,
 *   format?: 'live'|'daily',
 *   exportUrl?: string,
 *   callbackUrl?: string,
 *   error?: string
 * }} ChessImportResolved
 */

/** Normalize pasted text that might be a URL or path-ish string. */
export function normalizeImportInput(raw) {
  return String(raw || "").trim().replace(/^<|>$/g, "");
}

/**
 * Resolve a user-pasted URL into fetch targets.
 * @param {string} raw
 * @returns {ChessImportResolved}
 */
export function resolveChessImport(raw) {
  const input = normalizeImportInput(raw);
  if (!input) {
    return { kind: "unknown", input, error: "Paste a Lichess, chess.com, or .pgn URL." };
  }

  let url;
  try {
    url = new URL(input.includes("://") ? input : `https://${input}`);
  } catch {
    return { kind: "unknown", input, error: "That doesn’t look like a valid URL." };
  }

  const host = url.hostname.replace(/^www\./, "").toLowerCase();
  const path = url.pathname;

  // Lichess — /abcdefghi or /game/export/abcdefghi
  if (host === "lichess.org" || host.endsWith(".lichess.org")) {
    let gameId = null;
    const exportMatch = path.match(/\/game\/export\/([a-zA-Z0-9]{8})/i);
    const bareMatch = path.match(/^\/([a-zA-Z0-9]{8})(?:\/|$)/);
    if (exportMatch) gameId = exportMatch[1];
    else if (bareMatch) gameId = bareMatch[1];
    if (!gameId) {
      return {
        kind: "lichess",
        input,
        error: "Couldn’t find a Lichess game id in that URL.",
      };
    }
    return {
      kind: "lichess",
      input,
      gameId,
      exportUrl: `https://lichess.org/game/export/${gameId}?clocks=false&evals=false&literate=1`,
    };
  }

  // chess.com — /game/live/ID or /game/daily/ID
  if (host === "chess.com" || host.endsWith(".chess.com")) {
    const m = path.match(/\/game\/(live|daily)\/(\d+)/i);
    if (!m) {
      return {
        kind: "chesscom",
        input,
        error: "Use a chess.com game URL like /game/live/123… or /game/daily/123…",
      };
    }
    const format = m[1].toLowerCase();
    const gameId = m[2];
    return {
      kind: "chesscom",
      input,
      gameId,
      format,
      callbackUrl: `https://www.chess.com/callback/${format}/game/${gameId}`,
    };
  }

  // Direct PGN link
  if (path.toLowerCase().endsWith(".pgn") || url.searchParams.has("pgn")) {
    return { kind: "pgnUrl", input, exportUrl: url.toString() };
  }

  return {
    kind: "unknown",
    input,
    error: "Supported: lichess.org/…, chess.com/game/live|daily/…, or a direct .pgn URL.",
  };
}

/** Build monthly archive URL from chess.com callback headers. */
export function chessComArchiveUrl(pgnHeaders = {}) {
  const white = String(pgnHeaders.White || "").trim();
  const date = String(pgnHeaders.Date || pgnHeaders.UTCDate || "").trim();
  // Date forms: YYYY.MM.DD or YYYY-MM-DD
  const m = date.match(/^(\d{4})[.\-/](\d{2})/);
  if (!white || !m) return null;
  const user = white.toLowerCase().replace(/\s+/g, "");
  return `https://api.chess.com/pub/player/${encodeURIComponent(user)}/games/${m[1]}/${m[2]}`;
}

/** Find PGN for a game id inside a chess.com monthly archive payload. */
export function pgnFromChessComArchive(archive, gameId) {
  const id = String(gameId);
  const games = Array.isArray(archive?.games) ? archive.games : [];
  for (const g of games) {
    const url = String(g?.url || "");
    if (url.includes(id) && typeof g.pgn === "string" && g.pgn.trim()) {
      return g.pgn.trim();
    }
  }
  return null;
}

/** Headers → minimal stub PGN (no moves) — useful for smoke tests. */
export function headersToStubPgn(headers = {}, result = "*") {
  const keys = ["Event", "Site", "Date", "Round", "White", "Black", "Result"];
  const lines = [];
  for (const k of keys) {
    const v = headers[k] ?? (k === "Result" ? result : "?");
    lines.push(`[${k} "${v}"]`);
  }
  lines.push("");
  lines.push(String(result));
  return lines.join("\n");
}

/**
 * Fetch PGN text for a resolved import (Node). Uses global fetch.
 * @param {ChessImportResolved} resolved
 * @param {{ fetchImpl?: typeof fetch, userAgent?: string }} [opts]
 */
export async function fetchPgnForResolved(resolved, opts = {}) {
  const fetchImpl = opts.fetchImpl || fetch;
  const ua = opts.userAgent || CHESS_IMPORT_USER_AGENT;
  if (resolved.error) throw new Error(resolved.error);

  if (resolved.kind === "lichess" || resolved.kind === "pgnUrl") {
    const res = await fetchImpl(resolved.exportUrl, {
      headers: { Accept: "application/x-chess-pgn, text/plain, */*", "User-Agent": ua },
    });
    if (!res.ok) throw new Error(`Download failed (${res.status})`);
    const text = (await res.text()).trim();
    if (!text.includes("[") && !/\d+\./.test(text)) {
      throw new Error("Downloaded text doesn’t look like PGN.");
    }
    return { pgn: text, source: resolved.kind };
  }

  if (resolved.kind === "chesscom") {
    const cbRes = await fetchImpl(resolved.callbackUrl, {
      headers: { Accept: "application/json", "User-Agent": ua },
    });
    if (!cbRes.ok) throw new Error(`chess.com callback failed (${cbRes.status})`);
    const body = await cbRes.json();
    if (body?.message && !body?.game) throw new Error(String(body.message));
    const game = body.game || {};
    if (typeof game.pgn === "string" && game.pgn.trim()) {
      return { pgn: game.pgn.trim(), source: "chesscom-callback-pgn" };
    }
    const headers = game.pgnHeaders || {};
    const archiveUrl = chessComArchiveUrl(headers);
    if (!archiveUrl) {
      throw new Error(
        "chess.com didn’t return PGN headers — paste the PGN or export from Share → Download."
      );
    }
    const arRes = await fetchImpl(archiveUrl, {
      headers: { Accept: "application/json", "User-Agent": ua },
    });
    if (!arRes.ok) throw new Error(`chess.com archive failed (${arRes.status})`);
    const archive = await arRes.json();
    const pgn = pgnFromChessComArchive(archive, resolved.gameId);
    if (!pgn) {
      throw new Error(
        "Couldn’t find that game in the monthly archive — paste PGN from chess.com Share → Download."
      );
    }
    return { pgn, source: "chesscom-archive" };
  }

  throw new Error(resolved.error || "Unsupported import source.");
}
