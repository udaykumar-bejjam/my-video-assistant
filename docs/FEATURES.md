# Feature catalog (`master`)

User-facing and system features on **`master`**. Unmerged capabilities: [IN_FLIGHT_BRANCHES.md](./IN_FLIGHT_BRANCHES.md). File ownership: [CODEBASE_MAP.md](./CODEBASE_MAP.md).

---

## 1. Project lifecycle

| Feature | Behavior |
|---------|----------|
| Import video | Home → caches → `EditorViewModel.loadVideo` |
| Try Demo | Sample project without user media |
| Drafts | Save / reopen / delete (`ProjectStore`) |
| Project package | Export/import portable package |
| Leave without saving | Clears session → Home |

---

## 2. Captions

| Language | Engine (master) |
|----------|-----------------|
| English | Apple Speech |
| Hindi (when available) | Apple Speech |
| Other locales in picker | Apple Speech when system supports |

**Flow:** **AI Captions** → segments on Caps lane → edit in Captions tab → style presets.

---

## 3. Shorts Packs

**Hook / Story / Tip / Hype / Tutorial** — bias 9:16, caption style, enhance density (effects / SFX / GIFs), early hook hit + SFX, lexicon B-roll caps.

UI: Home, editor chrome, Export (`PackPickerView`).

---

## 4. AI Place (enhance)

Sends captions + duration (+ pack, brand, safe zone, language, video size) to `POST /enhance`.

Returns placements, word hits, distribution copy, safe zone — same schema for Cursor agent or heuristic.

**Fallbacks:** no API key → server heuristic; server down → app-local heuristic.

**Long media (>60s):** ~45s chunks with boundary context → per-chunk export → stitch; dedupe placements at seams.

---

## 5. Libraries & overlays

Text styles, fonts, effects, GIFs (preview scrub-synced + export frames), PNGs, SFX (timed mix on export).

Manual: **Library** tab. Edit: **Layers** + scrubber lanes. Timing metadata (SFX duration, GIF loop, clamp on-canvas) respected by aligner + server.

---

## 6. Timeline (master scrubber)

`TimelineScrubber` in `EditorView` shows Caps / Hits / Stickers / Text / Audio / SFX (+ trim marks). Tap selects; detailed retime in Layers (`OverlayEditorView`).

*(Zoomable cross-lane drag workspace is in-flight — not on master.)*

---

## 7. Trim

Heuristic suggestions → multi-select → apply via `VideoTrimComposer`. Re-run captions/enhance after structural cuts when timings drift.

---

## 8. Preview

`AVPlayer` + overlays; optional safe-zone guide; preview SFX triggers. Canvas matches export aspect (9:16 / 16:9 fill).

---

## 9. Brand kit

Colors / fonts / watermark → enhance payload + optional watermark overlay (`BrandKitSettingsView`).

---

## 10. Export & distribution

Burn-in MP4 (captions, word hits, stickers, text), SFX mix, optional peak loudness normalize, 9:16/16:9 (batch multi-aspect), cover PNG, copy title/hashtags/hook.

---

## 11. Enhancer HTTP

| Endpoint | Role |
|----------|------|
| `GET /health` | Status |
| `GET /libraries` | Catalogs (+ static under `/libraries/...`) |
| `POST /enhance` | Placement plan |

CLI: `npm run enhance -- examples/sample-captions.json`

---

## Happy path (Shorts)

1. Optional: `cd enhancer-server && npm start`
2. Open app → import/demo → pick pack (e.g. Hype)
3. **AI Captions** → **AI Place** → tune Layers
4. Trim if needed → Export → copy distribution fields
