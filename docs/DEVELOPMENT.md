# Development Guide

How to build, run, test, and ship CaptionStudio.

---

## Prerequisites

| Tool | Purpose |
|------|---------|
| **Xcode 15+** (macOS) | Native app build |
| **Node.js 18+** | Enhancer server |
| **ffmpeg / ffprobe** | Optional local audio normalize; required in CI for macOS zip |
| **GitHub Actions** | Release packaging |

---

## Native app (Xcode)

### Open

```bash
open CaptionStudio.xcodeproj
```

### Schemes / destinations

- Target: **CaptionStudio**
- Destinations: iPhone simulator, Mac (Designed for iPhone / Mac Catalyst as configured)

### Build from CLI

```bash
# Simulator (example)
xcodebuild -scheme CaptionStudio \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build

# macOS (when Mac destination available)
xcodebuild -scheme CaptionStudio \
  -destination 'platform=macOS' \
  build
```

Cloud Linux agents **cannot** compile the Swift app; use GitHub Actions for unsigned macOS zips.

### Adding Swift files

1. Create the `.swift` file under the correct folder.
2. **Add it to the CaptionStudio target** in Xcode (Membership).
3. Confirm it appears in `project.pbxproj` `PBXSourcesBuildPhase`.
4. Missing membership → compile succeeds for some files but runtime/linker issues, or CI fails with “cannot find type in scope”.

Known gotcha: GIF-related files (`AnimatedGIF*`, `GIFTimelineLaneView`) must stay in the target.

---

## Enhancer server

```bash
cd enhancer-server
npm install
npm start
# → http://127.0.0.1:8787
```

### Env vars (common)

| Variable | Effect |
|----------|--------|
| `PORT` | Listen port (default 8787) |
| `OPENAI_API_KEY` | Live LLM for place planning / captions |
| `CAPTION_STUDIO_REQUIRE_OPENAI` | Fail closed if key missing (production-ish) |
| `CAPTION_STUDIO_ALLOW_OFFLINE` | Explicit offline/fixture mode |

Without a key, the server uses **fixture** planners so local demos still work.

### Smoke tests

```bash
cd enhancer-server
node test/full-duration-smoke.mjs   # duration + word hits
node test/gif-phase2-smoke.mjs      # GIF library shape
# npm test if package.json defines a suite
```

---

## Project save format (for manual debugging)

Pretty JSON at:

```
~/Library/Application Support/CaptionStudio/Projects/<id>.json
```

Package for sharing:

```
Something.captionstudio/project.json
```

Validate by opening in Home → Saved projects, or File → Open Package.

---

## Release (macOS zip)

1. Bump `CFBundleShortVersionString` / `CFBundleVersion` in `Info.plist` if needed.
2. Tag: `git tag vX.Y.Z && git push origin vX.Y.Z`
3. Workflow: `.github/workflows/macos-unsigned-release.yml`
4. Artifact: `CaptionStudio-macOS.zip` on the GitHub Release

Requires available macOS runners. If jobs stay **Queued**, wait or retry; previous tags (e.g. v1.0.6) remain downloadable.

---

## Git / PR conventions (this repo’s cloud agents)

- Feature branches: `cursor/<descriptive-name>-ce40`
- Base: `master`
- Prefer small, reviewable PRs with regression notes for export/duration/GIF

---

## Debugging checklist

| Symptom | Check |
|---------|--------|
| AI Place only covers ~8–10s | Client `prefix(8)`; JS `Number(duration)\|\|10`; stitch remnant |
| Export captions wrong mid-video | Word hits empty → Swift fill; enhancer clamp |
| Overlays invisible in export | Opacity animation must be **CAKeyframeAnimation** |
| Preview ≠ export position | Canvas fit / letterbox / Y flip |
| GIF won’t compile | pbxproj membership |
| Save doesn’t restore playhead | `session` block missing / `ProjectStore` not writing |
| Audio duck not hearing | Duck windows empty; SFX muted; gains at 0 |
| Enhancer 500s | Server log; OpenAI key; offline fixtures |

---

## Useful references

- [ARCHITECTURE.md](./ARCHITECTURE.md)
- [FEATURES.md](./FEATURES.md)
- [FILE_INDEX.md](./FILE_INDEX.md)
- [ROADMAP.md](./ROADMAP.md)
