# In-flight branches (not on `master`)

`master` is the documentation baseline. Substantial product work lives on open feature branches. **Read this before implementing “new” Telugu, timeline, or chess features** — they may already exist.

Last reviewed against remote tips during the documentation pass (branch names may move).

---

## Why this doc exists

Agents and humans often clone `master` and miss:

- OpenAI Telugu/bilingual ASR + timing policy
- Zoomable cross-lane timeline workspace
- Chess PGN walkthrough UI
- Enhancer `/transcribe` + lexicon trees

Those changes are real, tested on Mac CI in places, but **not merged to `master` yet**.

---

## Primary feature line

Approximate stack (oldest → newest) culminating in chess tip:

| Theme | Branch (typical) | Highlights |
|-------|------------------|------------|
| Telugu / Whisper captions | `cursor/fix-telugu-english-captions-ac05` | `WhisperTranscriptionClient`, `APIKeyStore`, `OpenAIKeySheet`, `docs/TELUGU_ASR_PLAN.md`; gpt-transcribe + whisper clocks; no `language=te` on whisper-1 |
| Timeline UX | same lineage (~v1.0.26) | `TimelineWorkspaceView`, `applyTimelineDrag`, zoom fit→frame, cross-lane Caps↔overlays |
| Chess Walkthrough | `cursor/chess-analysis-overlays-ac05` (~v1.0.27) | `ChessAnalysis`, `ChessEngine`, `ChessWalkthroughViewModel`, `ChessWalkthroughView`, `docs/CHESS_WALKTHROUGH.md` |

Also related remotes historically: preview/SFX/export fixes, GIF phases, distribution polish, drafts/trim, rebuild tags — see `git branch -r`.

### Telugu ASR (summary)

- Apple has no reliable Telugu dictation → OpenAI path.
- **`gpt-transcribe`** with `languages[]=te,en` for text; **`whisper-1`** (never `language=te`) for word clocks; align with light anticipation.
- Do **not** stretch short transcripts to fill full video duration (historical late/early bugs).
- Full write-up on the feature branch: `docs/TELUGU_ASR_PLAN.md`.

### Timeline workspace (summary)

- Replaces/extends simple scrubber with zoomable multi-lane editor.
- Drag L/R = retime; U/D across lanes = kind/lane changes.
- Orange media-end marker; +1h pad beyond media for zoom-out.

### Chess Walkthrough (summary)

- PGN / move list → animated Unicode board (not PNG sticker import).
- Colors from `!!` / `?` / `??` / NAGs + check heuristics — **no Stockfish yet**.
- **Not** burned into video export yet.
- Entry: Home CTA + editor checkerboard.
- Full write-up on the feature branch: `docs/CHESS_WALKTHROUGH.md`.

### Enhancer deltas on that line

- `POST /transcribe` Whisper proxy (`OPENAI_API_KEY`).
- Richer `lexicons/` under `AssetLibraries/` (en/hi/te).
- Larger body size for audio base64 on `/transcribe`.

---

## How to work with in-flight code

```bash
git fetch origin
git log --oneline master..origin/cursor/chess-analysis-overlays-ac05 | head
git checkout origin/cursor/chess-analysis-overlays-ac05 -- path/of/interest
# or open the existing PR and rebase onto latest master
```

**Do not** copy incomplete fragments onto `master` without the supporting services/models — prefer merging the feature PR.

---

## Documentation on this (`docs`) PR vs feature branches

| On docs PR (`master` + these files) | On chess/telugu tip |
|-------------------------------------|---------------------|
| ARCHITECTURE / CODEBASE_MAP / FEATURES for **master** | Same + Telugu/Chess/Timeline files |
| ENHANCEMENT_ROADMAP + this IN_FLIGHT note | Domain docs `TELUGU_ASR_PLAN.md`, `CHESS_WALKTHROUGH.md` |
| AGENTS.md restored for Cloud | AGENTS may need refresh after merge |

After feature PRs merge, update CODEBASE_MAP / FEATURES and fold domain docs into [INDEX.md](./INDEX.md); trim this file.
