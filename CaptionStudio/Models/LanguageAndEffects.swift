import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en-US"
    case hindi = "hi-IN"
    case telugu = "te-IN"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: return "English"
        case .hindi: return "हिन्दी Hindi"
        case .telugu: return "తెలుగు Telugu"
        }
    }

    var localeIdentifier: String { rawValue }

    var scriptTags: [String] {
        switch self {
        case .english: return ["latin", "en"]
        case .hindi: return ["devanagari", "hi", "hindi"]
        case .telugu: return ["telugu", "te"]
        }
    }

    var defaultFontId: String {
        switch self {
        case .english: return "latin-heavy"
        case .hindi: return "hindi-bold"
        case .telugu: return "telugu-bold"
        }
    }

    var demoLines: [String] {
        switch self {
        case .english:
            return [
                "Hey — welcome to CaptionStudio",
                "AI captions in one tap",
                "Pick a style that pops",
                "Add overlays and emojis",
                "Export ready for social"
            ]
        case .hindi:
            return [
                "नमस्ते — कैप्शन स्टूडियो में स्वागत है",
                "एक टैप में एआई कैप्शन",
                "स्टाइल चुनो जो धमाकेदार हो",
                "ओवरले और इफ़ेक्ट जोड़ो",
                "सोशल के लिए एक्सपोर्ट तैयार"
            ]
        case .telugu:
            return [
                "నమస్కారం — క్యాప్షన్ స్టూడియోకి స్వాగతం",
                "ఒక్క ట్యాప్‌తో AI క్యాప్షన్లు",
                "బాగా కనిపించే స్టైల్ ఎంచుకోండి",
                "ఓవర్‌లేలు మరియు ఎఫెక్టులు జోడించండి",
                "సోషల్ కోసం ఎగుమతి సిద్ధం"
            ]
        }
    }
}

enum WordHitEffect: String, CaseIterable, Identifiable, Codable {
    case slam, bounce, zoom, shake, spin, flash, rise, glitch, typepop, pulse

    var id: String { rawValue }

    var title: String { rawValue.capitalized }

    static func random() -> WordHitEffect {
        allCases.randomElement() ?? .bounce
    }
}
