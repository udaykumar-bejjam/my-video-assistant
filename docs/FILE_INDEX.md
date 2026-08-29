# CaptionStudio — File index

Quick map of important paths. Prefer reading the file header / types over this
list when implementing; keep this index updated when adding modules.

---

## Root

| Path | Purpose |
|------|---------|
| `README.md` | Product overview, run/build/download |
| `docs/` | Architecture, features, roadmap, plan |
| `CaptionStudio/` | SwiftUI multiplatform app |
| `CaptionStudio.xcodeproj/` | Xcode project / scheme |
| `AssetLibraries/` | Source-of-truth media catalogs + binaries |
| `enhancer-server/` | Node enhance API + Cursor SDK |
| `scripts/build-macos.sh` | Release build → zip |
| `.github/workflows/build-macos.yml` | CI macOS build + GitHub Release |
| `tools/iconify-sync/` | Import Iconify PNGs into catalogs |

---

## App entry

| File | Purpose |
|------|---------|
| `CaptionStudio/CaptionStudioApp.swift` | `@main`, RootView Home↔Editor, shared `EditorViewModel` |

---

## Models (`CaptionStudio/Models/`)

| File | Purpose |
|------|---------|
| `Caption.swift` | Segments, words, presets, `CaptionStyle`, `CodableColor` |
| `Overlay.swift` | `OverlayKind`, `OverlayItem`, runtime `VideoProject` (+ `audio`) |
| `SavedProject.swift` | Codable project + `ProjectSessionState` + distribution |
| `MediaLibrary.swift` | Catalog items, `EnhancementPlan` / placements, `SoundEffectCue`, `ProjectAudioSettings`, enhancer presets |
| `AspectRatio.swift` | Canvas sizes, `VideoChunkPlanner`, `AspectFit` crop |
| `LanguageAndEffects.swift` | `AppLanguage`, `WordHitEffect` |
| `ShortsPack.swift` | Pack recipe model, `EnhancementHook` |
| `SafeZoneAndDistribution.swift` | Safe rects, `DistributionPackage` |
| `ColorHex.swift` | Hex → Color |
| `ChessAnalysis.swift` | Move categories, colors, arrows, annotated moves, walkthrough spec |

---

## ViewModel

| File | Purpose |
|------|---------|
| `ViewModels/EditorViewModel.swift` | Editor hub: load, captions, enhance, timeline drag, trim, export, save |
| `ViewModels/ChessWalkthroughViewModel.swift` | PGN snapshots, play/step, category SFX |

---

## Services (`CaptionStudio/Services/`)

| File | Purpose |
|------|---------|
| `TranscriptionService.swift` | Apple Speech → captions; routes Telugu to Whisper client |
| `WhisperTranscriptionClient.swift` | OpenAI gpt-transcribe + whisper-1 clocks (Telugu dual-pass) |
| `APIKeyStore.swift` | Keychain for OpenAI API key |
| `CursorEnhancerClient.swift` | HTTP enhance + local heuristic (parity-contract v1) |
| `HeuristicParity.swift` | Loads shared filler/punchy/rules; thinWordHits |
| `TimelineSnap.swift` | Snap interval / anchors (parity with `timelineSnap.js`) |
| `MediaLibraryStore.swift` | Load catalogs; resolve file URLs |
| `PackLibrary.swift` | Load Shorts Packs |
| `BrandKitStore.swift` | UserDefaults brand kit |
| `ProjectStore.swift` | Projects/ JSON + video; package import/export; legacy Drafts migrate |
| `PlacementAligner.swift` | Snap timing / position to asset + caption + safe zone |
| `BrollPlanner.swift` | Strong-word stickers; `StrongWordLexicon` |
| `TrimService.swift` | Silence/filler suggestions; shift cues through keeps |
| `VideoTrimComposer.swift` | Write trimmed MP4 from keep ranges |
| `VideoExportService.swift` | Burn-in captions/overlays/GIF frames; SFX mix; audio settings |
| `VideoStitchService.swift` | Chunked export then concatenate |
| `CoverExportService.swift` | Cover PNG from frame + cover text |
| `AudioNormalizeService.swift` | LUFS (BS.1770) + peak ceiling; duck windows |
| `AnimatedGIFDecoder.swift` | Decode GIF frames for preview/export |
| `ChessEngine.swift` | Board state, SAN apply, PGN parser |
| `ChessVOClock.swift` | Fixed pace / fit-to-range ply start times for overlay + SFX |
| `ChessPGNImportService.swift` | File / Lichess / chess.com URL → PGN text |

---

## Views (`CaptionStudio/Views/`)

| File | Purpose |
|------|---------|
| `HomeView.swift` | Landing, import/demo, packs, saved projects, Chess CTA, API key |
| `EditorView.swift` | Chrome, preview, tabs, AI actions, chess button |
| `TimelineWorkspaceView.swift` | Zoomable multi-lane timeline; multi-select, snap guides, drag retime |
| `CaptionListView.swift` | Caption editing + style picker |
| `CaptionOverlayView.swift` | Live captions + `LiveOverlayCanvas` |
| `WordHitView.swift` | Word-hit styling / motion |
| `OverlayEditorView.swift` | Layers + **Audio layer** + Export / share panels |
| `LibraryBrowserView.swift` | Browse/place library assets |
| `PackPickerView.swift` | Pack chips |
| `TrimAssistView.swift` | Trim suggestions UI |
| `BrandKitSettingsView.swift` | Brand kit sheet |
| `OpenAIKeySheet.swift` | OpenAI API key entry |
| `AnimatedGIFView.swift` | Scrub-synced GIF preview |
| `ChessWalkthroughView.swift` | PGN board, arrows, highlights, transport, VO clock panel |

---

## enhancer-server

| File | Purpose |
|------|---------|
| `src/server.js` | Express app, routes, static libraries, `/transcribe` |
| `src/enhance.js` | Cursor SDK vs heuristic entry; duration resolve |
| `src/heuristicCore.js` | Shared offline heuristic (parity-contract v1) |
| `src/timelineSnap.js` | Timeline snap / multi-retime helpers (P1.2) |
| `src/chessPgnImport.js` | Lichess / chess.com URL resolve + PGN fetch (P1.9) |
| `src/chessVOClock.js` | Fixed pace / fit-to-range ply times (P1.8) |
| `src/lufs.js` | BS.1770 LUFS metering + gain (P1.14) |
| `src/libraries.js` | Load catalogs, validate/align, full-duration fill |
| `src/packs.js` | Pack helpers (biases, hits per caption) |
| `src/broll.js` | Sticker pairing for strong hits |
| `src/lexicon.js` | Strong-word categories |
| `src/safezone.js` | Clamp + distribution normalize |
| `src/transcribe.js` | Whisper proxy for optional `/transcribe` |
| `src/cli.js` | Offline CLI enhance |
| `test/*-smoke.mjs` | Packs, B-roll, distribution, trim, full-duration |

---

## Asset libraries

| Path | Contents |
|------|----------|
| `AssetLibraries/text-styles/` | Stylish text catalog |
| `AssetLibraries/gifs/` | Animated loops + catalog |
| `AssetLibraries/pngs/` | Stickers (+ Iconify) |
| `AssetLibraries/sfx/` | Audio one-shots |
| `AssetLibraries/fonts/` | Script-tagged font ids |
| `AssetLibraries/effects/` | Word-hit effects |
| `AssetLibraries/packs/` | Shorts Pack recipes |
| `AssetLibraries/lexicons/` | `en.json` / `hi.json` / `te.json` |

Mirror under `CaptionStudio/Resources/Libraries/` for the app bundle.

---

## Tools

| Path | Purpose |
|------|---------|
| `tools/iconify-sync/` | Search/add/sync-moods Iconify → PNG catalogs |
| `scripts/build-macos.sh` | xcodebuild Release + zip |

---

## When you add a feature

1. Put models in `Models/`, side-effects in `Services/`, UI in `Views/`.
2. Wire through `EditorViewModel` (single source of truth).
3. If library assets: update **both** `AssetLibraries/` and Resources copy;
   ensure Xcode membership for new Swift/media files.
4. If enhance schema changes: update `enhancer-server` + Swift `EnhancementPlan`
   Codable + a smoke test.
5. Update `docs/FEATURES.md` + this index.
