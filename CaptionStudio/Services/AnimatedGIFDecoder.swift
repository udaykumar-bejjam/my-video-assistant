import Foundation
import ImageIO
import CoreGraphics

/// Decoded GIF (or multi-frame image) ready for preview scrubbing and export keyframes.
struct AnimatedGIFFrames {
    var images: [CGImage]
    /// Delay for each frame in seconds (GIF delay of 0 → default 0.1s).
    var delays: [TimeInterval]
    var totalDuration: TimeInterval

    static let empty = AnimatedGIFFrames(images: [], delays: [], totalDuration: 0)

    var isAnimated: Bool { images.count > 1 }

    func frameIndex(at localTime: TimeInterval) -> Int {
        guard !images.isEmpty else { return 0 }
        guard isAnimated, totalDuration > 0 else { return 0 }
        var t = localTime.truncatingRemainder(dividingBy: totalDuration)
        if t < 0 { t += totalDuration }
        var acc: TimeInterval = 0
        for (i, delay) in delays.enumerated() {
            acc += delay
            if t < acc { return i }
        }
        return images.count - 1
    }

    func image(at localTime: TimeInterval) -> CGImage? {
        guard !images.isEmpty else { return nil }
        return images[frameIndex(at: localTime)]
    }

    /// Normalized keyTimes (0…1) for CAKeyframeAnimation with discrete calculation mode.
    var keyTimes: [NSNumber] {
        guard totalDuration > 0, !delays.isEmpty else { return [0] }
        var times: [NSNumber] = []
        var acc: TimeInterval = 0
        for delay in delays {
            times.append(NSNumber(value: acc / totalDuration))
            acc += delay
        }
        return times
    }
}

enum AnimatedGIFDecoder {
    private static var cache: [String: AnimatedGIFFrames] = [:]
    private static let lock = NSLock()

    static func load(url: URL, useCache: Bool = true) -> AnimatedGIFFrames {
        let key = url.path
        if useCache {
            lock.lock()
            if let hit = cache[key] {
                lock.unlock()
                return hit
            }
            lock.unlock()
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return .empty
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return .empty }

        var images: [CGImage] = []
        var delays: [TimeInterval] = []
        images.reserveCapacity(count)
        delays.reserveCapacity(count)

        for i in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            images.append(image)
            delays.append(frameDelay(source: source, index: i))
        }

        if images.isEmpty { return .empty }
        if delays.count != images.count {
            delays = Array(repeating: 0.1, count: images.count)
        }

        let total = max(delays.reduce(0, +), 0.01)
        let frames = AnimatedGIFFrames(images: images, delays: delays, totalDuration: total)

        if useCache {
            lock.lock()
            cache[key] = frames
            lock.unlock()
        }
        return frames
    }

    private static func frameDelay(source: CGImageSource, index: Int) -> TimeInterval {
        let defaultDelay: TimeInterval = 0.1
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return defaultDelay
        }

        if let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
            let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
            let delay = unclamped ?? clamped ?? defaultDelay
            return delay < 0.011 ? defaultDelay : delay
        }

        if let png = props[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
            let unclamped = png[kCGImagePropertyAPNGUnclampedDelayTime] as? Double
            let clamped = png[kCGImagePropertyAPNGDelayTime] as? Double
            let delay = unclamped ?? clamped ?? defaultDelay
            return delay < 0.011 ? defaultDelay : delay
        }

        return defaultDelay
    }

    static func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }
}
