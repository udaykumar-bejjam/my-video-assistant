# CaptionStudio

AI captions + Cursor SDK placement of stylish text, GIFs, PNGs, and sound effects — for **iOS** and **macOS**.

## Documentation

Deep project docs live under [`docs/INDEX.md`](docs/INDEX.md) (also [`docs/README.md`](docs/README.md)):

| Doc | Purpose |
|-----|---------|
| [INDEX](docs/INDEX.md) | Documentation hub |
| [ARCHITECTURE](docs/ARCHITECTURE.md) | Pipelines, persistence, invariants |
| [FEATURES](docs/FEATURES.md) | Shipped capabilities |
| [CODEBASE_MAP](docs/CODEBASE_MAP.md) / [FILE_INDEX](docs/FILE_INDEX.md) | Source maps |
| [DATA_MODEL](docs/DATA_MODEL.md) | Runtime + disk schema |
| [DEVELOPMENT](docs/DEVELOPMENT.md) | Build, test, release, debug |
| [ROADMAP](docs/ROADMAP.md) / [ENHANCEMENT_ROADMAP](docs/ENHANCEMENT_ROADMAP.md) | Planned enhancements |
| [TELUGU_ASR_PLAN](docs/TELUGU_ASR_PLAN.md) | Telugu / bilingual ASR |
| [CHESS_WALKTHROUGH](docs/CHESS_WALKTHROUGH.md) | PGN chess walkthrough |
| [CONTRIBUTING](docs/CONTRIBUTING.md) | Change rules / regressions |
| [AGENTS.md](AGENTS.md) | Cursor Cloud (Linux = Node only) |

## Architecture

```
Captions
  EN → Apple Speech
  TE → OpenAI Whisper (Apple has no Telugu Dictation)
  HI → Apple Speech, else Whisper
        │
        ▼
Enhancer server  ── @cursor/sdk (composer-2.5)
        │              asks: where to place what
        ▼
Asset libraries  ── text-styles / gifs / pngs / sfx
        │
        ▼
SwiftUI editor + AVFoundation export (burn-in + SFX mix)
```

| Piece | What it does |
|--------|----------------|
| Apple Speech | English (and Hindi when available) captions |
| OpenAI Whisper | Telugu + English mixed captions — paste API key in Brand Kit |
| `@cursor/sdk` | Agent decides **precise** placements from the transcript + catalogs |
| `AssetLibraries/` | Bundled libraries for stylish text, GIFs, PNGs, SFX |
| Swift app | Preview, manual library picks, export MP4 |

Without `CURSOR_API_KEY`, the enhancer returns the **same JSON schema** via a mood-tag heuristic so the app stays usable.

## Asset libraries

| Library | Path | Contents |
|---------|------|----------|
| Stylish text | `AssetLibraries/text-styles/` | Neon Punch, Mint Glow, Outline Impact, … |
| GIFs | `AssetLibraries/gifs/` | pop-burst, confetti, heart-pulse, slam-stomp, … (11 loops) |
| PNGs | `AssetLibraries/pngs/` | starburst, flame, bolt, heart, … |
| Sound FX | `AssetLibraries/sfx/` | whoosh, pop, ding, bass-hit, riser, … |
| Shorts Packs | `AssetLibraries/packs/` | Hook, Story, Tip, Hype, Tutorial recipes |

Catalogs are JSON (`catalog.json`). The same trees are copied into `CaptionStudio/Resources/Libraries` for the app bundle.

## Iconify sticker sync (optional)

Fetch open-license icons into the PNG library for auto B-roll:

```bash
cd tools/iconify-sync
npm install
npm start -- search fire
npm start -- add mdi:fire --tags power,hype,energy
npm start -- sync-moods          # power / reveal / emotion / numbers / cta
```

See `tools/iconify-sync/README.md`. Writes to `AssetLibraries/pngs/` and the app Resources copy.

## Download (macOS)

GitHub Actions builds an ad-hoc signed **CaptionStudio.app** zip:

1. Open [Releases](https://github.com/udaykumar-bejjam/my-video-assistant/releases) and download `CaptionStudio-macOS.zip`, **or**
2. Run workflow **Build macOS app** under [Actions](https://github.com/udaykumar-bejjam/my-video-assistant/actions/workflows/build-macos.yml) → download the artifact.

Install: unzip → drag to Applications → **right-click → Open** (Gatekeeper).  
Optional: `xattr -dr com.apple.quarantine /Applications/CaptionStudio.app`

Local build on a Mac:

```bash
./scripts/build-macos.sh
# → build/dist/CaptionStudio-macOS.zip
```

## Run the Cursor SDK enhancer

```bash
cd enhancer-server
npm install
export CURSOR_API_KEY="your-key"   # from https://cursor.com/dashboard/api
export OPENAI_API_KEY="sk-..."     # optional — Whisper proxy at POST /transcribe
npm start                          # http://127.0.0.1:8787
```

### Telugu captions (Whisper)

Apple Dictation does **not** include Telugu. In the Mac app:

1. Open **Brand Kit**
2. Paste an **OpenAI API key** ([create one](https://platform.openai.com/api-keys))
3. Select **తెలుగు + EN** → **AI Captions**

- `GET /health` — SDK status (+ `hasOpenAIKey`)  
- `GET /libraries` — catalogs  
- `POST /enhance` — `{ captions, duration, packId? }` → placement plan  
- `POST /transcribe` — Whisper proxy (`audioBase64`, needs `OPENAI_API_KEY`)  


CLI smoke test (offline heuristic):

```bash
npm run enhance -- examples/sample-captions.json
# with a Shorts Pack:
npm run enhance -- examples/sample-captions-hype.json
```

## Shorts Packs (one-tap recipes)

Pick a pack on Home / editor chrome / Export:

| Pack | Feel |
|------|------|
| Hook | Stop-the-scroll punches in first 3s |
| Story | Softer emotional emphasis |
| Tip | Clear teachable moments |
| Hype | Max energy (punch / color-pulse / stomp) |
| Tutorial | Step clarity (zoom / typepop) |

Selecting a pack sets **9:16**, caption style, and biases AI Place (`effectBias` / `sfxBias` / GIF density). The enhancer also guarantees an opening **hook** word hit + SFX, and auto-drops **B-roll stickers** (GIF/PNG) on strong words from the EN/HI/TE lexicon (power / reveal / emotion / numbers / CTA), capped per 15s.

**Animated GIFs (Phase 1):** Library GIFs play in preview (scrub-synced) and burn into export as looping frame sequences with transparency preserved.

**Animated GIFs (Phase 2):** Expanded transparent GIF library (11 loops) with mood tags; B-roll prefers GIF over PNG for power / emotion / reveal when a tagged GIF exists.

**Export burn-in:** Captions, word hits, stickers, and stylish text use Core Animation keyframe opacity (macOS-safe) so overlays actually appear in the MP4 — not only in preview.

**Canvas alignment:** Preview captions/overlays use the same aspect canvas as export (9:16 / 16:9 fill). Positions and font scale match the export frame — not a smaller player-intrinsic rect.

1. Open `CaptionStudio.xcodeproj` in Xcode 15+  
2. Start the enhancer (`npm start` above)  
3. Run on iPhone / simulator / My Mac  
4. Import or **Try Demo** → pick a **Shorts Pack** → **AI Captions** → **AI Place**  
5. Browse **Layers** (timeline lanes under the scrubber + start/end controls) / **Library** / **Trim** tabs or export  
6. **Save Draft** (Export tab or leave editor) — reopen from Home drafts list  
7. After export: copy **title / hashtags**, optional **cover PNG**, toggle **safe zone** in preview, **normalize loudness** on Export  

**AI Place** calls the enhancer. If the server is down, the app applies a local library heuristic. Placed word hits, stickers, text, and SFX appear as **timeline layers** you can select, retime, scale, or delete.

## Distribution, safe zones & loudness

- **Distribution:** enhance returns `title` / `coverText` / `hashtags` / `hookLine` — shown on Export + share sheet with one-tap copy and cover PNG export  
- **Safe zone:** Reels/TikTok chrome guide in preview (toggle); placements clamped in enhancer + Swift aligner  
- **Loudness:** optional peak normalize on export so dialogue + SFX stay consistent across daily posts  

## Languages, fonts & significant word hits

- **Languages:** English (Apple Speech); **Telugu + EN via OpenAI Whisper** (Apple has no Telugu Dictation); Hindi via Apple or Whisper fallback — see `docs/TELUGU_ASR_PLAN.md`
- **Fonts library:** Latin + Kohinoor Devanagari + Kohinoor Telugu (and ITF Devanagari)
- **Effects library:** slam, bounce, zoom, shake, spin, flash, rise, glitch, typepop, pulse
- **AI Place** returns a precise JSON plan:
  - `wordHits[]` — significant words with `fontId`, randomised `effectId`, paired `sfxId`, timed to word start/end
  - `placements[]` — supporting GIFs / text / SFX
- The app applies that response exactly (overlays + SFX cues + export burn-in)

## Aspect ratios & long videos

- **9:16** (1080×1920) and **16:9** (1920×1080) canvases — auto-inferred from the source, overridable in Export
- Source video is **center-cropped to fill** the chosen canvas
- Videos longer than **60s** are processed in **45s parts**:
  1. Enhance each part (with 1.5s caption context at boundaries)
  2. Export each part with local 0-based timelines
  3. **Stitch** parts with frame-accurate `AVMutableComposition` cuts
- Placements are deduped at chunk boundaries so assets don’t double up

## Timing-aware placements

Every library item carries measured metadata that Cursor (and the aligner) must respect:

| Kind | Metadata used for timing |
|------|---------------------------|
| **SFX** | Exact `durationSeconds` of the audio file → `endTime = startTime + length` |
| **GIF** | Full animation cycle length + pixel size → whole loops inside the caption window |
| **PNG** | Pixel size + default hold length → clipped to the active caption |
| **Text** | Estimated glyph box + hold length → rides the spoken caption window |

`startTime` snaps to the caption currently playing. Positions are clamped using each asset’s `normalizedWidth/Height` so stickers stay on-screen.


```json
{
  "summary": "…",
  "placements": [
    {
      "kind": "text|gif|png|sfx",
      "assetId": "neon-punch",
      "startTime": 1.2,
      "endTime": 2.8,
      "x": 0.5,
      "y": 0.28,
      "scale": 1,
      "rotation": -2,
      "text": "LET'S GO",
      "reason": "Hype beat on caption 2"
    }
  ]
}
```

Only `assetId`s that exist in the libraries are accepted.

## Requirements

- macOS 14+ / Xcode 15+  
- Node 22.13+ for `@cursor/sdk`  
- `CURSOR_API_KEY` for live Cursor agent placements (optional)
