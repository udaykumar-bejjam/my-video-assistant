# Enhancement roadmap (agent companion)

Companion to [ROADMAP.md](./ROADMAP.md). Prefer that file for product prioritization.

Legend: **P0** correctness · **P1** high leverage · **P2** strategic · **P3** explore

---

## Shipped (do not re-implement)

- Telugu + EN dual-pass ASR (`WhisperTranscriptionClient`)
- Zoomable cross-lane timeline (`TimelineWorkspaceView`)
- Timeline **multi-select + snap guides** (`TimelineSnap`, Multi toggle / Shift·⌘)
- **Preview SFX on play** with dialogue duck (`TimelineSFXPreview`, Audio layer toggle)
- Chess Walkthrough (interactive)
- Chess **PGN import** from file / Lichess / chess.com (`ChessPGNImportService`)
- Chess **MP4 export** (`ChessExportService`)
- Chess **project video overlay** (`ChessWalkthroughSpec` + export/preview)
- Heuristic + optional **Stockfish** eval (`ChessEvalService`)
- Editor **undo/redo** (`EditorHistory`, ⌘Z / ⇧⌘Z)
- Linux **enhancer smokes CI** (`.github/workflows/enhancer-smokes.yml` + `npm test`)
- **1:1 square** canvas + **AspectOverlayRemapper** (9:16 / 16:9 / 1:1 batch)
- **App ↔ server enhance heuristic parity** (`AssetLibraries/heuristic/parity-contract.json`, `heuristicCore.js`, `HeuristicParity.swift`)
- Iconify PNG sync tool
- Documentation suites

---

## P0 — Correctness & parity

| ID | Enhancement | Touch points |
|----|-------------|--------------|
| ~~P0.1~~ | ~~Sync app-local enhance heuristic with server heuristic~~ | **Shipped** — shared parity-contract v1 |
| P0.2 | `/libraries` static vs JSON route hygiene | `server.js` |
| P0.4 | ~~Aspect-aware overlay remap on batch 9:16→16:9→1:1~~ | **Shipped** (`AspectOverlayRemapper`) |
| P0.5 | Notarized / Developer ID macOS builds | CI secrets, `build-macos.sh` |

---

## P1 — Editor

| ID | Enhancement |
|----|-------------|
| ~~P1.2~~ | ~~Multi-select + snap guides~~ | **Shipped** |
| P1.3 | Keyboard shortcuts (J/K/L, delete, nudge) beyond undo |
| P1.4 | Waveform on audio lane |
| P1.5 | Word-level caption split/merge editor |

---

## P1 — Chess follow-ons

| ID | Enhancement |
|----|-------------|
| P1.7 | Bundle Stockfish binary in app for guaranteed UCI |
| P1.8 | Sync chess to imported game video clock (multi-offset UI) |
| ~~P1.9~~ | ~~PGN from file / lichess / chess.com URL~~ | **Shipped** |

---

## P1 — Captions / enhance / export

| ID | Enhancement |
|----|-------------|
| P1.10 | More Indic languages (same dual-pass pattern) |
| P1.11 | Brand kit fully honored on server agent path |
| P1.12 | User-imported GIF/PNG/SFX folders |
| P1.13 | Placement density slider |
| P1.14 | True LUFS loudness |
| P1.15 | ~~1:1 aspect preset~~ | **Shipped** (1080×1080 + batch) |
| P1.16 | Soft-sub track toggle |

---

## P2 — Architecture

| ID | Enhancement |
|----|-------------|
| P2.1 | Split `EditorViewModel` into focused stores |
| P2.2 | Shared JSON schema fixtures (Zod + Codable) |
| P2.3 | XCTest on Mac CI |

---

## Suggested next slices

1. **P1.14** — true LUFS loudness.
2. **P1.8** — sync chess overlay to game video clock.
3. **P1.3** — more keyboard shortcuts (J/K/L, delete, nudge).
4. **P0.5** — notarized Mac builds.
5. **P1.7** — bundle Stockfish binary.
