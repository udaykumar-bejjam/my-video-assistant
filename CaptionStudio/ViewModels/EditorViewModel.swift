import Foundation
import AVFoundation
import SwiftUI
import Combine
import UniformTypeIdentifiers
#if canImport(AVFAudio)
import AVFAudio
#endif

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var project: VideoProject = .empty()
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var isTranscribing = false
    @Published var isEnhancing = false
    @Published var isExporting = false
    @Published var selectedCaptionID: CaptionSegment.ID?
    @Published var selectedOverlayID: OverlayItem.ID?
    @Published var selectedPreset: CaptionPreset = .boldWhite
    @Published var errorMessage: String?
    @Published var exportURL: URL?
    @Published var showExporter = false
    @Published var editorTab: EditorTab = .captions
    @Published var lastEnhancementNote: String?
    @Published var libraryKind: MediaLibraryKind = .textStyles
    @Published var chunkProgressLabel: String?
    @Published var language: AppLanguage = .english

    let transcription = TranscriptionService()
    let exporter = VideoExportService()
    let stitcher = VideoStitchService()
    let libraries = MediaLibraryStore()
    let enhancer = CursorEnhancerClient()

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var sfxPlayers: [AVAudioPlayer] = []

    enum EditorTab: String, CaseIterable, Identifiable {
        case captions, styles, overlays, libraries, export
        var id: String { rawValue }
        var title: String {
            switch self {
            case .captions: return "Captions"
            case .styles: return "Styles"
            case .overlays: return "Overlays"
            case .libraries: return "Library"
            case .export: return "Export"
            }
        }
        var icon: String {
            switch self {
            case .captions: return "text.bubble.fill"
            case .styles: return "paintpalette.fill"
            case .overlays: return "square.stack.3d.up.fill"
            case .libraries: return "square.grid.2x2.fill"
            case .export: return "square.and.arrow.up.fill"
            }
        }
    }

    var activeCaption: CaptionSegment? {
        project.captions.first { $0.contains(time: currentTime) }
    }

    var visibleOverlays: [OverlayItem] {
        project.overlays.filter { $0.isVisible(at: currentTime) }
    }

    // MARK: - Video load

    func loadVideo(url: URL) async {
        tearDownPlayer()

        // Copy into app sandbox so security-scoped imports stay readable.
        let localURL: URL
        do {
            localURL = try Self.copyIntoCaches(url)
        } catch {
            errorMessage = "Could not open video: \(error.localizedDescription)"
            return
        }

        project.videoURL = localURL
        project.title = url.deletingPathExtension().lastPathComponent
        project.captions = []
        project.overlays = []
        project.soundEffects = []
        project.enhancementSummary = nil
        project.captionStyle = selectedPreset.style
        project.chunkCount = 1
        lastEnhancementNote = nil
        chunkProgressLabel = nil
        Task { await enhancer.checkHealth() }

        let asset = AVURLAsset(url: localURL)
        if let duration = try? await asset.load(.duration) {
            project.duration = CMTimeGetSeconds(duration)
        }
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            let natural = (try? await track.load(.naturalSize)) ?? .zero
            let transform = (try? await track.load(.preferredTransform)) ?? .identity
            let oriented = VideoExportService.orientedSizePublic(natural, transform: transform)
            project.sourceSize = oriented
            project.aspectRatio = AspectRatioPreset.inferred(from: oriented)
        }
        project.chunkCount = VideoChunkPlanner.chunks(duration: project.duration).count

        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        currentTime = 0
        isPlaying = false

        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = CMTimeGetSeconds(time)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.seek(to: 0)
            }
        }
    }

    private static func copyIntoCaches(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dest = caches.appendingPathComponent("import-\(UUID().uuidString)-\(url.lastPathComponent)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }

    func generateCaptions() async {
        guard let url = project.videoURL else {
            errorMessage = "Import a video first."
            return
        }
        isTranscribing = true
        errorMessage = nil
        defer { isTranscribing = false }

        transcription.language = language
        do {
            let captions = try await transcription.transcribe(videoURL: url)
            project.captions = captions
            selectedCaptionID = captions.first?.id
            editorTab = .styles
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Ask Cursor SDK where to place assets — long videos are enhanced part-by-part then merged.
    func enhanceWithCursorSDK() async {
        guard !project.captions.isEmpty else {
            errorMessage = "Generate captions first so the agent knows where to place assets."
            return
        }
        isEnhancing = true
        errorMessage = nil
        chunkProgressLabel = nil
        defer {
            isEnhancing = false
            chunkProgressLabel = nil
        }

        await enhancer.checkHealth()
        let chunks = VideoChunkPlanner.chunks(duration: project.duration)
        project.chunkCount = chunks.count
        let canvas = project.aspectRatio.canvasSize

        var merged: [EnhancementPlacement] = []
        var notes: [String] = []

        for chunk in chunks {
            chunkProgressLabel = chunks.count == 1
                ? "Placing on \(project.aspectRatio.rawValue)…"
                : "Part \(chunk.index + 1)/\(chunks.count) (\(formatClock(chunk.startTime))–\(formatClock(chunk.endTime)))"

            let sliceCaptions = VideoChunkPlanner.captions(
                project.captions,
                overlapping: chunk,
                useContext: true
            )
            guard !sliceCaptions.isEmpty || chunks.count == 1 else { continue }

            let plan: EnhancementPlan
            if enhancer.isHealthy {
                do {
                    plan = try await enhancer.enhance(
                        captions: sliceCaptions.isEmpty ? project.captions : sliceCaptions,
                        duration: project.duration,
                        videoSize: canvas,
                        language: language,
                        forceHeuristic: false
                    )
                } catch {
                    plan = enhancer.localHeuristicPlan(
                        captions: sliceCaptions.isEmpty ? project.captions : sliceCaptions,
                        duration: project.duration,
                        libraries: libraries
                    )
                    notes.append(error.localizedDescription)
                }
            } else {
                plan = enhancer.localHeuristicPlan(
                    captions: sliceCaptions.isEmpty ? project.captions : sliceCaptions,
                    duration: project.duration,
                    libraries: libraries
                )
            }

            let absolute = VideoChunkPlanner.absolutize(placements: plan.allEdits, chunk: chunk)
            merged.append(contentsOf: absolute)
            if let note = plan.note { notes.append("p\(chunk.index + 1): \(note)") }
        }

        // Deduplicate near-identical placements at chunk boundaries.
        merged = Self.dedupe(placements: merged)

        let wordHits = merged.filter { $0.kind == "wordHit" }
        let others = merged.filter { $0.kind != "wordHit" }

        let plan = EnhancementPlan(
            summary: chunks.count == 1
                ? "Word hits + placements for \(language.title) / \(project.aspectRatio.rawValue)."
                : "Merged \(wordHits.count) word hits across \(chunks.count) parts (\(language.title)).",
            placements: others,
            wordHits: wordHits,
            source: enhancer.isHealthy ? "cursor-sdk-chunked" : "local-chunked",
            model: enhancer.usesCursorKey ? "composer-2.5" : nil,
            note: notes.last ?? "Enhanced in \(chunks.count) part(s)",
            language: language.localeIdentifier
        )
        apply(plan: plan)
        lastEnhancementNote = plan.summary
        editorTab = .libraries
    }

    private static func dedupe(placements: [EnhancementPlacement]) -> [EnhancementPlacement] {
        var kept: [EnhancementPlacement] = []
        for p in placements.sorted(by: { $0.startTime < $1.startTime }) {
            let duplicate = kept.contains {
                $0.kind == p.kind
                    && $0.assetId == p.assetId
                    && abs($0.startTime - p.startTime) < 0.12
                    && abs($0.x - p.x) < 0.05
                    && abs($0.y - p.y) < 0.05
            }
            if !duplicate { kept.append(p) }
        }
        return kept
    }

    private func formatClock(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }

    func setAspectRatio(_ aspect: AspectRatioPreset) {
        project.aspectRatio = aspect
    }

    func apply(plan: EnhancementPlan) {
        var newOverlays: [OverlayItem] = []
        var newSFX: [SoundEffectCue] = []

        for placement in plan.allEdits {
            switch placement.kind {
            case "text":
                if let item = makeStylishText(from: placement) {
                    newOverlays.append(item)
                }
            case "gif":
                if let item = makeImageOverlay(from: placement, kind: .gif, library: .gifs) {
                    newOverlays.append(item)
                }
            case "png":
                if let item = makeImageOverlay(from: placement, kind: .png, library: .pngs) {
                    newOverlays.append(item)
                }
            case "sfx":
                if let cue = makeSFX(from: placement) {
                    newSFX.append(cue)
                }
            case "wordHit":
                if let item = makeWordHit(from: placement) {
                    newOverlays.append(item)
                }
                if let cue = makeWordHitSFX(from: placement) {
                    newSFX.append(cue)
                }
            default:
                continue
            }
        }

        let manual = project.overlays.filter {
            $0.assetId == nil && $0.styleAssetId == nil && $0.fontId == nil
                && ($0.kind == .emoji || $0.kind == .shape || $0.kind == .watermark)
        }
        project.overlays = manual + newOverlays
        project.soundEffects = newSFX
        project.enhancementSummary = plan.summary
        let hitCount = plan.wordHits?.count ?? newOverlays.filter { $0.kind == .wordHit }.count
        lastEnhancementNote = plan.note
            ?? "Applied \(hitCount) word hits + \(newOverlays.count) overlays + \(newSFX.count) SFX"
        if let first = newOverlays.first {
            selectedOverlayID = first.id
            seek(to: first.startTime)
        }
    }

    private func makeWordHit(from placement: EnhancementPlacement) -> OverlayItem? {
        let fontId = placement.fontId ?? placement.assetId
        let font = libraries.item(kind: .fonts, id: fontId)
            ?? libraries.items(for: .fonts).first { $0.scripts?.contains(where: { language.scriptTags.contains($0) }) == true }
        guard let font else { return nil }
        let effectId = placement.effectId ?? WordHitEffect.random().rawValue
        let effect = WordHitEffect(rawValue: effectId)
        let effectColors = libraries.item(kind: .effects, id: effectId)?.colors
        let primaryHex = placement.color
            ?? effectColors?.first
            ?? "#FFEF5A"
        let color = Color(hex: primaryHex) ?? (effect?.palette.first ?? .yellow)
        return OverlayItem(
            kind: .wordHit,
            text: placement.displayText.isEmpty ? (font.previewText ?? "!") : placement.displayText,
            assetId: font.id,
            assetFileName: nil,
            styleAssetId: nil,
            fontId: font.id,
            fontName: font.fontName,
            effectId: effectId,
            sfxId: placement.sfxId,
            x: placement.x,
            y: placement.y,
            scale: max(placement.scale, 1.25),
            rotation: placement.rotation,
            startTime: placement.startTime,
            endTime: placement.endTime,
            color: color.codable,
            fontSize: 52,
            shape: .rectangle,
            opacity: 1,
            reason: placement.reason,
            captionIndex: placement.captionIndex,
            wordIndex: placement.wordIndex
        )
    }

    private func makeWordHitSFX(from placement: EnhancementPlacement) -> SoundEffectCue? {
        guard let sfxId = placement.sfxId,
              libraries.item(kind: .sfx, id: sfxId) != nil
        else { return nil }
        return SoundEffectCue(
            assetId: sfxId,
            startTime: placement.startTime,
            gain: libraries.item(kind: .sfx, id: sfxId)?.defaultGain ?? 0.85,
            reason: "Word hit SFX for \(placement.text ?? "")"
        )
    }

    private func makeStylishText(from placement: EnhancementPlacement) -> OverlayItem? {
        guard let style = libraries.item(kind: .textStyles, id: placement.assetId) else { return nil }
        let aligned = PlacementAligner.align(
            placement,
            asset: style,
            kind: "text",
            captions: project.captions,
            videoDuration: project.duration
        )
        let color = Color(hex: style.textColor ?? "#FFFFFF") ?? .white
        return OverlayItem(
            kind: .text,
            text: placement.text ?? style.previewText ?? "Look",
            assetId: nil,
            assetFileName: nil,
            styleAssetId: style.id,
            x: aligned.x,
            y: aligned.y,
            scale: placement.scale,
            rotation: placement.rotation,
            startTime: aligned.start,
            endTime: aligned.end,
            color: color.codable,
            fontSize: style.fontSize ?? 34,
            shape: .rectangle,
            opacity: 1,
            reason: placement.reason ?? "hold \(String(format: "%.2fs", style.playLength))"
        )
    }

    private func makeImageOverlay(
        from placement: EnhancementPlacement,
        kind: OverlayKind,
        library: MediaLibraryKind
    ) -> OverlayItem? {
        guard let asset = libraries.item(kind: library, id: placement.assetId),
              let file = asset.file
        else { return nil }
        let aligned = PlacementAligner.align(
            placement,
            asset: asset,
            kind: kind == .gif ? "gif" : "png",
            captions: project.captions,
            videoDuration: project.duration
        )
        return OverlayItem(
            kind: kind,
            text: asset.name,
            assetId: asset.id,
            assetFileName: file,
            styleAssetId: nil,
            x: aligned.x,
            y: aligned.y,
            scale: placement.scale,
            rotation: placement.rotation,
            startTime: aligned.start,
            endTime: aligned.end,
            color: .white,
            fontSize: 24,
            shape: .rectangle,
            opacity: 1,
            reason: placement.reason
                ?? "\(Int(asset.pixelSize.width))×\(Int(asset.pixelSize.height)), \(String(format: "%.2fs", asset.playLength))"
        )
    }

    private func makeSFX(from placement: EnhancementPlacement) -> SoundEffectCue? {
        guard let asset = libraries.item(kind: .sfx, id: placement.assetId) else { return nil }
        let aligned = PlacementAligner.align(
            placement,
            asset: asset,
            kind: "sfx",
            captions: project.captions,
            videoDuration: project.duration
        )
        return SoundEffectCue(
            assetId: asset.id,
            startTime: aligned.start,
            gain: asset.defaultGain ?? 0.8,
            reason: placement.reason ?? "length \(String(format: "%.2fs", asset.playLength))"
        )
    }

    func addLibraryItem(_ item: MediaLibraryItem, kind: MediaLibraryKind) {
        switch kind {
        case .textStyles:
            let placement = EnhancementPlacement(
                kind: "text",
                assetId: item.id,
                startTime: currentTime,
                endTime: currentTime + item.playLength,
                x: 0.5,
                y: 0.3,
                scale: 1,
                rotation: 0,
                text: item.previewText,
                reason: "Manual · \(String(format: "%.2fs", item.playLength))",
                lengthSeconds: item.playLength
            )
            if let overlay = makeStylishText(from: placement) {
                project.overlays.append(overlay)
                selectedOverlayID = overlay.id
            }
        case .gifs, .pngs:
            let placement = EnhancementPlacement(
                kind: kind == .gifs ? "gif" : "png",
                assetId: item.id,
                startTime: currentTime,
                endTime: currentTime + item.playLength,
                x: 0.75,
                y: 0.25,
                scale: item.defaultScale ?? 1,
                rotation: 0,
                reason: "Manual · \(Int(item.pixelSize.width))×\(Int(item.pixelSize.height)) · \(String(format: "%.2fs", item.playLength))",
                lengthSeconds: item.playLength
            )
            if let overlay = makeImageOverlay(
                from: placement,
                kind: kind == .gifs ? .gif : .png,
                library: kind
            ) {
                project.overlays.append(overlay)
                selectedOverlayID = overlay.id
            }
        case .sfx:
            let cue = SoundEffectCue(
                assetId: item.id,
                startTime: currentTime,
                gain: item.defaultGain ?? 0.8,
                reason: "Manual · exact \(String(format: "%.2fs", item.playLength))"
            )
            project.soundEffects.append(cue)
            previewSFX(cue)
        }
        editorTab = .overlays
    }

    func previewSFX(_ cue: SoundEffectCue) {
        guard let asset = libraries.item(kind: .sfx, id: cue.assetId),
              let file = asset.file ?? asset.wav,
              let url = libraries.fileURL(kind: .sfx, fileName: file)
        else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(cue.gain)
            player.prepareToPlay()
            player.play()
            sfxPlayers.append(player)
            sfxPlayers = sfxPlayers.filter(\.isPlaying)
        } catch {
            errorMessage = "Could not play SFX: \(error.localizedDescription)"
        }
    }

    func libraryFileURL(for overlay: OverlayItem) -> URL? {
        guard let file = overlay.assetFileName else { return nil }
        let kind: MediaLibraryKind = overlay.kind == .gif ? .gifs : .pngs
        return libraries.fileURL(kind: kind, fileName: file)
    }

    func stylishTextStyle(for overlay: OverlayItem) -> MediaLibraryItem? {
        guard let id = overlay.styleAssetId else { return nil }
        return libraries.item(kind: .textStyles, id: id)
    }

    // MARK: - Playback

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= project.duration - 0.05 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        }
    }

    func seek(to time: TimeInterval) {
        let cm = CMTime(seconds: max(0, time), preferredTimescale: 600)
        player?.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = max(0, time)
    }

    // MARK: - Captions / style

    func applyPreset(_ preset: CaptionPreset) {
        selectedPreset = preset
        project.captionStyle = preset.style
    }

    func updateCaption(_ caption: CaptionSegment) {
        guard let index = project.captions.firstIndex(where: { $0.id == caption.id }) else { return }
        project.captions[index] = caption
    }

    func deleteCaption(_ id: CaptionSegment.ID) {
        project.captions.removeAll { $0.id == id }
        if selectedCaptionID == id { selectedCaptionID = nil }
    }

    // MARK: - Overlays

    func addTextOverlay(_ text: String = "Your text") {
        let item = OverlayItem.textSticker(text, at: currentTime)
        project.overlays.append(item)
        selectedOverlayID = item.id
        editorTab = .overlays
    }

    func addEmojiOverlay(_ emoji: String) {
        let item = OverlayItem.emoji(emoji, at: currentTime)
        project.overlays.append(item)
        selectedOverlayID = item.id
    }

    func updateOverlay(_ item: OverlayItem) {
        guard let index = project.overlays.firstIndex(where: { $0.id == item.id }) else { return }
        project.overlays[index] = item
    }

    func deleteOverlay(_ id: OverlayItem.ID) {
        project.overlays.removeAll { $0.id == id }
        if selectedOverlayID == id { selectedOverlayID = nil }
    }

    // MARK: - Export

    func exportVideo() async {
        guard let url = project.videoURL else {
            errorMessage = "Import a video first."
            return
        }
        isExporting = true
        errorMessage = nil
        chunkProgressLabel = nil
        defer {
            isExporting = false
            chunkProgressLabel = nil
        }

        do {
            let chunks = VideoChunkPlanner.chunks(duration: project.duration)
            project.chunkCount = chunks.count
            let result: URL

            if chunks.count == 1 {
                chunkProgressLabel = "Exporting \(project.aspectRatio.rawValue)…"
                result = try await exporter.export(
                    videoURL: url,
                    captions: project.captions,
                    style: project.captionStyle,
                    overlays: project.overlays,
                    soundEffects: project.soundEffects,
                    libraryRoot: libraries.rootURL,
                    aspect: project.aspectRatio
                )
            } else {
                let segments: [VideoStitchService.SegmentSpec] = chunks.map { chunk in
                    let caps = VideoChunkPlanner.captions(project.captions, overlapping: chunk, useContext: false)
                    let overlays = project.overlays.filter {
                        $0.endTime > chunk.startTime && $0.startTime < chunk.endTime
                    }
                    let sfx = project.soundEffects.filter {
                        $0.startTime >= chunk.startTime && $0.startTime < chunk.endTime
                    }
                    return .init(
                        chunk: chunk,
                        captions: caps,
                        overlays: overlays,
                        soundEffects: sfx
                    )
                }
                chunkProgressLabel = "Exporting \(chunks.count) parts → stitch…"
                // Bind stitcher progress into exporter progress for the UI meter.
                result = try await stitcher.exportChunked(
                    videoURL: url,
                    aspect: project.aspectRatio,
                    style: project.captionStyle,
                    segments: segments,
                    libraryRoot: libraries.rootURL
                )
                exporter.progress = stitcher.progress
                exporter.statusMessage = stitcher.statusMessage
            }

            exportURL = result
            showExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Cleanup

    func tearDownPlayer() {
        player?.pause()
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        timeObserver = nil
        endObserver = nil
        player = nil
        isPlaying = false
    }

    deinit {
        // Cannot call MainActor tearDown from deinit safely; observers cleared on replace.
    }
}
