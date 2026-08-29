# CaptionStudio

AI captions + Cursor SDK placement of stylish text, GIFs, PNGs, and sound effects for iOS and macOS.

Two pieces live in this repo:

- `CaptionStudio.xcodeproj` / `CaptionStudio/` — SwiftUI app (iOS/macOS). Requires macOS 14+ / Xcode 15+. Built via `./scripts/build-macos.sh` or the `Build macOS app` GitHub Actions workflow (`.github/workflows/build-macos.yml`).
- `enhancer-server/` — Node.js/Express service (`@cursor/sdk`) that decides asset placements. Endpoint/CLI details are in the root `README.md`.

## Cursor Cloud specific instructions

This is a Linux cloud VM, so the **Swift/Xcode app cannot be built or run here** (it needs macOS + Xcode). All runnable development work in this environment is scoped to the `enhancer-server` Node.js service (and small Node tools under `tools/`).

- Node 22.13+ is required (`enhancer-server/package.json` `engines`).
- All enhancer commands run from `enhancer-server/`. Run `npm install` if `node_modules` is missing.
- Run the server: `npm start` (listens on `0.0.0.0:8787`; dev mode is `npm run dev`). Override with `PORT`.
- `CURSOR_API_KEY` is **optional**. Without it, `/enhance` and the CLI use a deterministic heuristic with the same JSON schema.
- Endpoints: `GET /health`, `GET /libraries`, `POST /enhance`, `POST /transcribe` (needs `OPENAI_API_KEY`; the Mac app usually calls OpenAI client-side instead).
- Non-obvious: `express.static` is mounted at `/libraries` before the JSON `GET /libraries` route — check middleware order if catalog fetch misbehaves.
- Smoke tests: `npm run test:packs`, `npm run test:broll`, `npm run test:distribution`, `npm run test:trim`, and `node test/full-duration-smoke.mjs`.
- CLI smoke: `npm run enhance -- examples/sample-captions.json`.
- Deep docs hub: [`docs/INDEX.md`](docs/INDEX.md) (also [`docs/README.md`](docs/README.md)).
