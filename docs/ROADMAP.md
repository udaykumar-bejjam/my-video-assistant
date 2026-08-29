# CaptionStudio — Enhancement roadmap

Prioritized future work after Phases A–C (see [SHORTS_MAKER_PLAN.md](./SHORTS_MAKER_PLAN.md)).
Use technical scope (not calendar estimates). Longer backlog: [ENHANCEMENT_ROADMAP.md](./ENHANCEMENT_ROADMAP.md).
Merge wave: [MERGE_HISTORY.md](./MERGE_HISTORY.md).

---

## Product pillars (unchanged)

1. **Speed** — few taps from clip → post  
2. **Engagement** — hooks, punches, SFX, B-roll on the right words  
3. **Consistency** — brand, loudness, safe zones, resume projects  
4. **Distribution** — multi-aspect + copy + cover  

---

## Now / next (high leverage)

### P0 — Reliability & parity

| Item | Why | Touches | Status |
|------|-----|---------|--------|
| Aspect-aware overlay remap on batch 9:16↔16:9↔1:1 | Positions stay in chrome-safe zones | `AspectOverlayRemapper` | **Shipped** |
| App ↔ server enhance heuristic parity | Offline Swift fallback matches Node | `parity-contract.json` + `heuristicCore.js` + `HeuristicParity` | **Shipped** |
| Notarized / Developer ID macOS builds | Gatekeeper friction on Releases | CI signing secrets, `build-macos.sh` | Open |
| CI smoke: enhance full-duration + export dry path | Catch duration regressions | GitHub Actions, Node tests | **Shipped** (enhancer-smokes) |
| Keep Xcode membership in sync for new GIF/Swift files | Silent missing burn-in / compile gaps | `project.pbxproj` checklist | Open |

### P1 — Edit surface

| Item | Why | Touches | Status |
|------|-----|---------|--------|
| Zoomable / drag-to-retime timeline | Faster than sliders alone | `TimelineWorkspaceView`, `applyTimelineDrag` | **Shipped** |
| Undo stack for apply(plan) / trim / delete | Safe daily experimentation | `EditorHistory` | **Shipped** |
| Multi-select + snap guides | Precision edits | `TimelineSnap`, multi-retime | **Shipped** |
| Preview SFX while playhead crosses cues | WYSIWYG audio | `TimelineSFXPreview`, Audio layer toggle | **Shipped** |
| Hide or dim phrase captions under dense word hits | Reduce clutter | Export + preview flags | Open |

### P1b — Chess (next)

| Item | Why | Touches | Status |
|------|-----|---------|--------|
| Burn chess walkthrough into export | Ship analysis videos | `ChessExportService` | **Shipped** (standalone MP4) |
| Stockfish (or cloud) eval → categories | Real analysis beyond NAGs | `ChessEvalService` | **Shipped** (heuristic always; Stockfish if binary present) |
| Sync board clock to imported game VO | Coach commentary + board | Shared offset UI | Open |
| PGN from file / lichess / chess.com URL | Lower friction | `ChessPGNImportService` | **Shipped** |
| Chess board as overlay on project video | Composite with VO | `VideoExportService` + `ChessWalkthroughSpec` | **Shipped** |

### P1c — Editor history

| Item | Status |
|------|--------|
| Undo / redo for captions, overlays, enhance, timeline, trim | **Shipped** (`EditorHistory`, ⌘Z / ⇧⌘Z) |

### P0 — CI

| Item | Status |
|------|--------|
| Linux enhancer smokes on PR (`npm test` incl. full-duration + chess-eval) | **Shipped** (`.github/workflows/enhancer-smokes.yml`) |

### P2 — Audio v2

| Item | Why | Touches |
|------|-----|---------|
| True LUFS metering (replace peak-only) | Platform-safe loudness | `AudioNormalizeService` |
| Per-track EQ / compressor presets on Audio layer | Stronger enhancers story | Export audio taps |
| Music bed track (ducked under dialogue) | Beyond one-shot SFX | New cue type + mix |

### P3 — Trim & captions v2

| Item | Why | Touches | Status |
|------|-----|---------|--------|
| Telugu Whisper dual-pass | Apple has no te-IN | Whisper + gpt-transcribe | **Shipped** |
| Trim auto-apply + undo | Faster silence cleanup | `TrimService` | Open |
| Chunked Speech for long files | Avoid truncated transcripts | `TranscriptionService` | Open |
| Word-level split/merge editor | Fix ASR mistakes | Caption list UI | Open |
| Caption translation / bilingual burn-in | HI/TE growth | Models + export | Open |
| More Indic languages (same as Telugu path) | Market expand | Whisper client | Open |

### P4 — Libraries & AI Place

| Item | Why | Touches | Status |
|------|-----|---------|--------|
| Iconify sync tool | Richer sticker set | `tools/iconify-sync` | **Shipped** (expand presets next) |
| Square 1:1 batch export | IG feed | `AspectRatioPreset.square1x1` | **Shipped** |
| Enhancer returns `trimSuggestions` | Single AI pass for cuts | `enhance.js` | Open |
| Per-project brand kit snapshot | Freeze fonts/watermark with draft | `SavedProject` | Open |

---

## Explicit non-goals (still)

- Full multi-track NLE  
- Cloud render farm  
- Stock B-roll marketplace  
- AI avatar / eye-contact  
- Real-time collaborative editing  

---

## Suggested implementation order

```text
P1b sync chess overlay to VO clock + bundle Stockfish
P1.3 keyboard shortcuts (J/K/L, delete, nudge)
P2 LUFS / music bed
P3 trim v2 / long Speech / more Indic languages
P4 expand Iconify presets + enhance trim suggestions
P0 notarized Mac builds
```

Each item should ship with: docs touch (`FEATURES` / this roadmap), smoke test
where applicable, and a Releases rebuild when user-facing on macOS.

---

## Decision checkpoints

Ask before building:

1. Signing / notarization budget for Gatekeeper?  
2. LUFS required vs peak normalize enough?  
3. Square 1:1 in batch export now or later?  
4. Per-project brand kit vs keep global UserDefaults?  
5. Chess export burn-in before Stockfish, or Stockfish first?

---

## Related docs

- Architecture invariants: [ARCHITECTURE.md](./ARCHITECTURE.md)  
- Shipped baseline: [FEATURES.md](./FEATURES.md)  
- Original A–C plan status: [SHORTS_MAKER_PLAN.md](./SHORTS_MAKER_PLAN.md)  
- Longer backlog: [ENHANCEMENT_ROADMAP.md](./ENHANCEMENT_ROADMAP.md)  
- Merge wave: [MERGE_HISTORY.md](./MERGE_HISTORY.md)  
