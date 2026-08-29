import Foundation
import CoreGraphics
import AVFoundation

/// Output / editor canvas aspect. Source video is center-cropped to fill this frame.
enum AspectRatioPreset: String, CaseIterable, Identifiable, Codable {
    case portrait9x16 = "9:16"
    case landscape16x9 = "16:9"
    case square1x1 = "1:1"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .portrait9x16: return "9:16 Vertical"
        case .landscape16x9: return "16:9 Landscape"
        case .square1x1: return "1:1 Square"
        }
    }

    var systemImage: String {
        switch self {
        case .portrait9x16: return "rectangle.portrait"
        case .landscape16x9: return "rectangle"
        case .square1x1: return "square"
        }
    }

    /// Short filename token for batch exports (`9x16`, `16x9`, `1x1`).
    var fileToken: String {
        rawValue.replacingOccurrences(of: ":", with: "x")
    }

    /// Export / enhancer reference canvas in pixels.
    var canvasSize: CGSize {
        switch self {
        case .portrait9x16: return CGSize(width: 1080, height: 1920)
        case .landscape16x9: return CGSize(width: 1920, height: 1080)
        case .square1x1: return CGSize(width: 1080, height: 1080)
        }
    }

    var aspectValue: CGFloat {
        canvasSize.width / canvasSize.height
    }

    /// Pick a sensible default from the source video's oriented size.
    static func inferred(from orientedSize: CGSize) -> AspectRatioPreset {
        guard orientedSize.height > 0 else { return .portrait9x16 }
        let r = orientedSize.width / orientedSize.height
        if abs(r - 1) < 0.08 { return .square1x1 }
        return r >= 1 ? .landscape16x9 : .portrait9x16
    }

    static func fromPackAspect(_ aspect: String) -> AspectRatioPreset {
        switch aspect.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "16:9": return .landscape16x9
        case "1:1", "square": return .square1x1
        default: return .portrait9x16
        }
    }
}

/// Remaps normalized overlay positions when the export canvas aspect changes.
/// Maps each coordinate through the source/target safe zones so Reels/IG chrome
/// stays respected across 9:16 ↔ 16:9 ↔ 1:1 batch exports.
enum AspectOverlayRemapper {
    static func remapPoint(
        x: CGFloat,
        y: CGFloat,
        from: AspectRatioPreset,
        to: AspectRatioPreset
    ) -> (CGFloat, CGFloat) {
        guard from != to else { return (x, y) }
        let src = SafeZone.forAspect(from)
        let dst = SafeZone.forAspect(to)
        let nx = remapAxis(value: x, fromMin: src.xMin, fromMax: src.xMax, toMin: dst.xMin, toMax: dst.xMax)
        let ny = remapAxis(value: y, fromMin: src.yMin, fromMax: src.yMax, toMin: dst.yMin, toMax: dst.yMax)
        return dst.clamp(x: nx, y: ny)
    }

    /// Mild scale adjust so stickers don't dominate the shorter canvas axis.
    static func remapScale(
        _ scale: CGFloat,
        from: AspectRatioPreset,
        to: AspectRatioPreset
    ) -> CGFloat {
        guard from != to else { return scale }
        let fromMin = min(from.canvasSize.width, from.canvasSize.height)
        let toMin = min(to.canvasSize.width, to.canvasSize.height)
        let factor = toMin / max(fromMin, 1)
        // Soften extreme shrink/grow (portrait→landscape ≈ 1080/1080 = 1 for min axis;
        // portrait height 1920 vs square 1080 → stickers slightly smaller on square).
        let soft = sqrt(factor)
        return min(1.6, max(0.55, scale * soft))
    }

    static func remapOverlays(
        _ overlays: [OverlayItem],
        from: AspectRatioPreset,
        to: AspectRatioPreset
    ) -> [OverlayItem] {
        guard from != to else { return overlays }
        return overlays.map { item in
            var copy = item
            if copy.kind == .watermark {
                // Keep brand watermark at its authored edge; only clamp into target safe X.
                let zone = SafeZone.forAspect(to)
                copy.x = min(zone.xMax, max(zone.xMin, item.x))
                copy.y = item.y
                return copy
            }
            let (nx, ny) = remapPoint(x: item.x, y: item.y, from: from, to: to)
            copy.x = nx
            copy.y = ny
            copy.scale = remapScale(item.scale, from: from, to: to)
            return copy
        }
    }

    static func remapChessLayout(
        _ layout: ChessBoardLayout,
        from: AspectRatioPreset,
        to: AspectRatioPreset
    ) -> ChessBoardLayout {
        guard from != to else { return layout }
        let (nx, ny) = remapPoint(x: layout.originX, y: layout.originY, from: from, to: to)
        var next = layout
        next.originX = nx
        next.originY = ny
        // Board size is fraction of min(canvas W,H) already in export; nudge slightly on square.
        if to == .square1x1 {
            next.size = min(0.48, layout.size * 0.92)
        } else if from == .square1x1 && to == .portrait9x16 {
            next.size = min(0.55, layout.size / 0.92)
        }
        return next
    }

    private static func remapAxis(
        value: CGFloat,
        fromMin: CGFloat,
        fromMax: CGFloat,
        toMin: CGFloat,
        toMax: CGFloat
    ) -> CGFloat {
        let span = max(fromMax - fromMin, 0.001)
        let t = (value - fromMin) / span
        return toMin + t * (toMax - toMin)
    }
}

/// One contiguous timeline slice used for enhance/export of long videos.
struct TimelineChunk: Identifiable, Equatable {
    var id: Int { index }
    var index: Int
    var startTime: TimeInterval
    var endTime: TimeInterval
    /// Slightly wider window sent to Cursor for boundary context (does not affect stitch cuts).
    var contextStart: TimeInterval
    var contextEnd: TimeInterval

    var duration: TimeInterval { max(0, endTime - startTime) }
    var contextDuration: TimeInterval { max(0, contextEnd - contextStart) }

    func contains(_ time: TimeInterval) -> Bool {
        time >= startTime && time < endTime
    }
}

enum VideoChunkPlanner {
    /// Chunk length for part-by-part work. Shorter = more precise boundary control.
    static let defaultChunkSeconds: TimeInterval = 45
    /// Extra caption context on each side when asking Cursor to place assets.
    static let contextPadding: TimeInterval = 1.5
    /// Videos shorter than this export/enhance in one pass.
    static let singlePassLimit: TimeInterval = 60

    static func chunks(
        duration: TimeInterval,
        chunkSeconds: TimeInterval = defaultChunkSeconds,
        contextPadding: TimeInterval = contextPadding
    ) -> [TimelineChunk] {
        guard duration > 0 else { return [] }
        if duration <= singlePassLimit {
            return [
                TimelineChunk(
                    index: 0,
                    startTime: 0,
                    endTime: duration,
                    contextStart: 0,
                    contextEnd: duration
                )
            ]
        }

        var result: [TimelineChunk] = []
        var start: TimeInterval = 0
        var index = 0
        while start < duration - 0.001 {
            let end = min(duration, start + chunkSeconds)
            let contextStart = max(0, start - contextPadding)
            let contextEnd = min(duration, end + contextPadding)
            result.append(
                TimelineChunk(
                    index: index,
                    startTime: start,
                    endTime: end,
                    contextStart: contextStart,
                    contextEnd: contextEnd
                )
            )
            start = end
            index += 1
        }
        return result
    }

    static func captions(
        _ captions: [CaptionSegment],
        overlapping chunk: TimelineChunk,
        useContext: Bool
    ) -> [CaptionSegment] {
        let a = useContext ? chunk.contextStart : chunk.startTime
        let b = useContext ? chunk.contextEnd : chunk.endTime
        return captions.filter { $0.endTime > a && $0.startTime < b }
    }

    static func shiftCaptions(_ captions: [CaptionSegment], by delta: TimeInterval) -> [CaptionSegment] {
        captions.map { cap in
            var c = cap
            c.startTime += delta
            c.endTime += delta
            c.words = c.words.map { w in
                var word = w
                word.startTime += delta
                word.endTime += delta
                return word
            }
            return c
        }
    }

    static func shiftOverlays(_ overlays: [OverlayItem], by delta: TimeInterval) -> [OverlayItem] {
        overlays.map { item in
            var o = item
            o.startTime += delta
            o.endTime += delta
            return o
        }
    }

    static func shiftSFX(_ cues: [SoundEffectCue], by delta: TimeInterval) -> [SoundEffectCue] {
        cues.map { cue in
            var c = cue
            c.startTime += delta
            return c
        }
    }

    /// Remap chunk-local placements (0-based inside context window) back to absolute timeline.
    static func absolutize(
        placements: [EnhancementPlacement],
        chunk: TimelineChunk
    ) -> [EnhancementPlacement] {
        placements.compactMap { p in
            var abs = p
            // Enhancer receives captions with absolute times; prefer absolute.
            // If a model returns times relative to context, detect and fix.
            let looksRelative = p.startTime <= chunk.contextDuration + 0.05
                && p.startTime < chunk.contextStart
                && chunk.contextStart > 0.5
            if looksRelative {
                abs.startTime = p.startTime + chunk.contextStart
                abs.endTime = p.endTime + chunk.contextStart
            }
            // Keep only placements that intersect this chunk's hard cut (avoids double-apply).
            let start = abs.startTime
            let end = abs.endTime
            guard end > chunk.startTime && start < chunk.endTime else { return nil }
            // Clamp soft edges into the hard chunk for stitch safety on visuals that span cuts.
            if abs.kind != "sfx" {
                abs.startTime = max(abs.startTime, chunk.startTime)
                abs.endTime = min(abs.endTime, chunk.endTime)
            } else if abs.startTime < chunk.startTime || abs.startTime >= chunk.endTime {
                return nil
            }
            guard abs.endTime > abs.startTime else { return nil }
            return abs
        }
    }
}

/// Fit a source frame into a target aspect canvas (center **crop to fill**).
/// Matches preview `videoGravity = .resizeAspectFill`.
enum AspectFit {
    /// - Returns: layer instruction transform mapping track natural pixels → `targetSize`.
    static func transform(
        naturalSize: CGSize,
        preferredTransform: CGAffineTransform,
        targetSize: CGSize
    ) -> CGAffineTransform {
        // preferredTransform can leave a non-zero origin; neutralize before scale/center
        // or the video sits in a sub-rect of the render canvas.
        let orientedRect = CGRect(origin: .zero, size: naturalSize).applying(preferredTransform)
        let oriented = CGSize(width: abs(orientedRect.width), height: abs(orientedRect.height))

        let scale = max(
            targetSize.width / max(oriented.width, 1),
            targetSize.height / max(oriented.height, 1)
        )
        let scaled = CGSize(width: oriented.width * scale, height: oriented.height * scale)
        let tx = (targetSize.width - scaled.width) / 2
        let ty = (targetSize.height - scaled.height) / 2

        return preferredTransform
            .concatenating(
                CGAffineTransform(translationX: -orientedRect.origin.x, y: -orientedRect.origin.y)
            )
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: tx, y: ty))
    }

    /// Compatibility wrapper when only the oriented size is available.
    static func transform(
        sourceOrientedSize: CGSize,
        sourcePreferredTransform: CGAffineTransform,
        targetSize: CGSize
    ) -> (displayTransform: CGAffineTransform, layerInstructionTransform: CGAffineTransform) {
        // Best-effort: recover natural size by inverting preferredTransform.
        let probe = CGRect(origin: .zero, size: sourceOrientedSize)
            .applying(sourcePreferredTransform.inverted())
        let natural = CGSize(width: abs(probe.width), height: abs(probe.height))
        let t = transform(
            naturalSize: natural.width > 1 ? natural : sourceOrientedSize,
            preferredTransform: sourcePreferredTransform,
            targetSize: targetSize
        )
        return (t, t)
    }
}
