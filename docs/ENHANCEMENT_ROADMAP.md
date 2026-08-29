# Enhancement roadmap

Prioritized plan for future agents. Prefer small vertical slices. Former in-flight Telugu / timeline / chess work is **on `master`** — see [IN_FLIGHT_BRANCHES.md](./IN_FLIGHT_BRANCHES.md). Compact list: [ROADMAP.md](./ROADMAP.md).

Legend: **P0** correctness · **P1** high leverage · **P2** strategic · **P3** explore

---

## P0 — Correctness & parity

| ID | Enhancement | Touch points |
|----|-------------|--------------|
| P0.1 | Sync app-local enhance heuristic with server heuristic | `CursorEnhancerClient` ↔ `libraries.js` |
| P0.2 | `/libraries` static vs JSON route hygiene | `server.js` |
| P0.3 | Wire `test:full-duration` into `package.json` + PR CI (Linux) | `package.json`, `.github/workflows` |
| P0.4 | ~~Land Telugu + timeline + chess~~ | **Done** — merged to `master` |
| P0.5 | Aspect-aware overlay Y remap on batch 9:16→16:9 | Export / packs |
| P0.6 | Notarized / Developer ID macOS builds | CI signing |

---

## P1 — Editor & timeline

| ID | Enhancement | Notes |
|----|-------------|-------|
| P1.1 | ~~Zoomable multi-lane drag workspace~~ | **Shipped** (`TimelineWorkspaceView`) |
| P1.2 | Undo / redo | `EditorViewModel` command stack |
| P1.3 | Multi-select + snap guides | Timeline |
| P1.4 | Trim remaps captions/overlays | Avoid silent desync |
| P1.5 | Keyboard shortcuts (J/K/L, nudge) | Mac |
| P1.6 | Audio waveform lane | Scrub accuracy |

---

## P1 — Captions & languages

| ID | Enhancement | Notes |
|----|-------------|-------|
| P1.7 | ~~Telugu + EN via OpenAI dual-pass~~ | **Shipped** — [TELUGU_ASR_PLAN.md](./TELUGU_ASR_PLAN.md) |
| P1.8 | Word-level split/merge editor | ASR fix-up |
| P1.9 | More Indic languages | Same pattern as Telugu |
| P1.10 | Optional whisper.cpp offline | Packaging cost |

---

## P1 — Enhance & libraries

| ID | Enhancement | Notes |
|----|-------------|-------|
| P1.11 | Brand kit fully honored on agent path | `enhance.js` |
| P1.12 | User-imported GIF/PNG/SFX | Sandbox folders |
| P1.13 | Placement density slider | UX |
| P1.14 | Lexicon files in AssetLibraries on master | Align with in-flight B-roll |

---

## P1 — Export & distribution

| ID | Enhancement | Notes |
|----|-------------|-------|
| P1.15 | True LUFS (not only peak) | `AudioNormalizeService` |
| P1.16 | 1:1 aspect | IG feed |
| P1.17 | Soft-sub track toggle | Accessibility |
| P1.18 | Cancel/progress for long stitch | UX |

---

## P2 — Chess & analysis overlays

| ID | Enhancement | Notes |
|----|-------------|-------|
| P2.1 | ~~PGN animated walkthrough~~ | **Shipped** — [CHESS_WALKTHROUGH.md](./CHESS_WALKTHROUGH.md) |
| P2.2 | Stockfish (or cloud) eval categories | Next chess step |
| P2.3 | Burn chess into video export | Main follow-on |
| P2.4 | Sync board to imported game VO | Shared clock |

---

## P2 — Architecture & quality

| ID | Enhancement | Notes |
|----|-------------|-------|
| P2.5 | Split `EditorViewModel` | Captions / Enhance / Export stores |
| P2.6 | Shared JSON schema fixtures (Zod + Codable) | Drift prevention |
| P2.7 | XCTest on Mac CI + Node smokes on Linux CI | Gates |
| P2.8 | Structured logging (request ids) | Support |

---

## P3 — Product expansion

Templates marketplace, auto-cut silence, TTS hooks, collaborative review, richer iOS timeline, non-Apple enhance JSON preview. Also see [SHORTS_MAKER_PLAN.md](./SHORTS_MAKER_PLAN.md).

---

## Suggested next slices

1. **P2.3** — burn Chess Walkthrough into video export (CALayer path).
2. **P1.2** — undo/redo for timeline + trim.
3. **P0.3** — Linux CI for enhancer full-duration smokes on every PR.
4. **P0.1** — single heuristic source of truth.
5. **P0.5 + P1.16** — aspect Y remap + 1:1 batch export.
6. **P2.2** — Stockfish categories once export exists.
7. **P1.15** — true LUFS + music bed (see ROADMAP).

## Definition of done

- Code + these docs updated.
- Verification: Node smokes and/or Mac GHA when Swift changes.
- No silent schema drift between `/enhance` and `EditorViewModel.apply(plan:)`.
