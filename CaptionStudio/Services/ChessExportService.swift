import Foundation
import AVFoundation
import CoreGraphics
import CoreText
import QuartzCore
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Exports an animated chess walkthrough as a standalone MP4 (board + callouts + SFX).
@MainActor
final class ChessExportService: ObservableObject {
    @Published var progress: Double = 0
    @Published var statusMessage: String = ""

    private let libraries = MediaLibraryStore()

    func export(
        boards: [ChessBoard],
        moves: [ChessAnnotatedMove],
        secondsPerMove: Double,
        title: String,
        canvasSize: CGSize = CGSize(width: 1080, height: 1920)
    ) async throws -> URL {
        guard boards.count >= 2, !moves.isEmpty else {
            throw ExportError.compositionFailed("Analyze a game with moves before exporting.")
        }
        progress = 0.02
        statusMessage = "Rendering chess frames…"

        let fps: Int32 = 30
        let holdFrames = max(1, Int((secondsPerMove * Double(fps)).rounded()))
        let totalPlies = moves.count
        // Frame 0 = start position briefly, then one hold per move on the resulting board.
        let introFrames = max(fps / 2, 8)

        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionStudio-Chess-\(UUID().uuidString).mp4")
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }

        let writer = try AVAssetWriter(outputURL: dest, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(canvasSize.width),
            AVVideoHeightKey: Int(canvasSize.height),
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: Int(canvasSize.width),
            kCVPixelBufferHeightKey as String: Int(canvasSize.height),
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: attrs
        )
        guard writer.canAdd(videoInput) else {
            throw ExportError.compositionFailed("Cannot add chess video track.")
        }
        writer.add(videoInput)
        guard writer.startWriting() else {
            throw ExportError.exportFailed(writer.error?.localizedDescription ?? "Writer failed to start.")
        }
        writer.startSession(atSourceTime: .zero)

        var frameIndex = 0
        func append(board: ChessBoard, move: ChessAnnotatedMove?, callout: String) throws {
            guard let buffer = ChessBoardRenderer.makePixelBuffer(
                board: board,
                move: move,
                callout: callout,
                title: title,
                size: canvasSize,
                transparentBackground: false
            ) else {
                throw ExportError.exportFailed("Could not rasterize chess frame.")
            }
            let time = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
            while !videoInput.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }
            if !adaptor.append(buffer, withPresentationTime: time) {
                throw ExportError.exportFailed(writer.error?.localizedDescription ?? "Frame append failed.")
            }
            frameIndex += 1
        }

        // Intro: starting board
        let startCallout = title.isEmpty ? "Chess Walkthrough" : title
        for _ in 0..<introFrames {
            try append(board: boards[0], move: nil, callout: startCallout)
        }

        for moveIndex in 0..<totalPlies {
            let boardIndex = min(moveIndex + 1, boards.count - 1)
            let move = moves[moveIndex]
            let callout = Self.callout(for: move)
            let frames = holdFrames
            for _ in 0..<frames {
                try append(board: boards[boardIndex], move: move, callout: callout)
            }
            progress = 0.05 + 0.7 * Double(moveIndex + 1) / Double(totalPlies)
            statusMessage = "Rendering move \(moveIndex + 1)/\(totalPlies)…"
        }

        videoInput.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw ExportError.exportFailed(writer.error?.localizedDescription ?? "Chess export failed.")
        }

        progress = 0.8
        statusMessage = "Mixing move SFX…"
        let duration = Double(frameIndex) / Double(fps)
        let withAudio = try await mixCategorySFX(
            videoURL: dest,
            moves: moves,
            secondsPerMove: secondsPerMove,
            introSeconds: Double(introFrames) / Double(fps),
            timelineDuration: duration
        )
        progress = 1
        statusMessage = "Chess export ready"
        return withAudio
    }

    private func mixCategorySFX(
        videoURL: URL,
        moves: [ChessAnnotatedMove],
        secondsPerMove: Double,
        introSeconds: Double,
        timelineDuration: TimeInterval
    ) async throws -> URL {
        var cues: [SoundEffectCue] = []
        for (i, move) in moves.enumerated() {
            cues.append(
                SoundEffectCue(
                    assetId: move.category.sfxId,
                    startTime: introSeconds + Double(i) * secondsPerMove,
                    gain: move.category == .normal ? 0.45 : 0.85,
                    reason: move.category.label
                )
            )
        }
        // Re-export through VideoExportService with empty captions and no overlays —
        // only SFX mix onto the rendered chess video.
        let exporter = VideoExportService()
        return try await exporter.export(
            videoURL: videoURL,
            captions: [],
            style: .default,
            overlays: [],
            soundEffects: cues,
            libraryRoot: libraries.rootURL,
            aspect: .portrait9x16,
            audioSettings: ProjectAudioSettings(
                dialogueGain: 0,
                sfxMasterGain: 1,
                normalizeLoudness: false,
                duckDialogueUnderSFX: false,
                duckAmount: 0,
                enhancerPreset: .balanced
            ),
            brandSfxGain: 1
        )
    }

    private static func callout(for move: ChessAnnotatedMove) -> String {
        var parts = ["\(move.moveNumber)\(move.isWhite ? "." : "...") \(move.san)"]
        if move.category.isHighlightWorthy {
            parts.append(move.category.label.uppercased())
        }
        if let d = move.evalDeltaCp, move.evalSource != nil {
            let sign = d >= 0 ? "+" : ""
            parts.append("\(sign)\(d)cp")
        }
        if move.givesCheck { parts.append("Check!") }
        return parts.joined(separator: " · ")
    }
}
