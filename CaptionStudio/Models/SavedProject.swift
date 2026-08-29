import Foundation
import CoreGraphics

/// Where the editor was left — restored on open so work resumes mid-timeline.
struct ProjectSessionState: Equatable, Codable, Hashable {
    var playheadTime: TimeInterval = 0
    /// Matches `EditorViewModel.EditorTab.rawValue` (`captions`, `overlays`, …).
    var editorTab: String = "captions"
    var selectedCaptionID: UUID?
    var selectedOverlayID: UUID?
    var selectedSoundEffectID: UUID?
    var isAudioLayerSelected: Bool = false
    var showSafeZone: Bool = true
    var libraryKind: String?

    static let `default` = ProjectSessionState()
}

/// On-disk snapshot of an editable project (`project.json` next to `video.*`).
///
/// Layout per project folder:
/// ```
/// <id>/
///   project.json   — captions, overlays, SFX refs, audio mix, session
///   video.<ext>    — source footage copy
/// ```
/// Library assets (GIF/PNG/SFX/fonts) are referenced by `assetId` / `assetFileName`
/// and resolved from the Media Library at load time.
struct SavedProject: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var videoFileName: String
    var duration: TimeInterval
    var aspectRatio: AspectRatioPreset
    var sourceWidth: Double
    var sourceHeight: Double
    var captions: [CaptionSegment]
    var captionStyle: CaptionStyle
    var overlays: [OverlayItem]
    var soundEffects: [SoundEffectCue]
    var audio: ProjectAudioSettings
    var enhancementSummary: String?
    var packId: String?
    var language: AppLanguage
    var chunkCount: Int
    var createdAt: Date
    var updatedAt: Date
    /// Resume playhead, tab, and layer selection.
    var session: ProjectSessionState
    /// Social post copy from AI Place / heuristics.
    var distribution: DistributionPackage?
    /// Optional chess walkthrough composited onto export.
    var chessOverlay: ChessWalkthroughSpec?

    var sourceSize: CGSize {
        CGSize(width: sourceWidth, height: sourceHeight)
    }

    var languageBadge: String {
        switch language {
        case .english: return "EN"
        case .hindi: return "HI"
        case .telugu: return "TE"
        }
    }

    var resumeClock: String {
        let t = max(0, session.playheadTime)
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }

    static func from(
        project: VideoProject,
        videoFileName: String,
        session: ProjectSessionState = .default,
        distribution: DistributionPackage? = nil,
        updatedAt: Date = .now
    ) -> SavedProject {
        SavedProject(
            id: project.id,
            title: project.title,
            videoFileName: videoFileName,
            duration: project.duration,
            aspectRatio: project.aspectRatio,
            sourceWidth: project.sourceSize.width,
            sourceHeight: project.sourceSize.height,
            captions: project.captions,
            captionStyle: project.captionStyle,
            overlays: project.overlays,
            soundEffects: project.soundEffects,
            audio: project.audio,
            enhancementSummary: project.enhancementSummary,
            packId: project.packId,
            language: project.language,
            chunkCount: project.chunkCount,
            createdAt: project.createdAt,
            updatedAt: updatedAt,
            session: session,
            distribution: distribution,
            chessOverlay: project.chessOverlay
        )
    }

    func toProject(videoURL: URL) -> VideoProject {
        VideoProject(
            id: id,
            title: title,
            videoURL: videoURL,
            duration: duration,
            aspectRatio: aspectRatio,
            sourceSize: sourceSize,
            captions: captions,
            captionStyle: captionStyle,
            overlays: overlays,
            soundEffects: soundEffects,
            audio: audio,
            enhancementSummary: enhancementSummary,
            packId: packId,
            language: language,
            chunkCount: chunkCount,
            createdAt: createdAt,
            chessOverlay: chessOverlay
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, title, videoFileName, duration, aspectRatio
        case sourceWidth, sourceHeight, captions, captionStyle, overlays, soundEffects
        case audio, enhancementSummary, packId, language, chunkCount, createdAt, updatedAt
        case session, distribution, chessOverlay
    }

    init(
        id: UUID,
        title: String,
        videoFileName: String,
        duration: TimeInterval,
        aspectRatio: AspectRatioPreset,
        sourceWidth: Double,
        sourceHeight: Double,
        captions: [CaptionSegment],
        captionStyle: CaptionStyle,
        overlays: [OverlayItem],
        soundEffects: [SoundEffectCue],
        audio: ProjectAudioSettings = .default,
        enhancementSummary: String?,
        packId: String?,
        language: AppLanguage,
        chunkCount: Int,
        createdAt: Date,
        updatedAt: Date,
        session: ProjectSessionState = .default,
        distribution: DistributionPackage? = nil,
        chessOverlay: ChessWalkthroughSpec? = nil
    ) {
        self.id = id
        self.title = title
        self.videoFileName = videoFileName
        self.duration = duration
        self.aspectRatio = aspectRatio
        self.sourceWidth = sourceWidth
        self.sourceHeight = sourceHeight
        self.captions = captions
        self.captionStyle = captionStyle
        self.overlays = overlays
        self.soundEffects = soundEffects
        self.audio = audio
        self.enhancementSummary = enhancementSummary
        self.packId = packId
        self.language = language
        self.chunkCount = chunkCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.session = session
        self.distribution = distribution
        self.chessOverlay = chessOverlay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        videoFileName = try c.decode(String.self, forKey: .videoFileName)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        aspectRatio = try c.decode(AspectRatioPreset.self, forKey: .aspectRatio)
        sourceWidth = try c.decode(Double.self, forKey: .sourceWidth)
        sourceHeight = try c.decode(Double.self, forKey: .sourceHeight)
        captions = try c.decode([CaptionSegment].self, forKey: .captions)
        captionStyle = try c.decode(CaptionStyle.self, forKey: .captionStyle)
        overlays = try c.decode([OverlayItem].self, forKey: .overlays)
        soundEffects = try c.decodeIfPresent([SoundEffectCue].self, forKey: .soundEffects) ?? []
        audio = try c.decodeIfPresent(ProjectAudioSettings.self, forKey: .audio) ?? .default
        enhancementSummary = try c.decodeIfPresent(String.self, forKey: .enhancementSummary)
        packId = try c.decodeIfPresent(String.self, forKey: .packId)
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .english
        chunkCount = try c.decodeIfPresent(Int.self, forKey: .chunkCount) ?? 1
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        session = try c.decodeIfPresent(ProjectSessionState.self, forKey: .session) ?? .default
        distribution = try c.decodeIfPresent(DistributionPackage.self, forKey: .distribution)
        chessOverlay = try c.decodeIfPresent(ChessWalkthroughSpec.self, forKey: .chessOverlay)
    }
}

struct TrimSuggestion: Identifiable, Equatable, Hashable, Codable {
    var id: UUID = UUID()
    var startTime: TimeInterval
    var endTime: TimeInterval
    var reason: String

    var duration: TimeInterval { max(0, endTime - startTime) }
}
