# CaptionStudio

AI captions and overlays for short video — a Captions-style editor for **iOS** and **macOS**.

Built with SwiftUI + AVFoundation + Apple's on-device Speech framework.

## Features

- **Import video** from Files / Photos (or tap **Try Demo** for a generated reel)
- **AI Captions** — on-device speech-to-text with timed segments and word-level karaoke
- **Caption styles** — Bold White, Neon, Boxed, Outline, Soft Shadow, lowercase, UPPER
- **Animations** — fade, pop, karaoke highlight, typewriter, bounce
- **Overlays** — timed text, emojis, and shapes (drag on the preview)
- **Export MP4** — burned-in captions + overlays via Core Animation composition
- **Share sheet** when export finishes

Demo captions appear automatically if Speech permission is denied or the simulator has no recognizer — so you can explore the UI anywhere.

## Requirements

- macOS 14+ with **Xcode 15+**
- iOS 17+ / macOS 14+ deployment targets
- Physical device recommended for real speech recognition (Simulator often falls back to demo captions)

## Open & run

1. Clone this repo on a Mac
2. Open `CaptionStudio.xcodeproj` in Xcode
3. Select the **CaptionStudio** scheme
4. Choose an iPhone simulator, a connected iPhone, or **My Mac**
5. Set your **Team** under Signing & Capabilities if needed
6. Press **Run** (⌘R)

### First-run flow

1. Tap **Try Demo** or **Import Video**
2. Tap **AI Captions** to transcribe
3. Pick a style under **Styles**
4. Add emojis / text under **Overlays**
5. **Export** → share the MP4

## Project layout

```
CaptionStudio/
├── CaptionStudioApp.swift          # App entry
├── Models/                         # Caption, style, overlay, project
├── Services/
│   ├── TranscriptionService.swift  # Speech → timed captions
│   └── VideoExportService.swift    # AVFoundation burn-in export
├── ViewModels/EditorViewModel.swift
├── Views/                          # Home, editor, overlays, export
└── Resources/                      # Assets + entitlements
```

## Privacy

All transcription uses **on-device** `SFSpeechRecognizer` when available. No API keys. Usage strings are included for Speech, Microphone, and Photos.

## Optional next steps

- Cloud Whisper / OpenAI for higher accuracy multilingual captions
- Auto-emoji from transcript sentiment
- Templates pack and brand kits
- Vertical crop presets (9:16 / 1:1 / 16:9)
