> **Status:** Design + implementation live on `cursor/chess-analysis-overlays-ac05` — see [IN_FLIGHT_BRANCHES.md](./IN_FLIGHT_BRANCHES.md). Not all referenced Swift files exist on `master` yet.

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
- Overlay **callout text** with the category label
- **SFX** per category (`click`, `ding`, `cheer-hit`, `whoosh`, `bass-hit`, `riser`)

## How to open
- Home → **Chess Walkthrough**
- Or editor chrome → checkerboard button

## Notation tips
Mark moves with `!!` `!` `!?` `?!` `?` `??` or PGN NAGs `$1`–`$6`, plus `{comments}`.

Example:
```
1. e4 e5 2. Qh5?! Nc6 3. Bc4 Nf6?? 4. Qxf7#
```

## Limits (v1)
- Classification uses annotations / checks (no Stockfish engine yet)
- Walkthrough is an interactive player (not yet burned into video export)
