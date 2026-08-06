# CaptionStudio

AI captions + Cursor SDK placement of stylish text, GIFs, PNGs, and sound effects — for **iOS** and **macOS**.

## Architecture

```
Captions (Apple Speech)
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
| Apple Speech | Timed captions from video audio |
| `@cursor/sdk` | Agent decides **precise** placements from the transcript + catalogs |
| `AssetLibraries/` | Bundled libraries for stylish text, GIFs, PNGs, SFX |
| Swift app | Preview, manual library picks, export MP4 |

Without `CURSOR_API_KEY`, the enhancer returns the **same JSON schema** via a mood-tag heuristic so the app stays usable.

## Asset libraries

| Library | Path | Contents |
|---------|------|----------|
| Stylish text | `AssetLibraries/text-styles/` | Neon Punch, Mint Glow, Outline Impact, … |
| GIFs | `AssetLibraries/gifs/` | pop-burst, confetti, pulse-ring, … |
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
npm start                          # http://127.0.0.1:8787
```

- `GET /health` — SDK status  
- `GET /libraries` — catalogs  
- `POST /enhance` — `{ captions, duration, packId? }` → placement plan  

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

1. Open `CaptionStudio.xcodeproj` in Xcode 15+  
2. Start the enhancer (`npm start` above)  
3. Run on iPhone / simulator / My Mac  
4. Import or **Try Demo** → pick a **Shorts Pack** → **AI Captions** → **AI Place**  
5. Browse **Library** / **Trim** tabs or export  
6. **Save Draft** (Export tab or leave editor) — reopen from Home drafts list  
7. After export: copy **title / hashtags**, optional **cover PNG**, toggle **safe zone** in preview, **normalize loudness** on Export  

**AI Place** calls the enhancer. If the server is down, the app applies a local library heuristic.

## Distribution, safe zones & loudness

- **Distribution:** enhance returns `title` / `coverText` / `hashtags` / `hookLine` — shown on Export + share sheet with one-tap copy and cover PNG export  
- **Safe zone:** Reels/TikTok chrome guide in preview (toggle); placements clamped in enhancer + Swift aligner  
- **Loudness:** optional peak normalize on export so dialogue + SFX stay consistent across daily posts  

## Languages, fonts & significant word hits

- **Languages:** English, Hindi (`hi-IN`), Telugu (`te-IN`) — Speech locale + demo captions
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
