# Telugu captions without Apple Speech

## Problem
Apple Dictation / `SFSpeechRecognizer` does **not** ship a Telugu (`te-IN`) model on many Macs. Dual-pass Apple ASR cannot caption Telugu audio.

## Decision
Use **OpenAI Whisper** for Telugu (and as Hindi fallback when Apple’s pack is missing). Keep Apple Speech for English.

| Option | Verdict |
|--------|---------|
| Apple Speech `te-IN` | Blocked — language unavailable |
| OpenAI Whisper API | **Chosen** — strong Tanglish, small change, word timestamps |
| Local whisper.cpp | Deferred — large zip / packaging cost |
| Google Cloud STT | Viable later — heavier GCP setup |

## Architecture
```
Video → extract M4A (AVFoundation)
     → OpenAI Whisper (whisper-1, verbose_json + word timestamps)
     → CaptionSegment / CaptionWord
     → existing editor / enhance / export
```

English still uses on-device Apple Speech (no API key).

## User setup
1. Get an API key from https://platform.openai.com/api-keys
2. Home screen / **Add API Key** → paste OpenAI key
3. Select **తెలుగు + EN (Whisper)** → **AI Captions**

Optional: `export OPENAI_API_KEY=...` and run enhancer (`POST /transcribe`) as a localhost proxy.

## Kannada mix-up / `language=te` 400
OpenAI **whisper-1 does not support Telugu** (`language=te` → `unsupported_language`).
It *does* support Kannada — so auto-detect often emits Kannada for Telugu audio.

CaptionStudio therefore uses **`gpt-transcribe`** with `languages[]=te` + `languages[]=en` for Telugu,
and never sends `language=te` to whisper-1.

## Timing (no word clocks from gpt-transcribe)
`gpt-transcribe` returns text only. CaptionStudio:
1. Uses the **video timeline duration** as a **cap** (never pack into a wrong short window)
2. Stamps words at a **natural speaking rate** — does **not** stretch a short transcript across the full video (that made on-timeline captions late)
3. Holds each caption line until the next (extends end only); slight anticipation so overlays aren't late
4. Word hits hold ~1.6–2.8s through the caption window

**After updating the app, re-run AI Captions** (then AI Place) — old timings stay baked in the project.
