import Foundation
import AVFoundation
import CoreImage
import CoreText
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
        outputURL: URL? = nil
    ) async throws -> URL {
        progress = 0.02
        statusMessage = "Building composition…"

        let asset = AVURLAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw ExportError.compositionFailed("No video track found.")
        }

        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let renderSize = Self.orientedSize(naturalSize, transform: preferredTransform)

        let composition = AVMutableComposition()
        guard
            let compVideo = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw ExportError.compositionFailed("Could not create video track.")
        }

        try compVideo.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: videoTrack,
            at: .zero
        )
        compVideo.preferredTransform = preferredTransform

        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let compAudio = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compAudio.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: audioTrack,
                at: .zero
            )
        }

        progress = 0.15
        statusMessage = "Rendering captions…"

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        layerInstruction.setTransform(preferredTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        // Core Animation overlay pipeline
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.isGeometryFlipped = true

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
            duration: CMTimeGetSeconds(duration)
        )
        addOverlayLayers(
            to: overlayRoot,
            overlays: overlays,
            size: renderSize
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

        progress = 0.25
        statusMessage = "Encoding video…"

        // Poll progress while exporting
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

    private func addOverlayLayers(
        to root: CALayer,
        overlays: [OverlayItem],
        size: CGSize
    ) {
        for item in overlays {
            let layer: CALayer
            switch item.kind {
            case .emoji, .text, .watermark:
                layer = Self.makeTextLayer(
                    text: item.text,
                    fontName: "AvenirNext-Bold",
                    fontSize: item.fontSize * item.scale * (size.width / 390),
                    textColor: item.color.platformColor,
                    strokeColor: .clear,
                    strokeWidth: 0,
                    backgroundColor: .clear,
                    cornerRadius: 0,
                    shadowColor: PlatformColor.black.withAlphaComponent(0.4),
                    shadowRadius: 4,
                    maxWidth: size.width * 0.7
                )
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
