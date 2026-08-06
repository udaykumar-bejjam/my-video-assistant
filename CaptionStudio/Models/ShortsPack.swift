import Foundation
import SwiftUI

/// Creative recipe for one-tap short-form enhancement.
struct ShortsPack: Identifiable, Hashable, Codable {
    var id: String
    var name: String
    var subtitle: String?
    var systemImage: String?
    var aspect: String
    var captionStyle: String
    var effectBias: [String]
    var sfxBias: [String]
    var gifTags: [String]?
    var wordHitsPerCaption: Int
    var requireHookInFirstSeconds: Double
    var gifDensity: String
    var accentColor: String?

    var aspectPreset: AspectRatioPreset {
        aspect == "16:9" ? .landscape16x9 : .portrait9x16
    }

    var captionPreset: CaptionPreset {
        switch captionStyle {
        case "neon": return .neon
        case "boxed": return .boxed
        case "outline": return .outline
        case "softShadow": return .softShadow
        case "lowercase": return .lowercase
        case "upperPunch": return .upperPunch
        case "boldWhite": return .boldWhite
        default: return .upperPunch
        }
    }

    var icon: String { systemImage ?? "sparkles" }

    var accent: Color {
        Color(hex: accentColor ?? "#33F2CF") ?? Color(red: 0.2, green: 0.95, blue: 0.8)
    }

    var gifEveryN: Int {
        switch gifDensity {
        case "high": return 1
        case "low": return 3
        default: return 2
        }
    }
}

struct ShortsPackCatalog: Codable {
    var version: Int
    var library: String
    var items: [ShortsPack]
}

struct EnhancementHook: Hashable, Codable {
    var word: String?
    var startTime: TimeInterval?
    var endTime: TimeInterval?
    var effectId: String?
    var sfxId: String?
    var fontId: String?
    var reason: String?
}
