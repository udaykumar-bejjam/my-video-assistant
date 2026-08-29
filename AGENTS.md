# CaptionStudio

AI captions + Cursor SDK placement of stylish text, GIFs, PNGs, and sound effects for iOS and macOS.

Two pieces live in this repo:

- `CaptionStudio.xcodeproj` / `CaptionStudio/` — SwiftUI app (iOS/macOS). Requires macOS 14+ / Xcode 15+. Built via `./scripts/build-macos.sh` or the `Build macOS app` GitHub Actions workflow (`.github/workflows/build-macos.yml`).
- `enhancer-server/` — Node.js/Express service (`@cursor/sdk`) that decides asset placements. Endpoint/CLI details are in the root `README.md`.

## Cursor Cloud specific instructions

This is a Linux cloud VM, so the **Swift/Xcode app cannot be built or run here** (it needs macOS + Xcode). All runnable development work in this environment is scoped to the `enhancer-server` Node.js service.

- Node 22.13+ is required (`enhancer-server/package.json` `engines`).
- All commands run from `enhancer-server/`. Run `npm install` if `node_modules` is missing.
- Run the server: `npm start` (listens on `0.0.0.0:8787`; dev mode with reload is `npm run dev`). Override the port with `PORT`.
- `CURSOR_API_KEY` is **optional**. Without it, `/enhance` and the CLI return the same JSON schema via a deterministic heuristic, so the service is fully testable offline. Set the key only to exercise the live `@cursor/sdk` (`composer-2.5`) path.
- Endpoints on `master`: `GET /health`, `GET /libraries`, `POST /enhance` (`{ captions, duration, packId?, ... }`).
- Non-obvious: `express.static` is mounted at `/libraries` before the JSON `GET /libraries` route in `src/server.js`. If catalog fetch misbehaves, check middleware order.
- Smoke tests: `npm run test:packs`, `npm run test:broll`, `npm run test:distribution`, `npm run test:trim`, and `node test/full-duration-smoke.mjs`.
- CLI smoke (offline heuristic): `npm run enhance -- examples/sample-captions.json`.
- There is no lint config or build step for the server; it runs directly from source.
- Deep docs: [`docs/INDEX.md`](docs/INDEX.md). Unmerged feature work: [`docs/IN_FLIGHT_BRANCHES.md`](docs/IN_FLIGHT_BRANCHES.md).
