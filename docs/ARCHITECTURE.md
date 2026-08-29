# CaptionStudio — Architecture

Last updated for `master` (Audio layer, project save/load + session resume,
full-duration AI Place, animated GIF export).

---

## 1. Big picture

```text
┌─────────────┐     ┌──────────────────┐     ┌────────────────────┐
│  SwiftUI    │────▶│  EditorViewModel │────▶│  AVFoundation      │
│  Editor     │◀────│  (single source  │     │  export / stitch   │
└─────────────┘     │   of truth)      │     └────────────────────┘
                    └────────┬─────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
      Transcription    Media libraries   ProjectStore
      (Apple Speech)   (catalog.json)    (Projects/*.json)
              │
              ▼
      CursorEnhancerClient ──HTTP──▶ enhancer-server :8787
                                         │
                              ┌──────────┴──────────┐
                              ▼                     ▼
                        @cursor/sdk            heuristicPlan
                        composer-2.5           (+ hook + B-roll)
```

Without `CURSOR_API_KEY` (or if the server is down), enhance returns the **same
JSON schema** via heuristics so the editor stays usable offline.

---

## 2. Runtime model graph

```text
VideoProject                          BrandKit (UserDefaults)
├── videoURL, duration, aspect        ├── fonts / colors / watermark
├── captions: [CaptionSegment]        ├── defaultPackId, language
│     └── words: [CaptionWord]        └── defaultSfxGain
├── captionStyle: CaptionStyle
├── overlays: [OverlayItem]           ShortsPack (catalog)
│     kinds: text, emoji, shape,      ├── aspect + captionPreset
│            watermark, gif, png,     ├── effectBias / sfxBias
│            wordHit                  └── wordHitsPerCaption, hook window
├── soundEffects: [SoundEffectCue]      → assetId → sfx catalog
├── audio: ProjectAudioSettings       ← Audio layer (dialogue/SFX/duck/preset)
├── packId, language, chunkCount
└── enhancementSummary

SavedProject  = Codable snapshot of VideoProject
              + videoFileName
              + session (playhead, tab, selections)
              + distribution (title/hashtags/cover)
              + timestamps
```

**Apply rule:** enhancer output becomes an `EnhancementPlan`. The app always
`validate → align → apply` via `EditorViewModel.apply(plan:)`. Manual emoji /
shape / watermark overlays (no library ids) are preserved across re-enhance.

---

## 3. End-to-end pipelines

### 3.1 Captions

1. Import copies video into app sandbox (Caches → later Projects on save).
2. `TranscriptionService` extracts audio → `SFSpeechRecognizer` (locale from
   `AppLanguage`) → phrase segments (~4–5 words) with word timings.
3. Demo captions fill in when Speech is denied / unavailable.
4. Preview: `CaptionOverlayView` (karaoke / typewriter / pop…).
5. Export: `VideoExportService.addCaptionLayers` (karaoke/typewriter burn-in on
   master; plain phrase fallback).

### 3.2 AI Place (enhance)

1. `VideoChunkPlanner.chunks(duration)` — single pass if ≤60s; else 45s parts
   with 1.5s caption context.
2. Per chunk: filter captions → `CursorEnhancerClient.enhance` **or**
   `localHeuristicPlan`.
3. Duration must be positive and ≥ last caption end (never coerce `0 → 10`,
   which historically clamped hits into the first 10s).
4. Server path: prompt / heuristic → `validatePlacements` →
   `ensureOpeningHook` → `appendMissingCaptionWordHits` → `ensureBrollStickers`.
5. Client: `absolutize` placements to absolute timeline → dedupe → fill any
   still-missing caption windows → `apply`.

### 3.3 Export

1. Remap overlays if batch aspect ≠ project aspect.
2. If one chunk: `VideoExportService.export` with full captions/overlays/SFX +
   `ProjectAudioSettings`.
3. If many: filter cues per hard chunk → `VideoStitchService.exportChunked`
   (shift times to local 0, export parts, concatenate). Drop razor-thin caption
   remnants at seams.
4. Mix: dialogue gain × optional peak normalize; SFX master × per-cue gain;
   optional duck windows under SFX; muted cues skipped.
5. Overlays: CALayers + **CAKeyframeAnimation** opacity (macOS ignores
   `CABasicAnimation` in offline export). GIF frames via `AnimatedGIFDecoder`.

Coordinate space: export parent layer `isGeometryFlipped = true` (Y-down),
matching SwiftUI preview. Do **not** invert `positionY` again.

---

## 4. Persistence

```text
~/Library/Application Support/CaptionStudio/Projects/
  index.json
  <uuid>/
    project.json     # pretty JSON, ISO8601 dates
    video.<ext>
```

Legacy `Drafts/` is migrated once into `Projects/`.

| Field group | Contents |
|-------------|----------|
| Creative | captions, captionStyle, overlays, soundEffects, pack, language |
| Audio | `ProjectAudioSettings` (gains, normalize, duck, enhancer preset) |
| Session | playhead, editor tab, selected IDs, audio-layer focus, safe zone |
| Distribution | title, coverText, hashtags, hookLine |

Library GIF/PNG/SFX/fonts are **referenced by `assetId` / filename**, not copied.
Missing assets soft-fail at preview/export.

Portable package (macOS): `Name.captionstudio/` = `project.json` + video
(Home **Open package** / Export **Export package…**).

---

## 5. Asset libraries

**Source of truth:** `AssetLibraries/<kind>/catalog.json`  
**App bundle mirror:** `CaptionStudio/Resources/Libraries/`  
**Enhancer:** reads `AssetLibraries/` via `libraries.js`

| Kind | Role |
|------|------|
| text-styles | Stylish text holds |
| gifs | Animated loops (preview + export frames) |
| pngs | Stickers (incl. Iconify imports) |
| sfx | One-shots with `durationSeconds` / gain |
| fonts | Script-tagged (latin / hindi / telugu) |
| effects | Word-hit motion + colors + preferred SFX |
| packs | Shorts recipes (Hook / Story / Tip / Hype / Tutorial) |
| lexicons | EN/HI/TE power·reveal·emotion·numbers·CTA |

Catalog items carry timing/size metadata used by `PlacementAligner` and enhancer
enrichment. Keep both trees in sync when adding assets (`tools/iconify-sync`
writes both PNG trees).

---

## 6. enhancer-server

| Route | Role |
|-------|------|
| `GET /health` | `{ ok, hasCursorKey, model }` |
| `GET /libraries` | Catalog dump |
| `POST /enhance` | Captions + duration + pack/brand/safeZone → plan |

`resolveVideoDuration(duration, captions)` must never treat `0` as falsy → 10.
Full-duration rule: word hits across **every** caption window; smoke test
`enhancer-server/test/full-duration-smoke.mjs`.

---

## 7. Chunking constants

Defined in `VideoChunkPlanner` (`AspectRatio.swift`):

| Constant | Value | Meaning |
|----------|-------|---------|
| `singlePassLimit` | 60s | Enhance/export in one pass |
| `defaultChunkSeconds` | 45s | Part length when longer |
| `contextPadding` | 1.5s | Extra captions for enhance context |

---

## 8. Build & release

- Local: `./scripts/build-macos.sh` → `build/dist/CaptionStudio-macOS.zip`
- CI: `.github/workflows/build-macos.yml` — tags `v*`, push to `master`,
  `workflow_dispatch`; runner `macos-15`
- Ad-hoc signed; Gatekeeper: right-click Open / clear quarantine xattr

---

## 9. Invariants (do not regress)

1. AI Place covers **full** caption timeline (no `prefix(8)` / early-only caps).
2. Export overlay visibility uses **keyframe** opacity, not `CABasicAnimation`.
3. Preview and export share the same aspect canvas + Y-down geometry.
4. Enhance duration ≥ caption span (never `Number(x) \|\| 10`).
5. Manual non-library overlays survive `apply(plan:)`.
6. Project JSON round-trips session so reopen resumes playhead/tab/selection.
7. Xcode `PBXFileReference` membership must include every Swift/GIF source used.

---

## 10. Key modules map

| Concern | Primary files |
|---------|----------------|
| State | `EditorViewModel.swift` |
| Models | `Overlay.swift`, `SavedProject.swift`, `MediaLibrary.swift`, `Caption.swift` |
| Enhance | `CursorEnhancerClient.swift`, `enhancer-server/src/*` |
| Export | `VideoExportService.swift`, `VideoStitchService.swift` |
| Audio mix | `ProjectAudioSettings`, `AudioNormalizeService.swift` |
| Persist | `ProjectStore.swift` |
| UI shell | `HomeView.swift`, `EditorView.swift`, `OverlayEditorView.swift` |
