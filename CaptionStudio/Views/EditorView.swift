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
            if !editor.batchExportURLs.isEmpty {
                ExportShareView(urls: editor.batchExportURLs)
                    .environmentObject(editor)
            } else if let url = editor.exportURL {
                ExportShareView(urls: [url])
                    .environmentObject(editor)
            }
        }
        .sheet(isPresented: $editor.showBrandKit) {
            BrandKitSettingsView()
                .environmentObject(editor)
        }
        .confirmationDialog("Leave editor?", isPresented: $showLeaveConfirm) {
            Button("Save Project & Leave") {
                do {
                    try editor.saveProject()
                    editor.leaveWithoutSaving()
                } catch {
                    editor.errorMessage = error.localizedDescription
                }
            }
            Button("Discard & Leave", role: .destructive) {
                editor.leaveWithoutSaving()
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

            Button {
                do {
                    _ = try editor.saveProject()
                } catch {
                    editor.errorMessage = error.localizedDescription
                }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .font(.custom("AvenirNext-DemiBold", size: 12))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.1), in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(editor.project.videoURL == nil)

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

            Menu {
                Button("None") { editor.selectPack(nil) }
                ForEach(editor.packs.packs) { pack in
                    Button {
                        editor.selectPack(pack.id)
                    } label: {
                        Label(pack.name, systemImage: pack.icon)
                    }
                }
            } label: {
                Label(
                    editor.selectedPack?.name ?? "Pack",
                    systemImage: editor.selectedPack?.icon ?? "square.stack.3d.up.fill"
                )
                .font(.custom("AvenirNext-DemiBold", size: 12))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    (editor.selectedPack?.accent ?? Color.white.opacity(0.12)).opacity(editor.selectedPack == nil ? 1 : 0.95),
                    in: Capsule()
                )
                .foregroundStyle(editor.selectedPack == nil ? .white : .black)
            }

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
        case .trim:
            TrimAssistView()
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
            let fitted: CGSize = {
                if maxW / maxH > aspect {
                    let height = maxH
                    return CGSize(width: height * aspect, height: height)
                }
                let width = maxW
                return CGSize(width: width, height: width / aspect)
            }()
            let width = fitted.width
            let height = fitted.height

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.55))

                if let player = editor.player {
                    // Player + overlays must share the aspect canvas size (same
                    // normalized space as export `renderSize`). Do not size
                    // overlays from the player view's intrinsic video aspect —
                    // that creates a smaller caption rect inside the canvas.
                    ZStack {
                        VideoPlayerRepresentable(player: player)

                        CaptionOverlayView()
                            .allowsHitTesting(false)

                        LiveOverlayCanvas()

                        if editor.showSafeZone {
                            SafeZoneGuideView(zone: editor.activeSafeZone)
                        }
                    }
                    .frame(width: width, height: height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                        Button {
                            editor.showSafeZone.toggle()
                        } label: {
                            Text(editor.showSafeZone ? "Safe zone" : "Safe off")
                                .font(.custom("AvenirNext-Bold", size: 10))
                                .foregroundStyle(editor.showSafeZone ? Color(red: 1.0, green: 0.92, blue: 0.35) : .white.opacity(0.55))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.45), in: Capsule())
                        }
                        .buttonStyle(.plain)
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

struct SafeZoneGuideView: View {
    let zone: SafeZone

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(
                x: zone.xMin * geo.size.width,
                y: zone.yMin * geo.size.height,
                width: zone.rect.width * geo.size.width,
                height: zone.rect.height * geo.size.height
            )
            ZStack {
                // Dim outside safe area
                Rectangle()
                    .fill(Color.black.opacity(0.28))
                    .mask(
                        ZStack {
                            Rectangle().fill(Color.white)
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.black)
                                .frame(width: rect.width, height: rect.height)
                                .position(x: rect.midX, y: rect.midY)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    )
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color(red: 1.0, green: 0.92, blue: 0.35).opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
            .allowsHitTesting(false)
        }
    }
}

struct TimelineScrubber: View {
    @EnvironmentObject private var editor: EditorViewModel

    private var duration: TimeInterval { max(editor.project.duration, 0.1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Slider(
                value: Binding(
                    get: { editor.currentTime },
                    set: { editor.seek(to: $0) }
                ),
                in: 0...duration
            )
            .tint(TimelineLaneStyle.captions)

            // Multi-lane timeline of placed items
            VStack(spacing: 4) {
                timelineLane(
                    title: "Caps",
                    color: TimelineLaneStyle.captions,
                    spans: editor.project.captions.map {
                        TimelineSpan(id: $0.id.uuidString, start: $0.startTime, end: $0.endTime, selected: editor.selectedCaptionID == $0.id)
                    }
                ) { span in
                    if let cap = editor.project.captions.first(where: { $0.id.uuidString == span.id }) {
                        editor.selectedCaptionID = cap.id
                        editor.seek(to: cap.startTime)
                        editor.editorTab = .captions
                    }
                }

                timelineLane(
                    title: "Hits",
                    color: TimelineLaneStyle.wordHit,
                    spans: editor.project.overlays.filter { $0.kind == .wordHit }.map {
                        TimelineSpan(id: $0.id.uuidString, start: $0.startTime, end: $0.endTime, selected: editor.selectedOverlayID == $0.id)
                    }
                ) { span in
                    selectOverlay(idString: span.id)
                }

                timelineLane(
                    title: "Stick",
                    color: TimelineLaneStyle.sticker,
                    spans: editor.project.overlays.filter { $0.kind == .gif || $0.kind == .png }.map {
                        TimelineSpan(id: $0.id.uuidString, start: $0.startTime, end: $0.endTime, selected: editor.selectedOverlayID == $0.id)
                    }
                ) { span in
                    selectOverlay(idString: span.id)
                }

                timelineLane(
                    title: "Text",
                    color: TimelineLaneStyle.text,
                    spans: editor.project.overlays.filter {
                        $0.kind == .text || $0.kind == .emoji || $0.kind == .watermark || $0.kind == .shape
                    }.map {
                        TimelineSpan(id: $0.id.uuidString, start: $0.startTime, end: $0.endTime, selected: editor.selectedOverlayID == $0.id)
                    }
                ) { span in
                    selectOverlay(idString: span.id)
                }

                timelineLane(
                    title: "Audio",
                    color: TimelineLaneStyle.audio,
                    spans: [
                        TimelineSpan(
                            id: "dialogue",
                            start: 0,
                            end: duration,
                            selected: editor.isAudioLayerSelected
                        )
                    ]
                ) { _ in
                    editor.selectAudioLayer()
                }

                timelineLane(
                    title: "SFX",
                    color: TimelineLaneStyle.sfx,
                    spans: editor.timelineSoundEffects.map { cue in
                        let len = editor.sfxDuration(for: cue)
                        return TimelineSpan(
                            id: cue.id.uuidString,
                            start: cue.startTime,
                            end: min(duration, cue.startTime + len),
                            selected: editor.selectedSoundEffectID == cue.id
                        )
                    }
                ) { span in
                    if let cue = editor.project.soundEffects.first(where: { $0.id.uuidString == span.id }) {
                        editor.selectSoundEffect(cue.id)
                        editor.seek(to: cue.startTime)
                    }
                }

                if !editor.trimSuggestions.isEmpty {
                    timelineLane(
                        title: "Trim",
                        color: TimelineLaneStyle.trim,
                        spans: editor.trimSuggestions.map {
                            TimelineSpan(
                                id: $0.id.uuidString,
                                start: $0.startTime,
                                end: $0.endTime,
                                selected: editor.selectedTrimIDs.contains($0.id)
                            )
                        }
                    ) { span in
                        if let cut = editor.trimSuggestions.first(where: { $0.id.uuidString == span.id }) {
                            if editor.selectedTrimIDs.contains(cut.id) {
                                editor.selectedTrimIDs.remove(cut.id)
                            } else {
                                editor.selectedTrimIDs.insert(cut.id)
                            }
                            editor.seek(to: cut.startTime)
                            editor.editorTab = .trim
                        }
                    }
                }
            }
        }
    }

    private func selectOverlay(idString: String) {
        guard let item = editor.project.overlays.first(where: { $0.id.uuidString == idString }) else { return }
        editor.selectedOverlayID = item.id
        editor.selectedSoundEffectID = nil
        editor.isAudioLayerSelected = false
        editor.seek(to: item.startTime)
        editor.editorTab = .overlays
    }

    private func timelineLane(
        title: String,
        color: Color,
        spans: [TimelineSpan],
        markerOnly: Bool = false,
        onTap: @escaping (TimelineSpan) -> Void
    ) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.custom("AvenirNext-Medium", size: 9))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 28, alignment: .leading)

            GeometryReader { geo in
                let w = max(geo.size.width, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    ForEach(spans) { span in
                        let x = CGFloat(span.start / duration) * w
                        let width = markerOnly
                            ? 3
                            : max(3, CGFloat((span.end - span.start) / duration) * w)
                        Capsule()
                            .fill(color.opacity(span.selected ? 0.95 : 0.55))
                            .frame(width: width, height: markerOnly ? 10 : 8)
                            .offset(x: x)
                            .contentShape(Rectangle())
                            .onTapGesture { onTap(span) }
                    }
                    // Playhead
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 1.5, height: 12)
                        .offset(x: CGFloat(editor.currentTime / duration) * w)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 12)
        }
        .frame(height: 14)
    }
}

private struct TimelineSpan: Identifiable {
    var id: String
    var start: TimeInterval
    var end: TimeInterval
    var selected: Bool
}
