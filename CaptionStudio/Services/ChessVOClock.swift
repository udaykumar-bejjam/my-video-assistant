import Foundation

/// How chess plies map onto the project video timeline (VO / commentary clock).
enum ChessTimingMode: String, Codable, CaseIterable, Identifiable {
    /// Uniform `secondsPerMove` from `startOffset`.
    case fixedPace = "fixed"
    /// Stretch plies evenly across `[startOffset, endOffset)`.
    case fitRange = "fit"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fixedPace: return "Fixed pace"
        case .fitRange: return "Fit to range"
        }
    }

    var subtitle: String {
        switch self {
        case .fixedPace: return "Constant seconds per move from start"
        case .fitRange: return "Evenly map all plies between start and end marks"
        }
    }
}

/// Pure helpers for resolving ply times on a video clock.
enum ChessVOClock {
    /// Absolute start time of each ply (index 0 = first move). Length == moveCount.
    static func moveStartTimes(
        mode: ChessTimingMode,
        startOffset: TimeInterval,
        endOffset: TimeInterval?,
        moveCount: Int,
        secondsPerMove: Double
    ) -> [TimeInterval] {
        let n = max(0, moveCount)
        guard n > 0 else { return [] }
        let start = max(0, startOffset)
        switch mode {
        case .fixedPace:
            let pace = max(0.05, secondsPerMove)
            return (0..<n).map { start + Double($0) * pace }
        case .fitRange:
            let end = max(start + Double(n) * 0.05, endOffset ?? (start + Double(n) * max(0.05, secondsPerMove)))
            let span = max(0.05 * Double(n), end - start)
            let pace = span / Double(n)
            return (0..<n).map { start + Double($0) * pace }
        }
    }

    /// Effective seconds-per-move for display / SFX spacing.
    static func effectivePace(
        mode: ChessTimingMode,
        startOffset: TimeInterval,
        endOffset: TimeInterval?,
        moveCount: Int,
        secondsPerMove: Double
    ) -> Double {
        let n = max(1, moveCount)
        switch mode {
        case .fixedPace:
            return max(0.05, secondsPerMove)
        case .fitRange:
            let start = max(0, startOffset)
            let end = max(start + Double(n) * 0.05, endOffset ?? (start + Double(n) * max(0.05, secondsPerMove)))
            return max(0.05, (end - start) / Double(n))
        }
    }

    /// Absolute end of the last ply hold.
    static func endTime(
        mode: ChessTimingMode,
        startOffset: TimeInterval,
        endOffset: TimeInterval?,
        moveCount: Int,
        secondsPerMove: Double
    ) -> TimeInterval {
        let n = max(0, moveCount)
        guard n > 0 else { return max(0, startOffset) }
        let starts = moveStartTimes(
            mode: mode,
            startOffset: startOffset,
            endOffset: endOffset,
            moveCount: n,
            secondsPerMove: secondsPerMove
        )
        let pace = effectivePace(
            mode: mode,
            startOffset: startOffset,
            endOffset: endOffset,
            moveCount: n,
            secondsPerMove: secondsPerMove
        )
        return (starts.last ?? startOffset) + pace
    }

    /// Board snapshot index (0 = start position) visible at `time`.
    static func boardIndex(
        at time: TimeInterval,
        mode: ChessTimingMode,
        startOffset: TimeInterval,
        endOffset: TimeInterval?,
        moveCount: Int,
        secondsPerMove: Double
    ) -> Int {
        let n = max(0, moveCount)
        guard n > 0 else { return 0 }
        let starts = moveStartTimes(
            mode: mode,
            startOffset: startOffset,
            endOffset: endOffset,
            moveCount: n,
            secondsPerMove: secondsPerMove
        )
        if time < starts[0] { return 0 }
        var idx = 0
        for i in 0..<n {
            if starts[i] <= time { idx = i + 1 }
        }
        return min(n, idx)
    }
}
