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
        audioSettings: ProjectAudioSettings = .default,
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

        var dialogueTrack: AVMutableCompositionTrack?
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first,
           let compAudio = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compAudio.insertTimeRange(insertRange, of: audioTrack, at: .zero)
            dialogueTrack = compAudio
        }

        var norm = AudioNormalizeService.Normalization(
            dialogueGain: 1,
            measuredPeak: AudioNormalizeService.targetPeak,
            sfxGainScale: brandSfxGain * audioSettings.sfxMasterGain
        )
        if audioSettings.normalizeLoudness {
            statusMessage = "Measuring loudness…"
            let peak = try await AudioNormalizeService.analyzeDialoguePeak(videoURL: videoURL)
            norm = AudioNormalizeService.normalization(
                measuredPeak: peak,
                brandSfxGain: brandSfxGain * audioSettings.sfxMasterGain
            )
        }

        // Mix in library SFX cues (already shifted to local 0-based timeline when chunked).
        // `norm.sfxGainScale` already folds brand × master when loudness-normalize is on —
        // pass peak compensation only so we don't multiply those factors twice (which could
        // crush SFX toward silence).
        let sfxMaster = audioSettings.sfxMasterGain * brandSfxGain
        let peakCompensation: Double = {
            guard audioSettings.normalizeLoudness else { return 1.0 }
            return norm.sfxGainScale / max(sfxMaster, 0.01)
        }()
        let mixedSFX = try await mixSoundEffects(
            into: composition,
            cues: soundEffects,
            libraryRoot: libraryRoot,
            timelineDuration: compositionDuration,
            masterGain: sfxMaster,
            normalizeScale: peakCompensation
        )

        progress = 0.15
        statusMessage = "Rendering \(aspect.rawValue) canvas…"

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: compositionDuration)

        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)
        let fitTransform = AspectFit.transform(
            naturalSize: naturalSize,
            preferredTransform: preferredTransform,
            targetSize: renderSize
        )
        layerInstruction.setTransform(fitTransform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        // Core Animation overlay pipeline on the target aspect canvas.
        // isGeometryFlipped = true → UIKit/SwiftUI coords (origin top-left, Y down),
        // matching CaptionOverlayView / LiveOverlayCanvas normalized positions.
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

        let timelineSeconds = CMTimeGetSeconds(compositionDuration)
        addCaptionLayers(
            to: overlayRoot,
            captions: captions,
            style: style,
            size: renderSize,
            duration: timelineSeconds
        )
        addOverlayLayers(
            to: overlayRoot,
            overlays: overlays,
            size: renderSize,
            libraryRoot: libraryRoot,
            duration: timelineSeconds
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

        let dialogueVolume = Float(audioSettings.dialogueGain)
            * (audioSettings.normalizeLoudness ? norm.dialogueGain : 1)
        var mixGains: [AudioNormalizeService.TrackGain] = []
        if let dialogueTrack {
            var duckWindows: [(start: TimeInterval, end: TimeInterval, amount: Float)] = []
            if audioSettings.duckDialogueUnderSFX {
                duckWindows = mixedSFX.map {
                    (
                        start: $0.startTime,
                        end: $0.startTime + $0.duration,
                        amount: Float(max(0, min(0.85, audioSettings.duckAmount)))
                    )
                }
            }
            mixGains.append(
                .init(track: dialogueTrack, volume: dialogueVolume, duckWindows: duckWindows)
            )
        }
        for sfx in mixedSFX {
            mixGains.append(.init(track: sfx.track, volume: sfx.volume))
        }
        if let mix = AudioNormalizeService.audioMix(gains: mixGains) {
            session.audioMix = mix
            statusMessage = "Encoding \(aspect.rawValue) (audio ×\(String(format: "%.2f", dialogueVolume)))…"
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
            let start = max(0, caption.startTime)
            let end = max(start + 0.05, min(caption.endTime, duration > 0 ? duration : caption.endTime))
            guard end > start, start < duration || duration <= 0 else { continue }

            let midX = size.width * style.positionX
            let midY = size.height * style.positionY
            let fontSize = style.fontSize * (size.width / 390)
            let maxWidth = size.width * 0.88

            // Match preview: karaoke / typewriter when word timings exist.
            if style.animation == .karaoke, !caption.words.isEmpty {
                addKaraokeCaptionLayers(
                    to: root,
                    caption: caption,
                    style: style,
                    fontSize: fontSize,
                    maxWidth: maxWidth,
                    midX: midX,
                    midY: midY,
                    clipStart: start,
                    clipEnd: end,
                    timelineDuration: duration
                )
                continue
            }

            if style.animation == .typewriter {
                addTypewriterCaptionLayers(
                    to: root,
                    caption: caption,
                    style: style,
                    fontSize: fontSize,
                    maxWidth: maxWidth,
                    midX: midX,
                    midY: midY,
                    clipStart: start,
                    clipEnd: end,
                    timelineDuration: duration
                )
                continue
            }

            let text = style.textCase.apply(caption.text)
            let layer = Self.makeTextLayer(
                text: text,
                fontName: style.fontName,
                fontSize: fontSize,
                textColor: style.textColor.platformColor,
                strokeColor: style.strokeColor.platformColor,
                strokeWidth: style.strokeWidth,
                backgroundColor: style.backgroundColor.platformColor,
                cornerRadius: style.cornerRadius,
                shadowColor: style.shadowColor.platformColor,
                shadowRadius: style.shadowRadius,
                maxWidth: maxWidth
            )
            layer.position = CGPoint(x: midX, y: midY)
            Self.scheduleVisibility(
                on: layer,
                startTime: start,
                endTime: end,
                opacity: 1,
                timelineDuration: duration
            )
            root.addSublayer(layer)
        }
    }

    /// Word-by-word karaoke burn-in (parity with `AnimatedCaptionText` preview).
    private func addKaraokeCaptionLayers(
        to root: CALayer,
        caption: CaptionSegment,
        style: CaptionStyle,
        fontSize: CGFloat,
        maxWidth: CGFloat,
        midX: CGFloat,
        midY: CGFloat,
        clipStart: TimeInterval,
        clipEnd: TimeInterval,
        timelineDuration: TimeInterval
    ) {
        let words = caption.words.filter { $0.endTime > clipStart && $0.startTime < clipEnd }
        guard !words.isEmpty else {
            let text = style.textCase.apply(caption.text)
            let layer = Self.makeTextLayer(
                text: text,
                fontName: style.fontName,
                fontSize: fontSize,
                textColor: style.textColor.platformColor,
                strokeColor: style.strokeColor.platformColor,
                strokeWidth: style.strokeWidth,
                backgroundColor: style.backgroundColor.platformColor,
                cornerRadius: style.cornerRadius,
                shadowColor: style.shadowColor.platformColor,
                shadowRadius: style.shadowRadius,
                maxWidth: maxWidth
            )
            layer.position = CGPoint(x: midX, y: midY)
            Self.scheduleVisibility(
                on: layer,
                startTime: clipStart,
                endTime: clipEnd,
                opacity: 1,
                timelineDuration: timelineDuration
            )
            root.addSublayer(layer)
            return
        }

        let spacing: CGFloat = 5 * (fontSize / 42)
        var wordSizes: [CGSize] = []
        var totalWidth: CGFloat = 0
        for word in words {
            let text = style.textCase.apply(word.text)
            let size = Self.measureText(text, fontName: style.fontName, fontSize: fontSize, maxWidth: maxWidth)
            wordSizes.append(size)
            totalWidth += size.width
        }
        totalWidth += spacing * CGFloat(max(0, words.count - 1))
        var cursorX = midX - min(totalWidth, maxWidth) / 2
        let highlight = PlatformColor(red: 1, green: 0.92, blue: 0.35, alpha: 1)

        for (index, word) in words.enumerated() {
            let text = style.textCase.apply(word.text)
            let wSize = wordSizes[index]
            let center = CGPoint(x: cursorX + wSize.width / 2, y: midY)
            let wordStart = max(clipStart, min(clipEnd, word.startTime))
            let wordEnd = max(wordStart + 0.05, min(clipEnd, word.endTime))

            func place(_ color: PlatformColor, from t0: TimeInterval, to t1: TimeInterval, opacity: Float) {
                guard t1 > t0 + 0.02 else { return }
                let layer = Self.makeTextLayer(
                    text: text,
                    fontName: style.fontName,
                    fontSize: fontSize,
                    textColor: color,
                    strokeColor: style.strokeColor.platformColor,
                    strokeWidth: style.strokeWidth,
                    backgroundColor: .clear,
                    cornerRadius: 0,
                    shadowColor: style.shadowColor.platformColor,
                    shadowRadius: style.shadowRadius,
                    maxWidth: maxWidth
                )
                layer.position = center
                Self.scheduleVisibility(
                    on: layer,
                    startTime: t0,
                    endTime: t1,
                    opacity: opacity,
                    timelineDuration: timelineDuration
                )
                root.addSublayer(layer)
            }

            // Dim before spoken → highlight while active → full after (matches preview).
            place(style.textColor.platformColor, from: clipStart, to: wordStart, opacity: 0.35)
            place(highlight, from: wordStart, to: wordEnd, opacity: 1)
            place(style.textColor.platformColor, from: wordEnd, to: clipEnd, opacity: 1)

            cursorX += wSize.width + spacing
        }
    }

    private func addTypewriterCaptionLayers(
        to root: CALayer,
        caption: CaptionSegment,
        style: CaptionStyle,
        fontSize: CGFloat,
        maxWidth: CGFloat,
        midX: CGFloat,
        midY: CGFloat,
        clipStart: TimeInterval,
        clipEnd: TimeInterval,
        timelineDuration: TimeInterval
    ) {
        let full = style.textCase.apply(caption.text)
        guard !full.isEmpty else { return }
        let span = max(0.2, clipEnd - clipStart)
        let steps = min(full.count, 24)
        for step in 1...steps {
            let count = max(1, (full.count * step) / steps)
            let visible = String(full.prefix(count))
            let layer = Self.makeTextLayer(
                text: visible,
                fontName: style.fontName,
                fontSize: fontSize,
                textColor: style.textColor.platformColor,
                strokeColor: style.strokeColor.platformColor,
                strokeWidth: style.strokeWidth,
                backgroundColor: style.backgroundColor.platformColor,
                cornerRadius: style.cornerRadius,
                shadowColor: style.shadowColor.platformColor,
                shadowRadius: style.shadowRadius,
                maxWidth: maxWidth
            )
            layer.position = CGPoint(x: midX, y: midY)
            let t0 = clipStart + span * Double(step - 1) / Double(steps)
            let t1 = step == steps ? clipEnd : clipStart + span * Double(step) / Double(steps)
            Self.scheduleVisibility(
                on: layer,
                startTime: t0,
                endTime: t1,
                opacity: 1,
                timelineDuration: timelineDuration
            )
            root.addSublayer(layer)
        }
    }

    private struct MixedSFXTrack {
        var track: AVMutableCompositionTrack
        var volume: Float
        var startTime: TimeInterval
        var duration: TimeInterval
    }

    private func mixSoundEffects(
        into composition: AVMutableComposition,
        cues: [SoundEffectCue],
        libraryRoot: URL?,
        timelineDuration: CMTime,
        masterGain: Double,
        normalizeScale: Double
    ) async throws -> [MixedSFXTrack] {
        guard let libraryRoot, !cues.isEmpty else { return [] }
        let catalogURL = libraryRoot.appendingPathComponent("sfx/catalog.json")
        guard
            let data = try? Data(contentsOf: catalogURL),
            let catalog = try? JSONDecoder().decode(MediaLibraryCatalog.self, from: data)
        else { return [] }

        var mixed: [MixedSFXTrack] = []
        for cue in cues where !cue.isMuted {
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
            let volume = Float(min(1.4, max(0.05, cue.gain * masterGain * normalizeScale)))
            mixed.append(
                MixedSFXTrack(
                    track: compAudio,
                    volume: volume,
                    startTime: cue.startTime,
                    duration: insertDuration.seconds
                )
            )
        }
        return mixed
    }

    private func addOverlayLayers(
        to root: CALayer,
        overlays: [OverlayItem],
        size: CGSize,
        libraryRoot: URL?,
        duration: TimeInterval
    ) {
        for item in overlays {
            let start = max(0, item.startTime)
            let end = max(start + 0.05, min(item.endTime, duration > 0 ? duration : item.endTime))
            guard end > start else { continue }
            if duration > 0, start >= duration { continue }

            let layer: CALayer
            switch item.kind {
            case .emoji, .text, .watermark, .wordHit:
                let fontName = Self.resolveFontName(for: item, libraryRoot: libraryRoot)
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
                // Outer host owns opacity + rotation; inner content can punch-scale without fighting transforms.
                let content = Self.makeTextLayer(
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
                let host = CALayer()
                host.bounds = content.bounds
                content.position = CGPoint(x: host.bounds.midX, y: host.bounds.midY)
                host.addSublayer(content)
                if isHit {
                    let punch = CAKeyframeAnimation(keyPath: "transform.scale")
                    punch.values = [0.45, 1.28, 1.0]
                    punch.keyTimes = [0, 0.55, 1]
                    punch.duration = 0.22
                    punch.beginTime = AVCoreAnimationBeginTimeAtZero + start
                    punch.fillMode = .both
                    punch.isRemovedOnCompletion = false
                    content.add(punch, forKey: "punchScale")
                }
                layer = host
            case .gif:
                guard let libraryRoot,
                      let url = Self.libraryMediaURL(
                        kindFolder: "gifs",
                        fileName: item.assetFileName,
                        assetId: item.assetId,
                        libraryRoot: libraryRoot
                      )
                else { continue }
                let frames = AnimatedGIFDecoder.load(url: url)
                guard let first = frames.images.first else { continue }

                let imageLayer = CALayer()
                let side = 90 * item.scale * (size.width / 390)
                imageLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
                imageLayer.contents = first
                imageLayer.contentsGravity = .resizeAspect
                layer = imageLayer

                if frames.isAnimated, frames.images.count == frames.keyTimes.count {
                    let cycle = max(frames.totalDuration, 0.05)
                    let visible = max(0.05, end - start)
                    let anim = CAKeyframeAnimation(keyPath: "contents")
                    anim.values = frames.images.map { $0 as Any }
                    anim.keyTimes = frames.keyTimes
                    anim.duration = cycle
                    anim.calculationMode = .discrete
                    anim.repeatCount = Float(ceil(visible / cycle) + 1)
                    anim.beginTime = AVCoreAnimationBeginTimeAtZero + start
                    anim.fillMode = .both
                    anim.isRemovedOnCompletion = false
                    imageLayer.add(anim, forKey: "gifFrames")
                }
            case .png:
                guard let libraryRoot,
                      let url = Self.libraryMediaURL(
                        kindFolder: "pngs",
                        fileName: item.assetFileName,
                        assetId: item.assetId,
                        libraryRoot: libraryRoot
                      ),
                      let image = Self.loadCGImage(url: url)
                else { continue }
                let imageLayer = CALayer()
                let side = 90 * item.scale * (size.width / 390)
                imageLayer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
                imageLayer.contents = image
                imageLayer.contentsGravity = .resizeAspect
                layer = imageLayer
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
                y: size.height * item.y
            )
            layer.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(item.rotation * .pi / 180)))
            Self.scheduleVisibility(
                on: layer,
                startTime: start,
                endTime: end,
                opacity: Float(max(0, min(1, item.opacity))),
                timelineDuration: duration
            )
            root.addSublayer(layer)
        }
    }

    /// macOS/Catalyst often ignore deferred `beginTime` opacity animations during
    /// `AVAssetExportSession` offline render. Drive opacity across the **full**
    /// composition timeline so layers actually appear in the MP4.
    private static func scheduleVisibility(
        on layer: CALayer,
        startTime: TimeInterval,
        endTime: TimeInterval,
        opacity: Float,
        timelineDuration: TimeInterval
    ) {
        let fadeIn: TimeInterval = 0.08
        let fadeOut: TimeInterval = 0.1
        let start = max(0, startTime)
        let end = max(start + 0.05, endTime)
        let total = max(timelineDuration, end + fadeOut, 0.05)

        let appear = start
        let visible = min(end, start + min(fadeIn, max(0.02, (end - start) * 0.25)))
        let fade = end
        let gone = min(total, end + fadeOut)

        // Build strictly increasing key times over the full composition.
        var samples: [(t: Double, v: Float)] = [
            (0, 0),
            (appear / total, 0),
            (visible / total, opacity),
            (fade / total, opacity),
            (gone / total, 0),
            (1, 0)
        ]
        var keyTimes: [NSNumber] = []
        var values: [Float] = []
        var lastT: Double = -1
        for sample in samples {
            let t = min(1, max(0, sample.t))
            if t <= lastT + 0.0005 {
                // Keep last value for duplicate/near-duplicate times.
                if !values.isEmpty {
                    values[values.count - 1] = sample.v
                }
                continue
            }
            keyTimes.append(NSNumber(value: t))
            values.append(sample.v)
            lastT = t
        }
        if keyTimes.count < 2 {
            keyTimes = [0, 1]
            values = [opacity, opacity]
        }

        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = values
        anim.keyTimes = keyTimes
        anim.duration = total
        anim.beginTime = AVCoreAnimationBeginTimeAtZero
        anim.calculationMode = .linear
        anim.fillMode = .both
        anim.isRemovedOnCompletion = false

        layer.opacity = 0
        layer.add(anim, forKey: "visibility")
    }

    private static func libraryMediaURL(
        kindFolder: String,
        fileName: String?,
        assetId: String?,
        libraryRoot: URL
    ) -> URL? {
        if let fileName {
            let url = libraryRoot.appendingPathComponent(kindFolder).appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        guard let assetId,
              let data = try? Data(contentsOf: libraryRoot.appendingPathComponent("\(kindFolder)/catalog.json")),
              let catalog = try? JSONDecoder().decode(MediaLibraryCatalog.self, from: data),
              let file = catalog.items.first(where: { $0.id == assetId })?.file
        else { return nil }
        let url = libraryRoot.appendingPathComponent(kindFolder).appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static func resolveFontName(for item: OverlayItem, libraryRoot: URL?) -> String {
        if let fontName = item.fontName, !fontName.isEmpty { return fontName }
        guard let libraryRoot else { return "AvenirNext-Heavy" }
        if let styleId = item.styleAssetId,
           let data = try? Data(contentsOf: libraryRoot.appendingPathComponent("text-styles/catalog.json")),
           let catalog = try? JSONDecoder().decode(MediaLibraryCatalog.self, from: data),
           let name = catalog.items.first(where: { $0.id == styleId })?.fontName,
           !name.isEmpty {
            return name
        }
        if let fontId = item.fontId ?? item.assetId,
           let data = try? Data(contentsOf: libraryRoot.appendingPathComponent("fonts/catalog.json")),
           let catalog = try? JSONDecoder().decode(MediaLibraryCatalog.self, from: data),
           let name = catalog.items.first(where: { $0.id == fontId })?.fontName,
           !name.isEmpty {
            return name
        }
        return "AvenirNext-Heavy"
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

    private static func measureText(
        _ text: String,
        fontName: String,
        fontSize: CGFloat,
        maxWidth: CGFloat
    ) -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: PlatformFont(name: fontName, size: fontSize) ?? .systemFont(ofSize: fontSize, weight: .bold)
        ]
        let bound = (text as NSString).boundingRect(
            with: CGSize(width: maxWidth, height: 400),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs,
            context: nil
        )
        return CGSize(width: ceil(bound.width) + 4, height: ceil(bound.height) + 4)
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
