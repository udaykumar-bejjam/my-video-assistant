import Foundation
import AVFoundation

/// Exports long timelines part-by-part, then stitches segments with frame-accurate cuts.
@MainActor
final class VideoStitchService: ObservableObject {
    @Published var progress: Double = 0
    @Published var statusMessage: String = ""

    private let exporter = VideoExportService()

    struct SegmentSpec {
        var chunk: TimelineChunk
        var captions: [CaptionSegment]
        var overlays: [OverlayItem]
        var soundEffects: [SoundEffectCue]
    }

    /// Process each chunk into a temp MP4 (times shifted to 0), then concatenate precisely.
    func exportChunked(
        videoURL: URL,
        aspect: AspectRatioPreset,
        style: CaptionStyle,
        segments: [SegmentSpec],
        libraryRoot: URL?,
        outputURL: URL? = nil,
        audioSettings: ProjectAudioSettings = .default,
        brandSfxGain: Double = 0.8
    ) async throws -> URL {
        guard !segments.isEmpty else {
            throw ExportError.compositionFailed("No segments to export.")
        }

        progress = 0.02
        statusMessage = "Exporting \(segments.count) parts…"

        var partURLs: [URL] = []
        defer {
            for url in partURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        for (offset, segment) in segments.enumerated() {
            let chunk = segment.chunk
            statusMessage = "Rendering part \(offset + 1)/\(segments.count)…"
            progress = 0.05 + 0.7 * (Double(offset) / Double(segments.count))

            // Shift timeline so this part starts at t=0 for the segment exporter.
            let delta = -chunk.startTime
            let localCaptions = VideoChunkPlanner.shiftCaptions(segment.captions, by: delta).compactMap { cap -> CaptionSegment? in
                var c = cap
                c.startTime = max(0, min(chunk.duration, c.startTime))
                c.endTime = max(c.startTime, min(chunk.duration, c.endTime))
                // Drop razor-thin remnants at chunk seams (avoids duplicate/ghost captions).
                guard c.endTime - c.startTime >= 0.12 else { return nil }
                c.words = c.words.compactMap { w in
                    var word = w
                    word.startTime = max(0, min(chunk.duration, w.startTime))
                    word.endTime = max(word.startTime, min(chunk.duration, w.endTime))
                    guard word.endTime - word.startTime >= 0.04 else { return nil }
                    return word
                }
                return c
            }
            let localOverlays = VideoChunkPlanner.shiftOverlays(segment.overlays, by: delta).compactMap { item -> OverlayItem? in
                var o = item
                o.startTime = max(0, o.startTime)
                o.endTime = min(chunk.duration, o.endTime)
                guard o.endTime > o.startTime else { return nil }
                return o
            }
            let localSFX = VideoChunkPlanner.shiftSFX(segment.soundEffects, by: delta).compactMap { cue -> SoundEffectCue? in
                var s = cue
                s.startTime = max(0, s.startTime)
                guard s.startTime < chunk.duration else { return nil }
                return s
            }

            let partURL = try await exporter.export(
                videoURL: videoURL,
                captions: localCaptions,
                style: style,
                overlays: localOverlays,
                soundEffects: localSFX,
                libraryRoot: libraryRoot,
                aspect: aspect,
                sourceTimeRange: CMTimeRange(
                    start: CMTime(seconds: chunk.startTime, preferredTimescale: 600),
                    duration: CMTime(seconds: chunk.duration, preferredTimescale: 600)
                ),
                outputURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("CaptionStudio-part-\(offset)-\(UUID().uuidString).mp4"),
                audioSettings: audioSettings,
                brandSfxGain: brandSfxGain
            )
            partURLs.append(partURL)
        }

        progress = 0.78
        statusMessage = "Stitching \(partURLs.count) parts…"

        let dest = outputURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionStudio-stitched-\(UUID().uuidString).mp4")
        try await stitch(parts: partURLs, aspect: aspect, outputURL: dest)

        progress = 1
        statusMessage = "Export complete (\(partURLs.count) parts stitched)"
        // Prevent defer cleanup of final? parts only — dest is kept.
        let kept = dest
        partURLs.removeAll()
        return kept
    }

    /// Frame-accurate concatenation of already-rendered parts (same canvas size).
    func stitch(parts: [URL], aspect: AspectRatioPreset, outputURL: URL) async throws {
        try? FileManager.default.removeItem(at: outputURL)

        let composition = AVMutableComposition()
        guard
            let videoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw ExportError.compositionFailed("Could not create stitch video track.")
        }
        let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )

        var cursor = CMTime.zero
        var maxSize = aspect.canvasSize

        for part in parts {
            let asset = AVURLAsset(url: part)
            let duration = try await asset.load(.duration)
            guard duration.seconds > 0 else { continue }

            if let srcVideo = try await asset.loadTracks(withMediaType: .video).first {
                try videoTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: srcVideo,
                    at: cursor
                )
                let nat = try await srcVideo.load(.naturalSize)
                let transform = try await srcVideo.load(.preferredTransform)
                let oriented = VideoExportService.orientedSizePublic(nat, transform: transform)
                if oriented.width > 1 && oriented.height > 1 {
                    maxSize = oriented
                }
            }
            if let srcAudio = try await asset.loadTracks(withMediaType: .audio).first,
               let audioTrack {
                try? audioTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: srcAudio,
                    at: cursor
                )
            }
            cursor = CMTimeAdd(cursor, duration)
        }

        guard cursor.seconds > 0 else {
            throw ExportError.compositionFailed("Stitch produced empty timeline.")
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = maxSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: cursor)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.exportFailed("Could not create stitch export session.")
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: ExportError.exportFailed("Stitch cancelled."))
                default:
                    continuation.resume(
                        throwing: ExportError.exportFailed(
                            session.error?.localizedDescription ?? "Stitch failed."
                        )
                    )
                }
            }
        }
    }
}
