# Merged feature lines (historical)

This file used to list **unmerged** Telugu / timeline / chess work. Those stacks are now on **`master`**.

Keep this as a short historical map so agents do not reinvent the same features.

---

## Merged into `master` (this integration)

| Theme | Former branch | What landed |
|-------|---------------|-------------|
| Preview SFX + export burn-in polish | `cursor/fix-preview-sfx-export-overlays-ac05` | Preview SFX sync, export glow, word-hit polish |
| Telugu / Whisper captions + timing | `cursor/fix-telugu-english-captions-ac05` | `WhisperTranscriptionClient`, gpt-transcribe + whisper clocks, OpenAI key UI |
| Zoomable timeline | (same lineage, ~v1.0.26) | `TimelineWorkspaceView`, cross-lane drag, zoom |
| Chess Walkthrough | `cursor/chess-analysis-overlays-ac05` (~v1.0.27) | PGN replay, arrows, callouts, SFX |
| Deep docs (suite A) | `cursor/project-docs-ce40` | ARCHITECTURE, FEATURES, FILE_INDEX, ROADMAP, … |
| Deep docs (suite B) | `cursor/project-documentation-ac05` | CODEBASE_MAP, ENHANCEMENT_ROADMAP, INDEX, AGENTS.md |
| Iconify PNG sync | `cursor/iconify-sync-tool-ce40` | `tools/iconify-sync` + sample PNGs |
| Dev env notes | `cursor/setup-dev-environment-ac05` | `AGENTS.md` cloud constraints |
| Rebuild trigger | `cursor/rebuild-v110-ac05` | macOS v1.0.10 workflow bump |

Design write-ups: [TELUGU_ASR_PLAN.md](./TELUGU_ASR_PLAN.md), [CHESS_WALKTHROUGH.md](./CHESS_WALKTHROUGH.md).

---

## Still open / follow-ups

See [ROADMAP.md](./ROADMAP.md) and [ENHANCEMENT_ROADMAP.md](./ENHANCEMENT_ROADMAP.md) for prioritized next work (Stockfish chess export burn-in, LUFS, notarization, square 1:1, etc.).
