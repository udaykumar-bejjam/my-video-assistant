# Chess Walkthrough

**Status:** Shipped on `master` (interactive + standalone MP4 export + heuristic/Stockfish eval + file/URL import + VO clock sync).

Paste a **PGN** or move list, **open a `.pgn` file**, or paste a **Lichess / chess.com game URL** → CaptionStudio animates the game step-by-step on a live board.

## What it does
- Plays each move with piece animation on a chessboard (Unicode pieces — not PNG stickers)
- Colors moves by category:
  - **Green** — Brilliant / Good
  - **Blue** — Book
  - **Yellow** — Interesting / Inaccuracy
  - **Orange** — Mistake / Critical
  - **Red** — Blunder (+ check arrows)
- Draws **arrows** for the played move and check ideas
- **Boxes** critical squares (from / to / checked king)
- Overlay **callout text** with the category label (+ eval Δcp when available)
- **SFX** per category (`click`, `ding`, `cheer-hit`, `whoosh`, `bass-hit`, `riser`)
- **Eval**: PGN annotations / NAGs win; otherwise **heuristic** material+hanging eval fills categories. If a `stockfish` binary is on PATH (or bundled), UCI Stockfish is preferred.
- **Export MP4**: toolbar **Export MP4** burns the walkthrough (board frames + callouts + category SFX) via `ChessExportService`
- **Import**: **File** picker for `.pgn`, or **Fetch** a `lichess.org/…` / `chess.com/game/live|daily/…` URL (`ChessPGNImportService`)
- **VO / video clock**: mark start (and optional end) on the project timeline; **Fixed pace** or **Fit to range** spaces ply times for overlay keyframes + SFX

## How to open
- Home → **Chess Walkthrough**
- Or editor chrome → checkerboard button

## Notation tips
Mark moves with `!!` `!` `!?` `?!` `?` `??` or PGN NAGs `$1`–`$6`, plus `{comments}`.

Example:
```
1. e4 e5 2. Qh5?! Nc6 3. Bc4 Nf6?? 4. Qxf7#
```

URL examples:
- `https://lichess.org/q7ZvsdUF`
- `https://www.chess.com/game/live/169227053782`

## Attach to project video (VO sync)
1. Open a video in the editor
2. Chess Walkthrough → Analyze
3. Optionally open **VO / video clock**: scrub to the spoken/game start → **Mark start**; scrub to the end of the VO range → **Mark end**
4. Choose **Fixed pace** (`secondsPerMove`) or **Fit to range** (even ply spacing across start→end)
5. **Attach to video** pins the animated board + eval + SFX using those offsets
6. **Retarget clock** rebuilds keyframes + SFX without re-analyzing
7. Preview shows a corner board; **Export** burns it into the MP4
8. **Clear** removes the overlay + chess-tagged SFX

| Control | Role |
|---------|------|
| Attach to video | Writes `ProjectOverlayItem` + `ProjectAudioItem` SFX using VO start/end + timing mode |
| Mark start / Mark end | Capture project playhead as VO sync anchors |
| Retarget clock | Rebuild overlay keyframes + SFX without re-analyzing |
| Timing mode | **Fixed pace** or **Fit to range** |

## Code map
| File | Role |
|------|------|
| `CaptionStudio/Models/ChessAnalysis.swift` | Categories, colors, arrows, annotated moves, `ChessWalkthroughSpec` |
| `CaptionStudio/Services/ChessVOClock.swift` | Fixed pace / fit-to-range ply start times |
| `CaptionStudio/Services/ChessEngine.swift` | Board + SAN + PGN parser |
| `CaptionStudio/Services/ChessPGNImportService.swift` | File / Lichess / chess.com URL → PGN |
| `CaptionStudio/Services/ChessEvalService.swift` | Heuristic + optional Stockfish enrich |
| `CaptionStudio/Services/ChessExportService.swift` | Standalone MP4 burn-in |
| `CaptionStudio/Services/ChessOverlayRenderer.swift` | Board + last-move + eval bar for project overlay |
| `CaptionStudio/ViewModels/ChessWalkthroughViewModel.swift` | Snapshots, play/step, SFX, export, import, VO marks |
| `CaptionStudio/Views/ChessWalkthroughView.swift` | Board UI + VO sync panel |
| `enhancer-server/src/chessVOClock.js` | Parity helper for CI smoke |

## Limits
- Stockfish requires a local UCI binary; otherwise heuristic eval always runs
- chess.com import uses the public callback + monthly archive (needs network); if that fails, paste PGN from Share → Download
- Linux CI covers heuristic category mapping via `npm run test:chess-eval`, URL resolve via `npm run test:chess-pgn-import`, and VO clock math via `npm run test:chess-vo-clock`
