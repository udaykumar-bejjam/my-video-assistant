import SwiftUI
import AVFoundation
import AVKit
#if os(macOS)
import AppKit
#endif

struct EditorView: View {
    @EnvironmentObject private var editor: EditorViewModel
    @State private var showLeaveConfirm = false

    var body: some View {
        ZStack {
            AtmosphereBackground()

            #if os(macOS)
            macLayout
            #else
            phoneLayout
            #endif
        }
        .safeAreaInset(edge: .top) {
            editorChrome
        }
        .sheet(isPresented: $editor.showExporter) {
            if let url = editor.exportURL {
                ExportShareView(url: url)
            }
        }
        .confirmationDialog("Leave editor?", isPresented: $showLeaveConfirm) {
            Button("Discard & Leave", role: .destructive) {
                editor.tearDownPlayer()
                editor.project = .empty()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var editorChrome: some View {
        HStack {
            Button {
                showLeaveConfirm = true
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(editor.project.title)
                    .font(.custom("AvenirNext-DemiBold", size: 15))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(formatTime(editor.currentTime) + " / " + formatTime(editor.project.duration))
                    .font(.custom("AvenirNext-Medium", size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Spacer()

            if editor.isTranscribing || editor.isEnhancing || editor.isExporting {
                ProgressView()
                    .tint(Color(red: 0.4, green: 0.95, blue: 0.8))
                    .scaleEffect(0.85)
            }

            if let chunk = editor.chunkProgressLabel {
                Text(chunk)
                    .font(.custom("AvenirNext-Medium", size: 10))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
            #if os(macOS)
            Picker("", selection: $editor.language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.title).tag(lang)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            #else
            Menu {
                ForEach(AppLanguage.allCases) { lang in
                    Button(lang.title) { editor.language = lang }
                }
            } label: {
                Text(editor.language == .english ? "EN" : (editor.language == .hindi ? "हि" : "తె"))
                    .font(.custom("AvenirNext-DemiBold", size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.1), in: Capsule())
                    .foregroundStyle(.white)
            }
            #endif

            Button {
                Task { await editor.generateCaptions() }
            } label: {
                Label("AI Captions", systemImage: "waveform.badge.mic")
                    .font(.custom("AvenirNext-DemiBold", size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(red: 0.15, green: 0.9, blue: 0.72), in: Capsule())
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .disabled(editor.isTranscribing)

            Button {
                Task { await editor.enhanceWithCursorSDK() }
            } label: {
                Label("AI Place", systemImage: "sparkles")
                    .font(.custom("AvenirNext-DemiBold", size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(red: 1.0, green: 0.92, blue: 0.35), in: Capsule())
                    .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .disabled(editor.isEnhancing || editor.project.captions.isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial.opacity(0.35))
    }

    // MARK: - Layouts

    private var phoneLayout: some View {
        VStack(spacing: 0) {
            VideoPreviewPane()
                .padding(.horizontal, 16)
                .padding(.top, 8)

            TimelineScrubber()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            tabBar
                .padding(.horizontal, 12)

            tabContent
                .frame(maxHeight: 280)
        }
    }

    private var macLayout: some View {
        HStack(spacing: 0) {
            VStack(spacing: 12) {
                VideoPreviewPane()
                    .padding(16)
                TimelineScrubber()
                    .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)

            Divider().overlay(Color.white.opacity(0.08))

            VStack(spacing: 0) {
                tabBar
                    .padding(12)
                tabContent
            }
            .frame(width: 360)
            .background(Color.black.opacity(0.25))
        }
    }

    private var tabBar: some View {
        HStack(spacing: 6) {
            ForEach(EditorViewModel.EditorTab.allCases) { tab in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        editor.editorTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 14))
                        Text(tab.title)
                            .font(.custom("AvenirNext-Medium", size: 10))
                    }
                    .foregroundStyle(editor.editorTab == tab ? Color(red: 0.4, green: 0.95, blue: 0.8) : .white.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        editor.editorTab == tab
                        ? Color.white.opacity(0.08)
                        : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch editor.editorTab {
        case .captions:
            CaptionListView()
        case .styles:
            StylePickerView()
        case .overlays:
            OverlayEditorView()
        case .libraries:
            LibraryBrowserView()
        case .export:
            ExportPanelView()
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite else { return "0:00" }
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Preview pane

struct VideoPreviewPane: View {
    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        GeometryReader { geo in
            let aspect = editor.project.aspectRatio.aspectValue
            let maxW = geo.size.width
            let maxH = geo.size.height
            let width: CGFloat
            let height: CGFloat
            if maxW / maxH > aspect {
                height = maxH
                width = height * aspect
            } else {
                width = maxW
                height = width / aspect
            }

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.55))

                if let player = editor.player {
                    VideoPlayerRepresentable(player: player)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            CaptionOverlayView()
                        }
                        .overlay {
                            LiveOverlayCanvas()
                        }
                }

                VStack {
                    HStack {
                        Text(editor.project.aspectRatio.rawValue)
                            .font(.custom("AvenirNext-Bold", size: 10))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.45), in: Capsule())
                        Spacer()
                    }
                    .padding(12)
                    Spacer()
                    HStack {
                        Button {
                            editor.togglePlayback()
                        } label: {
                            Image(systemName: editor.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(14)
                                .background(.black.opacity(0.45), in: Circle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(14)
                }
            }
            .frame(width: width, height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: 280)
        .animation(.easeInOut(duration: 0.25), value: editor.project.aspectRatio)
    }
}

#if os(iOS)
struct VideoPlayerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = false
        vc.videoGravity = .resizeAspectFill
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        vc.player = player
    }
}
#elseif os(macOS)
struct VideoPlayerRepresentable: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
    }
}
#endif

struct TimelineScrubber: View {
    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { editor.currentTime },
                    set: { editor.seek(to: $0) }
                ),
                in: 0...max(editor.project.duration, 0.1)
            )
            .tint(Color(red: 0.3, green: 0.92, blue: 0.75))

            // Caption markers
            GeometryReader { geo in
                let duration = max(editor.project.duration, 0.1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    ForEach(editor.project.captions) { caption in
                        let x = caption.startTime / duration * geo.size.width
                        let w = max(2, caption.duration / duration * geo.size.width)
                        Capsule()
                            .fill(Color(red: 0.3, green: 0.92, blue: 0.75).opacity(0.7))
                            .frame(width: w, height: 6)
                            .offset(x: x)
                    }
                }
            }
            .frame(height: 6)
        }
    }
}
