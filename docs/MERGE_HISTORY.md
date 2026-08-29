# Merge history (feature lines → `master`)

Recorded when open draft PRs were integrated into `master`.

| Source branch / PR | What landed |
|--------------------|-------------|
| `cursor/chess-analysis-overlays-ac05` (#19) | Chess Walkthrough (PGN → animated board) + stacked Telugu/timeline/SFX fixes |
| `cursor/fix-telugu-english-captions-ac05` (#18) | Zoomable `TimelineWorkspaceView` + Telugu ASR (ancestor of #19) |
| `cursor/fix-preview-sfx-export-overlays-ac05` (#17) | Preview SFX / export burn-in / word-hit polish (ancestor of #19) |
| `cursor/iconify-sync-tool-ce40` (#7) | `tools/iconify-sync` + sample Iconify PNGs |
| `cursor/setup-dev-environment-ac05` (#15) | Initial `AGENTS.md` |
| `cursor/project-docs-ce40` (#20) | ARCHITECTURE, FEATURES, FILE_INDEX, DATA_MODEL, DEVELOPMENT, ROADMAP, CONTRIBUTING |
| `cursor/project-documentation-ac05` (#21) | INDEX, CODEBASE_MAP, ENHANCEMENT_ROADMAP, hub links |
| `cursor/rebuild-v110-ac05` (#16) | Workflow bump only; **marketing version kept at 1.0.27** (chess tip) |
| `cursor/four-enhancements-ac05` (#22) | Chess MP4 export, eval, undo/redo, enhancer CI |
| `cursor/chess-video-overlay-ac05` (#23) | Chess walkthrough overlay on project video |
| `cursor/heuristic-parity-ac05` | App ↔ server enhance heuristic parity-contract v1 |
| `cursor/timeline-multiselect-ac05` | Timeline multi-select + snap guides (P1.2) |
| `cursor/chess-pgn-import-ac05` | PGN from file / Lichess / chess.com (P1.9) |

After this wave, Telugu ASR, timeline drag/zoom/multi-select, Chess Walkthrough (+ export/overlay/eval/import), Iconify sync, deep docs, undo/redo, enhancer CI, 1:1 aspect remap, and heuristic parity are on `master` (PGN import PR pending merge). See [ROADMAP.md](./ROADMAP.md) for follow-ons.
