import Foundation
import SwiftUI
import AVFoundation
import Combine

/// Drives an animated chess game walkthrough from PGN / move list notation.
@MainActor
final class ChessWalkthroughViewModel: ObservableObject {
    @Published var pgnText: String
    @Published var result: ChessAnalysisResult?
    @Published var boards: [ChessBoard] = [ChessBoard.starting()]
    @Published var plyIndex: Int = 0
    @Published var isPlaying = false
    @Published var secondsPerMove: Double = 1.35
    /// Project-video mark where the first ply begins (VO sync).
    @Published var voStartMark: TimeInterval? = nil
    /// Project-video mark where the last ply ends (fit-range mode).
    @Published var voEndMark: TimeInterval? = nil
    @Published var timingMode: ChessTimingMode = .fixedPace
    @Published var errorMessage: String?
    @Published var lastCallout: String?
    @Published var animatingMove: ChessAnnotatedMove?
    @Published var pulseCategory: ChessMoveCategory?
    @Published var isAnalyzing = false
    @Published var isExporting = false
    @Published var exportProgress: Double = 0
    @Published var exportStatus: String = ""
    @Published var exportURL: URL?
    @Published var evalEngineName: String = "heuristic"
    @Published var showExportShare = false
    @Published var importURLText: String = ""
    @Published var isImporting = false
    @Published var importNote: String?

    private var playTask: Task<Void, Never>?
    private var sfxPlayers: [AVAudioPlayer] = []
    private let libraries = MediaLibraryStore()
    private let exporter = ChessExportService()

    init() {
        pgnText = ChessWalkthroughViewModel.samplePGN
    }

    var moves: [ChessAnnotatedMove] { result?.moves ?? [] }

    var voSyncSummary: String {
        let n = max(1, moves.count)
        let start = voStartMark ?? 0
        let pace = ChessVOClock.effectivePace(
            mode: timingMode,
            startOffset: start,
            endOffset: voEndMark,
            moveCount: n,
            secondsPerMove: secondsPerMove
        )
        let end = ChessVOClock.endTime(
            mode: timingMode,
            startOffset: start,
            endOffset: voEndMark,
            moveCount: n,
            secondsPerMove: secondsPerMove
        )
        let fmt: (TimeInterval) -> String = { t in
            let m = Int(t) / 60
            let s = Int(t) % 60
            return String(format: "%d:%02d", m, s)
        }
        switch timingMode {
        case .fixedPace:
            return "Start \(fmt(start)) · \(String(format: "%.2fs", pace))/move · ends ~\(fmt(end))"
        case .fitRange:
            return "VO \(fmt(start))→\(fmt(end)) · \(n) plies · \(String(format: "%.2fs", pace))/move"
        }
    }

    var currentBoard: ChessBoard {
        let idx = min(max(0, plyIndex), boards.count - 1)
        return boards[idx]
    }
    var currentMove: ChessAnnotatedMove? {
        guard plyIndex > 0, plyIndex - 1 < moves.count else { return nil }
        return moves[plyIndex - 1]
    }
    var progressLabel: String {
        guard let result else { return "Paste notation, import a file, or paste a game URL" }
        if plyIndex == 0 { return "Start · \(result.moves.count) moves · eval:\(evalEngineName)" }
        if let m = currentMove {
            let side = m.isWhite ? "White" : "Black"
            var label = "\(m.moveNumber)\(m.isWhite ? "." : "...") \(m.san) · \(m.category.label) · \(side)"
            if let d = m.evalDeltaCp {
                label += " · \(d >= 0 ? "+" : "")\(d)cp"
            }
            return label
        }
        return "End of game"
    }

    func loadNotation() {
        stop()
        errorMessage = nil
        lastCallout = nil
        pulseCategory = nil
        animatingMove = nil
        exportURL = nil
        isAnalyzing = true
        do {
            let parsed = try ChessPGNParser.parse(pgnText)
            result = parsed
            var b = ChessBoard.starting()
            var snaps = [b]
            for move in parsed.moves {
                _ = try b.applySAN(move.san)
                snaps.append(b)
            }
            boards = snaps
            plyIndex = 0
            lastCallout = parsed.summary
            Task { await self.runEvalEnrichment() }
        } catch {
            isAnalyzing = false
            result = nil
            boards = [ChessBoard.starting()]
            plyIndex = 0
            errorMessage = error.localizedDescription
        }
    }

    /// Load PGN from a Lichess / chess.com / .pgn URL, then analyze.
    func importFromURL() {
        let raw = importURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            errorMessage = "Paste a Lichess, chess.com, or .pgn URL first."
            return
        }
        isImporting = true
        errorMessage = nil
        importNote = "Fetching game…"
        Task {
            defer { isImporting = false }
            do {
                let imported = try await ChessPGNImportService.fetch(from: raw)
                pgnText = imported.pgn
                importNote = "Imported via \(imported.source)"
                loadNotation()
            } catch {
                importNote = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Load PGN bytes from a file picker URL (security-scoped).
    func importFromFile(url: URL) {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try ChessPGNImportService.loadFile(url: url)
            pgnText = text
            importURLText = url.lastPathComponent
            importNote = "Loaded \(url.lastPathComponent)"
            loadNotation()
        } catch {
            importNote = nil
            errorMessage = error.localizedDescription
        }
    }

    private func runEvalEnrichment() async {
        guard let parsed = result else {
            isAnalyzing = false
            return
        }
        let engine = ChessEvalService.preferred()
        evalEngineName = engine.name
        let enriched = await engine.enrich(parsed)
        result = enriched
        lastCallout = enriched.summary
        isAnalyzing = false
    }

    func exportVideo() async {
        guard result != nil, boards.count > 1 else {
            errorMessage = "Analyze a game before exporting."
            return
        }
        if result == nil { loadNotation() }
        stop()
        isExporting = true
        exportProgress = 0
        exportStatus = "Rendering…"
        errorMessage = nil
        defer { isExporting = false }
        do {
            let title = result?.summary ?? "Chess Walkthrough"
            let url = try await exporter.export(
                boards: boards,
                moves: moves,
                secondsPerMove: secondsPerMove,
                title: title
            )
            exportURL = url
            exportProgress = 1
            exportStatus = "Ready"
            lastCallout = "Exported chess video"
            showExportShare = true
        } catch {
            errorMessage = error.localizedDescription
            exportStatus = ""
        }
    }

    func jumpToStart() {
        stop()
        plyIndex = 0
        animatingMove = nil
        pulseCategory = nil
        lastCallout = result?.summary
    }

    func jumpToEnd() {
        stop()
        plyIndex = max(0, boards.count - 1)
        if let last = moves.last {
            animatingMove = last
            pulseCategory = last.category
            lastCallout = callout(for: last)
        }
    }

    func stepForward() {
        guard plyIndex < boards.count - 1 else {
            stop()
            return
        }
        plyIndex += 1
        presentMove(at: plyIndex - 1)
    }

    func stepBack() {
        stop()
        guard plyIndex > 0 else { return }
        plyIndex -= 1
        if plyIndex == 0 {
            animatingMove = nil
            pulseCategory = nil
            lastCallout = result?.summary
        } else {
            presentMove(at: plyIndex - 1, playSound: false)
        }
    }

    func togglePlay() {
        if isPlaying {
            stop()
        } else {
            play()
        }
    }

    func play() {
        if result == nil {
            loadNotation()
            guard result != nil else { return }
        }
        if plyIndex >= boards.count - 1 { plyIndex = 0 }
        isPlaying = true
        playTask?.cancel()
        playTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                if self.plyIndex >= self.boards.count - 1 {
                    await MainActor.run {
                        self.isPlaying = false
                    }
                    break
                }
                await MainActor.run { self.stepForward() }
                let delay = self.secondsPerMove
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    func stop() {
        isPlaying = false
        playTask?.cancel()
        playTask = nil
    }

    private func presentMove(at moveIndex: Int, playSound: Bool = true) {
        guard moves.indices.contains(moveIndex) else { return }
        let move = moves[moveIndex]
        animatingMove = move
        pulseCategory = move.category
        lastCallout = callout(for: move)
        if playSound {
            playSFX(for: move.category)
        }
    }

    private func callout(for move: ChessAnnotatedMove) -> String {
        var parts = ["\(move.moveNumber)\(move.isWhite ? "." : "...") \(move.san)"]
        if move.category.isHighlightWorthy {
            parts.append(move.category.label.uppercased())
        }
        if let d = move.evalDeltaCp {
            parts.append("\(d >= 0 ? "+" : "")\(d)cp")
        }
        if move.givesCheck { parts.append("Check!") }
        if move.isCapture { parts.append("Capture") }
        if let c = move.comment, !c.isEmpty { parts.append(c) }
        return parts.joined(separator: " · ")
    }

    private func playSFX(for category: ChessMoveCategory) {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        guard let asset = libraries.item(kind: .sfx, id: category.sfxId) else { return }
        let file = asset.wav ?? asset.file
        guard let file,
              let url = libraries.fileURL(kind: .sfx, fileName: file)
        else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = category == .normal ? 0.45 : 0.85
            player.prepareToPlay()
            player.play()
            sfxPlayers.append(player)
            sfxPlayers.removeAll { !$0.isPlaying && $0 !== player }
        } catch {
            // Non-fatal — walkthrough continues silently.
        }
    }

    static let samplePGN = """
    [Event "Scholar's Mate Demo"]
    [White "Attacker"]
    [Black "Defender"]
    [Result "1-0"]

    1. e4 e5 2. Qh5?! {Early queen — Interesting} Nc6 3. Bc4 Nf6?? {Blunder — hangs f7}
    4. Qxf7# {Critical mate}
    """
}
