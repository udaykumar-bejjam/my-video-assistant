# CaptionStudio documentation index

Start here for product understanding, architecture, and future work.

| Document | Purpose |
|----------|---------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | System design, process boundaries, data flows (**master**) |
| [CODEBASE_MAP.md](./CODEBASE_MAP.md) | File-by-file map of Swift app + enhancer-server (**master**) |
| [FEATURES.md](./FEATURES.md) | Feature catalog and end-to-end user flows (**master**) |
| [ENHANCEMENT_ROADMAP.md](./ENHANCEMENT_ROADMAP.md) | Prioritized enhancement plan |
| [IN_FLIGHT_BRANCHES.md](./IN_FLIGHT_BRANCHES.md) | Unmerged work (Telugu ASR, timeline UX, chess) — read before planning |
| [TELUGU_ASR_PLAN.md](./TELUGU_ASR_PLAN.md) | Telugu ASR design (code on feature branch) |
| [CHESS_WALKTHROUGH.md](./CHESS_WALKTHROUGH.md) | Chess PGN walkthrough (code on feature branch) |
| [SHORTS_MAKER_PLAN.md](./SHORTS_MAKER_PLAN.md) | Original Shorts-maker product vision |
| [BUILD_STAMP.txt](./BUILD_STAMP.txt) | Local build stamp (CI / release hygiene) |

## Related entry points

| Path | Role |
|------|------|
| [`README.md`](../README.md) | Product overview, install, API, packaging |
| [`AGENTS.md`](../AGENTS.md) | Cursor Cloud constraints (Linux = Node only) |
| [`enhancer-server/`](../enhancer-server/) | Enhancer service; CLI/HTTP also summarized in root README |
| [`.github/workflows/build-macos.yml`](../.github/workflows/build-macos.yml) | Tag `v*` → macOS zip release |

## Mental model (one paragraph)

CaptionStudio is a **local-first** caption + overlay editor. The **SwiftUI app** owns media, captions, layered timeline scrubbing, preview, and AVFoundation export. An optional **Node enhancer** (`enhancer-server`) places stickers/SFX/text/word-hits via Cursor SDK (`composer-2.5`) or an offline heuristic. Shorts Packs bias density and style. Cloud Linux agents can run only the enhancer; Mac builds ship via GitHub Actions.

## How to use these docs

1. New to the repo → **ARCHITECTURE**, then **FEATURES**.
2. Looking for a file → **CODEBASE_MAP** (matches `master`).
3. Planning work → **ENHANCEMENT_ROADMAP** + **IN_FLIGHT_BRANCHES** (avoid duplicating open PRs).
4. Cloud agent on Linux → **AGENTS.md**.
