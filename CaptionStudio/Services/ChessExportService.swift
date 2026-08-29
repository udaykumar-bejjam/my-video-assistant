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
            guard let buffer = Self.makePixelBuffer(
                board: board,
                move: move,
                callout: callout,
                title: title,
                size: canvasSize
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

    private static func makePixelBuffer(
        board: ChessBoard,
        move: ChessAnnotatedMove?,
        callout: String,
        title: String,
        size: CGSize
    ) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &buffer
        )
        guard let pixelBuffer = buffer else { return nil }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Background
        ctx.setFillColor(CGColor(red: 0.05, green: 0.08, blue: 0.1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))

        let boardSide = min(size.width, size.height) * 0.78
        let boardOrigin = CGPoint(
            x: (size.width - boardSide) / 2,
            y: size.height * 0.22
        )
        let sq = boardSide / 8
        let light = CGColor(red: 0.93, green: 0.85, blue: 0.70, alpha: 1)
        let dark = CGColor(red: 0.45, green: 0.58, blue: 0.40, alpha: 1)

        for rank in 0..<8 {
            for file in 0..<8 {
                let isLight = (file + rank) % 2 == 0
                // White at bottom: rank 0 drawn at bottom of board rect.
                let x = boardOrigin.x + CGFloat(file) * sq
                let y = boardOrigin.y + CGFloat(7 - rank) * sq
                ctx.setFillColor(isLight ? light : dark)
                ctx.fill(CGRect(x: x, y: y, width: sq, height: sq))
            }
        }

        if let move {
            let cat = move.category.color
            let highlight = CGColor(red: cat.r, green: cat.g, blue: cat.b, alpha: 0.45)
            for name in [move.from, move.to] + move.criticalSquares {
                guard let sqCoords = ChessSquare.parse(name) else { continue }
                let x = boardOrigin.x + CGFloat(sqCoords.file) * sq
                let y = boardOrigin.y + CGFloat(7 - sqCoords.rank) * sq
                ctx.setFillColor(highlight)
                ctx.fill(CGRect(x: x, y: y, width: sq, height: sq))
            }
            // Move arrow
            if let from = ChessSquare.parse(move.from), let to = ChessSquare.parse(move.to) {
                let fromC = CGPoint(
                    x: boardOrigin.x + (CGFloat(from.file) + 0.5) * sq,
                    y: boardOrigin.y + (CGFloat(7 - from.rank) + 0.5) * sq
                )
                let toC = CGPoint(
                    x: boardOrigin.x + (CGFloat(to.file) + 0.5) * sq,
                    y: boardOrigin.y + (CGFloat(7 - to.rank) + 0.5) * sq
                )
                ctx.setStrokeColor(CGColor(red: cat.r, green: cat.g, blue: cat.b, alpha: 0.95))
                ctx.setLineWidth(max(4, sq * 0.12))
                ctx.setLineCap(.round)
                ctx.move(to: fromC)
                ctx.addLine(to: toC)
                ctx.strokePath()
            }
        }

        let fontSize = sq * 0.72
        // Pieces (Unicode via Core Text)
        let font = CTFontCreateWithName("Menlo" as CFString, fontSize, nil)
        for rank in 0..<8 {
            for file in 0..<8 {
                guard let occ = board.piece(atFile: file, rank: rank) else { continue }
                let color = CGColor(gray: occ.isWhite ? 0.98 : 0.08, alpha: 1)
                let attrs: [CFString: Any] = [
                    kCTFontAttributeName: font,
                    kCTForegroundColorAttributeName: color,
                ]
                let attr = CFAttributedStringCreate(nil, occ.glyph as CFString, attrs as CFDictionary)!
                let line = CTLineCreateWithAttributedString(attr)
                let x = boardOrigin.x + CGFloat(file) * sq + sq * 0.14
                let y = boardOrigin.y + CGFloat(7 - rank) * sq + sq * 0.16
                ctx.textPosition = CGPoint(x: x, y: y)
                CTLineDraw(line, ctx)
            }
        }

        // Callout banner
        let bannerY = boardOrigin.y + boardSide + size.height * 0.04
        drawText(
            callout,
            in: ctx,
            rect: CGRect(x: size.width * 0.06, y: bannerY, width: size.width * 0.88, height: size.height * 0.08),
            fontSize: size.width * 0.038,
            color: move.map { CGColor(red: $0.category.color.r, green: $0.category.color.g, blue: $0.category.color.b, alpha: 1) }
                ?? CGColor(gray: 0.9, alpha: 1)
        )
        drawText(
            "CaptionStudio Chess",
            in: ctx,
            rect: CGRect(x: size.width * 0.06, y: size.height * 0.08, width: size.width * 0.88, height: size.height * 0.05),
            fontSize: size.width * 0.028,
            color: CGColor(red: 0.2, green: 0.95, blue: 0.72, alpha: 1)
        )

        return pixelBuffer
    }

    private static func drawText(
        _ text: String,
        in ctx: CGContext,
        rect: CGRect,
        fontSize: CGFloat,
        color: CGColor
    ) {
        let font = CTFontCreateWithName("AvenirNext-Bold" as CFString, fontSize, nil)
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: color,
        ]
        let attr = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attr)
        let lineWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
        let x = rect.midX - CGFloat(lineWidth) / 2
        let y = rect.midY - fontSize * 0.35
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
    }
}
