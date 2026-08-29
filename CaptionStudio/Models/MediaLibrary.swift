import Foundation
import SwiftUI

enum MediaLibraryKind: String, CaseIterable, Identifiable, Codable {
    case textStyles = "text-styles"
    case fonts
    case effects
    case gifs
    case pngs
    case sfx

    var id: String { rawValue }

    var title: String {
        switch self {
        case .textStyles: return "Stylish Text"
        case .fonts: return "Fonts"
        case .effects: return "Effects"
        case .gifs: return "GIFs"
        case .pngs: return "PNGs"
        case .sfx: return "Sound FX"
        }
    }

    var systemImage: String {
        switch self {
        case .textStyles: return "textformat"
        case .fonts: return "textformat.abc"
        case .effects: return "sparkles"
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
    var tags: [String]?
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
    var scripts: [String]?
    var preferredSfx: [String]?
    var colors: [String]?
    var description: String?
    var defaultDuration: TimeInterval?
    var defaultScale: CGFloat?
    var defaultGain: Double?
    var durationSeconds: TimeInterval?
    var lengthSeconds: TimeInterval?
    var width: CGFloat?
    var height: CGFloat?
    var frameCount: Int?
    var estimatedWidth: CGFloat?
    var estimatedHeight: CGFloat?
    var pixelWidth: CGFloat?
    var pixelHeight: CGFloat?
    var normalizedWidth: CGFloat?
    var normalizedHeight: CGFloat?
    var hasAlpha: Bool?
    var loop: Bool?

    var playLength: TimeInterval {
        lengthSeconds ?? durationSeconds ?? defaultDuration ?? 1.2
    }

    var pixelSize: CGSize {
        CGSize(
            width: pixelWidth ?? width ?? estimatedWidth ?? 128,
            height: pixelHeight ?? height ?? estimatedHeight ?? 128
        )
    }

    var tagList: [String] { tags ?? [] }

    enum CodingKeys: String, CodingKey {
        case id, name, tags, file, wav, previewText, fontName, fontSize
        case textCase, textColor, strokeColor, strokeWidth, backgroundColor
        case cornerRadius, shadowRadius, animation, scripts, preferredSfx, colors, description
        case defaultDuration, defaultScale, defaultGain
        case durationSeconds, lengthSeconds, width, height, frameCount
        case estimatedWidth, estimatedHeight, pixelWidth, pixelHeight
        case normalizedWidth, normalizedHeight, hasAlpha, loop
    }
}

struct MediaLibraryCatalog: Codable {
    var version: Int
    var library: String
    var items: [MediaLibraryItem]
}

/// Precise placement from Cursor SDK / heuristic — including significant word hits.
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
    var lengthSeconds: TimeInterval?
    var captionIndex: Int?
    var wordIndex: Int?
    var fontId: String?
    var effectId: String?
    var sfxId: String?
    var color: String?
    var secondaryColor: String?
    var word: String?
    var pairedWord: String?
    var mood: String?
    var assetPixelSize: AssetSize?
    var assetNormalizedSize: AssetSize?

    struct AssetSize: Hashable, Codable {
        var width: CGFloat
        var height: CGFloat
    }

    enum CodingKeys: String, CodingKey {
        case kind, assetId, startTime, endTime, x, y, scale, rotation, text, reason
        case lengthSeconds, captionIndex, wordIndex, fontId, effectId, sfxId, color, secondaryColor, word
        case pairedWord, mood
        case assetPixelSize, assetNormalizedSize
    }

    var displayText: String { word ?? text ?? "" }
}

struct EnhancementPlan: Codable {
    var summary: String
    var placements: [EnhancementPlacement]
    var wordHits: [EnhancementPlacement]?
    var hook: EnhancementHook?
    var packId: String?
    var distribution: DistributionPackage?
    var safeZone: SafeZone?
    var source: String?
    var model: String?
    var note: String?
    var language: String?
    /// Shared with Node `heuristicParityVersion` (AssetLibraries/heuristic/parity-contract.json).
    var heuristicParityVersion: String?

    /// All actionable edits the app must apply.
    var allEdits: [EnhancementPlacement] {
        placements + (wordHits ?? [])
    }
}

struct SoundEffectCue: Identifiable, Equatable, Codable, Hashable {
    var id: UUID = UUID()
    var assetId: String
    var startTime: TimeInterval
    var gain: Double
    var reason: String?
    /// When true, cue is skipped on export / preview mix.
    var isMuted: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, assetId, startTime, gain, reason, isMuted
    }

    init(
        id: UUID = UUID(),
        assetId: String,
        startTime: TimeInterval,
        gain: Double,
        reason: String? = nil,
        isMuted: Bool = false
    ) {
        self.id = id
        self.assetId = assetId
        self.startTime = startTime
        self.gain = gain
        self.reason = reason
        self.isMuted = isMuted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        assetId = try c.decode(String.self, forKey: .assetId)
        startTime = try c.decode(TimeInterval.self, forKey: .startTime)
        gain = try c.decode(Double.self, forKey: .gain)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        isMuted = try c.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
    }
}

/// Project-level dialogue + SFX mix / enhancer controls (Audio layer).
struct ProjectAudioSettings: Equatable, Codable, Hashable {
    /// Linear gain on the source dialogue track (0.25…2.0).
    var dialogueGain: Double = 1.0
    /// Peak-normalize dialogue on export (C3).
    var normalizeLoudness: Bool = true
    /// Multiplier applied to every SFX cue gain.
    var sfxMasterGain: Double = 1.0
    /// Briefly lower dialogue when an SFX cue plays.
    var duckDialogueUnderSFX: Bool = false
    /// How much to duck dialogue (0…0.85 of dialogue gain).
    var duckAmount: Double = 0.35
    /// Named enhancer recipe applied from the Audio layer.
    var enhancerPreset: AudioEnhancerPreset = .balanced

    static let `default` = ProjectAudioSettings()

    enum CodingKeys: String, CodingKey {
        case dialogueGain, normalizeLoudness, sfxMasterGain
        case duckDialogueUnderSFX, duckAmount, enhancerPreset
    }

    init(
        dialogueGain: Double = 1.0,
        normalizeLoudness: Bool = true,
        sfxMasterGain: Double = 1.0,
        duckDialogueUnderSFX: Bool = false,
        duckAmount: Double = 0.35,
        enhancerPreset: AudioEnhancerPreset = .balanced
    ) {
        self.dialogueGain = dialogueGain
        self.normalizeLoudness = normalizeLoudness
        self.sfxMasterGain = sfxMasterGain
        self.duckDialogueUnderSFX = duckDialogueUnderSFX
        self.duckAmount = duckAmount
        self.enhancerPreset = enhancerPreset
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dialogueGain = try c.decodeIfPresent(Double.self, forKey: .dialogueGain) ?? 1.0
        normalizeLoudness = try c.decodeIfPresent(Bool.self, forKey: .normalizeLoudness) ?? true
        sfxMasterGain = try c.decodeIfPresent(Double.self, forKey: .sfxMasterGain) ?? 1.0
        duckDialogueUnderSFX = try c.decodeIfPresent(Bool.self, forKey: .duckDialogueUnderSFX) ?? false
        duckAmount = try c.decodeIfPresent(Double.self, forKey: .duckAmount) ?? 0.35
        enhancerPreset = try c.decodeIfPresent(AudioEnhancerPreset.self, forKey: .enhancerPreset) ?? .balanced
    }

    mutating func apply(preset: AudioEnhancerPreset) {
        enhancerPreset = preset
        switch preset {
        case .balanced:
            dialogueGain = 1.0
            normalizeLoudness = true
            sfxMasterGain = 1.0
            duckDialogueUnderSFX = false
            duckAmount = 0.35
        case .podcast:
            dialogueGain = 1.15
            normalizeLoudness = true
            sfxMasterGain = 0.7
            duckDialogueUnderSFX = true
            duckAmount = 0.45
        case .hype:
            dialogueGain = 1.05
            normalizeLoudness = true
            sfxMasterGain = 1.15
            duckDialogueUnderSFX = true
            duckAmount = 0.25
        case .quiet:
            dialogueGain = 0.85
            normalizeLoudness = false
            sfxMasterGain = 0.55
            duckDialogueUnderSFX = false
            duckAmount = 0.3
        }
    }
}

enum AudioEnhancerPreset: String, CaseIterable, Identifiable, Codable {
    case balanced
    case podcast
    case hype
    case quiet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balanced: return "Balanced"
        case .podcast: return "Podcast"
        case .hype: return "Hype"
        case .quiet: return "Quiet"
        }
    }

    var subtitle: String {
        switch self {
        case .balanced: return "Normalize dialogue, natural SFX"
        case .podcast: return "Voice-forward, duck under SFX"
        case .hype: return "Punchy SFX, light duck"
        case .quiet: return "Softer mix, no normalize"
        }
    }

    var systemImage: String {
        switch self {
        case .balanced: return "slider.horizontal.3"
        case .podcast: return "mic.fill"
        case .hype: return "bolt.fill"
        case .quiet: return "speaker.wave.1.fill"
        }
    }
}
