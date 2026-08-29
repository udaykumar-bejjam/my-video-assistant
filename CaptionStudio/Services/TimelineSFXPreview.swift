import Foundation

/// Pure helpers for playhead-crossing one-shot SFX during preview playback.
/// Mirrors `enhancer-server/src/timelineSfxPreview.js` for smoke parity.
enum TimelineSFXPreview {
    /// Look-back when starting playback so a cue under the playhead still fires once.
    static let playbackLookback: TimeInterval = 0.08

    /// Cues whose startTime falls in `(from, to]` (or optional land-on window).
    static func cuesToTrigger(
        cues: [(id: UUID, startTime: TimeInterval, isMuted: Bool)],
        from: TimeInterval,
        to: TimeInterval,
        alreadyTriggered: Set<UUID>,
        landOnEpsilon: TimeInterval = 0.05
    ) -> [UUID] {
        var fired: [UUID] = []
        let scrubbedBack = to < from - 0.02
        var blocked = alreadyTriggered
        if scrubbedBack {
            blocked = Set(cues.filter { $0.startTime <= to + 0.001 }.map(\.id))
        }

        for cue in cues {
            guard !cue.isMuted else { continue }
            guard !blocked.contains(cue.id) else { continue }
            let crossed = cue.startTime > from && cue.startTime <= to + 0.001
            let landedOn = from < 0 && abs(cue.startTime - to) <= landOnEpsilon
            if crossed || landedOn {
                fired.append(cue.id)
                blocked.insert(cue.id)
            }
        }
        return fired
    }

    /// Dialogue volume while previewing, optionally ducked under active SFX windows.
    static func dialogueVolume(
        baseGain: Double,
        duckEnabled: Bool,
        duckAmount: Double,
        now: TimeInterval,
        duckUntil: TimeInterval?
    ) -> Float {
        let base = Float(min(2.0, max(0.05, baseGain)))
        guard duckEnabled, let until = duckUntil, now < until else { return base }
        let amount = Float(min(0.85, max(0, duckAmount)))
        return max(0.05, base * (1 - amount))
    }

    /// Extend duck window by the cue length from `fireTime`.
    static func extendDuck(
        currentUntil: TimeInterval?,
        fireTime: TimeInterval,
        cueLength: TimeInterval
    ) -> TimeInterval {
        let end = fireTime + max(0.05, cueLength)
        if let currentUntil {
            return max(currentUntil, end)
        }
        return end
    }
}
