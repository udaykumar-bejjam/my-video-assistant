import Foundation

/// Keyboard transport + nudge helpers (P1.3).
/// Keep nudge steps in sync with `enhancer-server/src/editorShortcuts.js`.
enum EditorShortcuts {
    /// ≈ one frame at 30fps.
    static let nudgeFine: TimeInterval = 1.0 / 30.0
    /// Shift+arrow coarse nudge.
    static let nudgeCoarse: TimeInterval = 1.0
    /// J/L rate ladder (absolute values).
    static let rateLadder: [Float] = [1, 2, 4, 8]

    /// Next forward (`L`) or reverse (`J`) rate from the current player rate.
    static func nextRate(current: Float, forward: Bool) -> Float {
        let ladder = rateLadder
        if forward {
            if current <= 0 { return ladder[0] }
            let absCurrent = abs(current)
            if let i = ladder.firstIndex(where: { abs($0 - absCurrent) < 0.01 }), i + 1 < ladder.count {
                return ladder[i + 1]
            }
            if absCurrent < ladder[0] { return ladder[0] }
            return ladder.last ?? 1
        } else {
            if current >= 0 { return -ladder[0] }
            let absCurrent = abs(current)
            if let i = ladder.firstIndex(where: { abs($0 - absCurrent) < 0.01 }), i + 1 < ladder.count {
                return -ladder[i + 1]
            }
            if absCurrent < ladder[0] { return -ladder[0] }
            return -(ladder.last ?? 1)
        }
    }

    static func nudgeDelta(shift: Bool) -> TimeInterval {
        shift ? nudgeCoarse : nudgeFine
    }
}
