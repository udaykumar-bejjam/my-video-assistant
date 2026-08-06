import Foundation
import AVFoundation
import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var project: VideoProject = .empty()
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var isTranscribing = false
    @Published var isExporting = false
    @Published var selectedCaptionID: CaptionSegment.ID?
    @Published var selectedOverlayID: OverlayItem.ID?
    @Published var selectedPreset: CaptionPreset = .boldWhite
    @Published var errorMessage: String?
    @Published var exportURL: URL?
    @Published var showExporter = false
    @Published var editorTab: EditorTab = .captions

    let transcription = TranscriptionService()
    let exporter = VideoExportService()

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?

    enum EditorTab: String, CaseIterable, Identifiable {
        case captions, styles, overlays, export
        var id: String { rawValue }
        var title: String {
            switch self {
            case .captions: return "Captions"
            case .styles: return "Styles"
            case .overlays: return "Overlays"
            case .export: return "Export"
            }
        }
        var icon: String {
            switch self {
            case .captions: return "text.bubble.fill"
            case .styles: return "paintpalette.fill"
            case .overlays: return "square.stack.3d.up.fill"
            case .export: return "square.and.arrow.up.fill"
            }
        }
    }

    var activeCaption: CaptionSegment? {
        project.captions.first { $0.contains(time: currentTime) }
    }

    var visibleOverlays: [OverlayItem] {
        project.overlays.filter { $0.isVisible(at: currentTime) }
    }

    // MARK: - Video load

    func loadVideo(url: URL) async {
        tearDownPlayer()

        // Copy into app sandbox so security-scoped imports stay readable.
        let localURL: URL
        do {
            localURL = try Self.copyIntoCaches(url)
        } catch {
            errorMessage = "Could not open video: \(error.localizedDescription)"
            return
        }

        project.videoURL = localURL
        project.title = url.deletingPathExtension().lastPathComponent
        project.captions = []
        project.overlays = []
        project.captionStyle = selectedPreset.style

        let asset = AVURLAsset(url: localURL)
        if let duration = try? await asset.load(.duration) {
            project.duration = CMTimeGetSeconds(duration)
        }

        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        currentTime = 0
        isPlaying = false

        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.currentTime = CMTimeGetSeconds(time)
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.seek(to: 0)
            }
        }
    }

    private static func copyIntoCaches(_ url: URL) throws -> URL {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dest = caches.appendingPathComponent("import-\(UUID().uuidString)-\(url.lastPathComponent)")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }

    func generateCaptions() async {
        guard let url = project.videoURL else {
            errorMessage = "Import a video first."
            return
        }
        isTranscribing = true
        errorMessage = nil
        defer { isTranscribing = false }

        do {
            let captions = try await transcription.transcribe(videoURL: url)
            project.captions = captions
            selectedCaptionID = captions.first?.id
            editorTab = .styles
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Playback

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            if currentTime >= project.duration - 0.05 {
                seek(to: 0)
            }
            player.play()
            isPlaying = true
        }
    }

    func seek(to time: TimeInterval) {
        let cm = CMTime(seconds: max(0, time), preferredTimescale: 600)
        player?.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = max(0, time)
    }

    // MARK: - Captions / style

    func applyPreset(_ preset: CaptionPreset) {
        selectedPreset = preset
        project.captionStyle = preset.style
    }

    func updateCaption(_ caption: CaptionSegment) {
        guard let index = project.captions.firstIndex(where: { $0.id == caption.id }) else { return }
        project.captions[index] = caption
    }

    func deleteCaption(_ id: CaptionSegment.ID) {
        project.captions.removeAll { $0.id == id }
        if selectedCaptionID == id { selectedCaptionID = nil }
    }

    // MARK: - Overlays

    func addTextOverlay(_ text: String = "Your text") {
        let item = OverlayItem.textSticker(text, at: currentTime)
        project.overlays.append(item)
        selectedOverlayID = item.id
        editorTab = .overlays
    }

    func addEmojiOverlay(_ emoji: String) {
        let item = OverlayItem.emoji(emoji, at: currentTime)
        project.overlays.append(item)
        selectedOverlayID = item.id
    }

    func updateOverlay(_ item: OverlayItem) {
        guard let index = project.overlays.firstIndex(where: { $0.id == item.id }) else { return }
        project.overlays[index] = item
    }

    func deleteOverlay(_ id: OverlayItem.ID) {
        project.overlays.removeAll { $0.id == id }
        if selectedOverlayID == id { selectedOverlayID = nil }
    }

    // MARK: - Export

    func exportVideo() async {
        guard let url = project.videoURL else {
            errorMessage = "Import a video first."
            return
        }
        isExporting = true
        errorMessage = nil
        defer { isExporting = false }

        do {
            let result = try await exporter.export(
                videoURL: url,
                captions: project.captions,
                style: project.captionStyle,
                overlays: project.overlays
            )
            exportURL = result
            showExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Cleanup

    func tearDownPlayer() {
        player?.pause()
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        timeObserver = nil
        endObserver = nil
        player = nil
        isPlaying = false
    }

    deinit {
        // Cannot call MainActor tearDown from deinit safely; observers cleared on replace.
    }
}
