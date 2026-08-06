import SwiftUI

struct OverlayEditorView: View {
    @EnvironmentObject private var editor: EditorViewModel

    private let emojiPalette = ["🔥", "✨", "💥", "😂", "❤️", "🙌", "⚡", "🎯", "🚀", "💯"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overlays")
                .font(.custom("AvenirNext-Bold", size: 15))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            HStack(spacing: 8) {
                addButton("Text", icon: "textformat") {
                    editor.addTextOverlay()
                }
                addButton("Shape", icon: "circle.fill") {
                    var item = OverlayItem.textSticker("●", at: editor.currentTime)
                    item.kind = .shape
                    item.shape = .circle
                    item.color = CodableColor(r: 0.2, g: 0.95, b: 0.75, a: 0.9)
                    item.text = ""
                    editor.project.overlays.append(item)
                    editor.selectedOverlayID = item.id
                }
            }
            .padding(.horizontal, 16)

            Text("Emojis")
                .font(.custom("AvenirNext-Medium", size: 12))
                .foregroundStyle(.white.opacity(0.45))
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(emojiPalette, id: \.self) { emoji in
                        Button {
                            editor.addEmojiOverlay(emoji)
                        } label: {
                            Text(emoji)
                                .font(.system(size: 28))
                                .frame(width: 48, height: 48)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            if editor.project.overlays.isEmpty {
                Text("Add text, emojis, or shapes timed to your clip.")
                    .font(.custom("AvenirNext-Medium", size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(editor.project.overlays) { item in
                            OverlayRow(
                                item: item,
                                isSelected: editor.selectedOverlayID == item.id
                            ) {
                                editor.selectedOverlayID = item.id
                                editor.seek(to: item.startTime)
                            } onDelete: {
                                editor.deleteOverlay(item.id)
                            } onChange: { updated in
                                editor.updateOverlay(updated)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private func addButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.custom("AvenirNext-DemiBold", size: 13))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

struct OverlayRow: View {
    let item: OverlayItem
    var isSelected: Bool
    var onSelect: () -> Void
    var onDelete: () -> Void
    var onChange: (OverlayItem) -> Void

    @State private var draft: OverlayItem

    init(
        item: OverlayItem,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onChange: @escaping (OverlayItem) -> Void
    ) {
        self.item = item
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onChange = onChange
        _draft = State(initialValue: item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.kind == .emoji ? item.text : item.kind.label)
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .foregroundStyle(.white)
                Spacer()
                Text(String(format: "%.1f–%.1fs", item.startTime, item.endTime))
                    .font(.custom("AvenirNext-Medium", size: 10))
                    .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.8).opacity(0.7))
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }

            if item.kind == .text || item.kind == .watermark {
                TextField("Overlay text", text: $draft.text)
                    .font(.custom("AvenirNext-Medium", size: 14))
                    .foregroundStyle(.white)
                    .onChange(of: draft.text) { _, newValue in
                        var updated = draft
                        updated.text = newValue
                        onChange(updated)
                    }
            }

            if let reason = item.reason {
                Text(reason)
                    .font(.custom("AvenirNext-Medium", size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }

            HStack {
                Text("Scale")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                Slider(value: $draft.scale, in: 0.5...2.5)
                    .tint(Color(red: 0.3, green: 0.92, blue: 0.75))
                    .onChange(of: draft.scale) { _, v in
                        var updated = draft
                        updated.scale = v
                        onChange(updated)
                    }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isSelected ? 0.1 : 0.05))
        )
        .onTapGesture(perform: onSelect)
        .onChange(of: item) { _, newValue in
            draft = newValue
        }
    }
}

struct ExportPanelView: View {
    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Export")
                .font(.custom("AvenirNext-Bold", size: 15))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 10) {
                Text("Aspect ratio")
                    .font(.custom("AvenirNext-Medium", size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 8) {
                    ForEach(AspectRatioPreset.allCases) { aspect in
                        Button {
                            editor.setAspectRatio(aspect)
                        } label: {
                            Label(aspect.rawValue, systemImage: aspect.systemImage)
                                .font(.custom("AvenirNext-DemiBold", size: 12))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    editor.project.aspectRatio == aspect
                                    ? Color(red: 0.15, green: 0.9, blue: 0.72)
                                    : Color.white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .foregroundStyle(editor.project.aspectRatio == aspect ? .black : .white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)

            PackPickerView(compact: true)
                .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 10) {
                Text("Batch export")
                    .font(.custom("AvenirNext-Medium", size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 8) {
                    ForEach(AspectRatioPreset.allCases) { aspect in
                        let on = editor.batchExportAspects.contains(aspect)
                        Button {
                            editor.toggleBatchAspect(aspect)
                        } label: {
                            Label(aspect.rawValue, systemImage: on ? "checkmark.square.fill" : "square")
                                .font(.custom("AvenirNext-DemiBold", size: 12))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    on ? Color(red: 1.0, green: 0.92, blue: 0.35) : Color.white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                                .foregroundStyle(on ? .black : .white)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)

            VStack(alignment: .leading, spacing: 8) {
                summaryRow("Canvas", "\(Int(editor.project.aspectRatio.canvasSize.width))×\(Int(editor.project.aspectRatio.canvasSize.height))")
                if let pack = editor.selectedPack {
                    summaryRow("Pack", pack.name)
                }
                summaryRow("Captions", "\(editor.project.captions.count)")
                summaryRow("Overlays", "\(editor.project.overlays.count)")
                summaryRow("Sound FX", "\(editor.project.soundEffects.count)")
                summaryRow("Parts", "\(max(1, editor.project.chunkCount))")
                summaryRow("Duration", String(format: "%.1fs", editor.project.duration))
                if let note = editor.lastEnhancementNote {
                    Text(note)
                        .font(.custom("AvenirNext-Medium", size: 11))
                        .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.8).opacity(0.8))
                        .padding(.top, 4)
                }
                if let chunk = editor.chunkProgressLabel {
                    Text(chunk)
                        .font(.custom("AvenirNext-Medium", size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)

            if editor.isExporting {
                VStack(spacing: 8) {
                    ProgressView(value: max(editor.exporter.progress, editor.stitcher.progress))
                        .tint(Color(red: 0.3, green: 0.92, blue: 0.75))
                    Text(editor.chunkProgressLabel
                         ?? (editor.stitcher.statusMessage.isEmpty ? editor.exporter.statusMessage : editor.stitcher.statusMessage))
                        .font(.custom("AvenirNext-Medium", size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 16)
            }

            Button {
                Task { await editor.exportVideo() }
            } label: {
                Label(
                    editor.isExporting
                    ? "Working…"
                    : (editor.project.chunkCount > 1
                       ? "Export \(editor.project.chunkCount) parts + stitch"
                       : "Export MP4"),
                    systemImage: "square.and.arrow.up"
                )
                .font(.custom("AvenirNext-DemiBold", size: 16))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(red: 0.15, green: 0.9, blue: 0.72), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(editor.isExporting || editor.project.videoURL == nil)
            .padding(.horizontal, 16)

            Button {
                Task { await editor.exportBatch() }
            } label: {
                Label(
                    editor.isExporting
                    ? "Working…"
                    : "Export all selected (\(editor.batchExportAspects.count))",
                    systemImage: "square.stack.3d.up.fill"
                )
                .font(.custom("AvenirNext-DemiBold", size: 14))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(red: 1.0, green: 0.92, blue: 0.35), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(editor.isExporting || editor.project.videoURL == nil || editor.batchExportAspects.isEmpty)
            .padding(.horizontal, 16)

            Button {
                editor.showBrandKit = true
            } label: {
                Label("Brand Kit", systemImage: "paintbrush.pointed.fill")
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            Text(editor.project.duration > VideoChunkPlanner.singlePassLimit
                 ? "Long video: processed in \(VideoChunkPlanner.defaultChunkSeconds, specifier: "%.0f")s parts, then stitched frame-accurately."
                 : "Single-pass export on the selected aspect canvas. Batch export writes one file per checked aspect.")
                .font(.custom("AvenirNext-Medium", size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 16)

            Spacer()
        }
        .padding(.top, 8)
        .onAppear {
            editor.project.chunkCount = VideoChunkPlanner.chunks(duration: editor.project.duration).count
            if editor.batchExportAspects.isEmpty {
                editor.batchExportAspects = [editor.project.aspectRatio]
            }
        }
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.custom("AvenirNext-Medium", size: 13))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            Text(value)
                .font(.custom("AvenirNext-DemiBold", size: 13))
                .foregroundStyle(.white)
        }
    }
}

struct ExportShareView: View {
    let urls: [URL]
    @Environment(\.dismiss) private var dismiss

    init(url: URL) {
        self.urls = [url]
    }

    init(urls: [URL]) {
        self.urls = urls
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color(red: 0.3, green: 0.92, blue: 0.75))
                    .padding(.top, 24)

                Text(urls.count > 1 ? "Ready to share (\(urls.count))" : "Ready to share")
                    .font(.custom("AvenirNext-Heavy", size: 24))
                    .foregroundStyle(.white)

                ForEach(urls, id: \.self) { url in
                    VStack(spacing: 8) {
                        Text(url.lastPathComponent)
                            .font(.custom("AvenirNext-Medium", size: 13))
                            .foregroundStyle(.white.opacity(0.5))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        ShareLink(item: url) {
                            Label(urls.count > 1 ? "Share \(url.lastPathComponent)" : "Share Video", systemImage: "square.and.arrow.up")
                                .font(.custom("AvenirNext-DemiBold", size: 15))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(red: 0.15, green: 0.9, blue: 0.72), in: Capsule())
                        }
                        .padding(.horizontal, 24)
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.05, green: 0.08, blue: 0.1).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
