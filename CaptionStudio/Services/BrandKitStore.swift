import Foundation
import SwiftUI

/// User brand defaults applied to new projects and soft-constrained in enhance.
struct BrandKit: Equatable, Codable {
    var primaryFontId: String
    var hindiFontId: String
    var teluguFontId: String
    var primaryColor: String
    var secondaryColor: String
    var watermarkText: String
    var watermarkX: Double
    var watermarkY: Double
    var defaultPackId: String?
    var defaultLanguage: String
    var defaultSfxGain: Double
    var watermarkEnabled: Bool

    static let `default` = BrandKit(
        primaryFontId: "latin-heavy",
        hindiFontId: "hindi-bold",
        teluguFontId: "telugu-bold",
        primaryColor: "#FFEF5A",
        secondaryColor: "#FF2D2D",
        watermarkText: "",
        watermarkX: 0.85,
        watermarkY: 0.92,
        defaultPackId: "hype",
        defaultLanguage: AppLanguage.english.rawValue,
        defaultSfxGain: 0.8,
        watermarkEnabled: false
    )

    var primarySwiftUIColor: Color {
        Color(hex: primaryColor) ?? Color(red: 1, green: 0.94, blue: 0.35)
    }

    var secondarySwiftUIColor: Color {
        Color(hex: secondaryColor) ?? Color(red: 1, green: 0.18, blue: 0.18)
    }

    var appLanguage: AppLanguage {
        AppLanguage(rawValue: defaultLanguage) ?? .english
    }

    func fontId(for language: AppLanguage) -> String {
        switch language {
        case .hindi: return hindiFontId
        case .telugu: return teluguFontId
        case .english: return primaryFontId
        }
    }
}

@MainActor
final class BrandKitStore: ObservableObject {
    @Published var kit: BrandKit {
        didSet { persist() }
    }

    private let defaultsKey = "CaptionStudio.BrandKit"

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode(BrandKit.self, from: data) {
            kit = decoded
        } else {
            kit = .default
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(kit) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    func reset() {
        kit = .default
    }
}
