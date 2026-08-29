# CaptionStudio documentation index

Living docs for understanding, extending, and shipping CaptionStudio
(`my-video-assistant`). Prefer these over chat history when returning to the project.

Also: [INDEX.md](./INDEX.md) (alternate hub).

| Doc | Purpose |
|-----|---------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | System design, data flow, persistence, enhance/export pipelines |
| [FEATURES.md](./FEATURES.md) | Shipped product capabilities (user-facing) |
| [FILE_INDEX.md](./FILE_INDEX.md) / [CODEBASE_MAP.md](./CODEBASE_MAP.md) | Source maps |
| [DATA_MODEL.md](./DATA_MODEL.md) | Runtime + disk models, package layout, schema rules |
| [DEVELOPMENT.md](./DEVELOPMENT.md) | Build, run enhancer, smoke tests, release, debug checklist |
| [ROADMAP.md](./ROADMAP.md) / [ENHANCEMENT_ROADMAP.md](./ENHANCEMENT_ROADMAP.md) | Prioritized enhancements |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | Agent/human change rules and regression guards |
| [TELUGU_ASR_PLAN.md](./TELUGU_ASR_PLAN.md) | Telugu Whisper / gpt-transcribe design |
| [CHESS_WALKTHROUGH.md](./CHESS_WALKTHROUGH.md) | Chess PGN walkthrough |
| [MERGE_HISTORY.md](./MERGE_HISTORY.md) | What landed from open PRs |
| [IN_FLIGHT_BRANCHES.md](./IN_FLIGHT_BRANCHES.md) | Points at merge history (formerly unmerged work) |
| [SHORTS_MAKER_PLAN.md](./SHORTS_MAKER_PLAN.md) | Original phased plan (A–C) with ship status |
| [`../AGENTS.md`](../AGENTS.md) | Cursor Cloud constraints |

**Start here if new to the repo:** `ARCHITECTURE.md` → `FEATURES.md` → `DATA_MODEL.md` → `FILE_INDEX.md`.

**Product one-liner:** AI captions + Cursor SDK (or heuristic) placement of word hits,
stylish text, GIFs/PNGs, and SFX — preview and export MP4 for short-form video on
iOS 17+ / macOS 14+. Telugu uses OpenAI Whisper; Chess Walkthrough animates PGN.

**Primary user loop**

```text
Import / Demo → Pack → AI Captions → AI Place → Layers / Library / Trim / Audio
  → Export (aspect / batch / loudness) → Save Project → Share
```
