# Enhancement roadmap (agent companion)

Companion to [ROADMAP.md](./ROADMAP.md). Prefer that file for product prioritization; use this for agent-oriented slices after the big merge ([MERGE_HISTORY.md](./MERGE_HISTORY.md)).

Legend: **P0** correctness · **P1** high leverage · **P2** strategic · **P3** explore

---

## Shipped (do not re-implement)

- Telugu + EN dual-pass ASR (`WhisperTranscriptionClient`)
- Zoomable cross-lane timeline (`TimelineWorkspaceView`)
- Chess Walkthrough (interactive)
- Iconify PNG sync tool
- Documentation suites

---

## P0 — Correctness & parity

| ID | Enhancement | Touch points |
|----|-------------|--------------|
| P0.1 | Sync app-local enhance heuristic with server heuristic | `CursorEnhancerClient` ↔ `libraries.js` |
| P0.2 | `/libraries` static vs JSON route hygiene | `server.js` |
| P0.3 | Wire `test:full-duration` into `package.json` + Linux PR CI | `package.json`, `.github/workflows` |
| P0.4 | Aspect-aware overlay remap on batch 9:16→16:9 | `EditorViewModel` |
| P0.5 | Notarized / Developer ID macOS builds | CI secrets, `build-macos.sh` |

---

## P1 — Editor

| ID | Enhancement |
|----|-------------|
| P1.1 | Undo / redo for timeline + captions |
| P1.2 | Multi-select + snap guides |
| P1.3 | Keyboard shortcuts (J/K/L, delete, nudge) |
| P1.4 | Waveform on audio lane |
| P1.5 | Word-level caption split/merge editor |

---

## P1 — Chess & export

| ID | Enhancement |
|----|-------------|
| P1.6 | **Burn chess into video export** (highest chess follow-on) |
| P1.7 | Stockfish / cloud eval categories |
| P1.8 | Sync chess to imported game video clock |

---

## P1 — Captions / enhance / export

| ID | Enhancement |
|----|-------------|
| P1.9 | More Indic languages (same dual-pass pattern) |
| P1.10 | Brand kit fully honored on server agent path |
| P1.11 | User-imported GIF/PNG/SFX folders |
| P1.12 | Placement density slider |
| P1.13 | True LUFS loudness |
| P1.14 | 1:1 aspect preset |
| P1.15 | Soft-sub track toggle |

---

## P2 — Architecture

| ID | Enhancement |
|----|-------------|
| P2.1 | Split `EditorViewModel` into focused stores |
| P2.2 | Shared JSON schema fixtures (Zod + Codable) |
| P2.3 | XCTest on Mac CI |

---

## Suggested next slices

1. **P0.3** — Linux CI for enhancer smokes on every PR.
2. **P1.6** — Chess export burn-in vertical slice (silent board animation first).
3. **P1.1** — Undo stack.
4. **P0.1** — Single heuristic source of truth.
5. **P1.7** — Stockfish once export path exists.
