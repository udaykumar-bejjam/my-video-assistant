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

- **AI Captions**
  - English → on-device Apple Speech
  - **Telugu + EN** → OpenAI (`gpt-transcribe` + `whisper-1` clocks); paste key via Home / Brand Kit (`APIKeyStore`)
  - Hindi → Apple when available, else Whisper
- Word-level timings when the engine provides them
- Demo captions if permission / recognizer unavailable (EN)
- Caption list: edit text, delete, scrub to segment
- Styles: Bold White, Neon, Boxed, Outline, Soft Shadow, lowercase, UPPER
- Animations in preview: none / fade / pop / bounce / karaoke / typewriter
- Export burn-in matches style (including karaoke / typewriter)

---

## AI Place

- Calls local enhancer (`127.0.0.1:8787`) or falls back to Swift heuristic
  aligned to the same **parity-contract v1** as the Node offline path
  (`AssetLibraries/heuristic/parity-contract.json`)
- **Full-duration** word hits (every caption window; gap-fill after sparse plans)
- Opening **hook** (visual + SFX) inside pack hook window (~3s)
- Pack-biased effects / SFX pools
- Auto **B-roll** GIF/PNG on strong lexicon words (power / reveal / emotion /
  numbers / CTA); GIF preferred for power/emotion/reveal when available
- Returns **distribution** copy (title, hashtags, cover, hook line)
- Long videos: enhance per 45s chunk, merge, dedupe

---

## Layers & timeline

- **`TimelineWorkspaceView`** — zoomable multi-lane workspace (fit media+1h → ~frame zoom)
- **Multi-select** — Multi toggle or Shift/⌘-click; drag moves the selection together (same kind)
- **Snap guides** — cyan line when edges snap to playhead, media bounds, or sibling clips
- Drag L/R to retime; drag across lanes to change kind / bring-to-front (`applyTimelineDrag`)
- Lanes: Caps / Hits / Stick / Text / **Audio** / **SFX** (+ trim marks)
- Layers tab: visual overlays (start/end/scale) + **Audio layer panel**
- Select lane items → seek + focus inspector
- Drag overlays on preview to reposition

---

## Chess Walkthrough

- Home **Chess Walkthrough** or editor checkerboard button
- Paste PGN / move list → animated Unicode board, category colors, arrows, boxes, SFX
- **Import** from `.pgn` file, Lichess URL, or chess.com live/daily game URL
- Classification from annotations / NAGs / checks, then **heuristic or Stockfish eval** for remaining moves
- **Export MP4** of the walkthrough alone, or **Attach to video** to composite a corner board onto the project timeline (preview + burn-in + SFX)
- Details: [CHESS_WALKTHROUGH.md](./CHESS_WALKTHROUGH.md)

---

## Undo / redo

- Editor chrome undo / redo (⌘Z / ⇧⌘Z on Mac)
- Covers captions, overlays, AI Place apply, timeline drag, library place, trim apply, audio settings

---

## Audio layer

- Enhancer presets: Balanced / Podcast / Hype / Quiet
- Dialogue gain, SFX bus gain
- Normalize loudness (export **−14 LUFS** BS.1770 + peak ceiling; peak fallback if clip too short)
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

- Aspect: **9:16**, **16:9**, and **1:1** (pack default applied; Export picker + batch checkboxes)
- Batch export remaps overlays (and chess board layout) through aspect safe zones
- Switching aspect in Export remaps live overlays (undoable)
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

## Captions — Telugu / bilingual (Whisper)

- English: on-device Apple Speech
- Telugu (+ Tanglish): OpenAI **gpt-transcribe** + **whisper-1** word clocks (never `language=te` on whisper-1)
- Hindi: Apple Speech when available, else Whisper fallback
- OpenAI API key via Brand Kit / Home sheet (`APIKeyStore`)
- Details: [TELUGU_ASR_PLAN.md](./TELUGU_ASR_PLAN.md)

---

## Timeline workspace

- Zoomable multi-lane timeline (`TimelineWorkspaceView`)
- Drag to retime; cross-lane drag between caption / overlay lanes
- Orange media-end marker; pad beyond media for zoom-out

---

## Chess Walkthrough

- Home / editor → paste PGN or move list
- Animated Unicode board, category colors, arrows, boxes, callouts, SFX
- Annotation-based classification (no Stockfish yet); not burned into export yet
- Details: [CHESS_WALKTHROUGH.md](./CHESS_WALKTHROUGH.md)

---

## Platforms & distribution

| Target | Notes |
|--------|-------|
| macOS 14+ | Primary; GitHub Releases zip (ad-hoc signed) |
| iOS 17+ | Same codebase; Photos import |

Enhancer optional for Cursor SDK quality; heuristic works offline.
