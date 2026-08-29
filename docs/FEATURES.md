# CaptionStudio — Shipped features

User-facing capabilities on current `master`. Pair with [ARCHITECTURE.md](./ARCHITECTURE.md)
for how they are wired.

---

## Home

- Brand landing (CaptionStudio) with atmospheric background
- **Import Video** (PhotosPicker on iOS / file importer on macOS)
- **Try Demo** — synthetic timed captions + demo reel
- **Shorts Pack** chips (Hook, Story, Tip, Hype, Tutorial)
- **Saved projects** list — resume clock, caps/overlays/SFX summary, language badge
- **Open package** — import a `.captionstudio` folder (`project.json` + video)

---

## Captions

- **AI Captions** — on-device Apple Speech (EN / Hindi / Telugu locales)
- Word-level timings when Speech provides them
- Demo captions if permission / recognizer unavailable
- Caption list: edit text, delete, scrub to segment
- Styles: Bold White, Neon, Boxed, Outline, Soft Shadow, lowercase, UPPER
- Animations in preview: none / fade / pop / bounce / karaoke / typewriter
- Export burn-in matches style (including karaoke / typewriter on master)

---

## AI Place

- Calls local enhancer (`127.0.0.1:8787`) or falls back to Swift heuristic
- **Full-duration** word hits (every caption window; gap-fill after sparse plans)
- Opening **hook** (visual + SFX) inside pack hook window (~3s)
- Pack-biased effects / SFX pools
- Auto **B-roll** GIF/PNG on strong lexicon words (power / reveal / emotion /
  numbers / CTA); GIF preferred for power/emotion/reveal when available
- Returns **distribution** copy (title, hashtags, cover, hook line)
- Long videos: enhance per 45s chunk, merge, dedupe

---

## Layers & timeline

- Multi-lane scrubber: Caps / Hits / Stick / Text / **Audio** / **SFX** / Trim
- Layers tab: visual overlays (start/end/scale) + **Audio layer panel**
- Select lane items → seek + focus inspector
- Drag overlays on preview to reposition

---

## Audio layer

- Enhancer presets: Balanced / Podcast / Hype / Quiet
- Dialogue gain, SFX bus gain
- Normalize loudness (export peak match)
- Duck dialogue under SFX (+ duck amount)
- Every timeline SFX listed: start, gain, mute, preview
- Settings persist on project and drive export mix

---

## Library

Browse and place:

| Kind | Place as |
|------|----------|
| Text styles | Stylish text overlay |
| GIFs | Animated sticker (preview scrub + export frames) |
| PNGs | Still sticker |
| SFX | Timed cue on audio layer |
| Fonts / effects | Used by word hits / styles |

Optional: `tools/iconify-sync` imports Iconify icons into PNG catalogs.

---

## Trim assist

- Suggest silence gaps and EN/HI/TE filler tokens
- User selects suggestions → apply composition trim
- Captions / overlays / SFX times shift through keep ranges

---

## Brand kit

- Primary / Hindi / Telugu font ids, colors, watermark, default pack/language,
  default SFX gain
- Stored in UserDefaults (app-wide, not per-project)
- Watermark regenerated on open from current kit

---

## Export & share

- Aspect: 9:16 and 16:9 (pack default applied)
- Batch export: one file per checked aspect
- Normalize loudness toggle (wired to `project.audio`)
- Chunked export + stitch for long timelines
- Share sheet: video files, copy title/hashtags/hook, export cover PNG
- Safe-zone guide toggle in preview

---

## Project save / load

- **Save** in editor chrome + Export tab
- Leave dialog: Save Project & Leave / Discard
- JSON project folder under Application Support `Projects/`
- Session restore: playhead, tab, selections, audio-layer focus
- macOS **Export package…** → portable `.captionstudio`

---

## Platforms & distribution

| Target | Notes |
|--------|-------|
| macOS 14+ | Primary; GitHub Releases zip (ad-hoc signed) |
| iOS 17+ | Same codebase; Photos import |

Enhancer optional for Cursor SDK quality; heuristic works offline.
