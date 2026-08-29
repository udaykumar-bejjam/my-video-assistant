import Foundation
import CoreGraphics
import CoreText
import CoreImage
import CoreVideo

/// Shared CoreGraphics chessboard rasterizer for standalone export and video overlays.
enum ChessBoardRenderer {
    static func makeCGImage(
        board: ChessBoard,
        move: ChessAnnotatedMove?,
        callout: String?,
        title: String?,
        size: CGSize,
        transparentBackground: Bool = false
    ) -> CGImage? {
        guard let buffer = makePixelBuffer(
            board: board,
            move: move,
            callout: callout,
            title: title,
            size: size,
            transparentBackground: transparentBackground
        ) else { return nil }
        return CGImage.create(from: buffer)
    }

    static func makePixelBuffer(
        board: ChessBoard,
        move: ChessAnnotatedMove?,
        callout: String?,
        title: String?,
        size: CGSize,
        transparentBackground: Bool = false
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

        if transparentBackground {
            ctx.clear(CGRect(origin: .zero, size: size))
        } else {
            ctx.setFillColor(CGColor(red: 0.05, green: 0.08, blue: 0.1, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
        }

        let boardSide = min(size.width, size.height) * (transparentBackground ? 0.92 : 0.78)
        let boardOrigin = CGPoint(
            x: (size.width - boardSide) / 2,
            y: transparentBackground ? (size.height - boardSide) / 2 : size.height * 0.22
        )
        let sq = boardSide / 8
        let light = CGColor(red: 0.93, green: 0.85, blue: 0.70, alpha: 1)
        let dark = CGColor(red: 0.45, green: 0.58, blue: 0.40, alpha: 1)

        for rank in 0..<8 {
            for file in 0..<8 {
                let isLight = (file + rank) % 2 == 0
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

        if let callout, !callout.isEmpty, !transparentBackground {
            let bannerY = boardOrigin.y + boardSide + size.height * 0.04
            drawText(
                callout,
                in: ctx,
                rect: CGRect(x: size.width * 0.06, y: bannerY, width: size.width * 0.88, height: size.height * 0.08),
                fontSize: size.width * 0.038,
                color: move.map { CGColor(red: $0.category.color.r, green: $0.category.color.g, blue: $0.category.color.b, alpha: 1) }
                    ?? CGColor(gray: 0.9, alpha: 1)
            )
        }
        if let title, !title.isEmpty, !transparentBackground {
            drawText(
                title,
                in: ctx,
                rect: CGRect(x: size.width * 0.06, y: size.height * 0.08, width: size.width * 0.88, height: size.height * 0.05),
                fontSize: size.width * 0.028,
                color: CGColor(red: 0.2, green: 0.95, blue: 0.72, alpha: 1)
            )
        }

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

private extension CGImage {
    static func create(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ci = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext(options: nil)
        return context.createCGImage(ci, from: ci.extent)
    }
}
