# Chess Walkthrough

Paste a **PGN** or move list → CaptionStudio animates the game step-by-step on a live board.

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

## How to open
- Home → **Chess Walkthrough**
- Or editor chrome → checkerboard button

## Notation tips
Mark moves with `!!` `!` `!?` `?!` `?` `??` or PGN NAGs `$1`–`$6`, plus `{comments}`.

Example:
```
1. e4 e5 2. Qh5?! Nc6 3. Bc4 Nf6?? 4. Qxf7#
```

## Code map
| File | Role |
|------|------|
| `CaptionStudio/Models/ChessAnalysis.swift` | Categories, colors, arrows, annotated moves |
| `CaptionStudio/Services/ChessEngine.swift` | Board + SAN + PGN parser |
| `CaptionStudio/Services/ChessEvalService.swift` | Heuristic + optional Stockfish enrich |
| `CaptionStudio/Services/ChessExportService.swift` | Standalone MP4 burn-in |
| `CaptionStudio/ViewModels/ChessWalkthroughViewModel.swift` | Snapshots, play/step, SFX, export |
| `CaptionStudio/Views/ChessWalkthroughView.swift` | Board UI |

## Limits
- Overlay onto an imported coach-video timeline is not wired yet (standalone chess MP4 only)
- Stockfish requires a local UCI binary; otherwise heuristic eval always runs
- Linux CI covers heuristic category mapping via `npm run test:chess-eval`
