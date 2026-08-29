# CaptionStudio — Enhancement roadmap

Prioritized future work after Phases A–C (see [SHORTS_MAKER_PLAN.md](./SHORTS_MAKER_PLAN.md)).
Use technical scope (not calendar estimates).

---

## Product pillars (unchanged)

1. **Speed** — few taps from clip → post  
2. **Engagement** — hooks, punches, SFX, B-roll on the right words  
3. **Consistency** — brand, loudness, safe zones, resume projects  
4. **Distribution** — multi-aspect + copy + cover  

---

## Now / next (high leverage)

### P0 — Reliability & parity

| Item | Why | Touches |
|------|-----|---------|
| Aspect-aware overlay Y remap on batch 9:16→16:9 | Positions tuned for portrait feel wrong on landscape | `EditorViewModel.remapOverlays`, packs |
| Notarized / Developer ID macOS builds | Gatekeeper friction on Releases | CI signing secrets, `build-macos.sh` |
| CI smoke: enhance full-duration + export dry path | Catch `prefix(8)` / duration `\|\| 10` regressions | GitHub Actions, Node tests, optional XCTest |
| Keep Xcode membership in sync for new GIF/Swift files | Silent missing burn-in / compile gaps | `project.pbxproj` checklist in PR template |

### P1 — Edit surface

| Item | Why | Touches |
|------|-----|---------|
| Zoomable / drag-to-retime timeline | Faster than sliders alone | `EditorView` timeline, overlay/SFX models |
| Undo stack for apply(plan) / trim / delete | Safe daily experimentation | `EditorViewModel` command history |
| Preview SFX while playhead crosses cues | WYSIWYG audio | Player time observer + `previewSFX` |
| Hide or dim phrase captions under dense word hits (optional toggle) | Reduce “two caption systems” clutter | Export + preview flags |

### P2 — Audio v2

| Item | Why | Touches |
|------|-----|---------|
| True LUFS metering (replace peak-only) | Platform-safe loudness | `AudioNormalizeService`, Accelerate / AVAudio |
| Per-track EQ / compressor presets on Audio layer | Stronger “enhancers” story | Export audio taps or offline render |
| Music bed track (ducked under dialogue) | Beyond one-shot SFX | New cue type + library + mix |

### P3 — Trim & captions v2

| Item | Why | Touches |
|------|-----|---------|
| Trim auto-apply + undo | Faster silence cleanup | `TrimService`, confirm UI |
| Chunked Speech for long files | Avoid truncated transcripts | `TranscriptionService` |
| Caption translation / bilingual burn-in | Growth in HI/TE markets | Models + export layers |

### P4 — Libraries & AI Place

| Item | Why | Touches |
|------|-----|---------|
| Merge / maintain Iconify sync on master | Richer sticker set | `tools/iconify-sync`, catalogs |
| Square 1:1 batch export | IG feed | `AspectRatioPreset`, export UI |
| Enhancer returns `trimSuggestions` | Single AI pass for cuts | `enhance.js` schema, Trim tab seed |
| Per-project brand kit snapshot | Watermark/fonts freeze with draft | `SavedProject`, BrandKit |

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
P0 aspect remap + CI smoke + signing path
P1 timeline zoom/drag + undo + preview SFX
P2 LUFS (if distribution partners require it)
P3 trim v2 / long Speech
P4 library growth + 1:1 + enhance trim suggestions
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

---

## Related docs

- Architecture invariants: [ARCHITECTURE.md](./ARCHITECTURE.md) §9  
- Shipped baseline: [FEATURES.md](./FEATURES.md)  
- Original A–C plan status: [SHORTS_MAKER_PLAN.md](./SHORTS_MAKER_PLAN.md)  
