# Codebase map (`master`)

Paths are repo-relative. For files that exist only on unmerged branches, see [IN_FLIGHT_BRANCHES.md](./IN_FLIGHT_BRANCHES.md).

## Top level

| Path | Role |
|------|------|
| `CaptionStudio/` | SwiftUI app (iOS 17+ / macOS 14+) |
| `CaptionStudio.xcodeproj/` | Xcode project + schemes |
| `AssetLibraries/` | Shared catalogs + media |
| `enhancer-server/` | Node/Express placement service |
| `scripts/build-macos.sh` | Local macOS zip build |
| `.github/workflows/build-macos.yml` | Tag `v*` → GitHub Release zip |
| `docs/` | Architecture, features, roadmap |
| `AGENTS.md` | Cursor Cloud: Linux = enhancer-server only |
| `README.md` | Public product overview |

`AssetLibraries/` is mirrored into `CaptionStudio/Resources/Libraries/` for the app bundle.

---

## Swift app

### Entry

| File | Responsibility |
|------|----------------|
| `CaptionStudio/CaptionStudioApp.swift` | `@main`; `RootView` shows `HomeView` or `EditorView`; owns `EditorViewModel` |

### Views (`CaptionStudio/Views/`)

| File | Responsibility |
|------|----------------|
| `HomeView.swift` | Media pick, demo, drafts, pack entry |
| `EditorView.swift` | Preview, tabs, AI Captions / AI Place, **lane scrubber** (`TimelineScrubber`) |
| `CaptionListView.swift` | Caption list editing |
| `CaptionOverlayView.swift` | On-preview captions |
| `WordHitView.swift` | Significant-word hit overlays |
| `OverlayEditorView.swift` | Layers list + per-lane timing/scale/mute; `TimelineLaneStyle` |
| `LibraryBrowserView.swift` | Browse bundled libraries |
| `PackPickerView.swift` | Shorts Pack picker |
| `BrandKitSettingsView.swift` | Brand kit (incl. Telugu font id field for future/locale fonts) |
| `TrimAssistView.swift` | Trim suggestions UI |
| `AnimatedGIFView.swift` | Scrub-synced GIF playback |

### View models

| File | Responsibility |
|------|----------------|
| `ViewModels/EditorViewModel.swift` | Hub: media, ASR, enhance, packs, brand, drafts, trim, export, SFX preview |

### Models (`CaptionStudio/Models/`)

| File | Responsibility |
|------|----------------|
| `Caption.swift` | Segments, words, presets |
| `Overlay.swift` | Overlay items, SFX cues |
| `AspectRatio.swift` | 9:16 / 16:9 |
| `ShortsPack.swift` | Pack recipes |
| `LanguageAndEffects.swift` | Languages + effect ids |
| `MediaLibrary.swift` | Library item shapes |
| `SafeZoneAndDistribution.swift` | Safe zone + title/hashtags |
| `SavedProject.swift` | Draft / session persistence |
| `ColorHex.swift` | Color helpers |

### Services (`CaptionStudio/Services/`)

| File | Responsibility |
|------|----------------|
| `TranscriptionService.swift` | Apple Speech → captions |
| `CursorEnhancerClient.swift` | HTTP → `/enhance`, health, libraries; local heuristic fallback |
| `PackLibrary.swift` | Load packs from bundle |
| `PlacementAligner.swift` | Clamp/snap placements |
| `BrollPlanner.swift` | Client B-roll helpers |
| `VideoExportService.swift` | Burn-in export |
| `CoverExportService.swift` | Cover PNG |
| `AudioNormalizeService.swift` | Optional peak normalize |
| `VideoStitchService.swift` | Stitch long exports |
| `TrimService.swift` | Trim suggestions |
| `VideoTrimComposer.swift` | Apply trims |
| `ProjectStore.swift` | Drafts / packages |
| `BrandKitStore.swift` | Persist brand kit |
| `MediaLibraryStore.swift` | Catalog access |
| `AnimatedGIFDecoder.swift` | GIF frames for preview/export |

---

## Asset libraries (`AssetLibraries/`)

| Folder | Contents |
|--------|----------|
| `text-styles/` | Stylish text + `catalog.json` |
| `fonts/` | Font catalog |
| `effects/` | slam, bounce, zoom, … |
| `gifs/` | Looping stickers |
| `pngs/` | Static stickers |
| `sfx/` | Sound effects + durations |
| `packs/` | Hook / Story / Tip / Hype / Tutorial |

*(Lexicon JSON trees appear on in-flight branches for stronger B-roll word scoring.)*

---

## Enhancer server (`enhancer-server/`)

| File | Responsibility |
|------|----------------|
| `package.json` | Node ≥22.13; `start` / `dev` / `enhance` / smoke scripts |
| `src/server.js` | `/health`, `/libraries`, `/enhance`, static assets |
| `src/enhance.js` | Cursor SDK or heuristic |
| `src/libraries.js` | Catalogs + heuristic placement (large) |
| `src/packs.js` | Pack biases |
| `src/broll.js` | Auto B-roll stickers |
| `src/lexicon.js` | Word significance |
| `src/safezone.js` | Safe zone + distribution helpers |
| `src/cli.js` | CLI enhance |
| `examples/*.json` | Sample timelines |
| `test/*-smoke.mjs` | Packs, b-roll, distribution, trim, full-duration |

### HTTP (master)

| Method | Path | Role |
|--------|------|------|
| GET | `/health` | Liveness + key flags |
| GET | `/libraries` | Catalog JSON |
| GET | `/libraries/*` | Static files via `express.static` |
| POST | `/enhance` | Placement plan |

```bash
cd enhancer-server && npm install
npm start
npm run enhance -- examples/sample-captions.json
npm run test:packs && npm run test:broll && npm run test:distribution && npm run test:trim
node test/full-duration-smoke.mjs
```

---

## Quick “where is X?”

| Intent | Start here |
|--------|------------|
| Caption ASR | `TranscriptionService.swift` |
| AI Place | `CursorEnhancerClient.swift` → `enhance.js` / `libraries.js` |
| Lane scrubber | `EditorView.swift` (`TimelineScrubber`) |
| Layer editing | `OverlayEditorView.swift` |
| Export burn-in | `VideoExportService.swift` |
| Drafts | `ProjectStore.swift` |
| Packs / B-roll | `packs.js`, `broll.js`, `ShortsPack.swift` |
| Telugu / chess / drag timeline | [IN_FLIGHT_BRANCHES.md](./IN_FLIGHT_BRANCHES.md) |
