import Foundation
import AVFoundation
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Builds a still cover frame (first video frame + cover text).
enum CoverExportService {
    static func exportCoverPNG(
        videoURL: URL,
        coverText: String,
        aspect: AspectRatioPreset,
        brandColor: CodableColor = CodableColor(r: 1, g: 0.94, b: 0.35, a: 1)
    ) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = aspect.canvasSize

        let cgImage = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CGImage, Error>) in
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: .zero)]) { _, image, _, result, error in
                if let image, result == .succeeded {
                    cont.resume(returning: image)
                } else {
                    cont.resume(throwing: error ?? ExportError.exportFailed("Could not grab cover frame."))
                }
            }
        }

        let size = aspect.canvasSize
        #if canImport(UIKit)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let ui = renderer.image { ctx in
            UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: size))
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "AvenirNext-Heavy", size: size.width * 0.08) ?? .boldSystemFont(ofSize: 48),
                .foregroundColor: UIColor(red: brandColor.r, green: brandColor.g, blue: brandColor.b, alpha: 1),
                .strokeColor: UIColor.black,
                .strokeWidth: -3,
                .paragraphStyle: paragraph
            ]
            let rect = CGRect(x: size.width * 0.08, y: size.height * 0.38, width: size.width * 0.84, height: size.height * 0.24)
            (coverText as NSString).draw(in: rect, withAttributes: attrs)
        }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionStudio-Cover-\(UUID().uuidString).png")
        guard let data = ui.pngData() else {
            throw ExportError.exportFailed("Could not encode cover PNG.")
        }
        try data.write(to: dest, options: .atomic)
        return dest
        #elseif canImport(AppKit)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let nsImage = NSImage(cgImage: cgImage, size: size)
        nsImage.draw(in: CGRect(origin: .zero, size: size))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "AvenirNext-Heavy", size: size.width * 0.08) ?? .boldSystemFont(ofSize: 48),
            .foregroundColor: NSColor(srgbRed: brandColor.r, green: brandColor.g, blue: brandColor.b, alpha: 1),
            .strokeColor: NSColor.black,
            .strokeWidth: -3,
            .paragraphStyle: paragraph
        ]
        let rect = CGRect(x: size.width * 0.08, y: size.height * 0.38, width: size.width * 0.84, height: size.height * 0.24)
        (coverText as NSString).draw(in: rect, withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptionStudio-Cover-\(UUID().uuidString).png")
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw ExportError.exportFailed("Could not encode cover PNG.")
        }
        try data.write(to: dest, options: .atomic)
        return dest
        #else
        throw ExportError.exportFailed("Cover export unavailable on this platform.")
        #endif
    }
}
