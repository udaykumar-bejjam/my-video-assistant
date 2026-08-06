# CaptionStudio — Shorts Maker Feature Plan

Plan for day-to-day short-form creation on top of the current CaptionStudio stack (Speech captions, Cursor SDK placements, fonts/effects/SFX libraries, 9:16 & 16:9, chunked stitch).

**Goal:** go from raw clip → engaging short with as few taps as possible, every day.

---

## Current baseline (already shipped)

| Capability | Status |
|------------|--------|
| Import / demo video | Done |
| AI captions (Apple Speech) + EN/Hindi/Telugu | Done |
| Cursor SDK / heuristic placements | Done |
| Fonts, effects, GIF/PNG/SFX libraries | Done |
| Significant word hits (punch, color-pulse, etc.) | Done |
| 9:16 & 16:9 canvases | Done |
| Long-video chunk → enhance → stitch | Done |
| MP4 export + share | Done |

---

## Product pillars

1. **Speed** — daily posting in a few taps  
2. **Engagement** — hooks, punches, SFX on the right words  
3. **Consistency** — brand kit + loudness + safe zones  
4. **Distribution** — multi-aspect export + titles/hashtags/cover  

---

## Phase A — One-tap Shorts Pack (highest leverage)

### A1. Shorts Pack templates
**Status:** Shipped (app + enhancer)

**What:** Preset creative recipes: `Hook`, `Story`, `Tip`, `Hype`, `Tutorial`.  
**User flow:** Import → pick pack → AI Captions (if needed) → AI Place with pack rules → preview → export 9:16.

**Pack config (JSON in `AssetLibraries/packs/`):**
```json
{
  "id": "hype",
  "aspect": "9:16",
  "captionStyle": "upperPunch",
  "effectBias": ["punch", "color-pulse", "stomp", "slam"],
  "sfxBias": ["bass-hit", "riser", "whoosh"],
  "wordHitsPerCaption": 2,
  "requireHookInFirstSeconds": 3,
  "gifDensity": "medium"
}
```

**AI contract additions:**
- `packId` on enhance request  
- Response must honor pack biases (effect/sfx pools, hook window)

**Acceptance:**
- One tap after captions produces word hits + SFX + overlays matching the pack  
- Default export aspect = pack aspect  

**Depends on:** existing enhance pipeline  
**Touches:** `enhancer-server`, `EditorViewModel`, new `PackLibrary`, Home/Export UI  

---

### A2. Hook detector (first 1–3s)
**Status:** Shipped with A1 (`ensureOpeningHook` in enhancer + local Swift fallback)

**What:** Force a retention hook at the open.

**Logic:**
1. Take captions/words with `startTime < 3`  
2. Score significance (length, emotion/power lexicon per language)  
3. Guarantee ≥1 `wordHit` + `riser`/`bass-hit` SFX in that window  
4. Optional stylish text: “WAIT” / localized equivalent if no strong word  

**AI contract:**
```json
{
  "hook": {
    "word": "…",
    "startTime": 0.4,
    "endTime": 1.1,
    "effectId": "punch",
    "sfxId": "riser",
    "fontId": "…",
    "reason": "Opening retention hook"
  }
}
```

**Acceptance:** Every Shorts Pack export has an audible+visual hook in the first 3 seconds  

**Depends on:** A1 (or can ship standalone)  
**Touches:** `alignWordHit` / heuristic, enhance prompt, apply()  

---

### A3. Auto B-roll / sticker moments
**What:** On strong words, auto-drop GIF/PNG + SFX without scrubbing.

**Trigger lexicon (per language):** power, reveal, emotion, numbers, CTA  
**Rules:**
- Max N stickers per 15s to avoid clutter  
- Prefer library tags matching mood  
- Place in safe corners (see C2)  
- Time to word start; length = asset `lengthSeconds`

**AI contract:** existing `placements[]` with stronger “must pair wordHit ↔ gif/png” rule  

**Acceptance:** Strong words get a sticker+SFX ≥70% of the time in heuristic/SDK tests  

---

### A4. Batch export presets
**Status:** Shipped

**What:** From one timeline, export:
- `reels` → 9:16 1080×1920  
- `youtube` → 16:9 1920×1080  
- Optional `square` later (1:1)

**UI:** Export → checkboxes → “Export all”  
**Implementation:** Reuse chunk/stitch path; change `aspect` per pass; same overlays (normalized coords already canvas-relative — may need light Y remap for 16:9 vs 9:16)

**Acceptance:** Two files from one project without re-running AI Place  

**Depends on:** aspect system (done)  
**Risk:** Overlay Y positions tuned for 9:16 may feel high/low on 16:9 — add pack-aware or aspect-aware position remap  

---

## Phase B — Daily workflow speed

### B1. Project history / drafts
**Status:** Shipped (Application Support Drafts + Home list + Save Draft / leave save)

**What:** Save/load projects (video bookmark, captions, overlays, SFX, aspect, language, pack).

**Storage:**
- App Support / Documents JSON + copy of imported video hash/path  
- List on Home: thumbnail, title, duration, last edited  

**Model:** `SavedProject` Codable beside `VideoProject`  

**Acceptance:** Kill app → reopen draft → scrub → export without re-transcribe  

---

### B2. Brand kit
**Status:** Shipped (on-device UserDefaults)

**What:** User defaults applied to every new project.

```json
{
  "primaryFontId": "latin-heavy",
  "hindiFontId": "hindi-bold",
  "teluguFontId": "telugu-bold",
  "primaryColor": "#FFEF5A",
  "secondaryColor": "#FF2D2D",
  "watermarkText": "@handle",
  "watermarkPosition": { "x": 0.85, "y": 0.92 },
  "defaultPackId": "hype",
  "defaultLanguage": "hi-IN",
  "defaultSfxGain": 0.8
}
```

**UI:** Settings → Brand Kit  
**Apply:** On new project + as soft constraints in enhance prompt (`preferBrandKit: true`)  

**Acceptance:** New projects inherit kit; watermark burned on export  

---

### B3. Language lock per project
**Status:** Shipped (`VideoProject.language` sticky with editor language)

**What:** Language is sticky on the project (already partially there via `editor.language`).

**Finish:**
- Persist on `VideoProject` / drafts  
- Home shows language badge  
- Enhance + Speech always use project language  

**Acceptance:** Switching projects restores that project’s language  

---

### B4. Silence / filler trim assist
**Status:** Shipped (v1 suggestions + confirm; applies composition trim + cue shift)

**What:** Suggest cuts for long pauses and filler (`um`, `uh`, Hindi/Telugu fillers).

**Approach (v1 — non-destructive):**
- Detect gaps between words > threshold (e.g. 0.45s)  
- Detect filler tokens from word list  
- Present “Trim suggestions” timeline markers  
- User accepts → rebuild composition by removing ranges, shift all captions/overlays/SFX  

**v2:** Auto-apply with undo  

**Depends on:** word-level timings (done for demos/Speech)  
**Touches:** new `TrimService`, timeline UI, export source ranges  

**Risk:** Aggressive auto-trim can chop breaths — keep human confirm in v1  

---

## Phase C — Growth & polish

### C1. Title + hashtags + cover text
**What:** From transcript, Cursor SDK returns:

```json
{
  "distribution": {
    "title": "…",
    "coverText": "…",
    "hashtags": ["#…"],
    "hookLine": "…"
  }
}
```

**UI:** Post-export sheet — copy buttons, optional cover frame export (first frame + coverText overlay)  

**Acceptance:** Copy title/hashtags in one tap; optional cover PNG/MP4 frame  

---

### C2. Safe-zone guide
**What:** Overlay guides for TikTok/Reels UI chrome (bottom caption bar, right buttons, top status).

**Implementation:**
- Semi-transparent safe rect in preview (toggle)  
- Enhancer prompt: keep `wordHit`/`gif` centers inside safe rect  
- Clamp in `alignWordHit` / `alignPlacement`  

**Acceptance:** AI/heuristic placements stay inside safe zone; preview shows guide  

---

### C3. Loudness normalize
**What:** Consistent dialogue + SFX levels across daily posts.

**v1:**  
- Measure dialogue loudness (AVAudio / Accelerate peek/RMS)  
- Apply `AVMutableAudioMix` input gains so voice ≈ target LUFS-ish (approx)  
- Cap SFX gain relative to voice (brand kit `defaultSfxGain`)  

**v2:** True LUFS with more accurate metering  

**Acceptance:** Exports don’t clip; SFX sit under voice consistently  

---

## Recommended build order (by dependency)

```text
A1 Shorts Pack
  ├─ A2 Hook detector
  ├─ A3 Auto B-roll density rules
  └─ A4 Batch export presets
B3 Language lock (small, parallel)
B2 Brand kit (feeds A1 prompt constraints)
B1 Drafts / history
B4 Trim assist
C2 Safe-zone (feeds A1/A3 clamping)
C1 Distribution copy + cover
C3 Loudness normalize
```

Ship value early: **A1 → A2 → A4 → B2 → B1**, then B4/C*.

---

## Shared architecture changes

### Enhancer request (extend)
```json
{
  "captions": [],
  "duration": 0,
  "language": "hi-IN",
  "videoSize": { "width": 1080, "height": 1920 },
  "packId": "hype",
  "brandKit": {},
  "safeZone": { "xMin": 0.08, "xMax": 0.92, "yMin": 0.12, "yMax": 0.78 },
  "options": {
    "requireHook": true,
    "hookWindowSeconds": 3,
    "maxStickersPer15s": 3
  }
}
```

### Enhancer response (extend)
```json
{
  "summary": "…",
  "packId": "hype",
  "hook": { },
  "wordHits": [ ],
  "placements": [ ],
  "distribution": {
    "title": "…",
    "coverText": "…",
    "hashtags": []
  },
  "trimSuggestions": [
    { "startTime": 4.2, "endTime": 5.1, "reason": "silence" }
  ]
}
```

App rule: **validate → align → apply** remains the single edit path (`allEdits`).

### New modules (Swift)
| Module | Role |
|--------|------|
| `PackLibrary` | Load packs JSON |
| `BrandKitStore` | UserDefaults / file |
| `ProjectStore` | Drafts persistence |
| `HookPlanner` | Guarantee opening hit |
| `TrimService` | Gap/filler detection + timeline shift |
| `SafeZone` | Rect + clamp |
| `AudioNormalizeService` | Gain / mix |
| `DistributionService` | Title/hashtags/cover |

### New libraries (assets)
- `AssetLibraries/packs/*.json`  
- Optional `AssetLibraries/lexicons/{en,hi,te}.json` for significant words + fillers  

---

## Testing plan

| Area | How |
|------|-----|
| Packs | Fixture captions × each pack → assert effect/sfx pools + hook present |
| Languages | EN/HI/TE demos → fonts script tags match |
| Batch export | Same project → 9:16 + 16:9 files exist, durations match |
| Drafts | Save/load round-trip Codable equality |
| Trim | Synthetic gaps → suggested ranges; apply → duration decreases, cues shift |
| Safe zone | Random placements clamped inside rect |
| Loudness | Peak sample under ceiling after normalize |

---

## Explicit non-goals (for now)

- Full multi-track NLE  
- Cloud render farm  
- Stock B-roll marketplace  
- Auto eye-contact / AI avatar (Captions-app extras)  
- Collaborative editing  

---

## Decision checkpoints (ask before building)

1. **Packs first vs Drafts first?** Recommendation: Packs (A1) — daily time saved immediately.  
2. **Trim v1: suggestions only or auto-apply?** Recommendation: suggestions + confirm.  
3. **Brand kit storage:** on-device only vs iCloud later? Recommendation: on-device first.  
4. **Cover export:** still image vs 1s motion bumper? Recommendation: still + optional 1s.  

---

## Success metrics (product)

- Time from import → share under a short daily routine (few taps)  
- Every export has: captions + ≥1 hook hit + branded look  
- Dual-aspect export without re-edit  
- Reopen yesterday’s draft in one tap  

When you’re ready to implement, start with **Phase A1 (Shorts Pack)** and we can build it end-to-end on the current branch.
