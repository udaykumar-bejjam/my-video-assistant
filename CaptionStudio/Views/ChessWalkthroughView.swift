import SwiftUI

/// Animated chess game walkthrough from pasted PGN / move notation.
/// Steps through the board with colored move callouts, arrows, square boxes, and SFX.
struct ChessWalkthroughView: View {
    @StateObject private var vm = ChessWalkthroughViewModel()
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var attachNote: String?

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.09, blue: 0.12),
                        Color(red: 0.04, green: 0.14, blue: 0.12),
                        Color(red: 0.08, green: 0.07, blue: 0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 14) {
                    header
                    boardCard
                    calloutBanner
                    transport
                    notationEditor
                }
                .padding(16)
            }
            .navigationTitle("Chess Walkthrough")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await vm.exportVideo() }
                    } label: {
                        if vm.isExporting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Export MP4", systemImage: "square.and.arrow.up")
                        }
                    }
                    .disabled(vm.result == nil || vm.isExporting || vm.isAnalyzing)
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        guard editor.project.videoURL != nil else {
                            attachNote = "Open a video in the editor first."
                            return
                        }
                        editor.attachChessOverlay(
                            pgn: vm.pgnText,
                            secondsPerMove: vm.secondsPerMove,
                            startOffset: editor.currentTime,
                            includeSFX: true,
                            title: vm.result?.summary ?? "Chess"
                        )
                        attachNote = "Attached at playhead — burns into project export."
                    } label: {
                        Label("Attach to video", systemImage: "rectangle.badge.plus")
                    }
                    .disabled(vm.result == nil || vm.isAnalyzing || editor.project.videoURL == nil)
                }
                ToolbarItem(placement: .automatic) {
                    if editor.project.chessOverlay != nil {
                        Button(role: .destructive) {
                            editor.clearChessOverlay()
                            attachNote = "Chess overlay cleared."
                        } label: {
                            Label("Clear", systemImage: "xmark.circle")
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Analyze") { vm.loadNotation() }
                        .fontWeight(.semibold)
                        .disabled(vm.isAnalyzing)
                }
            }
            .onAppear {
                if vm.result == nil { vm.loadNotation() }
            }
            .onDisappear { vm.stop() }
            .sheet(isPresented: $vm.showExportShare) {
                if let url = vm.exportURL {
                    ChessExportShareSheet(url: url)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(vm.result?.summary ?? "Paste PGN or moves, then Analyze")
                .font(.custom("AvenirNext-DemiBold", size: 14))
                .foregroundStyle(.white.opacity(0.9))
            Text(vm.progressLabel)
                .font(.custom("AvenirNext-Medium", size: 12))
                .foregroundStyle(.white.opacity(0.5))
            if vm.isAnalyzing {
                Text("Running \(vm.evalEngineName) eval…")
                    .font(.custom("AvenirNext-Medium", size: 11))
                    .foregroundStyle(Color(red: 0.2, green: 0.95, blue: 0.72))
            }
            if vm.isExporting {
                ProgressView(value: max(0.05, vm.exportProgress))
                    .tint(Color(red: 0.2, green: 0.95, blue: 0.72))
                Text(vm.exportStatus.isEmpty ? "Exporting chess MP4…" : vm.exportStatus)
                    .font(.custom("AvenirNext-Medium", size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            if let note = attachNote {
                Text(note)
                    .font(.custom("AvenirNext-Medium", size: 11))
                    .foregroundStyle(Color(red: 0.2, green: 0.95, blue: 0.72))
            }
            if let err = vm.errorMessage {
                Text(err)
                    .font(.custom("AvenirNext-Medium", size: 12))
                    .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.35))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var boardCard: some View {
        ChessBoardView(
            board: vm.currentBoard,
            move: vm.animatingMove,
            pulse: vm.pulseCategory
        )
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 520)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
    }

    private var calloutBanner: some View {
        Group {
            if let text = vm.lastCallout {
                Text(text)
                    .font(.custom("AvenirNext-Bold", size: 16))
                    .foregroundStyle(vm.pulseCategory?.color.color ?? .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        (vm.pulseCategory?.color.color ?? Color.white).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder((vm.pulseCategory?.color.color ?? .white).opacity(0.35), lineWidth: 1)
                    )
                    .scaleEffect(vm.pulseCategory?.isHighlightWorthy == true ? 1.02 : 1)
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: vm.plyIndex)
            }
        }
    }

    private var transport: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                transportButton("backward.end.fill") { vm.jumpToStart() }
                transportButton("backward.frame.fill") { vm.stepBack() }
                Button {
                    vm.togglePlay()
                } label: {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 54, height: 54)
                        .background(Color(red: 0.2, green: 0.95, blue: 0.72), in: Circle())
                }
                .buttonStyle(.plain)
                transportButton("forward.frame.fill") { vm.stepForward() }
                transportButton("forward.end.fill") { vm.jumpToEnd() }
            }

            HStack {
                Text("Speed")
                    .font(.custom("AvenirNext-Medium", size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                Slider(value: $vm.secondsPerMove, in: 0.45...3.0)
                    .tint(Color(red: 0.2, green: 0.95, blue: 0.72))
                Text(String(format: "%.1fs", vm.secondsPerMove))
                    .font(.custom("AvenirNext-Medium", size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 36, alignment: .trailing)
            }

            legend
        }
    }

    private var legend: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([ChessMoveCategory.brilliant, .good, .book, .interesting, .mistake, .blunder, .critical], id: \.self) { cat in
                    HStack(spacing: 4) {
                        Circle().fill(cat.color.color).frame(width: 8, height: 8)
                        Text(cat.label)
                            .font(.custom("AvenirNext-Medium", size: 10))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.05), in: Capsule())
                }
            }
        }
    }

    private func transportButton(_ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var notationEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notation (PGN or move list)")
                .font(.custom("AvenirNext-Medium", size: 11))
                .foregroundStyle(.white.opacity(0.45))
            TextEditor(text: $vm.pgnText)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(minHeight: 110, maxHeight: 160)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("Tip: mark moves with !! ? ?? !? or PGN $1–$6 NAGs. Unannotated moves get heuristic eval (or Stockfish if installed on PATH). Export MP4 burns the board walkthrough.")
                .font(.custom("AvenirNext-Medium", size: 10))
                .foregroundStyle(.white.opacity(0.35))
        }
    }
}

#if os(macOS)
import AppKit

private struct ChessExportShareSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Chess video ready")
                .font(.headline)
            Text(url.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button("Save As…") {
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.mpeg4Movie]
                    panel.nameFieldStringValue = url.lastPathComponent
                    if panel.runModal() == .OK, let dest = panel.url {
                        try? FileManager.default.removeItem(at: dest)
                        try? FileManager.default.copyItem(at: url, to: dest)
                    }
                }
                .keyboardShortcut(.defaultAction)
                Button("Done") { dismiss() }
            }
        }
        .padding(24)
        .frame(minWidth: 360)
    }
}
#elseif os(iOS)
import UIKit

private struct ChessExportShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

// MARK: - Board

struct ChessBoardView: View {
    let board: ChessBoard
    let move: ChessAnnotatedMove?
    let pulse: ChessMoveCategory?

    private let light = Color(red: 0.93, green: 0.85, blue: 0.70)
    private let dark = Color(red: 0.45, green: 0.58, blue: 0.40)

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let sq = side / 8
            ZStack {
                ForEach(0..<64, id: \.self) { idx in
                    let file = idx % 8
                    let rank = 7 - idx / 8 // draw rank 8 at top
                    let isLight = (file + rank) % 2 == 1
                    let name = ChessSquare(file: file, rank: rank).name
                    let x = CGFloat(file) * sq + sq / 2
                    let y = CGFloat(7 - rank) * sq + sq / 2

                    ZStack {
                        Rectangle()
                            .fill(isLight ? light : dark)
                        if let move, move.criticalSquares.contains(name) || move.from == name || move.to == name {
                            Rectangle()
                                .fill(highlightColor(for: name, move: move).opacity(name == move.to ? 0.55 : 0.35))
                        }
                        if let occ = board.piece(atFile: file, rank: rank) {
                            Text(occ.glyph)
                                .font(.system(size: sq * 0.72))
                                .foregroundStyle(occ.isWhite ? Color.white : Color(white: 0.12))
                                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        }
                    }
                    .frame(width: sq, height: sq)
                    .position(x: x, y: y)
                }

                if let move {
                    arrowLayer(move: move, sq: sq, side: side)
                    categoryBadge(move: move, sq: sq, side: side)
                }
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }

    private func highlightColor(for square: String, move: ChessAnnotatedMove) -> Color {
        if square == move.to { return move.category.color.color }
        if square == move.from { return Color.yellow.opacity(0.9) }
        if move.givesCheck { return Color.red }
        return move.category.color.color
    }

    @ViewBuilder
    private func arrowLayer(move: ChessAnnotatedMove, sq: CGFloat, side: CGFloat) -> some View {
        let arrows: [(String, String, Color)] = {
            var list: [(String, String, Color)] = [(move.from, move.to, move.category.color.color)]
            for idea in move.ideaArrows {
                list.append((idea.from, idea.to, Color.red.opacity(0.9)))
            }
            return list
        }()

        ForEach(Array(arrows.enumerated()), id: \.offset) { _, arrow in
            if let a = point(square: arrow.0, sq: sq), let b = point(square: arrow.1, sq: sq) {
                ChessArrowShape(from: a, to: b)
                    .stroke(arrow.2, style: StrokeStyle(lineWidth: max(3, sq * 0.12), lineCap: .round, lineJoin: .round))
                    .shadow(color: arrow.2.opacity(0.5), radius: 4)
            }
        }
    }

    private func categoryBadge(move: ChessAnnotatedMove, sq: CGFloat, side: CGFloat) -> some View {
        Group {
            if move.category.isHighlightWorthy, let p = point(square: move.to, sq: sq) {
                Text(move.category.label.uppercased())
                    .font(.system(size: max(9, sq * 0.22), weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(move.category.color.color, in: Capsule())
                    .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
                    .position(x: p.x, y: max(14, p.y - sq * 0.55))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: move.id)
    }

    private func point(square: String, sq: CGFloat) -> CGPoint? {
        guard let s = ChessSquare.parse(square) else { return nil }
        return CGPoint(
            x: CGFloat(s.file) * sq + sq / 2,
            y: CGFloat(7 - s.rank) * sq + sq / 2
        )
    }
}

struct ChessArrowShape: Shape {
    var from: CGPoint
    var to: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dx = to.x - from.x
        let dy = to.y - from.y
        let len = max(0.001, sqrt(dx * dx + dy * dy))
        let ux = dx / len
        let uy = dy / len
        // Shorten so arrow doesn't cover piece centers fully.
        let start = CGPoint(x: from.x + ux * len * 0.18, y: from.y + uy * len * 0.18)
        let end = CGPoint(x: to.x - ux * len * 0.18, y: to.y - uy * len * 0.18)
        path.move(to: start)
        path.addLine(to: end)
        // Arrow head
        let head: CGFloat = min(18, len * 0.22)
        let left = CGPoint(
            x: end.x - ux * head - uy * head * 0.55,
            y: end.y - uy * head + ux * head * 0.55
        )
        let right = CGPoint(
            x: end.x - ux * head + uy * head * 0.55,
            y: end.y - uy * head - ux * head * 0.55
        )
        path.move(to: left)
        path.addLine(to: end)
        path.addLine(to: right)
        return path
    }
}
