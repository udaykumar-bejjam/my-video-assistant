import Foundation
import AVFoundation
import SwiftUI
import Combine
import UniformTypeIdentifiers
#if canImport(AVFAudio)
import AVFAudio
#endif

@MainActor
final class EditorViewModel: ObservableObject {
    @Published var project: VideoProject = .empty()
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var isTranscribing = false
    @Published var isEnhancing = false
    @Published var isExporting = false
    @Published var selectedCaptionID: CaptionSegment.ID?
    @Published var selectedOverlayID: OverlayItem.ID?
    @Published var selectedSoundEffectID: SoundEffectCue.ID?
    /// Additive timeline multi-select (P1.2). Primary IDs above remain the inspector focus.
    @Published var selectedCaptionIDs: Set<CaptionSegment.ID> = []
    @Published var selectedOverlayIDs: Set<OverlayItem.ID> = []
    @Published var selectedSoundEffectIDs: Set<SoundEffectCue.ID> = []
    /// True when the Audio (dialogue) layer inspector should show as focused.
    @Published var isAudioLayerSelected = false
    /// When true, timeline taps toggle multi-select without modifier keys (iOS / accessibility).
    @Published var timelineMultiSelectMode = false
    @Published var selectedPreset: CaptionPreset = .boldWhite
    @Published var errorMessage: String?
    @Published var exportURL: URL?
    @Published var showExporter = false
    @Published var editorTab: EditorTab = .captions
    @Published var lastEnhancementNote: String?
    @Published var libraryKind: MediaLibraryKind = .textStyles
    @Published var chunkProgressLabel: String?
    @Published var language: AppLanguage = .english {
        didSet {
            project.language = language
            if !isRestoringHistory {
                applyLanguageCaptionDefaults()
            }
        }
    }
    @Published var batchExportAspects: Set<AspectRatioPreset> = [.portrait9x16]
    @Published var batchExportURLs: [URL] = []
    @Published var showBrandKit = false
    /// Focused OpenAI key sheet — shown on Home and before Telugu AI Captions.
    @Published var showOpenAIKeySheet = false
    @Published var trimSuggestions: [TrimSuggestion] = []
    @Published var selectedTrimIDs: Set<UUID> = []
    @Published var isTrimming = false
    @Published var draftMessage: String?
    @Published var showSafeZone = true
    @Published var distribution: DistributionPackage?
    @Published var coverURL: URL?
    /// Mirrors `project.audio.normalizeLoudness` for Export panel binding.
    @Published var normalizeLoudness = true {
        didSet {
            if project.audio.normalizeLoudness != normalizeLoudness {
                project.audio.normalizeLoudness = normalizeLoudness
            }
        }
    }
    /// When true, timeline SFX fire during playback as the playhead crosses cues.
    @Published var previewSFXDuringPlayback = true

    let transcription = TranscriptionService()
    let exporter = VideoExportService()
    let stitcher = VideoStitchService()
    let libraries = MediaLibraryStore()
    let packs = PackLibrary()
    let brandKit = BrandKitStore()
    let apiKeys = APIKeyStore()
    let projectStore = ProjectStore()
    let enhancer = CursorEnhancerClient()

    // MARK: - Undo / redo
    private let history = EditorHistory()
    private var isRestoringHistory = false
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    var selectedPack: ShortsPack? {
        packs.pack(id: project.packId)
    }

    var activeSafeZone: SafeZone {
        SafeZone.forAspect(project.aspectRatio)
    }

    var selectedTrimSuggestions: [TrimSuggestion] {
        trimSuggestions.filter { selectedTrimIDs.contains($0.id) }
    }

    init() {
        language = brandKit.kit.appLanguage
        project.audio.sfxMasterGain = brandKit.kit.defaultSfxGain
        normalizeLoudness = project.audio.normalizeLoudness
        if let defaultPack = brandKit.kit.defaultPackId {
            project.packId = defaultPack
            if let pack = packs.pack(id: defaultPack) {
                selectedPreset = pack.captionPreset
                project.captionStyle = pack.captionPreset.style
                project.aspectRatio = pack.aspectPreset
            }
        }
    }

    // MARK: - History

    private func documentSnapshot() -> EditorDocumentSnapshot {
        EditorDocumentSnapshot(
            project: project,
            selectedCaptionID: selectedCaptionID,
            selectedOverlayID: selectedOverlayID,
            selectedSoundEffectID: selectedSoundEffectID,
            selectedCaptionIDs: selectedCaptionIDs,
            selectedOverlayIDs: selectedOverlayIDs,
            selectedSoundEffectIDs: selectedSoundEffectIDs,
            isAudioLayerSelected: isAudioLayerSelected,
            selectedPreset: selectedPreset,
            language: language,
            trimSuggestions: trimSuggestions,
            selectedTrimIDs: selectedTrimIDs,
            distribution: distribution,
            editorTab: editorTab,
            lastEnhancementNote: lastEnhancementNote
        )
    }

    private func publishHistoryFlags() {
        canUndo = history.canUndo
        canRedo = history.canRedo
    }

    /// Call before a discrete document mutation.
    func registerUndoCheckpoint() {
        guard !isRestoringHistory else { return }
        history.push(documentSnapshot())
        publishHistoryFlags()
    }

    func undo() {
        guard let snap = history.undo(current: documentSnapshot()) else { return }
        applyDocumentSnapshot(snap)
        publishHistoryFlags()
    }

    func redo() {
        guard let snap = history.redo(current: documentSnapshot()) else { return }
        applyDocumentSnapshot(snap)
        publishHistoryFlags()
    }

    private func applyDocumentSnapshot(_ snap: EditorDocumentSnapshot) {
        isRestoringHistory = true
        defer { isRestoringHistory = false }
        project = snap.project
        selectedCaptionID = snap.selectedCaptionID
        selectedOverlayID = snap.selectedOverlayID
        selectedSoundEffectID = snap.selectedSoundEffectID
        selectedCaptionIDs = snap.selectedCaptionIDs
        selectedOverlayIDs = snap.selectedOverlayIDs
        selectedSoundEffectIDs = snap.selectedSoundEffectIDs
        isAudioLayerSelected = snap.isAudioLayerSelected
        selectedPreset = snap.selectedPreset
        language = snap.language
        trimSuggestions = snap.trimSuggestions
        selectedTrimIDs = snap.selectedTrimIDs
        distribution = snap.distribution
        editorTab = snap.editorTab
        lastEnhancementNote = snap.lastEnhancementNote
        normalizeLoudness = project.audio.normalizeLoudness
    }

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var sfxPlayers: [AVAudioPlayer] = []
    /// SFX cues already fired for the current play-through (timeline-synced preview).
    private var triggeredSFXIds: Set<UUID> = []
    /// Last playhead sample used to detect cue crossings (and backwards seeks).
    private var lastSFXCheckTime: TimeInterval = -1
    /// While `currentTime < previewDuckUntil`, dialogue preview volume is ducked under SFX.
    private var previewDuckUntil: TimeInterval?

    enum EditorTab: String, CaseIterable, Identifiable, Equatable {
        case captions, styles, overlays, libraries, trim, export
        var id: String { rawValue }
        var title: String {
            switch self {
            case .captions: return "Captions"
            case .styles: return "Styles"
            case .overlays: return "Layers"
            case .libraries: return "Library"
            case .trim: return "Trim"
            case .export: return "Export"
            }
        }
        var icon: String {
            switch self {
            case .captions: return "text.bubble.fill"
            case .styles: return "paintpalette.fill"
            case .overlays: return "rectangle.stack.fill"
            case .libraries: return "square.grid.2x2.fill"
            case .trim: return "scissors"
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
        history.clear()
        publishHistoryFlags()

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
        project.soundEffects = []
        project.enhancementSummary = nil
        // Keep pack selection across re-imports in the same session; apply its style/aspect if set.
        if let pack = selectedPack {
            applyPackSideEffects(pack)
        } else {
            project.captionStyle = selectedPreset.style
        }
        project.chunkCount = 1
        lastEnhancementNote = nil
        chunkProgressLabel = nil
        Task { await enhancer.checkHealth() }

        let asset = AVURLAsset(url: localURL)
        if let duration = try? await asset.load(.duration), CMTimeGetSeconds(duration) > 0 {
            project.duration = CMTimeGetSeconds(duration)
        } else {
            let fallback = CMTimeGetSeconds(asset.duration)
            project.duration = fallback.isFinite && fallback > 0 ? fallback : 0
        }
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            let natural = (try? await track.load(.naturalSize)) ?? .zero
            let transform = (try? await track.load(.preferredTransform)) ?? .identity
            let oriented = VideoExportService.orientedSizePublic(natural, transform: transform)
            project.sourceSize = oriented
            // Pack aspect wins when a Shorts Pack is selected; otherwise infer from source.
            if selectedPack == nil {
                project.aspectRatio = AspectRatioPreset.inferred(from: oriented)
            }
        }
        project.chunkCount = VideoChunkPlanner.chunks(duration: project.duration).count
        // Persist language on the project (B3 language lock).
        project.language = language
        trimSuggestions = []
        selectedTrimIDs = []
        refreshWatermarkOverlay()

        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        currentTime = 0
        isPlaying = false

        attachPlaybackObservers(to: newPlayer, item: item)
        resetTimelineSFXTracking(at: 0)
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

        // Telugu always needs Whisper — prompt for the key before starting.
        if language == .telugu, !apiKeys.hasOpenAIKey {
            errorMessage = "Add your OpenAI API key to caption Telugu (Apple has no Telugu Dictation)."
            showOpenAIKeySheet = true
            return
        }

        registerUndoCheckpoint()
        isTranscribing = true
        errorMessage = nil
        defer { isTranscribing = false }

        // Re-measure duration before ASR — a 0/stale project.duration packs captions too fast.
        if let measured = try? await AVURLAsset(url: url).load(.duration) {
            let seconds = CMTimeGetSeconds(measured)
            if seconds.isFinite, seconds > 0.2 {
                project.duration = max(project.duration, seconds)
            }
        }

        transcription.language = language
        transcription.openAIAPIKey = apiKeys.trimmedOpenAIKey
        // Floor ASR timing to the imported video length (avoids short/0 asset duration).
        transcription.knownTimelineDuration = max(project.duration, resolvedTimelineDuration())
        // Latin presets (Avenir/Georgia) cannot render Telugu/Hindi glyphs — looks like
        // "broken captions" even when ASR is fine. Lock script font + leave case as-is.
        applyLanguageCaptionDefaults()
        do {
            // Never demo-fallback for TE/HI — surface Whisper key / API errors clearly.
            let useDemo = language == .english
            let captions = try await transcription.transcribe(videoURL: url, useDemoFallback: useDemo)
            project.captions = captions
            // Keep project duration ≥ caption span / measured video (playback scrubber sync).
            if let lastEnd = captions.last?.endTime, lastEnd > project.duration {
                project.duration = lastEnd
            }
            selectedCaptionID = captions.first?.id
            // Surface ASR status (incl. locale pack warnings) in the editor chrome.
            if !transcription.statusMessage.isEmpty {
                lastEnhancementNote = transcription.statusMessage
                // Make missing Telugu/Hindi speech packs obvious in the UI.
                if transcription.statusMessage.localizedCaseInsensitiveContains("unavailable")
                    || transcription.statusMessage.localizedCaseInsensitiveContains("demo")
                    || transcription.statusMessage.localizedCaseInsensitiveContains("install") {
                    errorMessage = transcription.statusMessage
                }
            }
            editorTab = .captions
            refreshTrimSuggestions()
        } catch {
            let message = error.localizedDescription
            errorMessage = message
            if message.localizedCaseInsensitiveContains("API key")
                || message.localizedCaseInsensitiveContains("OpenAI") {
                showOpenAIKeySheet = true
            }
        }
    }

    /// Match caption style font/casing to the active language script.
    func applyLanguageCaptionDefaults() {
        project.captionStyle.fontName = language.captionFontName
        // UPPER/lower transforms are Latin-centric and wreck mixed TE/HI lines.
        if language != .english {
            project.captionStyle.textCase = .asIs
        }
    }

    /// Ask Cursor SDK where to place assets — long videos are enhanced part-by-part then merged.
    func enhanceWithCursorSDK() async {
        guard !project.captions.isEmpty else {
            errorMessage = "Generate captions first so the agent knows where to place assets."
            return
        }
        isEnhancing = true
        errorMessage = nil
        chunkProgressLabel = nil
        defer {
            isEnhancing = false
            chunkProgressLabel = nil
        }

        await enhancer.checkHealth()
        let timelineDuration = resolvedTimelineDuration()
        if timelineDuration > project.duration {
            project.duration = timelineDuration
        }
        let chunks = VideoChunkPlanner.chunks(duration: project.duration)
        project.chunkCount = chunks.count
        let canvas = project.aspectRatio.canvasSize

        var merged: [EnhancementPlacement] = []
        var notes: [String] = []
        var latestDistribution: DistributionPackage?

        for chunk in chunks {
            chunkProgressLabel = chunks.count == 1
                ? "Placing on \(project.aspectRatio.rawValue)…"
                : "Part \(chunk.index + 1)/\(chunks.count) (\(formatClock(chunk.startTime))–\(formatClock(chunk.endTime)))"

            let sliceCaptions = VideoChunkPlanner.captions(
                project.captions,
                overlapping: chunk,
                useContext: true
            )
            guard !sliceCaptions.isEmpty || chunks.count == 1 else { continue }

            let packId = project.packId
            let zone = activeSafeZone
            // Always pass a positive duration derived from captions when needed —
            // enhancer used to coerce 0 → 10s and clamp all hits into the first 10s.
            let enhanceDuration = max(project.duration, chunk.contextEnd, resolvedTimelineDuration())
            let plan: EnhancementPlan
            if enhancer.isHealthy {
                do {
                    plan = try await enhancer.enhance(
                        captions: sliceCaptions.isEmpty ? project.captions : sliceCaptions,
                        duration: enhanceDuration,
                        videoSize: canvas,
                        language: language,
                        packId: packId,
                        brandKit: brandKit.kit,
                        safeZone: zone,
                        forceHeuristic: false
                    )
                } catch {
                    plan = enhancer.localHeuristicPlan(
                        captions: sliceCaptions.isEmpty ? project.captions : sliceCaptions,
                        duration: enhanceDuration,
                        libraries: libraries,
                        language: language,
                        pack: selectedPack,
                        safeZone: zone
                    )
                    notes.append(error.localizedDescription)
                }
            } else {
                plan = enhancer.localHeuristicPlan(
                    captions: sliceCaptions.isEmpty ? project.captions : sliceCaptions,
                    duration: enhanceDuration,
                    libraries: libraries,
                    language: language,
                    pack: selectedPack,
                    safeZone: zone
                )
            }

            let absolute = VideoChunkPlanner.absolutize(placements: plan.allEdits, chunk: chunk)
            merged.append(contentsOf: absolute)
            if let note = plan.note { notes.append("p\(chunk.index + 1): \(note)") }
            if latestDistribution == nil {
                latestDistribution = plan.distribution
            }
        }

        // Deduplicate near-identical placements at chunk boundaries.
        merged = Self.dedupe(placements: merged)

        var wordHits = merged.filter { $0.kind == "wordHit" }
        let others = merged.filter { $0.kind != "wordHit" }
        // Defense in depth: fill any caption windows still missing hits (full timeline).
        let filled = appendMissingWordHits(
            wordHits: &wordHits,
            captions: project.captions,
            duration: project.duration
        )
        if filled > 0 {
            notes.append("Filled \(filled) word hit(s) for full-duration coverage")
        }

        let packLabel = selectedPack.map { " / pack:\($0.name)" } ?? ""
        let plan = EnhancementPlan(
            summary: chunks.count == 1
                ? "Word hits + placements for \(language.title) / \(project.aspectRatio.rawValue)\(packLabel)."
                : "Merged \(wordHits.count) word hits across \(chunks.count) parts (\(language.title)\(packLabel)).",
            placements: others,
            wordHits: wordHits,
            packId: project.packId,
            distribution: latestDistribution ?? DistributionPackage.heuristic(
                captions: project.captions,
                language: language,
                packName: selectedPack?.name
            ),
            safeZone: activeSafeZone,
            source: enhancer.isHealthy ? "cursor-sdk-chunked" : "local-chunked",
            model: enhancer.usesCursorKey ? "composer-2.5" : nil,
            note: notes.last ?? "Enhanced in \(chunks.count) part(s)",
            language: language.localeIdentifier
        )
        apply(plan: plan)
        lastEnhancementNote = plan.summary
        editorTab = .libraries
    }

    /// Prefer measured video duration; never leave 0 when captions already span the timeline.
    private func resolvedTimelineDuration() -> TimeInterval {
        let fromCaptions = project.captions.map(\.endTime).max() ?? 0
        let fromProject = project.duration
        if fromProject > 0.05 { return max(fromProject, fromCaptions) }
        if fromCaptions > 0.05 { return fromCaptions }
        return fromProject
    }

    /// Sparse full-duration fill — every other empty caption only (avoids wall-of-hits).
    private func appendMissingWordHits(
        wordHits: inout [EnhancementPlacement],
        captions: [CaptionSegment],
        duration: TimeInterval
    ) -> Int {
        let missing = captions.enumerated().compactMap { index, cap -> CaptionSegment? in
            // Keep density low: only consider even-index caption windows.
            guard index % 2 == 0 else { return nil }
            let hasHit = wordHits.contains {
                $0.startTime >= cap.startTime - 0.05 && $0.startTime <= cap.endTime + 0.05
            }
            return hasHit ? nil : cap
        }
        guard !missing.isEmpty else { return 0 }

        let fill = enhancer.localHeuristicPlan(
            captions: missing,
            duration: max(duration, missing.map(\.endTime).max() ?? duration),
            libraries: libraries,
            language: language,
            pack: selectedPack,
            safeZone: activeSafeZone
        )
        let extras = fill.wordHits ?? []
        wordHits.append(contentsOf: extras)
        return extras.count
    }

    /// Pick a Shorts Pack — sets aspect, caption style, and packId for enhance.
    func selectPack(_ packId: String?) {
        project.packId = packId
        if let pack = packs.pack(id: packId) {
            applyPackSideEffects(pack)
        }
    }

    private func applyPackSideEffects(_ pack: ShortsPack) {
        setAspectRatio(pack.aspectPreset)
        applyPreset(pack.captionPreset)
        refreshWatermarkOverlay()
    }

    func applyBrandKitToProject() {
        language = brandKit.kit.appLanguage
        if let packId = brandKit.kit.defaultPackId, packs.pack(id: packId) != nil {
            selectPack(packId)
        }
        refreshWatermarkOverlay()
    }

    func refreshWatermarkOverlay() {
        project.overlays.removeAll { $0.kind == .watermark }
        let kit = brandKit.kit
        guard kit.watermarkEnabled, !kit.watermarkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let mark = OverlayItem(
            kind: .watermark,
            text: kit.watermarkText,
            x: kit.watermarkX,
            y: kit.watermarkY,
            scale: 1,
            rotation: 0,
            startTime: 0,
            endTime: max(project.duration, 0.1),
            color: kit.primarySwiftUIColor.codable,
            fontSize: 18,
            shape: .rectangle,
            opacity: 0.85,
            reason: "Brand kit watermark"
        )
        project.overlays.append(mark)
    }

    // MARK: - Projects (JSON save / load)

    /// Snapshot of playhead, tab, and selections for `project.json`.
    func currentSessionState() -> ProjectSessionState {
        ProjectSessionState(
            playheadTime: currentTime,
            editorTab: editorTab.rawValue,
            selectedCaptionID: selectedCaptionID,
            selectedOverlayID: selectedOverlayID,
            selectedSoundEffectID: selectedSoundEffectID,
            isAudioLayerSelected: isAudioLayerSelected,
            showSafeZone: showSafeZone,
            libraryKind: libraryKind.rawValue
        )
    }

    @discardableResult
    func saveDraft() throws -> SavedProject {
        project.language = language
        let saved = try projectStore.save(
            project: project,
            session: currentSessionState(),
            distribution: distribution
        )
        // Point at the durable project copy so later saves are stable.
        project.videoURL = try projectStore.load(id: saved.id).1
        project.id = saved.id
        draftMessage = "Saved “\(saved.title)” at \(saved.resumeClock)"
        return saved
    }

    /// Alias — projects are JSON packages with media references.
    @discardableResult
    func saveProject() throws -> SavedProject {
        try saveDraft()
    }

    func openDraft(_ saved: SavedProject) async {
        do {
            let (draft, videoURL) = try projectStore.load(id: saved.id)
            tearDownPlayer()
            project = draft.toProject(videoURL: videoURL)
            language = draft.language
            normalizeLoudness = project.audio.normalizeLoudness
            selectedPreset = packs.pack(id: draft.packId)?.captionPreset ?? selectedPreset
            lastEnhancementNote = draft.enhancementSummary
            distribution = draft.distribution
            refreshTrimSuggestions()
            refreshWatermarkOverlay()

            let asset = AVURLAsset(url: videoURL)
            let item = AVPlayerItem(asset: asset)
            let newPlayer = AVPlayer(playerItem: item)
            player = newPlayer
            isPlaying = false

            attachPlaybackObservers(to: newPlayer, item: item)

            // Resume exactly where the project was left.
            applySession(draft.session, project: project)
            resetTimelineSFXTracking(at: currentTime)
            draftMessage = "Opened “\(draft.title)” · resume \(draft.resumeClock)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Restore playhead, tab, and selections from `project.json` session.
    private func applySession(_ session: ProjectSessionState, project: VideoProject) {
        if let tab = EditorTab(rawValue: session.editorTab) {
            editorTab = tab
        }
        showSafeZone = session.showSafeZone
        if let kindRaw = session.libraryKind,
           let kind = MediaLibraryKind(rawValue: kindRaw) {
            libraryKind = kind
        }

        selectedCaptionID = session.selectedCaptionID.flatMap { id in
            project.captions.contains(where: { $0.id == id }) ? id : nil
        }
        selectedOverlayID = session.selectedOverlayID.flatMap { id in
            project.overlays.contains(where: { $0.id == id }) ? id : nil
        }
        selectedSoundEffectID = session.selectedSoundEffectID.flatMap { id in
            project.soundEffects.contains(where: { $0.id == id }) ? id : nil
        }
        isAudioLayerSelected = session.isAudioLayerSelected
            && selectedOverlayID == nil
            && selectedSoundEffectID == nil

        let t = min(max(0, session.playheadTime), max(0, project.duration))
        currentTime = t
        seek(to: t)
    }

    func deleteDraft(_ id: UUID) {
        do {
            try projectStore.delete(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Export a portable `.captionstudio` folder (project.json + video) for sharing/backup.
    func exportProjectPackage(to directory: URL) throws -> URL {
        _ = try saveProject()
        return try projectStore.exportPackage(id: project.id, to: directory)
    }

    /// Import a `.captionstudio` package and open it at the saved playhead.
    func importProjectPackage(from packageURL: URL) async {
        do {
            let saved = try projectStore.importPackage(from: packageURL)
            await openDraft(saved)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func leaveWithoutSaving() {
        tearDownPlayer()
        history.clear()
        publishHistoryFlags()
        let packId = project.packId
        project = .empty()
        project.packId = packId
        project.audio.sfxMasterGain = brandKit.kit.defaultSfxGain
        normalizeLoudness = project.audio.normalizeLoudness
        isAudioLayerSelected = false
        selectedSoundEffectID = nil
        selectedOverlayID = nil
        selectedCaptionID = nil
        distribution = nil
        editorTab = .captions
        currentTime = 0
        if let pack = selectedPack {
            applyPackSideEffects(pack)
        }
        language = brandKit.kit.appLanguage
        trimSuggestions = []
        selectedTrimIDs = []
        draftMessage = nil
    }

    // MARK: - Trim assist

    func refreshTrimSuggestions() {
        let suggestions = TrimService.suggestions(
            captions: project.captions,
            duration: project.duration,
            language: language
        )
        trimSuggestions = suggestions
        selectedTrimIDs = Set(suggestions.map(\.id))
    }

    func toggleTrimSuggestion(_ id: UUID) {
        if selectedTrimIDs.contains(id) {
            selectedTrimIDs.remove(id)
        } else {
            selectedTrimIDs.insert(id)
        }
    }

    func applySelectedTrims() async {
        guard let url = project.videoURL else {
            errorMessage = "Import a video first."
            return
        }
        let cuts = selectedTrimSuggestions
        guard !cuts.isEmpty else {
            errorMessage = "Select at least one trim suggestion."
            return
        }

        registerUndoCheckpoint()
        isTrimming = true
        chunkProgressLabel = "Applying trims…"
        defer {
            isTrimming = false
            chunkProgressLabel = nil
        }

        let keeps = TrimService.keepRanges(duration: project.duration, removing: cuts)
        guard !keeps.isEmpty else {
            errorMessage = "Trim would remove the entire video."
            return
        }

        do {
            let trimmedURL = try await VideoTrimComposer.writeTrimmedVideo(
                sourceURL: url,
                keepRanges: keeps
            )
            project.captions = TrimService.shiftCaptions(project.captions, through: keeps)
            project.overlays = TrimService.shiftOverlays(project.overlays, through: keeps)
            project.soundEffects = TrimService.shiftSFX(project.soundEffects, through: keeps)
            project.duration = TrimService.trimmedDuration(keeps: keeps)
            project.chunkCount = VideoChunkPlanner.chunks(duration: project.duration).count
            refreshWatermarkOverlay()

            // Reload player on trimmed media
            tearDownPlayer()
            project.videoURL = trimmedURL
            let asset = AVURLAsset(url: trimmedURL)
            let item = AVPlayerItem(asset: asset)
            let newPlayer = AVPlayer(playerItem: item)
            player = newPlayer
            currentTime = 0
            isPlaying = false
            attachPlaybackObservers(to: newPlayer, item: item)
            resetTimelineSFXTracking(at: 0)

            refreshTrimSuggestions()
            draftMessage = "Applied \(cuts.count) trim(s) — \(String(format: "%.1fs", project.duration))"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func dedupe(placements: [EnhancementPlacement]) -> [EnhancementPlacement] {
        var kept: [EnhancementPlacement] = []
        for p in placements.sorted(by: { $0.startTime < $1.startTime }) {
            let duplicate = kept.contains {
                $0.kind == p.kind
                    && $0.assetId == p.assetId
                    && abs($0.startTime - p.startTime) < 0.12
                    && abs($0.x - p.x) < 0.05
                    && abs($0.y - p.y) < 0.05
            }
            if !duplicate { kept.append(p) }
        }
        return kept
    }

    private func formatClock(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }

    func setAspectRatio(_ aspect: AspectRatioPreset) {
        let from = project.aspectRatio
        guard from != aspect else { return }
        registerUndoCheckpoint()
        project.overlays = AspectOverlayRemapper.remapOverlays(
            project.overlays,
            from: from,
            to: aspect
        )
        if var chess = project.chessOverlay {
            chess.layout = AspectOverlayRemapper.remapChessLayout(
                chess.layout,
                from: from,
                to: aspect
            )
            project.chessOverlay = chess
        }
        project.aspectRatio = aspect
    }

    func apply(plan: EnhancementPlan) {
        registerUndoCheckpoint()
        var newOverlays: [OverlayItem] = []
        var newSFX: [SoundEffectCue] = []
        // Throttle audio so hits don't fire a whoosh on every punch.
        var standaloneSFXIndex = 0
        var wordHitSFXIndex = 0
        let wordHitSfxEvery = selectedPack?.gifDensity == "high" ? 2 : 3

        for placement in plan.allEdits {
            switch placement.kind {
            case "text":
                if let item = makeStylishText(from: placement) {
                    newOverlays.append(item)
                }
            case "gif":
                if let item = makeImageOverlay(from: placement, kind: .gif, library: .gifs) {
                    newOverlays.append(item)
                }
            case "png":
                if let item = makeImageOverlay(from: placement, kind: .png, library: .pngs) {
                    newOverlays.append(item)
                }
            case "sfx":
                if standaloneSFXIndex % 2 == 0, let cue = makeSFX(from: placement) {
                    newSFX.append(cue)
                }
                standaloneSFXIndex += 1
            case "wordHit":
                if let item = makeWordHit(from: placement) {
                    newOverlays.append(item)
                }
                if wordHitSFXIndex % wordHitSfxEvery == 0, let cue = makeWordHitSFX(from: placement) {
                    newSFX.append(cue)
                }
                wordHitSFXIndex += 1
            default:
                continue
            }
        }

        let manual = project.overlays.filter {
            $0.assetId == nil && $0.styleAssetId == nil && $0.fontId == nil
                && ($0.kind == .emoji || $0.kind == .shape || $0.kind == .watermark)
        }
        project.overlays = manual + newOverlays
        project.soundEffects = newSFX
        project.enhancementSummary = plan.summary
        if let packId = plan.packId, project.packId == nil {
            project.packId = packId
        }
        distribution = plan.distribution ?? DistributionPackage.heuristic(
            captions: project.captions,
            language: language,
            packName: selectedPack?.name
        )
        refreshWatermarkOverlay()
        let hitCount = plan.wordHits?.count ?? newOverlays.filter { $0.kind == .wordHit }.count
        lastEnhancementNote = plan.note
            ?? "Applied \(hitCount) word hits + \(newOverlays.count) overlays + \(newSFX.count) SFX"
        if let first = newOverlays.first {
            selectedOverlayID = first.id
            seek(to: first.startTime)
        }
    }

    private func makeWordHit(from placement: EnhancementPlacement) -> OverlayItem? {
        let fontId = placement.fontId ?? placement.assetId
        let font = libraries.item(kind: .fonts, id: fontId)
            ?? libraries.items(for: .fonts).first { $0.scripts?.contains(where: { language.scriptTags.contains($0) }) == true }
        guard let font else { return nil }
        let effectId = placement.effectId ?? WordHitEffect.random().rawValue
        let effect = WordHitEffect(rawValue: effectId)
        let effectColors = libraries.item(kind: .effects, id: effectId)?.colors
        var primaryHex = placement.color
            ?? effectColors?.first
            ?? "#FFEF5A"
        // Never settle on pure white — reads as "caption duplicate" next to yellow hits.
        if primaryHex.uppercased() == "#FFFFFF" || primaryHex.uppercased() == "#FFF" {
            primaryHex = "#FFEF5A"
        }
        let color = Color(hex: primaryHex) ?? (effect?.palette.first ?? Color(red: 1, green: 0.94, blue: 0.35))
        let scale = min(1.45, max(0.9, placement.scale == 0 ? 1.2 : placement.scale))
        // Estimate glyph box so the whole word stays inside the safe / mid band.
        let approxChars = max(1, CGFloat(placement.displayText.count))
        let halfW = min(0.28, 0.06 * scale * approxChars)
        let halfH = min(0.1, 0.055 * scale)
        let zone = activeSafeZone
        let yMaxHit = min(zone.yMax, 0.58)
        let yMinHit = max(zone.yMin, 0.14)
        var cx = min(zone.xMax - halfW, max(zone.xMin + halfW, placement.x))
        var cy = min(yMaxHit - halfH, max(yMinHit + halfH, placement.y))
        (cx, cy) = SafeZone(xMin: zone.xMin, xMax: zone.xMax, yMin: yMinHit, yMax: yMaxHit).clamp(x: cx, y: cy)
        let start = max(0, placement.startTime)
        // Estimated ASR clocks are short — hold punch words long enough to read with speech.
        let requested = placement.lengthSeconds ?? 2.0
        let minHold = max(1.6, min(2.8, requested))
        let end = max(start + minHold, placement.endTime)
        return OverlayItem(
            kind: .wordHit,
            text: placement.displayText.isEmpty ? (font.previewText ?? "!") : placement.displayText,
            assetId: font.id,
            assetFileName: nil,
            styleAssetId: nil,
            fontId: font.id,
            fontName: font.fontName,
            effectId: effectId,
            sfxId: placement.sfxId,
            x: cx,
            y: cy,
            scale: scale,
            rotation: min(8, max(-8, placement.rotation)),
            startTime: start,
            endTime: end,
            color: color.codable,
            fontSize: 44,
            shape: .rectangle,
            opacity: 1,
            reason: placement.reason,
            captionIndex: placement.captionIndex,
            wordIndex: placement.wordIndex
        )
    }

    private func makeWordHitSFX(from placement: EnhancementPlacement) -> SoundEffectCue? {
        guard let sfxId = placement.sfxId,
              libraries.item(kind: .sfx, id: sfxId) != nil
        else { return nil }
        return SoundEffectCue(
            assetId: sfxId,
            startTime: placement.startTime,
            gain: min(0.75, libraries.item(kind: .sfx, id: sfxId)?.defaultGain ?? 0.7),
            reason: "Word hit SFX for \(placement.text ?? "")"
        )
    }

    private func makeStylishText(from placement: EnhancementPlacement) -> OverlayItem? {
        guard let style = libraries.item(kind: .textStyles, id: placement.assetId) else { return nil }
        let aligned = PlacementAligner.align(
            placement,
            asset: style,
            kind: "text",
            captions: project.captions,
            videoDuration: project.duration,
            safeZone: activeSafeZone
        )
        let color = Color(hex: style.textColor ?? "#FFFFFF") ?? .white
        return OverlayItem(
            kind: .text,
            text: placement.text ?? style.previewText ?? "Look",
            assetId: nil,
            assetFileName: nil,
            styleAssetId: style.id,
            fontName: style.fontName,
            x: aligned.x,
            y: aligned.y,
            scale: placement.scale,
            rotation: placement.rotation,
            startTime: aligned.start,
            endTime: aligned.end,
            color: color.codable,
            fontSize: style.fontSize ?? 34,
            shape: .rectangle,
            opacity: 1,
            reason: placement.reason ?? "hold \(String(format: "%.2fs", style.playLength))"
        )
    }

    private func makeImageOverlay(
        from placement: EnhancementPlacement,
        kind: OverlayKind,
        library: MediaLibraryKind
    ) -> OverlayItem? {
        guard let asset = libraries.item(kind: library, id: placement.assetId),
              let file = asset.file
        else { return nil }
        let aligned = PlacementAligner.align(
            placement,
            asset: asset,
            kind: kind == .gif ? "gif" : "png",
            captions: project.captions,
            videoDuration: project.duration,
            safeZone: activeSafeZone
        )
        return OverlayItem(
            kind: kind,
            text: asset.name,
            assetId: asset.id,
            assetFileName: file,
            styleAssetId: nil,
            x: aligned.x,
            y: aligned.y,
            scale: placement.scale,
            rotation: placement.rotation,
            startTime: aligned.start,
            endTime: aligned.end,
            color: .whiteColor,
            fontSize: 24,
            shape: .rectangle,
            opacity: 1,
            reason: placement.reason
                ?? "\(Int(asset.pixelSize.width))×\(Int(asset.pixelSize.height)), \(String(format: "%.2fs", asset.playLength))"
        )
    }

    private func makeSFX(from placement: EnhancementPlacement) -> SoundEffectCue? {
        guard let asset = libraries.item(kind: .sfx, id: placement.assetId) else { return nil }
        let aligned = PlacementAligner.align(
            placement,
            asset: asset,
            kind: "sfx",
            captions: project.captions,
            videoDuration: project.duration,
            safeZone: activeSafeZone
        )
        return SoundEffectCue(
            assetId: asset.id,
            startTime: aligned.start,
            gain: asset.defaultGain ?? 0.8,
            reason: placement.reason ?? "length \(String(format: "%.2fs", asset.playLength))"
        )
    }

    func addLibraryItem(_ item: MediaLibraryItem, kind: MediaLibraryKind) {
        registerUndoCheckpoint()
        switch kind {
        case .textStyles:
            let placement = EnhancementPlacement(
                kind: "text",
                assetId: item.id,
                startTime: currentTime,
                endTime: currentTime + item.playLength,
                x: 0.5,
                y: 0.3,
                scale: 1,
                rotation: 0,
                text: item.previewText,
                reason: "Manual · \(String(format: "%.2fs", item.playLength))",
                lengthSeconds: item.playLength
            )
            if let overlay = makeStylishText(from: placement) {
                project.overlays.append(overlay)
                selectedOverlayID = overlay.id
            }
        case .gifs, .pngs:
            let placement = EnhancementPlacement(
                kind: kind == .gifs ? "gif" : "png",
                assetId: item.id,
                startTime: currentTime,
                endTime: currentTime + item.playLength,
                x: 0.75,
                y: 0.25,
                scale: item.defaultScale ?? 1,
                rotation: 0,
                reason: "Manual · \(Int(item.pixelSize.width))×\(Int(item.pixelSize.height)) · \(String(format: "%.2fs", item.playLength))",
                lengthSeconds: item.playLength
            )
            if let overlay = makeImageOverlay(
                from: placement,
                kind: kind == .gifs ? .gif : .png,
                library: kind
            ) {
                project.overlays.append(overlay)
                selectedOverlayID = overlay.id
            }
        case .sfx:
            let cue = SoundEffectCue(
                assetId: item.id,
                startTime: currentTime,
                gain: item.defaultGain ?? 0.8,
                reason: "Manual · exact \(String(format: "%.2fs", item.playLength))"
            )
            project.soundEffects.append(cue)
            previewSFX(cue)
        case .fonts, .effects:
            break
        }
        editorTab = .overlays
    }

    func previewSFX(_ cue: SoundEffectCue) {
        guard !cue.isMuted else { return }
        guard let asset = libraries.item(kind: .sfx, id: cue.assetId) else { return }
        // Prefer WAV — AVAudioPlayer on macOS is more reliable with PCM than AAC/m4a.
        let fileName = asset.wav ?? asset.file
        guard let fileName,
              let url = libraries.fileURL(kind: .sfx, fileName: fileName)
        else { return }
        Self.activatePlaybackAudioSessionIfNeeded()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = Float(min(1.4, max(0.05, cue.gain * project.audio.sfxMasterGain)))
            player.prepareToPlay()
            let started = player.play()
            guard started else {
                errorMessage = "Could not start SFX playback."
                return
            }
            // Keep a strong reference. Do NOT filter by isPlaying on the same turn —
            // macOS often reports isPlaying=false for a few ms after play(), which
            // would deallocate the player and produce silence.
            sfxPlayers.append(player)
            pruneFinishedSFXPlayers(keeping: player)
            if project.audio.duckDialogueUnderSFX {
                previewDuckUntil = TimelineSFXPreview.extendDuck(
                    currentUntil: previewDuckUntil,
                    fireTime: currentTime,
                    cueLength: asset.playLength
                )
                refreshPreviewDialogueVolume()
            }
        } catch {
            errorMessage = "Could not play SFX: \(error.localizedDescription)"
        }
    }

    // MARK: - Playback observers / timeline SFX

    private func attachPlaybackObservers(to newPlayer: AVPlayer, item: AVPlayerItem) {
        if let timeObserver {
            player?.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }

        refreshPreviewDialogueVolume(on: newPlayer)

        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        // Callback already runs on the main queue — update synchronously so
        // timeline SFX crossing detection sees ordered samples (no Task hop).
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = CMTimeGetSeconds(time)
            guard let self else { return }
            MainActor.assumeIsolated {
                self.currentTime = seconds
                self.syncTimelineSFX(at: seconds)
                self.refreshPreviewDialogueVolume()
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.isPlaying = false
                self.stopPreviewSFXPlayers()
                self.previewDuckUntil = nil
                self.refreshPreviewDialogueVolume()
                self.seek(to: 0)
            }
        }
    }

    /// Mark cues at/before `time` as already fired so resume/seek doesn't replay the past.
    private func resetTimelineSFXTracking(at time: TimeInterval) {
        lastSFXCheckTime = time
        triggeredSFXIds = Set(
            project.soundEffects
                .filter { $0.startTime <= time + 0.001 }
                .map(\.id)
        )
        stopPreviewSFXPlayers()
        previewDuckUntil = nil
        refreshPreviewDialogueVolume()
    }

    /// On play, allow cues in a small look-back window so a cue at the resume
    /// playhead still fires once (seek alone must not auto-play SFX).
    private func prepareTimelineSFXForPlayback(at time: TimeInterval) {
        let lookback = TimelineSFXPreview.playbackLookback
        lastSFXCheckTime = time - lookback
        triggeredSFXIds = Set(
            project.soundEffects
                .filter { $0.startTime < time - lookback }
                .map(\.id)
        )
        stopPreviewSFXPlayers()
        previewDuckUntil = nil
        refreshPreviewDialogueVolume()
    }

    private func stopPreviewSFXPlayers() {
        for player in sfxPlayers { player.stop() }
        sfxPlayers = []
    }

    private func pruneFinishedSFXPlayers(keeping newest: AVAudioPlayer? = nil) {
        sfxPlayers = sfxPlayers.filter { player in
            if let newest, player === newest { return true }
            return player.isPlaying
        }
        // Cap retained finished players to avoid unbounded growth if isPlaying flakes.
        if sfxPlayers.count > 24 {
            sfxPlayers.removeFirst(sfxPlayers.count - 24)
        }
    }

    /// Fire one-shot SFX when the playhead crosses each cue's startTime during playback.
    private func syncTimelineSFX(at time: TimeInterval) {
        guard isPlaying, previewSFXDuringPlayback else {
            lastSFXCheckTime = time
            return
        }

        pruneFinishedSFXPlayers()

        let from = lastSFXCheckTime
        if time < from - 0.02 {
            // Scrubbed backwards while playing — allow future cues to fire again.
            triggeredSFXIds = Set(
                project.soundEffects
                    .filter { $0.startTime <= time + 0.001 }
                    .map(\.id)
            )
        }

        let cueTuples = project.soundEffects.map {
            (id: $0.id, startTime: $0.startTime, isMuted: $0.isMuted)
        }
        let ids = TimelineSFXPreview.cuesToTrigger(
            cues: cueTuples,
            from: from,
            to: time,
            alreadyTriggered: triggeredSFXIds
        )
        lastSFXCheckTime = time

        for id in ids {
            guard let cue = project.soundEffects.first(where: { $0.id == id }) else { continue }
            triggeredSFXIds.insert(id)
            previewSFX(cue)
        }
    }

    private func refreshPreviewDialogueVolume(on overridePlayer: AVPlayer? = nil) {
        let target = overridePlayer ?? player
        guard let target else { return }
        if let until = previewDuckUntil, currentTime >= until {
            previewDuckUntil = nil
        }
        target.volume = TimelineSFXPreview.dialogueVolume(
            baseGain: project.audio.dialogueGain,
            duckEnabled: project.audio.duckDialogueUnderSFX && isPlaying,
            duckAmount: project.audio.duckAmount,
            now: currentTime,
            duckUntil: previewDuckUntil
        )
    }

    private static func activatePlaybackAudioSessionIfNeeded() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
    }

    func libraryFileURL(for overlay: OverlayItem) -> URL? {
        guard let file = overlay.assetFileName else { return nil }
        let kind: MediaLibraryKind = overlay.kind == .gif ? .gifs : .pngs
        return libraries.fileURL(kind: kind, fileName: file)
    }

    func stylishTextStyle(for overlay: OverlayItem) -> MediaLibraryItem? {
        guard let id = overlay.styleAssetId else { return nil }
        return libraries.item(kind: .textStyles, id: id)
    }

    // MARK: - Playback

    func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            pausePlayback()
        } else {
            if currentTime >= project.duration - 0.05 {
                seek(to: 0)
            }
            applyPlaybackRate(1)
        }
    }

    /// Pause and clear shuttle rate (K / Space while playing).
    func pausePlayback() {
        guard let player else { return }
        player.pause()
        player.rate = 0
        isPlaying = false
        stopPreviewSFXPlayers()
        previewDuckUntil = nil
        refreshPreviewDialogueVolume()
    }

    /// Apply AVPlayer rate for J/K/L shuttle (negative = reverse when the asset allows).
    func applyPlaybackRate(_ rate: Float) {
        guard let player else { return }
        if abs(rate) < 0.01 {
            pausePlayback()
            return
        }
        if currentTime >= project.duration - 0.05, rate > 0 {
            seek(to: 0)
        }
        prepareTimelineSFXForPlayback(at: currentTime)
        isPlaying = true
        Self.activatePlaybackAudioSessionIfNeeded()
        refreshPreviewDialogueVolume()
        player.rate = rate
    }

    /// J / L shuttle bump. `forward` true = L, false = J.
    func bumpPlaybackJKL(forward: Bool) {
        guard player != nil else { return }
        let current = player?.rate ?? 0
        let next = EditorShortcuts.nextRate(current: current, forward: forward)
        applyPlaybackRate(next)
    }

    func seek(to time: TimeInterval) {
        let cm = CMTime(seconds: max(0, time), preferredTimescale: 600)
        player?.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = max(0, time)
        resetTimelineSFXTracking(at: currentTime)
    }

    /// Nudge selected timeline clips, or step the playhead when nothing is selected.
    @discardableResult
    func nudgeSelectionOrPlayhead(delta: TimeInterval) -> Bool {
        let refs = timelineKeyboardSelectionRefs()
        if !refs.isEmpty {
            applyTimelineMultiRetime(refs: refs, delta: delta, seekToSelection: false)
            return true
        }
        seek(to: min(max(0, currentTime + delta), max(project.duration, 0)))
        return true
    }

    /// Delete all currently selected captions / overlays / SFX (one undo step).
    @discardableResult
    func deleteTimelineSelection() -> Bool {
        var captionIDs = selectedCaptionIDs
        if let id = selectedCaptionID { captionIDs.insert(id) }
        var overlayIDs = selectedOverlayIDs
        if let id = selectedOverlayID { overlayIDs.insert(id) }
        var sfxIDs = selectedSoundEffectIDs
        if let id = selectedSoundEffectID { sfxIDs.insert(id) }

        guard !captionIDs.isEmpty || !overlayIDs.isEmpty || !sfxIDs.isEmpty else { return false }

        registerUndoCheckpoint()
        if !captionIDs.isEmpty {
            project.captions.removeAll { captionIDs.contains($0.id) }
        }
        if !overlayIDs.isEmpty {
            project.overlays.removeAll { overlayIDs.contains($0.id) }
        }
        if !sfxIDs.isEmpty {
            project.soundEffects.removeAll { sfxIDs.contains($0.id) }
        }
        selectedCaptionID = nil
        selectedOverlayID = nil
        selectedSoundEffectID = nil
        clearTimelineMultiSelection()
        return true
    }

    private func timelineKeyboardSelectionRefs() -> [TimelineClipRef] {
        var refs: [TimelineClipRef] = []
        var captionIDs = selectedCaptionIDs
        if let id = selectedCaptionID { captionIDs.insert(id) }
        refs.append(contentsOf: captionIDs.map { .caption($0) })
        var overlayIDs = selectedOverlayIDs
        if let id = selectedOverlayID { overlayIDs.insert(id) }
        refs.append(contentsOf: overlayIDs.map { .overlay($0) })
        var sfxIDs = selectedSoundEffectIDs
        if let id = selectedSoundEffectID { sfxIDs.insert(id) }
        refs.append(contentsOf: sfxIDs.map { .sfx($0) })
        return refs
    }

    // MARK: - Captions / style

    func applyPreset(_ preset: CaptionPreset) {
        registerUndoCheckpoint()
        selectedPreset = preset
        project.captionStyle = preset.style
        // Presets ship with Latin fonts + UPPER case — re-apply script defaults for TE/HI.
        applyLanguageCaptionDefaults()
    }

    func updateCaption(_ caption: CaptionSegment) {
        registerUndoCheckpoint()
        guard let index = project.captions.firstIndex(where: { $0.id == caption.id }) else { return }
        project.captions[index] = caption
    }

    func deleteCaption(_ id: CaptionSegment.ID) {
        registerUndoCheckpoint()
        project.captions.removeAll { $0.id == id }
        if selectedCaptionID == id { selectedCaptionID = nil }
        selectedCaptionIDs.remove(id)
    }

    // MARK: - Overlays

    func addTextOverlay(_ text: String = "Your text") {
        registerUndoCheckpoint()
        let item = OverlayItem.textSticker(text, at: currentTime)
        project.overlays.append(item)
        selectedOverlayID = item.id
        selectedSoundEffectID = nil
        isAudioLayerSelected = false
        editorTab = .overlays
    }

    func addEmojiOverlay(_ emoji: String) {
        registerUndoCheckpoint()
        let item = OverlayItem.emoji(emoji, at: currentTime)
        project.overlays.append(item)
        selectedOverlayID = item.id
        selectedSoundEffectID = nil
        isAudioLayerSelected = false
    }

    func updateOverlay(_ item: OverlayItem) {
        registerUndoCheckpoint()
        guard let index = project.overlays.firstIndex(where: { $0.id == item.id }) else { return }
        project.overlays[index] = item
    }

    func deleteOverlay(_ id: OverlayItem.ID) {
        registerUndoCheckpoint()
        project.overlays.removeAll { $0.id == id }
        if selectedOverlayID == id { selectedOverlayID = nil }
        selectedOverlayIDs.remove(id)
    }

    /// Retiming + optional lane change from the zoomable timeline drag.
    func applyTimelineDrag(
        ref: TimelineClipRef,
        fromLane: TimelineLaneID,
        toLane: TimelineLaneID,
        start: TimeInterval,
        end: TimeInterval
    ) {
        registerUndoCheckpoint()
        let mediaEnd = max(project.duration, 0.1)
        let clampedStart = min(max(0, start), mediaEnd - 0.05)
        let clampedEnd = min(mediaEnd, max(clampedStart + 0.05, end))

        switch ref {
        case .caption(let id):
            applyCaptionTimelineDrag(
                id: id,
                toLane: toLane,
                start: clampedStart,
                end: clampedEnd
            )
        case .overlay(let id):
            applyOverlayTimelineDrag(
                id: id,
                toLane: toLane,
                start: clampedStart,
                end: clampedEnd
            )
        case .sfx(let id):
            guard toLane == .sfx || toLane == fromLane else { return }
            guard var cue = project.soundEffects.first(where: { $0.id == id }) else { return }
            cue.startTime = clampedStart
            updateSoundEffect(cue)
            selectSoundEffect(id)
            seek(to: clampedStart)
        case .trim(let id):
            guard toLane == .trim || toLane == fromLane else { return }
            guard let index = trimSuggestions.firstIndex(where: { $0.id == id }) else { return }
            let len = max(0.05, trimSuggestions[index].endTime - trimSuggestions[index].startTime)
            trimSuggestions[index].startTime = clampedStart
            trimSuggestions[index].endTime = min(mediaEnd, clampedStart + len)
            seek(to: clampedStart)
            editorTab = .trim
        case .audio:
            break
        }
    }

    /// Shift several same-kind clips by the same delta (multi-select drag). Lane stays put.
    func applyTimelineMultiRetime(refs: [TimelineClipRef], delta: TimeInterval, seekToSelection: Bool = true) {
        guard abs(delta) > 0.0005, !refs.isEmpty else { return }
        registerUndoCheckpoint()
        let mediaEnd = max(project.duration, 0.1)

        var captions = project.captions
        var overlays = project.overlays
        var sfx = project.soundEffects

        for ref in refs {
            switch ref {
            case .caption(let id):
                guard let idx = captions.firstIndex(where: { $0.id == id }) else { continue }
                var caption = captions[idx]
                let len = max(0.05, caption.endTime - caption.startTime)
                var start = caption.startTime + delta
                start = min(max(0, start), mediaEnd - 0.05)
                let end = min(mediaEnd, max(start + 0.05, start + len))
                let applied = start - caption.startTime
                caption.startTime = start
                caption.endTime = end
                caption.words = caption.words.map {
                    CaptionWord(
                        text: $0.text,
                        startTime: max(0, $0.startTime + applied),
                        endTime: max(0, $0.endTime + applied)
                    )
                }
                captions[idx] = caption
            case .overlay(let id):
                guard let idx = overlays.firstIndex(where: { $0.id == id }) else { continue }
                var item = overlays[idx]
                let len = max(0.05, item.endTime - item.startTime)
                var start = item.startTime + delta
                start = min(max(0, start), mediaEnd - 0.05)
                item.startTime = start
                item.endTime = min(mediaEnd, max(start + 0.05, start + len))
                overlays[idx] = item
            case .sfx(let id):
                guard let idx = sfx.firstIndex(where: { $0.id == id }) else { continue }
                var cue = sfx[idx]
                cue.startTime = min(max(0, cue.startTime + delta), mediaEnd - 0.05)
                sfx[idx] = cue
            case .trim, .audio:
                break
            }
        }

        project.captions = captions
        project.overlays = overlays
        project.soundEffects = sfx

        guard seekToSelection, let first = refs.first else { return }
        switch first {
        case .caption(let id):
            selectedCaptionID = id
            seek(to: project.captions.first(where: { $0.id == id })?.startTime ?? currentTime)
            editorTab = .captions
        case .overlay(let id):
            selectedOverlayID = id
            seek(to: project.overlays.first(where: { $0.id == id })?.startTime ?? currentTime)
            editorTab = .overlays
        case .sfx(let id):
            selectSoundEffect(id)
            seek(to: project.soundEffects.first(where: { $0.id == id })?.startTime ?? currentTime)
        default:
            break
        }
    }

    func clearTimelineMultiSelection() {
        selectedCaptionIDs = []
        selectedOverlayIDs = []
        selectedSoundEffectIDs = []
    }

    /// Select a timeline clip; `additive` toggles membership in the multi-select set.
    func selectTimelineClip(ref: TimelineClipRef, additive: Bool, seekTo start: TimeInterval? = nil) {
        if !additive {
            clearTimelineMultiSelection()
        }
        switch ref {
        case .caption(let id):
            if additive {
                if selectedCaptionIDs.contains(id) {
                    selectedCaptionIDs.remove(id)
                    if selectedCaptionID == id { selectedCaptionID = selectedCaptionIDs.first }
                } else {
                    selectedCaptionIDs.insert(id)
                    selectedCaptionID = id
                }
            } else {
                selectedCaptionID = id
                selectedCaptionIDs = [id]
            }
            selectedOverlayID = nil
            selectedOverlayIDs = []
            selectedSoundEffectID = nil
            selectedSoundEffectIDs = []
            isAudioLayerSelected = false
            editorTab = .captions
        case .overlay(let id):
            if additive {
                if selectedOverlayIDs.contains(id) {
                    selectedOverlayIDs.remove(id)
                    if selectedOverlayID == id { selectedOverlayID = selectedOverlayIDs.first }
                } else {
                    selectedOverlayIDs.insert(id)
                    selectedOverlayID = id
                }
            } else {
                selectedOverlayID = id
                selectedOverlayIDs = [id]
            }
            selectedCaptionID = nil
            selectedCaptionIDs = []
            selectedSoundEffectID = nil
            selectedSoundEffectIDs = []
            isAudioLayerSelected = false
            editorTab = .overlays
        case .sfx(let id):
            if additive {
                if selectedSoundEffectIDs.contains(id) {
                    selectedSoundEffectIDs.remove(id)
                    if selectedSoundEffectID == id { selectedSoundEffectID = selectedSoundEffectIDs.first }
                } else {
                    selectedSoundEffectIDs.insert(id)
                    selectedSoundEffectID = id
                }
            } else {
                selectedSoundEffectID = id
                selectedSoundEffectIDs = [id]
            }
            selectedOverlayID = nil
            selectedOverlayIDs = []
            selectedCaptionID = nil
            selectedCaptionIDs = []
            isAudioLayerSelected = false
            editorTab = .overlays
        case .trim(let id):
            if selectedTrimIDs.contains(id) {
                selectedTrimIDs.remove(id)
            } else {
                selectedTrimIDs.insert(id)
            }
            editorTab = .trim
        case .audio:
            clearTimelineMultiSelection()
            selectAudioLayer()
        }
        if let start {
            seek(to: start)
        }
    }

    func isTimelineClipSelected(_ ref: TimelineClipRef) -> Bool {
        switch ref {
        case .caption(let id):
            return selectedCaptionIDs.contains(id) || selectedCaptionID == id
        case .overlay(let id):
            return selectedOverlayIDs.contains(id) || selectedOverlayID == id
        case .sfx(let id):
            return selectedSoundEffectIDs.contains(id) || selectedSoundEffectID == id
        case .trim(let id):
            return selectedTrimIDs.contains(id)
        case .audio:
            return isAudioLayerSelected
        }
    }

    /// Refs that move together with `primary` during a multi-drag (same kind only).
    func timelineMultiDragGroup(for primary: TimelineClipRef) -> [TimelineClipRef] {
        switch primary {
        case .caption(let id):
            let ids = selectedCaptionIDs.isEmpty ? [id] : Array(selectedCaptionIDs.union([id]))
            return ids.map { .caption($0) }
        case .overlay(let id):
            let ids = selectedOverlayIDs.isEmpty ? [id] : Array(selectedOverlayIDs.union([id]))
            return ids.map { .overlay($0) }
        case .sfx(let id):
            let ids = selectedSoundEffectIDs.isEmpty ? [id] : Array(selectedSoundEffectIDs.union([id]))
            return ids.map { .sfx($0) }
        default:
            return [primary]
        }
    }

    private func applyCaptionTimelineDrag(
        id: UUID,
        toLane: TimelineLaneID,
        start: TimeInterval,
        end: TimeInterval
    ) {
        guard var caption = project.captions.first(where: { $0.id == id }) else { return }

        // Stay on Caps → retime only.
        if toLane == .captions {
            let delta = start - caption.startTime
            caption.startTime = start
            caption.endTime = end
            caption.words = caption.words.map {
                CaptionWord(
                    text: $0.text,
                    startTime: max(0, $0.startTime + delta),
                    endTime: max(0, $0.endTime + delta)
                )
            }
            updateCaption(caption)
            selectedCaptionID = id
            seek(to: start)
            editorTab = .captions
            return
        }

        // Drop onto overlay lanes → convert caption into an overlay (bring to front).
        guard toLane.acceptsClips, toLane != .sfx, toLane != .captions else {
            // Illegal drop — still apply retime on original lane.
            caption.startTime = start
            caption.endTime = end
            updateCaption(caption)
            return
        }

        let kind = overlayKind(for: toLane, preferring: nil)
        var item = OverlayItem.textSticker(caption.text, at: start, duration: max(0.4, end - start))
        item.kind = kind
        if kind == .wordHit {
            item.scale = 1.25
            item.fontSize = 44
            item.y = 0.36
        }
        deleteCaption(id)
        project.overlays.append(item)
        selectedOverlayID = item.id
        selectedCaptionID = nil
        selectedSoundEffectID = nil
        isAudioLayerSelected = false
        seek(to: start)
        editorTab = .overlays
    }

    private func applyOverlayTimelineDrag(
        id: UUID,
        toLane: TimelineLaneID,
        start: TimeInterval,
        end: TimeInterval
    ) {
        guard let index = project.overlays.firstIndex(where: { $0.id == id }) else { return }
        var item = project.overlays[index]

        // Convert overlay → caption.
        if toLane == .captions {
            let caption = CaptionSegment(
                text: item.text.isEmpty ? item.kind.label : item.text,
                startTime: start,
                endTime: end,
                words: []
            )
            project.overlays.remove(at: index)
            project.captions.append(caption)
            project.captions.sort { $0.startTime < $1.startTime }
            selectedCaptionID = caption.id
            selectedOverlayID = nil
            seek(to: start)
            editorTab = .captions
            return
        }

        guard toLane == .wordHits || toLane == .stickers || toLane == .text else {
            // Illegal lane — retime only, keep kind.
            item.startTime = start
            item.endTime = end
            project.overlays.remove(at: index)
            project.overlays.append(item)
            selectedOverlayID = item.id
            seek(to: start)
            editorTab = .overlays
            return
        }

        item.startTime = start
        item.endTime = end
        item.kind = overlayKind(for: toLane, preferring: item.kind)
        // Bring to front so lane drop changes on-screen stacking order.
        project.overlays.remove(at: index)
        project.overlays.append(item)
        selectedOverlayID = item.id
        selectedSoundEffectID = nil
        isAudioLayerSelected = false
        seek(to: start)
        editorTab = .overlays
    }

    private func overlayKind(for lane: TimelineLaneID, preferring current: OverlayKind?) -> OverlayKind {
        switch lane {
        case .wordHits:
            return .wordHit
        case .stickers:
            if let current, current == .gif || current == .png { return current }
            return .png
        case .text:
            if let current, current == .text || current == .emoji || current == .shape || current == .watermark {
                return current
            }
            return .text
        default:
            return current ?? .text
        }
    }

    func selectAudioLayer() {
        isAudioLayerSelected = true
        selectedSoundEffectID = nil
        selectedSoundEffectIDs = []
        selectedOverlayID = nil
        selectedOverlayIDs = []
        selectedCaptionID = nil
        selectedCaptionIDs = []
        editorTab = .overlays
    }

    func selectSoundEffect(_ id: SoundEffectCue.ID) {
        selectedSoundEffectID = id
        selectedSoundEffectIDs = [id]
        selectedOverlayID = nil
        selectedOverlayIDs = []
        selectedCaptionID = nil
        selectedCaptionIDs = []
        isAudioLayerSelected = false
        editorTab = .overlays
    }

    func updateSoundEffect(_ cue: SoundEffectCue) {
        registerUndoCheckpoint()
        guard let index = project.soundEffects.firstIndex(where: { $0.id == cue.id }) else { return }
        project.soundEffects[index] = cue
    }

    func deleteSoundEffect(_ id: SoundEffectCue.ID) {
        registerUndoCheckpoint()
        project.soundEffects.removeAll { $0.id == id }
        if selectedSoundEffectID == id { selectedSoundEffectID = nil }
        selectedSoundEffectIDs.remove(id)
    }

    func updateAudioSettings(_ settings: ProjectAudioSettings) {
        registerUndoCheckpoint()
        project.audio = settings
        normalizeLoudness = settings.normalizeLoudness
        refreshPreviewDialogueVolume()
    }

    func applyAudioEnhancer(_ preset: AudioEnhancerPreset) {
        registerUndoCheckpoint()
        var settings = project.audio
        settings.apply(preset: preset)
        // Avoid double checkpoint inside updateAudioSettings
        isRestoringHistory = true
        project.audio = settings
        normalizeLoudness = settings.normalizeLoudness
        isRestoringHistory = false
    }

    // MARK: - Chess overlay on project video

    /// Attach a PGN walkthrough to the current project (export + preview corner board).
    func attachChessOverlay(
        pgn: String,
        secondsPerMove: Double,
        startOffset: TimeInterval? = nil,
        endOffset: TimeInterval? = nil,
        timingMode: ChessTimingMode = .fixedPace,
        includeSFX: Bool = true,
        title: String = "Chess"
    ) {
        registerUndoCheckpoint()
        let offset = startOffset ?? currentTime
        var end = endOffset
        if timingMode == .fitRange {
            let moves = (try? ChessPGNParser.parse(pgn).moves.count) ?? 0
            let minEnd = offset + Double(max(1, moves)) * 0.05
            if let e = end {
                end = max(minEnd, e)
            } else {
                end = offset + Double(max(1, moves)) * max(0.05, secondsPerMove)
            }
        }
        let layout = ChessBoardLayout(originX: 0.58, originY: 0.58, size: 0.38, whiteAtBottom: true)
        let spec = ChessWalkthroughSpec(
            pgn: pgn,
            secondsPerMove: secondsPerMove,
            startOffset: max(0, offset),
            endOffset: end,
            timingMode: timingMode,
            layout: layout,
            includeCallouts: true,
            includeSFX: includeSFX,
            title: title
        )
        project.chessOverlay = spec
        rebuildChessOverlaySFX(spec: spec, includeSFX: includeSFX)
        let moveCount = (try? ChessPGNParser.parse(pgn).moves.count) ?? 0
        let pace = spec.effectivePace(moveCount: moveCount)
        draftMessage = timingMode == .fitRange
            ? "Chess VO sync \(formatClock(spec.startOffset))→\(formatClock(spec.endTime(moveCount: moveCount))) · \(String(format: "%.2fs", pace))/move"
            : "Chess overlay attached at \(formatClock(spec.startOffset))"
    }

    /// Update start/end/mode on an existing chess overlay and rebuild SFX cues.
    func updateChessOverlayClock(
        startOffset: TimeInterval? = nil,
        endOffset: TimeInterval? = nil,
        timingMode: ChessTimingMode? = nil,
        secondsPerMove: Double? = nil
    ) {
        guard var spec = project.chessOverlay else { return }
        registerUndoCheckpoint()
        if let startOffset { spec.startOffset = max(0, startOffset) }
        if let timingMode { spec.timingMode = timingMode }
        if let secondsPerMove { spec.secondsPerMove = max(0.05, secondsPerMove) }
        if let endOffset {
            spec.endOffset = max(spec.startOffset + 0.05, endOffset)
        }
        if spec.timingMode == .fitRange, spec.endOffset == nil {
            let moves = (try? ChessPGNParser.parse(spec.pgn).moves.count) ?? 0
            spec.endOffset = spec.startOffset + Double(max(1, moves)) * spec.secondsPerMove
        }
        project.chessOverlay = spec
        rebuildChessOverlaySFX(spec: spec, includeSFX: spec.includeSFX)
        draftMessage = "Chess VO clock updated"
    }

    private func rebuildChessOverlaySFX(spec: ChessWalkthroughSpec, includeSFX: Bool) {
        project.soundEffects.removeAll { ($0.reason ?? "").hasPrefix("chess:") }
        guard includeSFX, let moves = try? ChessPGNParser.parse(spec.pgn).moves, !moves.isEmpty else { return }
        let starts = spec.moveStartTimes(moveCount: moves.count)
        for (i, move) in moves.enumerated() {
            let t = i < starts.count ? starts[i] : spec.startOffset + Double(i) * spec.secondsPerMove
            project.soundEffects.append(
                SoundEffectCue(
                    assetId: move.category.sfxId,
                    startTime: t,
                    gain: move.category == .normal ? 0.45 : 0.85,
                    reason: "chess:\(move.san)"
                )
            )
        }
    }

    func clearChessOverlay() {
        guard project.chessOverlay != nil else { return }
        registerUndoCheckpoint()
        project.chessOverlay = nil
        project.soundEffects.removeAll { ($0.reason ?? "").hasPrefix("chess:") }
        draftMessage = "Chess overlay cleared"
    }

    /// Snapshot boards/move for live preview of the attached chess overlay.
    func chessPreviewState(at time: TimeInterval) -> (board: ChessBoard, move: ChessAnnotatedMove?)? {
        guard let spec = project.chessOverlay,
              let parsed = try? ChessPGNParser.parse(spec.pgn),
              !parsed.moves.isEmpty
        else { return nil }
        var board = ChessBoard.starting()
        var boards = [board]
        for move in parsed.moves {
            guard (try? board.applySAN(move.san)) != nil else { break }
            boards.append(board)
        }
        let idx = spec.boardIndex(at: time, moveCount: parsed.moves.count)
        let safeIdx = min(idx, boards.count - 1)
        let move: ChessAnnotatedMove? = idx > 0 && idx - 1 < parsed.moves.count ? parsed.moves[idx - 1] : nil
        return (boards[safeIdx], move)
    }

    /// Resolved play length for a cue from the SFX library (fallback 0.35s).
    func sfxDuration(for cue: SoundEffectCue) -> TimeInterval {
        libraries.item(kind: .sfx, id: cue.assetId)?.playLength ?? 0.35
    }

    /// Overlays sorted by start time for the layers timeline / inspector.
    var timelineOverlays: [OverlayItem] {
        project.overlays.sorted { $0.startTime < $1.startTime }
    }

    var timelineSoundEffects: [SoundEffectCue] {
        project.soundEffects.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Export

    func toggleBatchAspect(_ aspect: AspectRatioPreset) {
        if batchExportAspects.contains(aspect) {
            if batchExportAspects.count > 1 {
                batchExportAspects.remove(aspect)
            }
        } else {
            batchExportAspects.insert(aspect)
        }
    }

    func exportVideo() async {
        await exportVideo(aspects: [project.aspectRatio])
    }

    func exportBatch() async {
        let aspects = AspectRatioPreset.allCases.filter { batchExportAspects.contains($0) }
        await exportVideo(aspects: aspects.isEmpty ? [project.aspectRatio] : aspects)
    }

    private func exportVideo(aspects: [AspectRatioPreset]) async {
        guard let url = project.videoURL else {
            errorMessage = "Import a video first."
            return
        }
        isExporting = true
        errorMessage = nil
        chunkProgressLabel = nil
        batchExportURLs = []
        defer {
            isExporting = false
            chunkProgressLabel = nil
        }

        refreshWatermarkOverlay()

        // Keep export timeline aligned with captions if duration was never measured.
        let resolved = resolvedTimelineDuration()
        if resolved > project.duration {
            project.duration = resolved
        }

        do {
            var results: [URL] = []
            for aspect in aspects {
                let overlays = AspectOverlayRemapper.remapOverlays(
                    project.overlays,
                    from: project.aspectRatio,
                    to: aspect
                )
                let chessOverlay: ChessWalkthroughSpec? = {
                    guard var chess = project.chessOverlay else { return nil }
                    chess.layout = AspectOverlayRemapper.remapChessLayout(
                        chess.layout,
                        from: project.aspectRatio,
                        to: aspect
                    )
                    return chess
                }()
                let chunks = VideoChunkPlanner.chunks(duration: max(project.duration, 0.1))
                project.chunkCount = chunks.count
                let result: URL

                if chunks.count == 1 {
                    chunkProgressLabel = aspects.count > 1
                        ? "Exporting \(aspect.rawValue)…"
                        : "Exporting \(aspect.rawValue)…"
                    result = try await exporter.export(
                        videoURL: url,
                        captions: project.captions,
                        style: project.captionStyle,
                        overlays: overlays,
                        soundEffects: project.soundEffects,
                        libraryRoot: libraries.rootURL,
                        aspect: aspect,
                        audioSettings: project.audio,
                        brandSfxGain: brandKit.kit.defaultSfxGain,
                        chessOverlay: chessOverlay
                    )
                } else {
                    let segments: [VideoStitchService.SegmentSpec] = chunks.map { chunk in
                        let caps = VideoChunkPlanner.captions(project.captions, overlapping: chunk, useContext: false)
                        let chunkOverlays = overlays.filter {
                            $0.endTime > chunk.startTime && $0.startTime < chunk.endTime
                        }
                        let sfx = project.soundEffects.filter {
                            $0.startTime >= chunk.startTime && $0.startTime < chunk.endTime
                        }
                        return .init(
                            chunk: chunk,
                            captions: caps,
                            overlays: chunkOverlays,
                            soundEffects: sfx
                        )
                    }
                    chunkProgressLabel = "Exporting \(aspect.rawValue): \(chunks.count) parts → stitch…"
                    result = try await stitcher.exportChunked(
                        videoURL: url,
                        aspect: aspect,
                        style: project.captionStyle,
                        segments: segments,
                        libraryRoot: libraries.rootURL,
                        audioSettings: project.audio,
                        brandSfxGain: brandKit.kit.defaultSfxGain,
                        chessOverlay: chessOverlay
                    )
                    exporter.progress = stitcher.progress
                    exporter.statusMessage = stitcher.statusMessage
                }

                // Rename with aspect suffix for batch clarity
                if aspects.count > 1 {
                    let tagged = result.deletingLastPathComponent()
                        .appendingPathComponent(
                            "CaptionStudio-\(aspect.fileToken)-\(UUID().uuidString).mp4"
                        )
                    try? FileManager.default.removeItem(at: tagged)
                    try FileManager.default.moveItem(at: result, to: tagged)
                    results.append(tagged)
                } else {
                    results.append(result)
                }
            }

            batchExportURLs = results
            exportURL = results.first
            if distribution == nil, !project.captions.isEmpty {
                distribution = DistributionPackage.heuristic(
                    captions: project.captions,
                    language: language,
                    packName: selectedPack?.name
                )
            }
            showExporter = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func exportCoverImage() async {
        guard let url = project.videoURL else {
            errorMessage = "Import a video first."
            return
        }
        let package = distribution ?? DistributionPackage.heuristic(
            captions: project.captions,
            language: language,
            packName: selectedPack?.name
        )
        do {
            coverURL = try await CoverExportService.exportCoverPNG(
                videoURL: url,
                coverText: package.coverText,
                aspect: project.aspectRatio,
                brandColor: brandKit.kit.primarySwiftUIColor.codable
            )
            distribution = package
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func ensureDistribution() {
        if distribution == nil, !project.captions.isEmpty {
            distribution = DistributionPackage.heuristic(
                captions: project.captions,
                language: language,
                packName: selectedPack?.name
            )
        }
    }

    // MARK: - Cleanup

    func tearDownPlayer() {
        player?.pause()
        stopPreviewSFXPlayers()
        resetTimelineSFXTracking(at: 0)
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
