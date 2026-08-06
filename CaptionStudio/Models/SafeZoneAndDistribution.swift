import Foundation
import CoreGraphics
import SwiftUI

/// Reels/TikTok chrome-safe region in normalized coordinates (0…1).
struct SafeZone: Equatable, Codable, Hashable {
    var xMin: CGFloat
    var xMax: CGFloat
    var yMin: CGFloat
    var yMax: CGFloat

    /// Portrait defaults — leave room for top status, right buttons, bottom caption bar.
    static let reelsPortrait = SafeZone(xMin: 0.08, xMax: 0.82, yMin: 0.12, yMax: 0.78)
    static let reelsLandscape = SafeZone(xMin: 0.06, xMax: 0.94, yMin: 0.10, yMax: 0.88)

    static func forAspect(_ aspect: AspectRatioPreset) -> SafeZone {
        aspect == .landscape16x9 ? .reelsLandscape : .reelsPortrait
    }

    func clamp(x: CGFloat, y: CGFloat) -> (CGFloat, CGFloat) {
        (min(xMax, max(xMin, x)), min(yMax, max(yMin, y)))
    }

    var rect: CGRect {
        CGRect(x: xMin, y: yMin, width: max(0, xMax - xMin), height: max(0, yMax - yMin))
    }
}

/// Post metadata for social distribution (title / hashtags / cover).
struct DistributionPackage: Equatable, Codable, Hashable {
    var title: String
    var coverText: String
    var hashtags: [String]
    var hookLine: String?

    var hashtagLine: String {
        hashtags.map { tag in
            tag.hasPrefix("#") ? tag : "#\(tag)"
        }.joined(separator: " ")
    }

    static func heuristic(
        captions: [CaptionSegment],
        language: AppLanguage,
        packName: String?
    ) -> DistributionPackage {
        let text = captions.map(\.text).joined(separator: " ")
        let words = text
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
            .filter { $0.count > 2 }
        let significant = Array(words.prefix(6))
        let hook = significant.first ?? (language == .hindi ? "देखो" : language == .telugu ? "చూడండి" : "Watch this")
        let titleBase = significant.prefix(4).joined(separator: " ")
        let title = titleBase.isEmpty
            ? (packName.map { "\($0) short" } ?? "New short")
            : String(titleBase.prefix(60))
        let cover = String((significant.first ?? hook).uppercased().prefix(24))

        var tags: [String] = []
        switch language {
        case .english:
            tags = ["#shorts", "#reels", "#fyp"]
        case .hindi:
            tags = ["#शॉर्ट्स", "#reels", "#fyp"]
        case .telugu:
            tags = ["#shorts", "#reels", "#తెలుగు"]
        }
        if let packName {
            tags.append("#\(packName.lowercased())")
        }
        if let w = significant.first {
            tags.append("#\(w.lowercased())")
        }
        return DistributionPackage(
            title: title,
            coverText: cover,
            hashtags: Array(tags.prefix(6)),
            hookLine: hook
        )
    }
}
