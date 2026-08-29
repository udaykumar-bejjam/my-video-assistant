import Foundation

/// Snap helpers for the zoomable timeline (P1.2).
/// Keep algorithm in sync with `enhancer-server/src/timelineSnap.js`.
enum TimelineSnap {
    static let defaultThreshold: TimeInterval = 0.08
    static let pixelSlop: Double = 8
    static let minThreshold: TimeInterval = 0.04

    struct Result: Equatable {
        var start: TimeInterval
        var end: TimeInterval
        var guide: TimeInterval?
        var snapped: Bool
    }

    /// Pixel-aware threshold: at least `minThreshold`, or ~8px in time.
    static func threshold(pixelsPerSecond: Double) -> TimeInterval {
        let pps = max(pixelsPerSecond, 0.001)
        return max(minThreshold, pixelSlop / pps)
    }

    /// Snap moving `[start, end]` to the nearest anchor (start or end edge).
    static func snapInterval(
        start: TimeInterval,
        end: TimeInterval,
        anchors: [TimeInterval],
        threshold: TimeInterval = defaultThreshold
    ) -> Result {
        let length = max(0.05, end - start)
        var s = start
        var bestGuide: TimeInterval?
        var bestViaStart = true
        var bestDist = TimeInterval.infinity

        for anchor in anchors where anchor.isFinite {
            let dStart = abs(s - anchor)
            if dStart < bestDist {
                bestDist = dStart
                bestGuide = anchor
                bestViaStart = true
            }
            let e = s + length
            let dEnd = abs(e - anchor)
            if dEnd < bestDist {
                bestDist = dEnd
                bestGuide = anchor
                bestViaStart = false
            }
        }

        guard let guide = bestGuide, bestDist <= threshold + 1e-9 else {
            return Result(start: s, end: s + length, guide: nil, snapped: false)
        }

        if bestViaStart {
            s = guide
        } else {
            s = guide - length
        }
        return Result(start: s, end: s + length, guide: guide, snapped: true)
    }

    /// Collect edges from sibling clips plus playhead / media bounds.
    static func collectAnchors(
        clips: [(id: String, start: TimeInterval, end: TimeInterval)],
        excluding: Set<String>,
        playhead: TimeInterval?,
        mediaDuration: TimeInterval?
    ) -> [TimeInterval] {
        var anchors: [TimeInterval] = [0]
        if let playhead, playhead.isFinite { anchors.append(playhead) }
        if let mediaDuration, mediaDuration > 0 { anchors.append(mediaDuration) }
        for clip in clips where !excluding.contains(clip.id) {
            anchors.append(clip.start)
            anchors.append(clip.end)
        }
        return anchors
    }
}
