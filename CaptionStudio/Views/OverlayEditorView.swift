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

            VStack(alignment: .leading, spacing: 8) {
                summaryRow("Captions", "\(editor.project.captions.count)")
                summaryRow("Overlays", "\(editor.project.overlays.count)")
                summaryRow("Style", editor.selectedPreset.rawValue)
                summaryRow("Duration", String(format: "%.1fs", editor.project.duration))
            }
            .padding(14)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 16)

            if editor.isExporting {
                VStack(spacing: 8) {
                    ProgressView(value: editor.exporter.progress)
                        .tint(Color(red: 0.3, green: 0.92, blue: 0.75))
                    Text(editor.exporter.statusMessage)
                        .font(.custom("AvenirNext-Medium", size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.horizontal, 16)
            }

            Button {
                Task { await editor.exportVideo() }
            } label: {
                Label(
                    editor.isExporting ? "Exporting…" : "Export MP4",
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

            Spacer()
        }
        .padding(.top, 8)
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
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color(red: 0.3, green: 0.92, blue: 0.75))
                    .padding(.top, 24)

                Text("Ready to share")
                    .font(.custom("AvenirNext-Heavy", size: 24))
                    .foregroundStyle(.white)

                Text(url.lastPathComponent)
                    .font(.custom("AvenirNext-Medium", size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                ShareLink(item: url) {
                    Label("Share Video", systemImage: "square.and.arrow.up")
                        .font(.custom("AvenirNext-DemiBold", size: 16))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.15, green: 0.9, blue: 0.72), in: Capsule())
                }
                .padding(.horizontal, 24)

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
