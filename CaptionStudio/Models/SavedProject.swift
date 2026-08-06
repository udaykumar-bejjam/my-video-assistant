import Foundation
import CoreGraphics

/// On-disk snapshot of an editable project for drafts / history.
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

    static func from(project: VideoProject, videoFileName: String, updatedAt: Date = .now) -> SavedProject {
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
            updatedAt: updatedAt
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
            createdAt: createdAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, title, videoFileName, duration, aspectRatio
        case sourceWidth, sourceHeight, captions, captionStyle, overlays, soundEffects
        case audio, enhancementSummary, packId, language, chunkCount, createdAt, updatedAt
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
        updatedAt: Date
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
    }
}

struct TrimSuggestion: Identifiable, Equatable, Hashable, Codable {
    var id: UUID = UUID()
    var startTime: TimeInterval
    var endTime: TimeInterval
    var reason: String

    var duration: TimeInterval { max(0, endTime - startTime) }
}
