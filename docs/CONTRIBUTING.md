# Contributing & Agent Notes

Guidance for humans and coding agents working on CaptionStudio.

---

## Before you change code

1. Read [ARCHITECTURE.md](./ARCHITECTURE.md) — especially **invariants**.
2. Skim [FEATURES.md](./FEATURES.md) for the surface you’re touching.
3. Check [FILE_INDEX.md](./FILE_INDEX.md) for the owning files.
4. If the change is large, update [ROADMAP.md](./ROADMAP.md) status.

---

## Hard regressions (do not ship)

- AI Place / enhancer timelines truncated to ~8–10 seconds.
- Export overlay opacity via non-keyframe animations that bake to 0.
- Preview vs export coordinate mismatch (Y-up vs Y-down, letterbox ignore).
- New Swift sources not added to Xcode target membership.
- Project open that drops `session` or media refs.
- Audio export that ignores mute / duck / gains when UI shows them set.

---

## Preferred change style

- Small, focused PRs.
- Match existing Swift/JS style; avoid drive-by refactors.
- Prefer shared helpers for duration, canvas fit, and mix math.
- Add or extend enhancer smoke tests for duration / library shape bugs.
- Update docs when behavior or file ownership changes.

---

## Testing expectations

| Change type | Minimum verification |
|-------------|----------------------|
| Enhancer duration / captions | `full-duration-smoke.mjs` |
| GIF library | `gif-phase2-smoke.mjs` |
| Export mix / overlays | Manual export spot-check when Xcode available; reason about CALayer path |
| Save/load | Round-trip JSON + session fields |
| UI-only | Simulator or screenshot if feasible |

Cloud Linux cannot compile the Mac app — rely on Actions or local Xcode for native builds.

---

## Documentation maintenance

| Doc | Update when… |
|-----|----------------|
| ARCHITECTURE | New subsystem or pipeline |
| FEATURES | User-visible capability ships |
| FILE_INDEX | Files added/moved/renamed |
| DATA_MODEL | Persistence fields change |
| ROADMAP | Priority or status changes |
| DEVELOPMENT | Build/test/release process changes |
| SHORTS_MAKER_PLAN | Phase checklist items complete |

---

## PR description checklist

- [ ] What user problem this solves
- [ ] Files / subsystems touched
- [ ] Invariants considered
- [ ] Tests / smoke run
- [ ] Docs updated (if needed)
