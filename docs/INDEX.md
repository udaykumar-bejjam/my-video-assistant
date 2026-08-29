# CaptionStudio documentation index

Start here for product understanding, architecture, and future work.
Canonical hub also: [README.md](./README.md).

| Document | Purpose |
|----------|---------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | System design, process boundaries, data flows |
| [CODEBASE_MAP.md](./CODEBASE_MAP.md) / [FILE_INDEX.md](./FILE_INDEX.md) | Source maps |
| [FEATURES.md](./FEATURES.md) | Feature catalog and end-to-end user flows |
| [DATA_MODEL.md](./DATA_MODEL.md) | Persistence + package schema |
| [DEVELOPMENT.md](./DEVELOPMENT.md) | Build / test / release |
| [ENHANCEMENT_ROADMAP.md](./ENHANCEMENT_ROADMAP.md) / [ROADMAP.md](./ROADMAP.md) | Prioritized enhancement plans |
| [MERGE_HISTORY.md](./MERGE_HISTORY.md) | Feature PR merge wave |
| [TELUGU_ASR_PLAN.md](./TELUGU_ASR_PLAN.md) | Telugu ASR design (shipped) |
| [CHESS_WALKTHROUGH.md](./CHESS_WALKTHROUGH.md) | Chess PGN walkthrough (shipped) |
| [SHORTS_MAKER_PLAN.md](./SHORTS_MAKER_PLAN.md) | Original Shorts-maker product vision |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | Change rules |
| [BUILD_STAMP.txt](./BUILD_STAMP.txt) | Local build stamp (CI / release hygiene) |

## Related entry points

| Path | Role |
|------|------|
| [`README.md`](../README.md) | Product overview, install, API, packaging |
| [`AGENTS.md`](../AGENTS.md) | Cursor Cloud constraints (Linux = Node only) |
| [`enhancer-server/`](../enhancer-server/) | Enhancer service |
| [`.github/workflows/build-macos.yml`](../.github/workflows/build-macos.yml) | Tag `v*` → macOS zip release |

## Mental model (one paragraph)

CaptionStudio is a **local-first** caption + overlay editor. The **SwiftUI app** owns media, captions, layered timeline scrubbing, preview, and AVFoundation export. An optional **Node enhancer** (`enhancer-server`) places stickers/SFX/text/word-hits via Cursor SDK (`composer-2.5`) or an offline heuristic. Shorts Packs bias density and style. Telugu captions use OpenAI Whisper when Apple Speech has no model. Chess Walkthrough animates annotated PGN. Cloud Linux agents can run only the enhancer; Mac builds ship via GitHub Actions.

## How to use these docs

1. New to the repo → **ARCHITECTURE**, then **FEATURES**.
2. Looking for a file → **FILE_INDEX** / **CODEBASE_MAP**.
3. Planning work → **ROADMAP** / **ENHANCEMENT_ROADMAP**.
4. Cloud agent on Linux → **AGENTS.md**.
