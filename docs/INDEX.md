# CaptionStudio documentation index

Living docs for understanding, extending, and shipping CaptionStudio.
Prefer these over chat history when returning to the project.

| Doc | Purpose |
|-----|---------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | System design, data flow, persistence, enhance/export |
| [FEATURES.md](./FEATURES.md) | Shipped product capabilities |
| [CODEBASE_MAP.md](./CODEBASE_MAP.md) | File-by-file Swift + enhancer map |
| [FILE_INDEX.md](./FILE_INDEX.md) | Important source map (alternate index) |
| [DATA_MODEL.md](./DATA_MODEL.md) | Runtime + disk models, package layout |
| [DEVELOPMENT.md](./DEVELOPMENT.md) | Build, enhancer, smokes, release, debug |
| [ROADMAP.md](./ROADMAP.md) | Prioritized enhancements (P0–P4) |
| [ENHANCEMENT_ROADMAP.md](./ENHANCEMENT_ROADMAP.md) | Companion roadmap (agent-oriented) |
| [TELUGU_ASR_PLAN.md](./TELUGU_ASR_PLAN.md) | Telugu / bilingual ASR design |
| [CHESS_WALKTHROUGH.md](./CHESS_WALKTHROUGH.md) | PGN chess walkthrough |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | Change rules / regression guards |
| [SHORTS_MAKER_PLAN.md](./SHORTS_MAKER_PLAN.md) | Original phased plan (A–C) |
| [MERGE_HISTORY.md](./MERGE_HISTORY.md) | What landed on `master` from feature PRs |

**Start here if new:** `ARCHITECTURE.md` → `FEATURES.md` → `DATA_MODEL.md` → `CODEBASE_MAP.md`.

**Product one-liner:** AI captions (Apple Speech + OpenAI for Telugu) + Cursor SDK / heuristic placement of word hits, text, GIFs/PNGs, and SFX — plus Chess Walkthrough — for short-form video on iOS 17+ / macOS 14+.

**Primary user loop**

```text
Import / Demo → Pack → AI Captions → AI Place → Timeline / Layers / Library / Trim / Audio
  → Export (aspect / batch / loudness) → Save Project → Share

Optional: Chess Walkthrough (PGN) — interactive board (not in export yet)
```

Also: root [`README.md`](../README.md), [`AGENTS.md`](../AGENTS.md) (Cloud Linux = Node only).
