# Merge history (feature lines → `master`)

Recorded when open draft PRs were integrated into `master` in one merge wave.

| Source branch / PR | What landed |
|--------------------|-------------|
| `cursor/chess-analysis-overlays-ac05` (#19) | Chess Walkthrough (PGN → animated board) |
| `cursor/fix-telugu-english-captions-ac05` (#18) | Zoomable `TimelineWorkspaceView` + Telugu ASR lineage (ancestor of #19) |
| `cursor/fix-preview-sfx-export-overlays-ac05` (#17) | Preview SFX / export burn-in / word-hit polish (ancestor of #19) |
| `cursor/iconify-sync-tool-ce40` (#7) | `tools/iconify-sync` + sample Iconify PNGs |
| `cursor/setup-dev-environment-ac05` (#15) | Initial `AGENTS.md` |
| `cursor/project-docs-ce40` (#20) | ARCHITECTURE, FEATURES, FILE_INDEX, DATA_MODEL, DEVELOPMENT, ROADMAP, CONTRIBUTING |
| `cursor/project-documentation-ac05` (#21) | INDEX, CODEBASE_MAP, ENHANCEMENT_ROADMAP, hub links |

**Not merged (obsolete / one-off):** `cursor/rebuild-v110-ac05` (#16) — rebuild trigger only; superseded by later tags/workflows.

After this wave, Telugu ASR, timeline drag/zoom, and Chess Walkthrough are **on `master`**. See domain docs and [ROADMAP.md](./ROADMAP.md) for follow-ons (Stockfish, chess export burn-in, etc.).
