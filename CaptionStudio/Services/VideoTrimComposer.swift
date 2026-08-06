import Foundation
import AVFoundation

/// Builds a trimmed media file from keep-ranges for preview/export consistency after trim apply.
enum VideoTrimComposer {
    static func writeTrimmedVideo(
        sourceURL: URL,
        keepRanges: [(start: TimeInterval, end: TimeInterval)]
    ) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        let composition = AVMutableComposition()
        guard
            let videoTrack = try await asset.loadTracks(withMediaType: .video).first,
            let compVideo = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        else {
            throw ExportError.compositionFailed("No video track for trim.")
        }

        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let compAudio = audioTrack.flatMap {
            _ in composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        }

        var cursor = CMTime.zero
        for range in keepRanges {
            let start = CMTime(seconds: range.start, preferredTimescale: 600)
            let duration = CMTime(seconds: max(0.01, range.end - range.start), preferredTimescale: 600)
            let timeRange = CMTimeRange(start: start, duration: duration)
            try compVideo.insertTimeRange(timeRange, of: videoTrack, at: cursor)
            if let audioTrack, let compAudio {
                try? compAudio.insertTimeRange(timeRange, of: audioTrack, at: cursor)
            }
            cursor = CMTimeAdd(cursor, duration)
        }

        let preferredTransform = try await videoTrack.load(.preferredTransform)
        compVideo.preferredTransform = preferredTransform

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionStudio-Trim-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: dest)

        guard let session = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw ExportError.exportFailed("Could not create trim export session.")
        }
        session.outputURL = dest
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.exportAsynchronously {
                switch session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(
                        throwing: ExportError.exportFailed(session.error?.localizedDescription ?? "Trim export failed")
                    )
                default:
                    continuation.resume(throwing: ExportError.exportFailed("Unexpected trim export status"))
                }
            }
        }
        return dest
    }
}
