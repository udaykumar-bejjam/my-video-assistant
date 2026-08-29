# CaptionStudio documentation index

Living docs for understanding, extending, and shipping CaptionStudio
(`my-video-assistant`). Prefer these over chat history when returning to the project.

| Doc | Purpose |
|-----|---------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | System design, data flow, persistence, enhance/export pipelines |
| [FEATURES.md](./FEATURES.md) | Shipped product capabilities (user-facing) |
| [FILE_INDEX.md](./FILE_INDEX.md) | Every important source file and what it does |
| [DATA_MODEL.md](./DATA_MODEL.md) | Runtime + disk models, package layout, schema rules |
| [DEVELOPMENT.md](./DEVELOPMENT.md) | Build, run enhancer, smoke tests, release, debug checklist |
| [ROADMAP.md](./ROADMAP.md) | Prioritized enhancements (P0–P4) and non-goals |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | Agent/human change rules and regression guards |
| [SHORTS_MAKER_PLAN.md](./SHORTS_MAKER_PLAN.md) | Original phased plan (A–C) with ship status |

**Start here if new to the repo:** `ARCHITECTURE.md` → `FEATURES.md` → `DATA_MODEL.md` → `FILE_INDEX.md`.

**Product one-liner:** AI captions + Cursor SDK (or heuristic) placement of word hits,
stylish text, GIFs/PNGs, and SFX — preview and export MP4 for short-form video on
iOS 17+ / macOS 14+.

**Primary user loop**

```text
Import / Demo → Pack → AI Captions → AI Place → Layers / Library / Trim / Audio
  → Export (aspect / batch / loudness) → Save Project → Share
```
