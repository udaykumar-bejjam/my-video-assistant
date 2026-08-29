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
        brandSfxGain: Double = 0.8,
        chessOverlay: ChessWalkthroughSpec? = nil
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
        videoComposition.renderScale = 1.0

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
        // Use DEFAULT (bottom-left) Core Animation coords — the Apple sample-code
        // pattern for AVVideoCompositionCoreAnimationTool. Map SwiftUI/top-left
        // normalized Y with `height * (1 - y)`. Avoid isGeometryFlipped: it breaks
        // offline text burn-in on macOS (blank or upside-down CATextLayer).
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: renderSize)
        parentLayer.backgroundColor = PlatformColor.black.cgColor

        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.bounds
        parentLayer.addSublayer(videoLayer)

        let overlayRoot = CALayer()
        overlayRoot.frame = parentLayer.bounds
        parentLayer.addSublayer(overlayRoot)

        let timelineSeconds = CMTimeGetSeconds(compositionDuration)
        // Word hits already punch significant words — karaoke on the same words
        // reads as "double highlights". Prefer plain captions when hits exist.
        let hasWordHits = overlays.contains { $0.kind == .wordHit }
        addCaptionLayers(
            to: overlayRoot,
            captions: captions,
            style: style,
            size: renderSize,
            duration: timelineSeconds,
            suppressKaraoke: hasWordHits
        )
        addOverlayLayers(
            to: overlayRoot,
            overlays: overlays,
            size: renderSize,
            libraryRoot: libraryRoot,
            duration: timelineSeconds
        )
        if let chessOverlay {
            addChessOverlayLayers(
                to: overlayRoot,
                spec: chessOverlay,
                size: renderSize,
                duration: timelineSeconds
            )
        }

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
        duration: TimeInterval,
        suppressKaraoke: Bool = false
    ) {
        for caption in captions {
            let start = max(0, caption.startTime)
            let end = max(start + 0.05, min(caption.endTime, duration > 0 ? duration : caption.endTime))
            guard end > start, start < duration || duration <= 0 else { continue }

            let midX = size.width * style.positionX
            // Bottom-left CA coords: invert SwiftUI/top-left normalized Y.
            let midY = size.height * (1 - style.positionY)
            let fontSize = style.fontSize * (size.width / 390)
            let maxWidth = size.width * 0.88

            // Match preview: karaoke / typewriter when word timings exist.
            // Skip karaoke when word-hit overlays already highlight words.
            if style.animation == .karaoke, !caption.words.isEmpty, !suppressKaraoke {
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

            if style.animation == .typewriter, !suppressKaraoke {
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
    ///
    /// One layer per word (not dim/highlight/full stacks). Stacked layers plus
    /// fail-open opacity produced "double highlights" when Core Animation was ignored.
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

        // Match preview HStack spacing: 5 * (fontSize/42) ≈ 5 * layoutScale when fontSize = 42 * scale.
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
        let base = style.textColor.platformColor

        for (index, word) in words.enumerated() {
            let text = style.textCase.apply(word.text)
            let wSize = wordSizes[index]
            let center = CGPoint(x: cursorX + wSize.width / 2, y: midY)
            let wordStart = max(clipStart, min(clipEnd, word.startTime))
            let wordEnd = max(wordStart + 0.05, min(clipEnd, word.endTime))

            // Pre-rasterize the three visual states; swap `contents` on one layer.
            let dimImg = Self.rasterizeText(
                text: text,
                fontName: style.fontName,
                fontSize: fontSize,
                textColor: base.withAlphaComponent(0.35),
                strokeColor: style.strokeColor.platformColor,
                strokeWidth: style.strokeWidth,
                backgroundColor: .clear,
                cornerRadius: 0,
                shadowColor: style.shadowColor.platformColor,
                shadowRadius: style.shadowRadius * 0.5,
                maxWidth: maxWidth
            )
            let hitImg = Self.rasterizeText(
                text: text,
                fontName: style.fontName,
                fontSize: fontSize,
                textColor: highlight,
                strokeColor: style.strokeColor.platformColor,
                strokeWidth: style.strokeWidth,
                backgroundColor: .clear,
                cornerRadius: 0,
                shadowColor: style.shadowColor.platformColor,
                shadowRadius: style.shadowRadius,
                maxWidth: maxWidth
            )
            let fullImg = Self.rasterizeText(
                text: text,
                fontName: style.fontName,
                fontSize: fontSize,
                textColor: base,
                strokeColor: style.strokeColor.platformColor,
                strokeWidth: style.strokeWidth,
                backgroundColor: .clear,
                cornerRadius: 0,
                shadowColor: style.shadowColor.platformColor,
                shadowRadius: style.shadowRadius,
                maxWidth: maxWidth
            )

            let layer = CALayer()
            let ref = fullImg ?? hitImg ?? dimImg
            if let ref {
                let w = CGFloat(ref.width) / 3
                let h = CGFloat(ref.height) / 3
                layer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
                layer.contentsScale = 3
            } else {
                layer.bounds = CGRect(x: 0, y: 0, width: wSize.width, height: wSize.height)
            }
            layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            layer.position = center
            // Fail-open: readable settled word (not stacked dim+highlight+full).
            layer.contents = fullImg ?? hitImg ?? dimImg
            layer.opacity = 1

            let total = max(timelineDuration, clipEnd + 0.1, 0.05)
            func t(_ seconds: TimeInterval) -> NSNumber {
                NSNumber(value: min(1, max(0, seconds / total)))
            }

            // contents: dim → highlight → full across the caption window.
            if let dimImg, let hitImg, let fullImg {
                let contents = CAKeyframeAnimation(keyPath: "contents")
                contents.values = [dimImg, hitImg, fullImg, fullImg]
                contents.keyTimes = [t(0), t(wordStart), t(wordEnd), t(total)]
                contents.duration = total
                contents.beginTime = AVCoreAnimationBeginTimeAtZero
                contents.calculationMode = .discrete
                contents.fillMode = .both
                contents.isRemovedOnCompletion = false
                layer.add(contents, forKey: "karaokeContents")
            }

            Self.scheduleVisibility(
                on: layer,
                startTime: clipStart,
                endTime: clipEnd,
                opacity: 1,
                timelineDuration: timelineDuration
            )
            root.addSublayer(layer)

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
            // Prefer wav for composition insert reliability; fall back to m4a.
            let fileName = item.wav ?? item.file
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
                // Match preview: fontSize * scale * (width/390). No extra 0.95 shrink.
                let fontSize = item.fontSize * item.scale * (size.width / 390)
                let isHit = item.kind == .wordHit
                let catalogStyle = Self.resolveTextStyle(for: item, libraryRoot: libraryRoot)
                let fill: PlatformColor = {
                    if isHit { return item.color.platformColor }
                    return Self.platformColor(hex: catalogStyle?.textColor) ?? item.color.platformColor
                }()
                #if canImport(UIKit)
                let blackStroke = UIColor.black.withAlphaComponent(0.9)
                let yellowGlow = UIColor(red: 1, green: 0.94, blue: 0.35, alpha: 0.9)
                #else
                let blackStroke = NSColor.black.withAlphaComponent(0.9)
                let yellowGlow = NSColor(srgbRed: 1, green: 0.94, blue: 0.35, alpha: 0.9)
                #endif
                let bg: PlatformColor = Self.platformColor(hex: catalogStyle?.backgroundColor) ?? .clear
                let stroke: PlatformColor = isHit ? blackStroke : .clear
                let strokeW: CGFloat = isHit ? 2.5 : 0
                let shadow: PlatformColor = isHit ? yellowGlow : PlatformColor.black.withAlphaComponent(0.45)
                let shadowR: CGFloat = isHit ? 16 : (catalogStyle?.shadowRadius ?? 6)
                let resolvedFontSize = catalogStyle?.fontSize.map { $0 * item.scale * (size.width / 390) } ?? fontSize

                // Outer host owns opacity + rotation; inner content can punch-scale without fighting transforms.
                let content = Self.makeTextLayer(
                    text: item.text,
                    fontName: catalogStyle?.fontName ?? fontName,
                    fontSize: isHit ? fontSize : resolvedFontSize,
                    textColor: fill,
                    strokeColor: stroke,
                    strokeWidth: strokeW,
                    backgroundColor: isHit ? .clear : bg,
                    cornerRadius: catalogStyle?.cornerRadius ?? 0,
                    shadowColor: shadow,
                    shadowRadius: shadowR,
                    maxWidth: size.width * 0.8,
                    glowBloom: isHit
                )
                let host = CALayer()
                host.bounds = content.bounds
                content.position = CGPoint(x: host.bounds.midX, y: host.bounds.midY)
                host.addSublayer(content)
                if isHit {
                    // Punch scale over the hit window (full-timeline, fail-soft).
                    let total = max(duration, end + 0.05, 0.05)
                    let punch = CAKeyframeAnimation(keyPath: "transform.scale")
                    punch.values = [0.45, 1.28, 1.0, 1.0]
                    punch.keyTimes = [
                        NSNumber(value: 0),
                        NSNumber(value: min(1, start / total)),
                        NSNumber(value: min(1, (start + 0.22) / total)),
                        NSNumber(value: 1)
                    ]
                    punch.duration = total
                    punch.beginTime = AVCoreAnimationBeginTimeAtZero
                    punch.calculationMode = .linear
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
                y: size.height * (1 - item.y)
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

    /// Composite an analyzed PGN walkthrough as a corner board with timed frames.
    private func addChessOverlayLayers(
        to root: CALayer,
        spec: ChessWalkthroughSpec,
        size: CGSize,
        duration: TimeInterval
    ) {
        guard duration > 0.05 else { return }
        let parsed: ChessAnalysisResult
        do {
            parsed = try ChessPGNParser.parse(spec.pgn)
        } catch {
            return
        }
        guard !parsed.moves.isEmpty else { return }

        var board = ChessBoard.starting()
        var boards = [board]
        for move in parsed.moves {
            do {
                _ = try board.applySAN(move.san)
                boards.append(board)
            } catch {
                break
            }
        }
        let moveCount = min(parsed.moves.count, boards.count - 1)
        guard moveCount > 0 else { return }

        let boardPixel = min(size.width, size.height) * max(0.25, min(0.55, spec.layout.size))
        let renderSize = CGSize(width: boardPixel, height: boardPixel)

        var images: [CGImage] = []
        var keyTimes: [NSNumber] = []
        let total = max(duration, 0.05)

        // Before startOffset: empty / hidden via opacity; still need at least one contents frame.
        if let startImage = ChessBoardRenderer.makeCGImage(
            board: boards[0],
            move: nil,
            callout: nil,
            title: nil,
            size: renderSize,
            transparentBackground: true
        ) {
            images.append(startImage)
            keyTimes.append(0)
        }

        for i in 0..<moveCount {
            let boardIdx = min(i + 1, boards.count - 1)
            let move = parsed.moves[i]
            let callout: String? = {
                guard spec.includeCallouts else { return nil }
                var parts = ["\(move.moveNumber)\(move.isWhite ? "." : "...") \(move.san)"]
                if move.category.isHighlightWorthy { parts.append(move.category.label) }
                return parts.joined(separator: " · ")
            }()
            // For transparent corner board, skip callout text (preview/export use color flash on squares).
            guard let image = ChessBoardRenderer.makeCGImage(
                board: boards[boardIdx],
                move: move,
                callout: nil,
                title: nil,
                size: renderSize,
                transparentBackground: true
            ) else { continue }
            let t = min(1, max(0, (spec.startOffset + Double(i) * spec.secondsPerMove) / total))
            images.append(image)
            keyTimes.append(NSNumber(value: t))
            _ = callout
        }

        // Hold last frame until endTime
        let endT = min(1, max(0, spec.endTime(moveCount: moveCount) / total))
        if let last = images.last {
            images.append(last)
            keyTimes.append(NSNumber(value: endT))
        }
        if let last = images.last {
            images.append(last)
            keyTimes.append(1)
        }

        guard images.count == keyTimes.count, images.count >= 2 else { return }

        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: boardPixel, height: boardPixel)
        layer.contents = images[0]
        layer.contentsGravity = .resizeAspect
        layer.cornerRadius = 10
        layer.masksToBounds = true
        layer.borderWidth = 2
        layer.borderColor = CGColor(red: 0.2, green: 0.95, blue: 0.72, alpha: 0.85)
        // layout.origin is top-left normalized; CALayer Y is bottom-up.
        let centerX = size.width * (spec.layout.originX + spec.layout.size / 2)
        let centerY = size.height * (1 - (spec.layout.originY + spec.layout.size / 2))
        layer.position = CGPoint(x: centerX, y: centerY)

        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = images.map { $0 as Any }
        anim.keyTimes = keyTimes
        anim.duration = total
        anim.calculationMode = .discrete
        anim.beginTime = AVCoreAnimationBeginTimeAtZero
        anim.fillMode = .both
        anim.isRemovedOnCompletion = false
        layer.add(anim, forKey: "chessFrames")

        let visibleStart = max(0, spec.startOffset - 0.05)
        let visibleEnd = min(duration, spec.endTime(moveCount: moveCount) + 0.15)
        Self.scheduleVisibility(
            on: layer,
            startTime: visibleStart,
            endTime: visibleEnd,
            opacity: 1,
            timelineDuration: duration
        )
        root.addSublayer(layer)
    }

    /// Schedule when a layer is visible during offline export.
    ///
    /// CRITICAL: model `opacity` is set to the **visible** value (fail-open).
    /// macOS `AVAssetExportSession` often ignores Core Animation opacity
    /// animations entirely — if we leave model opacity at 0, the MP4 is blank
    /// (no captions, no overlays). Prefer wrong timing over a blank export.
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

        // Fail-open: if the animation is ignored, captions/overlays still burn in.
        layer.opacity = opacity
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

    private static func resolveTextStyle(for item: OverlayItem, libraryRoot: URL?) -> MediaLibraryItem? {
        guard let libraryRoot, let styleId = item.styleAssetId else { return nil }
        guard let data = try? Data(contentsOf: libraryRoot.appendingPathComponent("text-styles/catalog.json")),
              let catalog = try? JSONDecoder().decode(MediaLibraryCatalog.self, from: data)
        else { return nil }
        return catalog.items.first(where: { $0.id == styleId })
    }

    private static func platformColor(hex: String?) -> PlatformColor? {
        guard var cleaned = hex?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              !cleaned.isEmpty
        else { return nil }
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }
        guard cleaned.count == 6 || cleaned.count == 8 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }
        let a, r, g, b: CGFloat
        if cleaned.count == 8 {
            a = CGFloat((value & 0xFF00_0000) >> 24) / 255
            r = CGFloat((value & 0x00FF_0000) >> 16) / 255
            g = CGFloat((value & 0x0000_FF00) >> 8) / 255
            b = CGFloat(value & 0x0000_00FF) / 255
        } else {
            a = 1
            r = CGFloat((value & 0xFF0000) >> 16) / 255
            g = CGFloat((value & 0x00FF00) >> 8) / 255
            b = CGFloat(value & 0x0000FF) / 255
        }
        #if canImport(UIKit)
        return UIColor(red: r, green: g, blue: b, alpha: a)
        #elseif canImport(AppKit)
        return NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        #endif
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
        maxWidth: CGFloat,
        glowBloom: Bool = false
    ) -> CALayer {
        // Rasterize to CGImage — live CATextLayer often renders blank/upside-down
        // under AVVideoCompositionCoreAnimationTool on macOS offline export.
        let image = rasterizeText(
            text: text,
            fontName: fontName,
            fontSize: fontSize,
            textColor: textColor,
            strokeColor: strokeColor,
            strokeWidth: strokeWidth,
            backgroundColor: backgroundColor,
            cornerRadius: cornerRadius,
            shadowColor: shadowColor,
            shadowRadius: shadowRadius,
            maxWidth: maxWidth,
            glowBloom: glowBloom
        )
        let layer = CALayer()
        if let image {
            let w = CGFloat(image.width) / 3
            let h = CGFloat(image.height) / 3
            layer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
            layer.contents = image
            layer.contentsScale = 3
            layer.contentsGravity = .resize
        } else {
            layer.bounds = CGRect(x: 0, y: 0, width: 40, height: 20)
        }
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        return layer
    }

    /// Draw caption/overlay text into a bitmap. Offline export reliably burns
    /// `CALayer.contents` images; it often drops live `CATextLayer.string`.
    ///
    /// Uses Core Text in the CGContext's native bottom-left space so the bitmap
    /// is upright when composited (no flipped NSGraphicsContext — that mirrored
    /// captions in the exported MP4).
    private static func rasterizeText(
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
        maxWidth: CGFloat,
        glowBloom: Bool = false
    ) -> CGImage? {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping

        // Prefer PlatformFont for measurement; toll-free bridged for Core Text draw.
        let uiFont = PlatformFont(name: fontName, size: fontSize)
            ?? .systemFont(ofSize: fontSize, weight: .bold)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: uiFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraph
        ]
        if strokeWidth > 0 {
            attrs[.strokeColor] = strokeColor
            attrs[.strokeWidth] = -strokeWidth
        }

        let attributed = NSAttributedString(string: text, attributes: attrs)
        let textBound = attributed.boundingRect(
            with: CGSize(width: maxWidth, height: 800),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )
        let pad: CGFloat = backgroundColor.cgColor.alpha > 0.01 ? 16 : 8
        // Extra pad so multi-pass glow bloom isn't clipped at the bitmap edge.
        let bloomPad = glowBloom ? max(shadowRadius * 3.5, 28) : max(shadowRadius * 2.5, 6)
        let size = CGSize(
            width: max(8, ceil(textBound.width) + pad * 2 + bloomPad),
            height: max(8, ceil(textBound.height) + pad * 2 + bloomPad)
        )

        let scale: CGFloat = 3
        let pixelW = max(1, Int(size.width * scale))
        let pixelH = max(1, Int(size.height * scale))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Work in point space; CGContext origin is bottom-left (matches CALayer.contents).
        ctx.scaleBy(x: scale, y: scale)

        let inset = CGRect(
            x: bloomPad / 2,
            y: bloomPad / 2,
            width: size.width - bloomPad,
            height: size.height - bloomPad
        )

        if backgroundColor.cgColor.alpha > 0.01 {
            let path = CGPath(
                roundedRect: inset,
                cornerWidth: cornerRadius,
                cornerHeight: cornerRadius,
                transform: nil
            )
            ctx.setFillColor(backgroundColor.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
        }

        let frameSetter = CTFramesetterCreateWithAttributedString(attributed)
        let textRect = CGRect(
            x: (size.width - textBound.width) / 2,
            y: (size.height - textBound.height) / 2,
            width: max(1, textBound.width),
            height: max(1, textBound.height)
        )
        // CTFramesetter expects a path; Core Text draws with y-up inside the path.
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(
            frameSetter,
            CFRange(location: 0, length: attributed.length),
            path,
            nil
        )

        // Soft bloom behind word hits (preview uses a blurred duplicate + shadows).
        if glowBloom, shadowRadius > 0 {
            let soft = shadowColor.withAlphaComponent(0.35)
            let mid = shadowColor.withAlphaComponent(0.55)
            let tight = shadowColor.withAlphaComponent(0.85)
            ctx.setShadow(offset: .zero, blur: shadowRadius * 2.4, color: soft.cgColor)
            CTFrameDraw(frame, ctx)
            ctx.setShadow(offset: .zero, blur: shadowRadius * 1.4, color: mid.cgColor)
            CTFrameDraw(frame, ctx)
            ctx.setShadow(offset: .zero, blur: shadowRadius * 0.7, color: tight.cgColor)
            CTFrameDraw(frame, ctx)
            // Crisp fill + stroke on top (light residual glow).
            ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: max(4, shadowRadius * 0.35), color: shadowColor.cgColor)
            CTFrameDraw(frame, ctx)
        } else {
            if shadowRadius > 0 {
                ctx.setShadow(
                    offset: CGSize(width: 0, height: -2),
                    blur: shadowRadius,
                    color: shadowColor.cgColor
                )
            }
            CTFrameDraw(frame, ctx)
        }
        ctx.setShadow(offset: .zero, blur: 0, color: nil)

        return ctx.makeImage()
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
