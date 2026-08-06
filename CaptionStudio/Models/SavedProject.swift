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
            enhancementSummary: enhancementSummary,
            packId: packId,
            language: language,
            chunkCount: chunkCount,
            createdAt: createdAt
        )
    }
}

struct TrimSuggestion: Identifiable, Equatable, Hashable, Codable {
    var id: UUID = UUID()
    var startTime: TimeInterval
    var endTime: TimeInterval
    var reason: String

    var duration: TimeInterval { max(0, endTime - startTime) }
}
