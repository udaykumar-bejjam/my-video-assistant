import Foundation
import AVFoundation
import CoreImage
import CoreText
import QuartzCore
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum ExportError: LocalizedError {
    case noVideo
    case compositionFailed(String)
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideo: return "No video loaded to export."
        case .compositionFailed(let m): return m
        case .exportFailed(let m): return m
        }
    }
}

/// Composites captions + overlays onto video and exports an MP4.
@MainActor
final class VideoExportService: ObservableObject {
    @Published var progress: Double = 0
    @Published var statusMessage: String = ""

    func export(
        videoURL: URL,
        captions: [CaptionSegment],
        style: CaptionStyle,
        overlays: [OverlayItem],
        soundEffects: [SoundEffectCue] = [],
        libraryRoot: URL? = nil,
        aspect: AspectRatioPreset = .portrait9x16,
        sourceTimeRange: CMTimeRange? = nil,
        outputURL: URL? = nil,
        normalizeLoudness: Bool = true,
        brandSfxGain: Double = 0.8
    ) async throws -> URL {
        progress = 0.02
        statusMessage = "Building composition…"

        let asset = AVURLAsset(url: videoURL)
        let fullDuration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw ExportError.compositionFailed("No video track found.")
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let oriented = Self.orientedSize(naturalSize, transform: preferredTransform)
        let renderSize = aspect.canvasSize

        let insertRange: CMTimeRange = {
            if let sourceTimeRange, sourceTimeRange.duration.seconds > 0 {
                let start = max(0, CMTimeGetSeconds(sourceTimeRange.start))
                let end = min(CMTimeGetSeconds(fullDuration), start + CMTimeGetSeconds(sourceTimeRange.duration))
                return CMTimeRange(
                    start: CMTime(seconds: start, preferredTimescale: 600),
                    duration: CMTime(seconds: max(0.01, end - start), preferredTimescale: 600)
                )
            }
            return CMTimeRange(start: .zero, duration: fullDuration)
        }()
        let compositionDuration = insertRange.duration

        let composition = AVMutableComposition()
        guard
            let compVideo = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw ExportError.compositionFailed("Could not create video track.")
        }

        try compVideo.insertTimeRange(insertRange, of: videoTrack, at: .zero)

        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let compAudio = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compAudio.insertTimeRange(insertRange, of: audioTrack, at: .zero)
        }

        var norm = AudioNormalizeService.Normalization(
            dialogueGain: 1,
            measuredPeak: AudioNormalizeService.targetPeak,
            sfxGainScale: brandSfxGain
        )
        if normalizeLoudness {
            statusMessage = "Measuring loudness…"
            let peak = try await AudioNormalizeService.analyzeDialoguePeak(videoURL: videoURL)
            norm = AudioNormalizeService.normalization(measuredPeak: peak, brandSfxGain: brandSfxGain)
        }

        let scaledSFX = soundEffects.map {
            SoundEffectCue(
                id: $0.id,
                assetId: $0.assetId,
                startTime: $0.startTime,
                gain: min(1.2, $0.gain * norm.sfxGainScale),
                reason: $0.reason
            )
        }

        // Mix in library SFX cues (already shifted to local 0-based timeline when chunked).
        try await mixSoundEffects(
            into: composition,
            cues: scaledSFX,
            libraryRoot: libraryRoot,
            timelineDuration: compositionDuration
        )

        progress = 0.15
        statusMessage = "Rendering \(aspect.rawValue) canvas…"

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: compositionDuration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        let (_, fitTransform) = AspectFit.transform(
            sourceOrientedSize: oriented,
            sourcePreferredTransform: preferredTransform,
            targetSize: renderSize
        )
        layerInstruction.setTransform(fitTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        // Core Animation overlay pipeline on the target aspect canvas
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = true
        parentLayer.backgroundColor = PlatformColor.black.cgColor

        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)

        let overlayRoot = CALayer()
        overlayRoot.frame = parentLayer.bounds
        parentLayer.addSublayer(overlayRoot)

        addCaptionLayers(
            to: overlayRoot,
            captions: captions,
            style: style,
            size: renderSize,
            duration: CMTimeGetSeconds(compositionDuration)
        )
        addOverlayLayers(
            to: overlayRoot,
            overlays: overlays,
            size: renderSize,
            libraryRoot: libraryRoot
        )

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )

        let dest = outputURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionStudio-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: dest)

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.exportFailed("Could not create export session.")
        }
        session.outputURL = dest
        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true
        if normalizeLoudness, let mix = AudioNormalizeService.audioMix(for: composition, dialogueGain: norm.dialogueGain) {
            session.audioMix = mix
            statusMessage = "Encoding \(aspect.rawValue) (loudness ×\(String(format: "%.2f", norm.dialogueGain)))…"
        } else {
            statusMessage = "Encoding \(aspect.rawValue)…"
        }

        progress = 0.25
        if statusMessage.isEmpty {
            statusMessage = "Encoding \(aspect.rawValue)…"
        }

        let progressTask = Task {
            while !Task.isCancelled {
                progress = 0.25 + Double(session.progress) * 0.7
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: ExportError.exportFailed("Export cancelled."))
                default:
                    continuation.resume(
                        throwing: ExportError.exportFailed(
                            session.error?.localizedDescription ?? "Export failed."
                        )
                    )
                }
            }
        }
        progressTask.cancel()

        progress = 1
        statusMessage = "Export complete"
        return dest
    }

    static func orientedSizePublic(_ size: CGSize, transform: CGAffineTransform) -> CGSize {
        orientedSize(size, transform: transform)
    }

    // MARK: - Layers

    private func addCaptionLayers(
        to root: CALayer,
        captions: [CaptionSegment],
        style: CaptionStyle,
        size: CGSize,
        duration: TimeInterval
    ) {
        for caption in captions {
            let text = style.textCase.apply(caption.text)
            let layer = Self.makeTextLayer(
                text: text,
                fontName: style.fontName,
                fontSize: style.fontSize * (size.width / 390),
                textColor: style.textColor.platformColor,
                strokeColor: style.strokeColor.platformColor,
                strokeWidth: style.strokeWidth,
                backgroundColor: style.backgroundColor.platformColor,
                cornerRadius: style.cornerRadius,
                shadowColor: style.shadowColor.platformColor,
                shadowRadius: style.shadowRadius,
                maxWidth: size.width * 0.88
            )

            let midX = size.width * style.positionX
            let midY = size.height * (1 - style.positionY) // flipped coords
            layer.position = CGPoint(x: midX, y: midY)

            let appear = CAPBasicAnimation(keyPath: "opacity")
            appear.fromValue = 0
            appear.toValue = 1
            appear.beginTime = AVCoreAnimationBeginTimeAtZero + caption.startTime
            appear.duration = 0.12
            appear.fillMode = .forwards
            appear.isRemovedOnCompletion = false

            let disappear = CAPBasicAnimation(keyPath: "opacity")
            disappear.fromValue = 1
            disappear.toValue = 0
            disappear.beginTime = AVCoreAnimationBeginTimeAtZero + caption.endTime
            disappear.duration = 0.1
            disappear.fillMode = .forwards
            disappear.isRemovedOnCompletion = false

            layer.opacity = 0
            layer.add(appear, forKey: "appear")
            layer.add(disappear, forKey: "disappear")
            root.addSublayer(layer)
        }
    }

    private func mixSoundEffects(
        into composition: AVMutableComposition,
        cues: [SoundEffectCue],
        libraryRoot: URL?,
        timelineDuration: CMTime
    ) async throws {
        guard let libraryRoot, !cues.isEmpty else { return }
        let catalogURL = libraryRoot.appendingPathComponent("sfx/catalog.json")
        guard
            let data = try? Data(contentsOf: catalogURL),
            let catalog = try? JSONDecoder().decode(MediaLibraryCatalog.self, from: data)
        else { return }

        for cue in cues {
            guard let item = catalog.items.first(where: { $0.id == cue.assetId }) else { continue }
            let fileName = item.file ?? item.wav
            guard let fileName else { continue }
            let url = libraryRoot.appendingPathComponent("sfx").appendingPathComponent(fileName)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            let sfxAsset = AVURLAsset(url: url)
            guard let track = try await sfxAsset.loadTracks(withMediaType: .audio).first,
                  let compAudio = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  )
            else { continue }

            let sfxDuration = try await sfxAsset.load(.duration)
            let start = CMTime(seconds: cue.startTime, preferredTimescale: 600)
            let available = CMTimeSubtract(timelineDuration, start)
            let insertDuration = CMTimeMinimum(sfxDuration, available)
            guard insertDuration.seconds > 0 else { continue }
            try? compAudio.insertTimeRange(
                CMTimeRange(start: .zero, duration: insertDuration),
                of: track,
                at: start
            )
        }
    }

    private func addOverlayLayers(
        to root: CALayer,
        overlays: [OverlayItem],
        size: CGSize,
        libraryRoot: URL?
    ) {
        for item in overlays {
            let layer: CALayer
            switch item.kind {
            case .emoji, .text, .watermark, .wordHit:
                let fontName = item.fontName ?? "AvenirNext-Heavy"
                let fontSize = (item.kind == .wordHit ? item.fontSize * 0.95 : item.fontSize)
                    * item.scale * (size.width / 390)
                let isHit = item.kind == .wordHit
                let fill = item.color.platformColor
                #if canImport(UIKit)
                let redStroke = UIColor(red: 1, green: 0.18, blue: 0.18, alpha: 1)
                let yellowGlow = UIColor(red: 1, green: 0.94, blue: 0.35, alpha: 0.9)
                #else
                let redStroke = NSColor(srgbRed: 1, green: 0.18, blue: 0.18, alpha: 1)
                let yellowGlow = NSColor(srgbRed: 1, green: 0.94, blue: 0.35, alpha: 0.9)
                #endif
                layer = Self.makeTextLayer(
                    text: item.text,
                    fontName: fontName,
                    fontSize: fontSize,
                    textColor: fill,
                    strokeColor: isHit ? redStroke : .clear,
                    strokeWidth: isHit ? 3.5 : 0,
                    backgroundColor: .clear,
                    cornerRadius: 0,
                    shadowColor: isHit ? yellowGlow : PlatformColor.black.withAlphaComponent(0.45),
                    shadowRadius: isHit ? 12 : 6,
                    maxWidth: size.width * 0.8
                )
                if isHit {
                    // Punch scale keyframes for export
                    let punch = CAPBasicAnimation(keyPath: "transform.scale")
                    punch.fromValue = 0.4
                    punch.toValue = 1.25
                    punch.beginTime = AVCoreAnimationBeginTimeAtZero + item.startTime
                    punch.duration = 0.18
                    punch.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    punch.fillMode = .forwards
                    punch.isRemovedOnCompletion = false
                    layer.add(punch, forKey: "punchScale")
                }
            case .gif:
                if let file = item.assetFileName,
                   let libraryRoot {
                    let url = libraryRoot.appendingPathComponent("gifs").appendingPathComponent(file)
                    let frames = AnimatedGIFDecoder.load(url: url)
                    if frames.images.isEmpty { continue }

                    let imageLayer = CALayer()
                    let side = 90 * item.scale * (size.width / 390)
                    imageLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
                    imageLayer.contents = frames.images[0]
                    imageLayer.contentsGravity = .resizeAspect
                    layer = imageLayer

                    if frames.isAnimated {
                        let cycle = max(frames.totalDuration, 0.05)
                        let visible = max(0.05, item.endTime - item.startTime)
                        let anim = CAKeyframeAnimation(keyPath: "contents")
                        anim.values = frames.images
                        anim.keyTimes = frames.keyTimes
                        anim.duration = cycle
                        anim.calculationMode = .discrete
                        anim.repeatCount = Float(ceil(visible / cycle) + 1)
                        anim.beginTime = AVCoreAnimationBeginTimeAtZero + item.startTime
                        anim.fillMode = .forwards
                        anim.isRemovedOnCompletion = false
                        imageLayer.add(anim, forKey: "gifFrames")
                    }
                } else {
                    continue
                }
            case .png:
                if let file = item.assetFileName,
                   let libraryRoot {
                    let url = libraryRoot.appendingPathComponent("pngs").appendingPathComponent(file)
                    if let image = Self.loadCGImage(url: url) {
                        let imageLayer = CALayer()
                        let side = 90 * item.scale * (size.width / 390)
                        imageLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
                        imageLayer.contents = image
                        imageLayer.contentsGravity = .resizeAspect
                        layer = imageLayer
                    } else {
                        continue
                    }
                } else {
                    continue
                }
            case .shape:
                let shape = CAShapeLayer()
                let side = 60 * item.scale * (size.width / 390)
                let rect = CGRect(x: -side / 2, y: -side / 2, width: side, height: side)
                switch item.shape {
                case .circle:
                    shape.path = CGPath(ellipseIn: rect, transform: nil)
                case .rectangle:
                    shape.path = CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)
                case .line:
                    let path = CGMutablePath()
                    path.move(to: CGPoint(x: -side, y: 0))
                    path.addLine(to: CGPoint(x: side, y: 0))
                    shape.path = path
                    shape.lineWidth = 4
                    shape.strokeColor = item.color.platformColor.cgColor
                    shape.fillColor = nil
                case .arrow:
                    shape.path = CGPath(roundedRect: rect, cornerWidth: 4, cornerHeight: 4, transform: nil)
                }
                if item.shape != .line {
                    shape.fillColor = item.color.platformColor.withAlphaComponent(item.opacity).cgColor
                }
                layer = shape
            }

            layer.position = CGPoint(
                x: size.width * item.x,
                y: size.height * (1 - item.y)
            )
            layer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(item.rotation * .pi / 180)))
            layer.opacity = 0

            let appear = CAPBasicAnimation(keyPath: "opacity")
            appear.fromValue = 0
            appear.toValue = Float(item.opacity)
            appear.beginTime = AVCoreAnimationBeginTimeAtZero + item.startTime
            appear.duration = 0.1
            appear.fillMode = .forwards
            appear.isRemovedOnCompletion = false

            let disappear = CAPBasicAnimation(keyPath: "opacity")
            disappear.fromValue = Float(item.opacity)
            disappear.toValue = 0
            disappear.beginTime = AVCoreAnimationBeginTimeAtZero + item.endTime
            disappear.duration = 0.1
            disappear.fillMode = .forwards
            disappear.isRemovedOnCompletion = false

            layer.add(appear, forKey: "appear")
            layer.add(disappear, forKey: "disappear")
            root.addSublayer(layer)
        }
    }

    private static func loadCGImage(url: URL) -> CGImage? {
        #if canImport(UIKit)
        return UIImage(contentsOfFile: url.path)?.cgImage
        #elseif canImport(AppKit)
        guard let ns = NSImage(contentsOf: url) else { return nil }
        var rect = NSRect(origin: .zero, size: ns.size)
        return ns.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #else
        return nil
        #endif
    }

    private static func makeTextLayer(
        text: String,
        fontName: String,
        fontSize: CGFloat,
        textColor: PlatformColor,
        strokeColor: PlatformColor,
        strokeWidth: CGFloat,
        backgroundColor: PlatformColor,
        cornerRadius: CGFloat,
        shadowColor: PlatformColor,
        shadowRadius: CGFloat,
        maxWidth: CGFloat
    ) -> CALayer {
        let textLayer = CATextLayer()
        textLayer.string = text
        textLayer.font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
        textLayer.fontSize = fontSize
        textLayer.foregroundColor = textColor.cgColor
        textLayer.alignmentMode = .center
        textLayer.contentsScale = 3
        textLayer.isWrapped = true

        let attrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize, weight: .bold)
        ]
        let bound = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: 400),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        let pad: CGFloat = backgroundColor.cgColor.alpha > 0.01 ? 16 : 4
        let size = CGSize(width: ceil(bound.width) + pad * 2, height: ceil(bound.height) + pad * 2)
        textLayer.frame = CGRect(origin: .zero, size: size)

        let container = CALayer()
        container.bounds = CGRect(origin: .zero, size: size)
        container.backgroundColor = backgroundColor.cgColor
        container.cornerRadius = cornerRadius
        container.shadowColor = shadowColor.cgColor
        container.shadowRadius = shadowRadius
        container.shadowOpacity = shadowRadius > 0 ? 1 : 0
        container.shadowOffset = CGSize(width: 0, height: 2)

        if strokeWidth > 0 {
            let stroke = CATextLayer()
            stroke.string = text
            stroke.font = textLayer.font
            stroke.fontSize = fontSize
            stroke.foregroundColor = strokeColor.cgColor
            stroke.alignmentMode = .center
            stroke.contentsScale = 3
            stroke.isWrapped = true
            stroke.frame = textLayer.frame.insetBy(dx: -strokeWidth, dy: -strokeWidth)
            // Approximate outline via slight offsets
            for dx in [-strokeWidth, 0, strokeWidth] {
                for dy in [-strokeWidth, 0, strokeWidth] where !(dx == 0 && dy == 0) {
                    let clone = CATextLayer()
                    clone.string = text
                    clone.font = textLayer.font
                    clone.fontSize = fontSize
                    clone.foregroundColor = strokeColor.cgColor
                    clone.alignmentMode = .center
                    clone.contentsScale = 3
                    clone.isWrapped = true
                    clone.frame = textLayer.frame.offsetBy(dx: dx, dy: dy)
                    container.addSublayer(clone)
                }
            }
        }

        container.addSublayer(textLayer)
        container.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        return container
    }

    private static func orientedSize(_ size: CGSize, transform: CGAffineTransform) -> CGSize {
        let rect = CGRect(origin: .zero, size: size).applying(transform)
        return CGSize(width: abs(rect.width), height: abs(rect.height))
    }
}

// MARK: - Platform aliases

#if canImport(UIKit)
typealias PlatformColor = UIColor
typealias PlatformFont = UIFont
#elseif canImport(AppKit)
typealias PlatformColor = NSColor
typealias PlatformFont = NSFont
#endif

extension CodableColor {
    var platformColor: PlatformColor {
        #if canImport(UIKit)
        return UIColor(red: r, green: g, blue: b, alpha: a)
        #elseif canImport(AppKit)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        #endif
    }
}

/// Thin wrapper so we can construct CABasicAnimation without name clash.
typealias CAPBasicAnimation = CABasicAnimation
