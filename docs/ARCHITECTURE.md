# Architecture

CaptionStudio is a two-process product: a **native SwiftUI editor** and an optional **Node enhancer service**. They share JSON schemas for overlays and packs, but run independently.

> Scope: this document describes **`master`**. Unmerged Telugu ASR, zoomable timeline workspace, and Chess Walkthrough are summarized in [IN_FLIGHT_BRANCHES.md](./IN_FLIGHT_BRANCHES.md).

```
┌─────────────────────────────────────────────────────────────┐
│  CaptionStudio.app (SwiftUI, macOS 14+ / iOS 17+)           │
│                                                             │
│  CaptionStudioApp → RootView                                │
│       HomeView (no video) ──► EditorView + EditorViewModel  │
│                                   │                         │
│                                   ├─ Preview + lane scrubber│
│                                   ├─ Captions / Styles / …  │
│                                   └─ Export (AVFoundation)  │
│                                                             │
│  Services: Speech, Enhancer client, Export, Trim, Drafts    │
└───────────────────────────┬─────────────────────────────────┘
                            │ HTTP localhost:8787 (optional)
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  enhancer-server (Node 22 / Express)                        │
│  POST /enhance  GET /health  GET /libraries (+ static)      │
│  Cursor Agent (composer-2.5) OR offline heuristic           │
│  AssetLibraries/ (stickers, SFX, packs, …)                  │
└─────────────────────────────────────────────────────────────┘
```

## Design principles

1. **Local-first editing** — Media stays on device. Export burns captions/overlays with AVFoundation.
2. **Optional AI** — Enhance works without `CURSOR_API_KEY` (heuristic). Live agent uses `@cursor/sdk`.
3. **Shared overlay model** — Server and app agree on placement JSON (`kind`, timing, layout, asset ids).
4. **Heuristic parity** — App applies a local enhance fallback when the server is down.
5. **Linux cloud ≠ Mac build** — Cloud agents develop/test `enhancer-server` only; Mac app ships via GHA `macos-15`.

## Process boundaries

| Concern | Owner | Notes |
|---------|-------|-------|
| Import / preview / scrub | Swift `AVPlayer` + `EditorViewModel` | |
| Captions CRUD + styles | Swift models + VM | |
| Speech → captions | `TranscriptionService` (Apple Speech) | Language: EN / HI (and related locale ids) |
| Stickers / word hits / SFX ideas | Enhancer HTTP or local heuristic | Pack-aware |
| Brand kit | App `BrandKitStore` → enhance payload | |
| Lane scrubber / layer edit | `EditorView` scrubber + `OverlayEditorView` | |
| Trim | `TrimService` + `VideoTrimComposer` | |
| Burn-in export | `VideoExportService` | Captions + overlays + optional audio norm |
| Long video | Chunk enhance/export + `VideoStitchService` | >60s → ~45s parts |
| Pack catalog | `AssetLibraries/` + bundle mirror | |

## Data flows

### A. Captions from speech (master)

```
Video/audio URL
  → TranscriptionService (Apple Speech)
  → CaptionSegment[] (+ words when available)
  → EditorViewModel.project.captions
  → Preview (CaptionOverlayView) + Caps lane on scrubber
```

### B. Enhance (stickers / text / SFX / word hits)

```
POST /enhance {
  captions, duration, packId?, brandKit?, safeZone?,
  language?, videoSize?, forceHeuristic?
}
  → Cursor Agent (if CURSOR_API_KEY) OR heuristic in libraries.js
  → { placements, wordHits, distribution, safeZone, … }
  → EditorViewModel.apply(plan:)
```

### C. Export

```
Project snapshot (media, captions, overlays, SFX, trim, style, aspect)
  → VideoExportService (+ optional AudioNormalizeService)
  → optional multi-chunk stitch (VideoStitchService)
  → mp4 (+ optional CoverExportService PNG)
```

## Versioning & release

| Artifact | Mechanism |
|----------|-----------|
| App marketing version | Xcode `MARKETING_VERSION` |
| Mac zip | Tag `v*` → `.github/workflows/build-macos.yml` → GitHub Release |
| Enhancer | Run from source (`npm start`); no separate versioned package |

## Security / secrets

| Secret | Where | Required? |
|--------|-------|-----------|
| `CURSOR_API_KEY` | Enhancer env | No (heuristic fallback) |
| No media upload for enhance | Captions text + metadata only | |

## Failure modes worth knowing

- **Static `/libraries` before JSON route** — `express.static` is mounted at `/libraries` before `GET /libraries`. Prefer the documented catalog fetch; unexpected redirects/listings → check `server.js` order.
- **Enhancer down** — app local heuristic still returns schema-compatible overlays.
- **Swift on Linux** — cannot compile; use GHA macOS runners.
- **Branch skew** — `master` may lag feature branches; see [IN_FLIGHT_BRANCHES.md](./IN_FLIGHT_BRANCHES.md).
