# Enhancement roadmap

Prioritized plan for future agents. Prefer small vertical slices. Check [IN_FLIGHT_BRANCHES.md](./IN_FLIGHT_BRANCHES.md) before starting — several items may already exist on open branches.

Legend: **P0** correctness · **P1** high leverage · **P2** strategic · **P3** explore

---

## P0 — Correctness & parity

| ID | Enhancement | Touch points |
|----|-------------|--------------|
| P0.1 | Sync app-local enhance heuristic with server heuristic | `CursorEnhancerClient` ↔ `libraries.js` |
| P0.2 | `/libraries` static vs JSON route hygiene | `server.js` |
| P0.3 | Wire `test:full-duration` into `package.json` + PR CI (Linux) | `package.json`, `.github/workflows` |
| P0.4 | Land / rebase in-flight Telugu + timeline + chess docs with code | Merge strategy for feature PRs |

---

## P1 — Editor & timeline

| ID | Enhancement | Notes |
|----|-------------|-------|
| P1.1 | Zoomable multi-lane drag workspace | **In flight** on feature branch |
| P1.2 | Undo / redo | `EditorViewModel` command stack |
| P1.3 | Multi-select + snap guides | Timeline |
| P1.4 | Trim remaps captions/overlays | Avoid silent desync |
| P1.5 | Keyboard shortcuts (J/K/L, nudge) | Mac |
| P1.6 | Audio waveform lane | Scrub accuracy |

---

## P1 — Captions & languages

| ID | Enhancement | Notes |
|----|-------------|-------|
| P1.7 | Telugu + EN via OpenAI dual-pass | **In flight** — see Telugu plan on feature branch |
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
| P2.1 | PGN animated walkthrough | **In flight** |
| P2.2 | Stockfish (or cloud) eval categories | After walkthrough lands |
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

1. **Merge or rebase in-flight PRs** (Telugu/timeline/chess) rather than re-implementing.
2. **P0.3** — Linux CI for enhancer smokes on every PR.
3. **P0.1** — single heuristic source of truth.
4. After chess lands: **P2.3** export burn-in vertical slice.
5. **P1.4** trim remaps captions.

## Definition of done

- Code + these docs updated.
- Verification: Node smokes and/or Mac GHA when Swift changes.
- No silent schema drift between `/enhance` and `EditorViewModel.apply(plan:)`.
