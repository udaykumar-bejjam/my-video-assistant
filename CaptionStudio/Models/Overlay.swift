import Foundation
import SwiftUI
import CoreGraphics

enum OverlayKind: String, CaseIterable, Identifiable, Codable {
    case text
    case emoji
    case shape
    case watermark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .text: return "Text"
        case .emoji: return "Emoji"
        case .shape: return "Shape"
        case .watermark: return "Watermark"
        }
    }

    var systemImage: String {
        switch self {
        case .text: return "textformat"
        case .emoji: return "face.smiling"
        case .shape: return "square.on.circle"
        case .watermark: return "seal"
        }
    }
}

enum OverlayShapeType: String, CaseIterable, Codable {
    case rectangle, circle, line, arrow
}

/// A freeform overlay (sticker / text / shape) on the video canvas.
struct OverlayItem: Identifiable, Equatable, Codable, Hashable {
    var id: UUID = UUID()
    var kind: OverlayKind
    var text: String
    /// Normalized center (0...1)
    var x: CGFloat
    var y: CGFloat
    var scale: CGFloat
    var rotation: Double
    var startTime: TimeInterval
    var endTime: TimeInterval
    var color: CodableColor
    var fontSize: CGFloat
    var shape: OverlayShapeType
    var opacity: Double

    static func textSticker(
        _ text: String,
        at time: TimeInterval,
        duration: TimeInterval = 3
    ) -> OverlayItem {
        OverlayItem(
            kind: .text,
            text: text,
            x: 0.5,
            y: 0.3,
            scale: 1,
            rotation: 0,
            startTime: time,
            endTime: time + duration,
            color: .white,
            fontSize: 28,
            shape: .rectangle,
            opacity: 1
        )
    }

    static func emoji(
        _ emoji: String,
        at time: TimeInterval,
        duration: TimeInterval = 2.5
    ) -> OverlayItem {
        OverlayItem(
            kind: .emoji,
            text: emoji,
            x: 0.75,
            y: 0.25,
            scale: 1.4,
            rotation: -8,
            startTime: time,
            endTime: time + duration,
            color: .white,
            fontSize: 48,
            shape: .circle,
            opacity: 1
        )
    }

    func isVisible(at time: TimeInterval) -> Bool {
        time >= startTime && time < endTime
    }
}

struct VideoProject: Identifiable, Equatable {
    var id: UUID = UUID()
    var title: String
    var videoURL: URL?
    var duration: TimeInterval
    var captions: [CaptionSegment]
    var captionStyle: CaptionStyle
    var overlays: [OverlayItem]
    var createdAt: Date

    static func empty(title: String = "Untitled") -> VideoProject {
        VideoProject(
            title: title,
            videoURL: nil,
            duration: 0,
            captions: [],
            captionStyle: .default,
            overlays: [],
            createdAt: .now
        )
    }
}
