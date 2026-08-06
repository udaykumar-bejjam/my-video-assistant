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

/// Punchy on-screen effects for significant words (not just bold).
enum WordHitEffect: String, CaseIterable, Identifiable, Codable {
    case punch
    case colorPulse = "color-pulse"
    case firePulse = "fire-pulse"
    case neonPulse = "neon-pulse"
    case slam
    case bounce
    case zoom
    case shake
    case spin
    case flash
    case rise
    case glitch
    case typepop
    case pulse
    case stomp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .colorPulse: return "Color Pulse"
        case .firePulse: return "Fire Pulse"
        case .neonPulse: return "Neon Pulse"
        default: return rawValue.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }

    /// Primary → secondary colors that animate during the hit.
    var palette: [Color] {
        switch self {
        case .punch, .colorPulse, .stomp, .pulse:
            return [Color(red: 1, green: 0.94, blue: 0.35), Color(red: 1, green: 0.18, blue: 0.18)]
        case .firePulse:
            return [
                Color(red: 1, green: 0.62, blue: 0.11),
                Color(red: 1, green: 0.18, blue: 0.18),
                Color(red: 1, green: 0.94, blue: 0.35)
            ]
        case .neonPulse:
            return [Color(red: 0.2, green: 0.95, blue: 0.81), Color(red: 1, green: 0.18, blue: 0.61)]
        case .shake, .glitch:
            return [Color(red: 1, green: 0.18, blue: 0.18), Color(red: 1, green: 0.94, blue: 0.35)]
        case .bounce:
            return [Color(red: 0.2, green: 0.95, blue: 0.81), Color(red: 1, green: 0.94, blue: 0.35)]
        case .spin:
            return [Color(red: 0.78, green: 0.49, blue: 1), Color(red: 1, green: 0.94, blue: 0.35)]
        case .slam, .flash, .typepop:
            return [.white, Color(red: 1, green: 0.94, blue: 0.35)]
        case .zoom, .rise:
            return [.white, Color(red: 0.2, green: 0.95, blue: 0.81)]
        }
    }

    static func random() -> WordHitEffect {
        // Bias toward the punchy/colorful ones the user asked for.
        let weighted: [WordHitEffect] = [
            .punch, .punch, .colorPulse, .colorPulse, .firePulse, .stomp,
            .slam, .shake, .pulse, .neonPulse, .bounce, .glitch, .zoom, .spin, .flash, .rise, .typepop
        ]
        return weighted.randomElement() ?? .punch
    }
}
