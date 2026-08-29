# Data Model Reference

Canonical types live in Swift under `CaptionStudio/Models/`. This document summarizes shape and persistence for humans and future agents.

---

## VideoProject (runtime)

In-memory project while editing.

| Field | Type | Notes |
|-------|------|--------|
| `id` | UUID | Stable identity |
| `sourceURL` | URL | Local video file |
| `duration` | TimeInterval | Authoritative length |
| `transcript` | [TranscriptSegment] | Timed dialogue |
| `captionStyle` | CaptionStyle | Typography/theme |
| `brollClips` | [BrollClip] | AI / manual B-roll |
| `stickers` | [StickerOverlay] | Emoji overlays |
| `textOverlays` | [TextOverlay] | Styled text |
| `soundEffects` | [SoundEffect] | Timed SFX |
| `audioSettings` | ProjectAudioSettings | Mix / enhancers |
| `aspectRatio` | AspectRatio | Export framing |
| `createdAt` / `modifiedAt` | Date | Bookkeeping |

---

## SavedProject (disk JSON)

Serializable mirror of `VideoProject` plus:

| Field | Purpose |
|-------|---------|
| `version` | Schema version for migrations |
| `mediaFolderName` | Relative media bundle name |
| `relativeVideoPath` | Video inside package / beside JSON |
| `session` | `ProjectSessionState` — playhead, tab, selections |

Written by `ProjectStore` as pretty-printed JSON.

### ProjectSessionState

| Field | Purpose |
|-------|---------|
| `playhead` | Resume time |
| `selectedTab` | Editor chrome tab |
| `selectedOverlayId` | Last overlay focus |
| `selectedCaptionIndex` | Caption list selection |
| (other UI keys as added) | Keep additive / optional |

---

## Overlay hierarchy (conceptual)

```
Overlay (protocol / shared fields)
├── position (normalized 0–1, Y-down in export)
├── size / scale
├── startTime / endTime
├── opacity / animations
├── BrollClip
├── StickerOverlay
├── TextOverlay
└── (GIF/PNG instances as specialized media overlays)
```

Exact struct names: see `Overlay.swift`, `MediaLibrary.swift`.

---

## Audio

### ProjectAudioSettings

| Concept | Behavior |
|---------|----------|
| Dialogue gain | Scale speech/original |
| SFX gain | Scale effect layer |
| Normalize | Peak/loudness pass when enabled |
| Duck | Lower dialogue under SFX windows |
| Mute skip | Omit muted regions from export mix |
| Preset | `AudioEnhancerPreset` quick looks |

### SoundEffect

Timed clip: asset ref, start, duration, volume, mute flag.

---

## Captions

### TranscriptSegment

Word- or phrase-level timing used by:

- On-canvas caption rendering
- Karaoke / typewriter modes
- Enhancer word-hit alignment

### CaptionStyle

Fonts, colors, highlight, shadow, animation mode (including karaoke/typewriter export paths).

---

## Enhancer wire format (high level)

**Request (typical):** video metadata + duration + optional transcript + place intent.

**Response (typical):**

- Phrase captions (full duration)
- Word hits (must span same duration — do not clamp to 10s)
- Overlay plans (B-roll, stickers, text, SFX)
- Optional GIF/PNG library picks

Client merges into `VideoProject` without truncating timelines.

---

## Package layout (.captionstudio)

```
MyEdit.captionstudio/
  project.json          # SavedProject
  media/                # or equivalent folder name
    video.mp4
    overlays/...
    audio/...
```

Import copies into Application Support and opens as a normal project.

---

## Schema evolution rules

1. **Additive first** — new optional fields with defaults.
2. Bump `version` when meaning of existing fields changes.
3. Migrate in `ProjectStore` load path; never crash on old files.
4. Document migrations in this file when they ship.
