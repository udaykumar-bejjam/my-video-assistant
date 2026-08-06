import Foundation
import SwiftUI
import CoreGraphics
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A single timed caption segment (phrase or word-level).
struct CaptionSegment: Identifiable, Equatable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval
    /// Optional word-level timings for karaoke-style highlight.
    var words: [CaptionWord] = []

    var duration: TimeInterval { max(0, endTime - startTime) }

    func contains(time: TimeInterval) -> Bool {
        time >= startTime && time < endTime
    }
}

struct CaptionWord: Identifiable, Equatable, Codable, Hashable {
    var id: UUID = UUID()
    var text: String
    var startTime: TimeInterval
    var endTime: TimeInterval

    func contains(time: TimeInterval) -> Bool {
        time >= startTime && time < endTime
    }
}

enum CaptionAnimation: String, CaseIterable, Identifiable, Codable {
    case none = "None"
    case fade = "Fade"
    case pop = "Pop"
    case karaoke = "Karaoke"
    case typewriter = "Typewriter"
    case bounce = "Bounce"

    var id: String { rawValue }
}

enum CaptionPreset: String, CaseIterable, Identifiable, Codable {
    case boldWhite = "Bold White"
    case neon = "Neon"
    case boxed = "Boxed"
    case outline = "Outline"
    case softShadow = "Soft Shadow"
    case lowercase = "lowercase"
    case upperPunch = "UPPER"

    var id: String { rawValue }

    var style: CaptionStyle {
        switch self {
        case .boldWhite:
            return CaptionStyle(
                fontName: "AvenirNext-Heavy",
                fontSize: 42,
                textColor: .white,
                strokeColor: .clear,
                strokeWidth: 0,
                backgroundColor: .clear,
                shadowColor: .black.opacity(0.55),
                shadowRadius: 8,
                cornerRadius: 0,
                animation: .karaoke,
                textCase: .asIs
            )
        case .neon:
            return CaptionStyle(
                fontName: "AvenirNext-Bold",
                fontSize: 40,
                textColor: Color(red: 0.2, green: 1.0, blue: 0.85),
                strokeColor: .black,
                strokeWidth: 1.5,
                backgroundColor: .clear,
                shadowColor: Color(red: 0.2, green: 1.0, blue: 0.85).opacity(0.8),
                shadowRadius: 14,
                cornerRadius: 0,
                animation: .pop,
                textCase: .asIs
            )
        case .boxed:
            return CaptionStyle(
                fontName: "AvenirNext-Bold",
                fontSize: 36,
                textColor: .white,
                strokeColor: .clear,
                strokeWidth: 0,
                backgroundColor: .black.opacity(0.75),
                shadowColor: .clear,
                shadowRadius: 0,
                cornerRadius: 10,
                animation: .fade,
                textCase: .asIs
            )
        case .outline:
            return CaptionStyle(
                fontName: "AvenirNext-Heavy",
                fontSize: 44,
                textColor: .white,
                strokeColor: .black,
                strokeWidth: 3,
                backgroundColor: .clear,
                shadowColor: .clear,
                shadowRadius: 0,
                cornerRadius: 0,
                animation: .karaoke,
                textCase: .asIs
            )
        case .softShadow:
            return CaptionStyle(
                fontName: "Georgia-Bold",
                fontSize: 38,
                textColor: .white,
                strokeColor: .clear,
                strokeWidth: 0,
                backgroundColor: .clear,
                shadowColor: .black.opacity(0.7),
                shadowRadius: 12,
                cornerRadius: 0,
                animation: .fade,
                textCase: .asIs
            )
        case .lowercase:
            return CaptionStyle(
                fontName: "AvenirNext-Medium",
                fontSize: 36,
                textColor: .white,
                strokeColor: .black,
                strokeWidth: 1,
                backgroundColor: .clear,
                shadowColor: .black.opacity(0.4),
                shadowRadius: 6,
                cornerRadius: 0,
                animation: .typewriter,
                textCase: .lower
            )
        case .upperPunch:
            return CaptionStyle(
                fontName: "AvenirNext-Heavy",
                fontSize: 40,
                textColor: Color(red: 1.0, green: 0.92, blue: 0.2),
                strokeColor: .black,
                strokeWidth: 2.5,
                backgroundColor: .clear,
                shadowColor: .black.opacity(0.5),
                shadowRadius: 4,
                cornerRadius: 0,
                animation: .bounce,
                textCase: .upper
            )
        }
    }
}

enum CaptionTextCase: String, Codable {
    case asIs, lower, upper

    func apply(_ text: String) -> String {
        switch self {
        case .asIs: return text
        case .lower: return text.lowercased()
        case .upper: return text.uppercased()
        }
    }
}

struct CaptionStyle: Equatable, Codable {
    var fontName: String
    var fontSize: CGFloat
    var textColor: CodableColor
    var strokeColor: CodableColor
    var strokeWidth: CGFloat
    var backgroundColor: CodableColor
    var shadowColor: CodableColor
    var shadowRadius: CGFloat
    var cornerRadius: CGFloat
    var animation: CaptionAnimation
    var textCase: CaptionTextCase
    /// Normalized position: (0.5, 0.82) = center-bottom
    var positionX: CGFloat = 0.5
    var positionY: CGFloat = 0.82

    static let `default` = CaptionPreset.boldWhite.style
}

/// Codable wrapper for SwiftUI Color (RGBA).
struct CodableColor: Equatable, Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double

    init(_ color: Color) {
        #if canImport(UIKit)
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            self.r = Double(r); self.g = Double(g); self.b = Double(b); self.a = Double(a)
        } else if ui.getWhite(&r, alpha: &a) {
            self.r = Double(r); self.g = Double(r); self.b = Double(r); self.a = Double(a)
        } else {
            self.r = 1; self.g = 1; self.b = 1; self.a = 1
        }
        #elseif canImport(AppKit)
        let ns = NSColor(color)
        guard let rgb = ns.usingColorSpace(.sRGB) else {
            self.r = 1; self.g = 1; self.b = 1; self.a = 1
            return
        }
        self.r = Double(rgb.redComponent)
        self.g = Double(rgb.greenComponent)
        self.b = Double(rgb.blueComponent)
        self.a = Double(rgb.alphaComponent)
        #else
        self.r = 1; self.g = 1; self.b = 1; self.a = 1
        #endif
    }

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    var color: Color {
        Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    static let clear = CodableColor(r: 0, g: 0, b: 0, a: 0)
    static let white = CodableColor(r: 1, g: 1, b: 1, a: 1)
    static let black = CodableColor(r: 0, g: 0, b: 0, a: 1)
}

extension Color {
    var codable: CodableColor { CodableColor(self) }
}

extension CodableColor {
    static func == (lhs: CodableColor, rhs: CodableColor) -> Bool {
        abs(lhs.r - rhs.r) < 0.001 &&
        abs(lhs.g - rhs.g) < 0.001 &&
        abs(lhs.b - rhs.b) < 0.001 &&
        abs(lhs.a - rhs.a) < 0.001
    }
}

// Convenience so CaptionStyle can use Color literals in presets
extension CaptionStyle {
    init(
        fontName: String,
        fontSize: CGFloat,
        textColor: Color,
        strokeColor: Color,
        strokeWidth: CGFloat,
        backgroundColor: Color,
        shadowColor: Color,
        shadowRadius: CGFloat,
        cornerRadius: CGFloat,
        animation: CaptionAnimation,
        textCase: CaptionTextCase,
        positionX: CGFloat = 0.5,
        positionY: CGFloat = 0.82
    ) {
        self.fontName = fontName
        self.fontSize = fontSize
        self.textColor = textColor.codable
        self.strokeColor = strokeColor.codable
        self.strokeWidth = strokeWidth
        self.backgroundColor = backgroundColor.codable
        self.shadowColor = shadowColor.codable
        self.shadowRadius = shadowRadius
        self.cornerRadius = cornerRadius
        self.animation = animation
        self.textCase = textCase
        self.positionX = positionX
        self.positionY = positionY
    }
}
