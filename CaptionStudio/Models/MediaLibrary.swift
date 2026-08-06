import Foundation
import SwiftUI

enum MediaLibraryKind: String, CaseIterable, Identifiable, Codable {
    case textStyles = "text-styles"
    case gifs
    case pngs
    case sfx

    var id: String { rawValue }

    var title: String {
        switch self {
        case .textStyles: return "Stylish Text"
        case .gifs: return "GIFs"
        case .pngs: return "PNGs"
        case .sfx: return "Sound FX"
        }
    }

    var systemImage: String {
        switch self {
        case .textStyles: return "textformat"
        case .gifs: return "livephoto.play"
        case .pngs: return "photo"
        case .sfx: return "speaker.wave.2.fill"
        }
    }

    var folderName: String { rawValue }
}

struct MediaLibraryItem: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var tags: [String]
    var file: String?
    var wav: String?
    var previewText: String?
    var fontName: String?
    var fontSize: CGFloat?
    var textCase: String?
    var textColor: String?
    var strokeColor: String?
    var strokeWidth: CGFloat?
    var backgroundColor: String?
    var cornerRadius: CGFloat?
    var shadowRadius: CGFloat?
    var animation: String?
    var defaultDuration: TimeInterval?
    var defaultScale: CGFloat?
    var defaultGain: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, tags, file, wav, previewText, fontName, fontSize
        case textCase, textColor, strokeColor, strokeWidth, backgroundColor
        case cornerRadius, shadowRadius, animation, defaultDuration, defaultScale, defaultGain
    }
}

struct MediaLibraryCatalog: Codable {
    var version: Int
    var library: String
    var items: [MediaLibraryItem]
}

/// Precise placement returned by Cursor SDK enhancer (or heuristic fallback).
struct EnhancementPlacement: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var kind: String
    var assetId: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    var x: CGFloat
    var y: CGFloat
    var scale: CGFloat
    var rotation: Double
    var text: String?
    var reason: String?

    enum CodingKeys: String, CodingKey {
        case kind, assetId, startTime, endTime, x, y, scale, rotation, text, reason
    }
}

struct EnhancementPlan: Codable {
    var summary: String
    var placements: [EnhancementPlacement]
    var source: String?
    var model: String?
    var note: String?
}

struct SoundEffectCue: Identifiable, Equatable, Codable, Hashable {
    var id: UUID = UUID()
    var assetId: String
    var startTime: TimeInterval
    var gain: Double
    var reason: String?
}
