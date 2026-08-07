import SwiftUI

struct CaptionListView: View {
    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Captions")
                    .font(.custom("AvenirNext-Bold", size: 15))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(editor.project.captions.count)")
                    .font(.custom("AvenirNext-Medium", size: 12))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 16)

            if editor.project.captions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach($editor.project.captions) { $caption in
                            CaptionRow(
                                caption: $caption,
                                isSelected: editor.selectedCaptionID == caption.id,
                                isActive: caption.contains(time: editor.currentTime)
                            ) {
                                editor.selectedCaptionID = caption.id
                                editor.seek(to: caption.startTime)
                            } onDelete: {
                                editor.deleteCaption(caption.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            }
        }
        .padding(.top, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 28))
                .foregroundStyle(Color(red: 0.3, green: 0.92, blue: 0.75).opacity(0.7))
            Text("Pick తెలుగు + EN (or हिन्दी + EN) for mixed speech, then tap AI Captions.")
                .font(.custom("AvenirNext-Medium", size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct CaptionRow: View {
    @Binding var caption: CaptionSegment
    var isSelected: Bool
    var isActive: Bool
    var onSelect: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(timeLabel)
                    .font(.custom("AvenirNext-Medium", size: 11))
                    .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.8))
                Spacer()
                if isActive {
                    Text("LIVE")
                        .font(.custom("AvenirNext-Bold", size: 9))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.4, green: 0.95, blue: 0.8), in: Capsule())
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }

            TextField("Caption text", text: $caption.text, axis: .vertical)
                .font(.custom("AvenirNext-Medium", size: 14))
                .foregroundStyle(.white)
                .lineLimit(1...3)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(isSelected || isActive ? 0.1 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isSelected
                            ? Color(red: 0.3, green: 0.92, blue: 0.75).opacity(0.6)
                            : Color.clear,
                            lineWidth: 1
                        )
                )
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var timeLabel: String {
        String(format: "%.1fs – %.1fs", caption.startTime, caption.endTime)
    }
}

struct StylePickerView: View {
    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Caption styles")
                .font(.custom("AvenirNext-Bold", size: 15))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CaptionPreset.allCases) { preset in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                editor.applyPreset(preset)
                            }
                        } label: {
                            VStack(spacing: 8) {
                                Text(previewLabel(for: preset))
                                    .font(.custom(preset.style.fontName, size: 13))
                                    .foregroundStyle(preset.style.textColor.color)
                                    .shadow(
                                        color: preset.style.shadowColor.color,
                                        radius: min(preset.style.shadowRadius, 6)
                                    )
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 10)
                                    .frame(width: 110, height: 64)
                                    .background(
                                        LinearGradient(
                                            colors: [
                                                Color(red: 0.12, green: 0.18, blue: 0.2),
                                                Color(red: 0.08, green: 0.1, blue: 0.12)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(
                                                editor.selectedPreset == preset
                                                ? Color(red: 0.3, green: 0.92, blue: 0.75)
                                                : Color.white.opacity(0.08),
                                                lineWidth: editor.selectedPreset == preset ? 2 : 1
                                            )
                                    )

                                Text(preset.rawValue)
                                    .font(.custom("AvenirNext-Medium", size: 11))
                                    .foregroundStyle(
                                        editor.selectedPreset == preset
                                        ? Color(red: 0.4, green: 0.95, blue: 0.8)
                                        : .white.opacity(0.5)
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Position")
                    .font(.custom("AvenirNext-Medium", size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                HStack {
                    Text("X")
                        .foregroundStyle(.white.opacity(0.4))
                        .font(.caption)
                    Slider(
                        value: Binding(
                            get: { editor.project.captionStyle.positionX },
                            set: { editor.project.captionStyle.positionX = $0 }
                        ),
                        in: 0.2...0.8
                    )
                    .tint(Color(red: 0.3, green: 0.92, blue: 0.75))
                }
                HStack {
                    Text("Y")
                        .foregroundStyle(.white.opacity(0.4))
                        .font(.caption)
                    Slider(
                        value: Binding(
                            get: { editor.project.captionStyle.positionY },
                            set: { editor.project.captionStyle.positionY = $0 }
                        ),
                        in: 0.55...0.92
                    )
                    .tint(Color(red: 0.3, green: 0.92, blue: 0.75))
                }
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private func previewLabel(for preset: CaptionPreset) -> String {
        preset.style.textCase.apply("Style")
    }
}
