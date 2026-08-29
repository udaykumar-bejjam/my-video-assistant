# Chess Walkthrough

**Status:** Shipped on `master` (interactive + standalone MP4 export + heuristic/Stockfish eval + file/URL import).

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

## Code map
| File | Role |
|------|------|
| `CaptionStudio/Models/ChessAnalysis.swift` | Categories, colors, arrows, annotated moves |
| `CaptionStudio/Services/ChessEngine.swift` | Board + SAN + PGN parser |
| `CaptionStudio/Services/ChessPGNImportService.swift` | File / Lichess / chess.com URL → PGN |
| `CaptionStudio/Services/ChessEvalService.swift` | Heuristic + optional Stockfish enrich |
| `CaptionStudio/Services/ChessExportService.swift` | Standalone MP4 burn-in |
| `CaptionStudio/ViewModels/ChessWalkthroughViewModel.swift` | Snapshots, play/step, SFX, export, import |
| `CaptionStudio/Views/ChessWalkthroughView.swift` | Board UI |

## Limits
- Sync board clock to an arbitrary VO still uses playhead `startOffset` (attach at current time)
- Stockfish requires a local UCI binary; otherwise heuristic eval always runs
- chess.com import uses the public callback + monthly archive (needs network); if that fails, paste PGN from Share → Download
- Linux CI covers heuristic category mapping via `npm run test:chess-eval` and URL resolve via `npm run test:chess-pgn-import`

## Attach to project video
1. Open a video in the editor
2. Chess Walkthrough → Analyze
3. Scrub to the moment the board should start → **Attach to video**
4. Preview shows a corner board; **Export** burns it into the MP4 (plus chess SFX cues on the timeline)
5. **Clear** removes the overlay + chess-tagged SFX
