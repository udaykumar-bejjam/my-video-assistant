import Foundation
import CoreGraphics

/// Snaps placements to measured asset length and the caption window currently playing.
enum PlacementAligner {
    static func align(
        _ placement: EnhancementPlacement,
        asset: MediaLibraryItem,
        kind: String,
        captions: [CaptionSegment],
        videoDuration: TimeInterval
    ) -> (start: TimeInterval, end: TimeInterval, x: CGFloat, y: CGFloat) {
        let length = placement.lengthSeconds ?? asset.playLength
        let caption: CaptionSegment? = {
            if let index = placement.captionIndex, captions.indices.contains(index) {
                return captions[index]
            }
            return captions.first {
                placement.startTime >= $0.startTime - 0.05 && placement.startTime < $0.endTime + 0.05
            } ?? captions.min(by: {
                abs($0.startTime - placement.startTime) < abs($1.startTime - placement.startTime)
            })
        }()

        var start = placement.startTime
        if let caption {
            start = caption.startTime
        }
        start = min(max(0, start), max(0, videoDuration - 0.05))

        let end: TimeInterval
        switch kind {
        case "sfx":
            end = min(videoDuration, start + length)
        case "gif":
            if let caption {
                let span = max(0.1, caption.endTime - start)
                let loops = max(1, Int(span / max(length, 0.01)))
                end = min(videoDuration, start + min(span, Double(loops) * length))
            } else {
                end = min(videoDuration, start + length)
            }
        case "png":
            if let caption {
                let span = caption.endTime - start
                end = min(videoDuration, start + min(max(0.4, span), length))
            } else {
                end = min(videoDuration, start + length)
            }
        default: // text
            if let caption {
                end = min(videoDuration, min(caption.endTime, start + length))
            } else {
                end = min(videoDuration, start + length)
            }
        }

        let nw = (asset.normalizedWidth ?? (asset.pixelSize.width / 1080)) * placement.scale
        let nh = (asset.normalizedHeight ?? (asset.pixelSize.height / 1920)) * placement.scale
        let x = clamp(placement.x, nw / 2 + 0.02, 1 - nw / 2 - 0.02)
        let y = clamp(placement.y, nh / 2 + 0.02, 1 - nh / 2 - 0.02)
        return (start, max(start + 0.05, end), x, y)
    }

    private static func clamp(_ value: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
        min(hi, max(lo, value))
    }
}
