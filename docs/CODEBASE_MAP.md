# Codebase map (`master`)

Paths are repo-relative. Reflects `master` after Telugu / timeline / chess / Iconify / docs merges. See [MERGE_HISTORY.md](./MERGE_HISTORY.md).

## Top level

| Path | Role |
|------|------|
| `CaptionStudio/` | SwiftUI app (iOS 17+ / macOS 14+) |
| `CaptionStudio.xcodeproj/` | Xcode project + schemes |
| `AssetLibraries/` | Shared catalogs + media |
| `enhancer-server/` | Node/Express placement + optional Whisper proxy |
| `tools/iconify-sync/` | Iconify → PNG catalog importer |
| `scripts/build-macos.sh` | Local macOS zip build |
| `.github/workflows/build-macos.yml` | Tag `v*` → GitHub Release zip |
| `docs/` | Architecture, features, roadmaps |
| `AGENTS.md` | Cursor Cloud: Linux = enhancer-server only |
| `README.md` | Public product overview |

`AssetLibraries/` is mirrored into `CaptionStudio/Resources/Libraries/`.

---

## Swift app

### Entry

| File | Responsibility |
|------|----------------|
| `CaptionStudio/CaptionStudioApp.swift` | `@main`; `RootView` Home ↔ Editor; shared `EditorViewModel` |

### Views

| File | Responsibility |
|------|----------------|
| `HomeView.swift` | Import, demo, drafts, packs, Chess CTA, API key |
| `EditorView.swift` | Preview chrome, tabs, AI Captions / AI Place, chess button |
| `TimelineWorkspaceView.swift` | Zoomable multi-lane timeline; multi-select, snap guides, drag retime |
| `CaptionListView.swift` | Caption list editing |
| `CaptionOverlayView.swift` | On-preview captions |
| `WordHitView.swift` | Word-hit overlays |
| `OverlayEditorView.swift` | Layers + audio panel; `TimelineLaneStyle` |
| `LibraryBrowserView.swift` | Browse libraries |
| `PackPickerView.swift` | Shorts Pack picker |
| `BrandKitSettingsView.swift` | Brand kit |
| `OpenAIKeySheet.swift` | OpenAI API key entry |
| `TrimAssistView.swift` | Trim suggestions |
| `AnimatedGIFView.swift` | Scrub-synced GIFs |
| `ChessWalkthroughView.swift` | PGN board UI |

### View models

| File | Responsibility |
|------|----------------|
| `EditorViewModel.swift` | Hub: media, ASR, enhance, timeline drag, packs, drafts, trim, export |
| `ChessWalkthroughViewModel.swift` | PGN parse, ply snapshots, play/step, SFX |

### Models

| File | Responsibility |
|------|----------------|
| `Caption.swift` | Segments, words, presets |
| `Overlay.swift` | Overlays, SFX, project audio settings |
| `AspectRatio.swift` | 9:16 / 16:9 / 1:1, chunk planner, `AspectOverlayRemapper` |
| `ShortsPack.swift` | Pack recipes |
| `LanguageAndEffects.swift` | Languages + effects |
| `MediaLibrary.swift` | Catalog + enhancement plan shapes |
| `SafeZoneAndDistribution.swift` | Safe zone + distribution copy |
| `SavedProject.swift` | Draft / session persistence |
| `ColorHex.swift` | Color helpers |
| `ChessAnalysis.swift` | Categories, colors, arrows, annotated moves |

### Services

| File | Responsibility |
|------|----------------|
| `TranscriptionService.swift` | Apple Speech + language routing |
| `WhisperTranscriptionClient.swift` | OpenAI gpt-transcribe + whisper clocks (Telugu) |
| `APIKeyStore.swift` | Keychain OpenAI key |
| `CursorEnhancerClient.swift` | HTTP enhance + local heuristic |
| `PackLibrary.swift` | Packs from bundle |
| `PlacementAligner.swift` | Snap/clamp placements |
| `BrollPlanner.swift` | Client B-roll helpers |
| `VideoExportService.swift` | Burn-in export |
| `CoverExportService.swift` | Cover PNG |
| `AudioNormalizeService.swift` | LUFS normalize / peak ceiling / duck |
| `VideoStitchService.swift` | Long-video stitch |
| `TrimService.swift` | Trim suggestions |
| `VideoTrimComposer.swift` | Apply trims |
| `ProjectStore.swift` | Drafts / packages |
| `BrandKitStore.swift` | Brand kit persistence |
| `MediaLibraryStore.swift` | Catalog access |
| `AnimatedGIFDecoder.swift` | GIF frames |
| `ChessEngine.swift` | Board + SAN + PGN parser |

---

## Enhancer (`enhancer-server/src/`)

| File | Responsibility |
|------|----------------|
| `server.js` | `/health`, `/libraries`, `/enhance`, `/transcribe`, static |
| `enhance.js` | Cursor SDK or heuristic |
| `heuristicCore.js` | Shared offline heuristic (parity-contract) |
| `libraries.js` | Catalogs + heuristic placement + validatePlacements |
| `packs.js` / `broll.js` / `lexicon.js` / `safezone.js` | Pack bias, B-roll, words, safe zone |
| `transcribe.js` | Whisper proxy |
| `cli.js` | CLI enhance |

---

## Quick “where is X?”

| Intent | Start here |
|--------|------------|
| Telugu timing | `WhisperTranscriptionClient.swift`, [TELUGU_ASR_PLAN.md](./TELUGU_ASR_PLAN.md) |
| Timeline drag | `TimelineWorkspaceView.swift`, `EditorViewModel.applyTimelineDrag` / `applyTimelineMultiRetime`, `TimelineSnap` |
| AI Place | `CursorEnhancerClient.swift` → `enhance.js` / `libraries.js` |
| Export | `VideoExportService.swift` |
| Chess | `ChessEngine.swift`, `ChessWalkthroughViewModel.swift` |
| Iconify PNGs | `tools/iconify-sync/` |
