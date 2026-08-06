import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct OverlayEditorView: View {
    @EnvironmentObject private var editor: EditorViewModel

    private let emojiPalette = ["🔥", "✨", "💥", "😂", "❤️", "🙌", "⚡", "🎯", "🚀", "💯"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Timeline layers")
                    .font(.custom("AvenirNext-Bold", size: 15))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(editor.project.overlays.count) overlays · \(editor.project.soundEffects.count) SFX")
                    .font(.custom("AvenirNext-Medium", size: 10))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)

            Text("Audio layer controls dialogue + every SFX. Visual layers sit below.")
                .font(.custom("AvenirNext-Medium", size: 11))
                .foregroundStyle(.white.opacity(0.4))
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

            ScrollView {
                LazyVStack(spacing: 8) {
                    AudioLayerPanel()

                    if !editor.timelineOverlays.isEmpty {
                        Text("Visual layers")
                            .font(.custom("AvenirNext-DemiBold", size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)

                        ForEach(editor.timelineOverlays) { item in
                            OverlayLayerRow(
                                item: item,
                                duration: max(editor.project.duration, 0.1),
                                currentTime: editor.currentTime,
                                isSelected: editor.selectedOverlayID == item.id
                            ) {
                                editor.selectedOverlayID = item.id
                                editor.selectedSoundEffectID = nil
                                editor.isAudioLayerSelected = false
                                editor.seek(to: item.startTime)
                            } onDelete: {
                                editor.deleteOverlay(item.id)
                            } onChange: { updated in
                                editor.updateOverlay(updated)
                            }
                        }
                    } else if editor.project.soundEffects.isEmpty {
                        Text("Run AI Place or add stickers — they show up here as adjustable layers.")
                            .font(.custom("AvenirNext-Medium", size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
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

/// Dialogue enhancers + every SFX cue on the Audio layer.
struct AudioLayerPanel: View {
    @EnvironmentObject private var editor: EditorViewModel

    private var audio: ProjectAudioSettings { editor.project.audio }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TimelineLaneStyle.audio)
                Text("Audio layer")
                    .font(.custom("AvenirNext-Bold", size: 14))
                    .foregroundStyle(.white)
                Spacer()
                Text(audio.enhancerPreset.title)
                    .font(.custom("AvenirNext-Medium", size: 10))
                    .foregroundStyle(TimelineLaneStyle.audio.opacity(0.9))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(TimelineLaneStyle.audio.opacity(0.18), in: Capsule())
            }

            Text("Enhancers")
                .font(.custom("AvenirNext-Medium", size: 11))
                .foregroundStyle(.white.opacity(0.45))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(AudioEnhancerPreset.allCases) { preset in
                    Button {
                        editor.applyAudioEnhancer(preset)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Label(preset.title, systemImage: preset.systemImage)
                                .font(.custom("AvenirNext-DemiBold", size: 12))
                                .foregroundStyle(audio.enhancerPreset == preset ? .black : .white)
                            Text(preset.subtitle)
                                .font(.custom("AvenirNext-Medium", size: 9))
                                .foregroundStyle(audio.enhancerPreset == preset ? .black.opacity(0.65) : .white.opacity(0.4))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(
                            audio.enhancerPreset == preset
                            ? TimelineLaneStyle.audio
                            : Color.white.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            audioSlider(
                label: "Dialogue",
                value: Binding(
                    get: { audio.dialogueGain },
                    set: { v in
                        var next = audio
                        next.dialogueGain = v
                        editor.updateAudioSettings(next)
                    }
                ),
                range: 0.25...2.0,
                format: { String(format: "%.2f×", $0) }
            )

            audioSlider(
                label: "SFX bus",
                value: Binding(
                    get: { audio.sfxMasterGain },
                    set: { v in
                        var next = audio
                        next.sfxMasterGain = v
                        editor.updateAudioSettings(next)
                    }
                ),
                range: 0.1...1.5,
                format: { String(format: "%.2f×", $0) }
            )

            Toggle(isOn: Binding(
                get: { audio.normalizeLoudness },
                set: { on in
                    var next = audio
                    next.normalizeLoudness = on
                    editor.updateAudioSettings(next)
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Normalize loudness")
                        .font(.custom("AvenirNext-DemiBold", size: 12))
                        .foregroundStyle(.white)
                    Text("Peak-match dialogue on export")
                        .font(.custom("AvenirNext-Medium", size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .tint(TimelineLaneStyle.audio)

            Toggle(isOn: Binding(
                get: { audio.duckDialogueUnderSFX },
                set: { on in
                    var next = audio
                    next.duckDialogueUnderSFX = on
                    editor.updateAudioSettings(next)
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Duck under SFX")
                        .font(.custom("AvenirNext-DemiBold", size: 12))
                        .foregroundStyle(.white)
                    Text("Lower dialogue while effects play")
                        .font(.custom("AvenirNext-Medium", size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .tint(TimelineLaneStyle.audio)

            if audio.duckDialogueUnderSFX {
                audioSlider(
                    label: "Duck",
                    value: Binding(
                        get: { audio.duckAmount },
                        set: { v in
                            var next = audio
                            next.duckAmount = v
                            editor.updateAudioSettings(next)
                        }
                    ),
                    range: 0.1...0.85,
                    format: { String(format: "%.0f%%", $0 * 100) }
                )
            }

            HStack {
                Text("Effects on this layer")
                    .font(.custom("AvenirNext-DemiBold", size: 12))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                Text("\(editor.project.soundEffects.count)")
                    .font(.custom("AvenirNext-Medium", size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.top, 4)

            if editor.timelineSoundEffects.isEmpty {
                Text("Drop SFX from Library or run AI Place — every effect lands here.")
                    .font(.custom("AvenirNext-Medium", size: 12))
                    .foregroundStyle(.white.opacity(0.35))
            } else {
                ForEach(editor.timelineSoundEffects) { cue in
                    SFXLayerRow(
                        cue: cue,
                        duration: max(editor.project.duration, 0.1),
                        cueLength: editor.sfxDuration(for: cue),
                        currentTime: editor.currentTime,
                        isSelected: editor.selectedSoundEffectID == cue.id
                    ) {
                        editor.selectSoundEffect(cue.id)
                        editor.seek(to: cue.startTime)
                        editor.previewSFX(cue)
                    } onDelete: {
                        editor.deleteSoundEffect(cue.id)
                    } onChange: { updated in
                        editor.updateSoundEffect(updated)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.white.opacity(editor.isAudioLayerSelected ? 0.1 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            TimelineLaneStyle.audio.opacity(editor.isAudioLayerSelected ? 0.7 : 0.35),
                            lineWidth: 1
                        )
                )
        )
        .onTapGesture {
            editor.selectAudioLayer()
        }
    }

    private func audioSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        format: @escaping (Double) -> String
    ) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 58, alignment: .leading)
            Slider(value: value, in: range)
                .tint(TimelineLaneStyle.audio)
            Text(format(value.wrappedValue))
                .font(.custom("AvenirNext-Medium", size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 42, alignment: .trailing)
        }
    }
}

struct OverlayLayerRow: View {
    let item: OverlayItem
    var duration: TimeInterval
    var currentTime: TimeInterval
    var isSelected: Bool
    var onSelect: () -> Void
    var onDelete: () -> Void
    var onChange: (OverlayItem) -> Void

    @State private var draft: OverlayItem

    init(
        item: OverlayItem,
        duration: TimeInterval,
        currentTime: TimeInterval,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onChange: @escaping (OverlayItem) -> Void
    ) {
        self.item = item
        self.duration = duration
        self.currentTime = currentTime
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onChange = onChange
        _draft = State(initialValue: item)
    }

    private var isLive: Bool { item.isVisible(at: currentTime) }

    private var title: String {
        switch item.kind {
        case .emoji: return item.text
        case .wordHit: return item.text.isEmpty ? "Word hit" : item.text
        case .gif, .png: return item.text.isEmpty ? item.kind.label : item.text
        default: return item.text.isEmpty ? item.kind.label : item.text
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TimelineLaneStyle.color(for: item.kind))
                    .frame(width: 18)

                Text(title)
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(item.kind.label.uppercased())
                    .font(.custom("AvenirNext-Medium", size: 9))
                    .foregroundStyle(TimelineLaneStyle.color(for: item.kind).opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(TimelineLaneStyle.color(for: item.kind).opacity(0.15), in: Capsule())

                if isLive {
                    Text("LIVE")
                        .font(.custom("AvenirNext-Bold", size: 9))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(red: 0.4, green: 0.95, blue: 0.8), in: Capsule())
                }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }

            // Mini span bar
            GeometryReader { geo in
                let w = max(geo.size.width, 1)
                let x = CGFloat(draft.startTime / duration) * w
                let width = max(4, CGFloat((draft.endTime - draft.startTime) / duration) * w)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(TimelineLaneStyle.color(for: item.kind).opacity(isSelected ? 0.95 : 0.55))
                        .frame(width: width)
                        .offset(x: x)
                    // Playhead tick
                    Rectangle()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 1.5)
                        .offset(x: CGFloat(currentTime / duration) * w)
                }
            }
            .frame(height: 8)

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
                    .lineLimit(2)
            }

            timingSlider(
                label: "Start",
                value: Binding(
                    get: { draft.startTime },
                    set: { newStart in
                        var updated = draft
                        let clamped = min(max(0, newStart), max(0, duration - 0.1))
                        updated.startTime = clamped
                        if updated.endTime <= clamped + 0.05 {
                            updated.endTime = min(duration, clamped + 0.4)
                        }
                        draft = updated
                        onChange(updated)
                    }
                ),
                range: 0...max(duration, 0.1)
            )

            timingSlider(
                label: "End",
                value: Binding(
                    get: { draft.endTime },
                    set: { newEnd in
                        var updated = draft
                        let minEnd = updated.startTime + 0.05
                        updated.endTime = min(duration, max(minEnd, newEnd))
                        draft = updated
                        onChange(updated)
                    }
                ),
                range: 0...max(duration, 0.1)
            )

            HStack {
                Text("Scale")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 40, alignment: .leading)
                Slider(value: $draft.scale, in: 0.5...2.5)
                    .tint(TimelineLaneStyle.color(for: item.kind))
                    .onChange(of: draft.scale) { _, v in
                        var updated = draft
                        updated.scale = v
                        onChange(updated)
                    }
                Text(String(format: "%.1f×", draft.scale))
                    .font(.custom("AvenirNext-Medium", size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isSelected ? 0.12 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isSelected ? TimelineLaneStyle.color(for: item.kind).opacity(0.55) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
        .onTapGesture(perform: onSelect)
        .onChange(of: item) { _, newValue in
            draft = newValue
        }
    }

    private func timingSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 40, alignment: .leading)
            Slider(value: value, in: range)
                .tint(TimelineLaneStyle.color(for: item.kind))
            Text(String(format: "%.1fs", value.wrappedValue))
                .font(.custom("AvenirNext-Medium", size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 36, alignment: .trailing)
        }
    }
}

struct SFXLayerRow: View {
    let cue: SoundEffectCue
    var duration: TimeInterval
    var cueLength: TimeInterval
    var currentTime: TimeInterval
    var isSelected: Bool
    var onSelect: () -> Void
    var onDelete: () -> Void
    var onChange: (SoundEffectCue) -> Void

    @State private var draft: SoundEffectCue

    init(
        cue: SoundEffectCue,
        duration: TimeInterval,
        cueLength: TimeInterval,
        currentTime: TimeInterval,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onChange: @escaping (SoundEffectCue) -> Void
    ) {
        self.cue = cue
        self.duration = duration
        self.cueLength = cueLength
        self.currentTime = currentTime
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onChange = onChange
        _draft = State(initialValue: cue)
    }

    private var isLive: Bool {
        currentTime >= cue.startTime && currentTime <= cue.startTime + cueLength
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: draft.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(TimelineLaneStyle.sfx.opacity(draft.isMuted ? 0.4 : 1))
                Text(cue.assetId)
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .foregroundStyle(.white.opacity(draft.isMuted ? 0.45 : 1))
                    .lineLimit(1)
                if isLive && !draft.isMuted {
                    Text("LIVE")
                        .font(.custom("AvenirNext-Bold", size: 9))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(TimelineLaneStyle.sfx, in: Capsule())
                }
                Spacer()
                Button {
                    var updated = draft
                    updated.isMuted.toggle()
                    draft = updated
                    onChange(updated)
                } label: {
                    Image(systemName: draft.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .foregroundStyle(draft.isMuted ? .white.opacity(0.35) : TimelineLaneStyle.sfx)
                }
                .buttonStyle(.plain)
                Button(action: onSelect) {
                    Image(systemName: "play.fill")
                        .foregroundStyle(TimelineLaneStyle.sfx.opacity(draft.isMuted ? 0.35 : 1))
                }
                .buttonStyle(.plain)
                .disabled(draft.isMuted)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.white.opacity(0.35))
                }
                .buttonStyle(.plain)
            }

            GeometryReader { geo in
                let w = max(geo.size.width, 1)
                let x = CGFloat(draft.startTime / duration) * w
                let width = max(4, CGFloat(cueLength / duration) * w)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(TimelineLaneStyle.sfx.opacity(draft.isMuted ? 0.25 : (isSelected ? 0.95 : 0.55)))
                        .frame(width: width)
                        .offset(x: x)
                    Rectangle()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 1.5)
                        .offset(x: CGFloat(currentTime / duration) * w)
                }
            }
            .frame(height: 8)

            if let reason = cue.reason {
                Text(reason)
                    .font(.custom("AvenirNext-Medium", size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(2)
            }

            HStack {
                Text("Start")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 40, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { draft.startTime },
                        set: { t in
                            var updated = draft
                            updated.startTime = min(max(0, t), duration)
                            draft = updated
                            onChange(updated)
                        }
                    ),
                    in: 0...max(duration, 0.1)
                )
                .tint(TimelineLaneStyle.sfx)
                Text(String(format: "%.1fs", draft.startTime))
                    .font(.custom("AvenirNext-Medium", size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 36, alignment: .trailing)
            }

            HStack {
                Text("Gain")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(width: 40, alignment: .leading)
                Slider(
                    value: Binding(
                        get: { draft.gain },
                        set: { g in
                            var updated = draft
                            updated.gain = g
                            draft = updated
                            onChange(updated)
                        }
                    ),
                    in: 0.05...1.2
                )
                .tint(TimelineLaneStyle.sfx)
                .disabled(draft.isMuted)
                Text(String(format: "%.2f", draft.gain))
                    .font(.custom("AvenirNext-Medium", size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(isSelected ? 0.12 : 0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            isSelected ? TimelineLaneStyle.sfx.opacity(0.55) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
        .onTapGesture(perform: onSelect)
        .onChange(of: cue) { _, newValue in
            draft = newValue
        }
    }
}

enum TimelineLaneStyle {
    static let captions = Color(red: 0.3, green: 0.92, blue: 0.75)
    static let wordHit = Color(red: 1.0, green: 0.94, blue: 0.35)
    static let sticker = Color(red: 1.0, green: 0.45, blue: 0.75)
    static let text = Color(red: 0.55, green: 0.75, blue: 1.0)
    static let trim = Color(red: 1.0, green: 0.55, blue: 0.2)
    static let sfx = Color(red: 0.7, green: 0.55, blue: 1.0)
    static let audio = Color(red: 0.35, green: 0.85, blue: 0.95)

    static func color(for kind: OverlayKind) -> Color {
        switch kind {
        case .wordHit: return wordHit
        case .gif, .png: return sticker
        case .text, .watermark, .emoji: return text
        case .shape: return captions
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

            Toggle(isOn: $editor.normalizeLoudness) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Normalize loudness")
                        .font(.custom("AvenirNext-DemiBold", size: 13))
                        .foregroundStyle(.white)
                    Text("Keeps dialogue + SFX levels consistent across posts")
                        .font(.custom("AvenirNext-Medium", size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .tint(Color(red: 0.15, green: 0.9, blue: 0.72))
            .padding(.horizontal, 16)

            if let dist = editor.distribution {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Post copy")
                        .font(.custom("AvenirNext-Medium", size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(dist.title)
                        .font(.custom("AvenirNext-DemiBold", size: 13))
                        .foregroundStyle(.white)
                    Text(dist.hashtagLine)
                        .font(.custom("AvenirNext-Medium", size: 11))
                        .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.8).opacity(0.85))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
            }

            VStack(alignment: .leading, spacing: 8) {
                summaryRow("Canvas", "\(Int(editor.project.aspectRatio.canvasSize.width))×\(Int(editor.project.aspectRatio.canvasSize.height))")
                if let pack = editor.selectedPack {
                    summaryRow("Pack", pack.name)
                }
                summaryRow("Captions", "\(editor.project.captions.count)")
                summaryRow("Overlays", "\(editor.project.overlays.count)")
                summaryRow("Sound FX", "\(editor.project.soundEffects.count)")
                summaryRow("Audio", editor.project.audio.enhancerPreset.title)
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

            Button {
                do {
                    _ = try editor.saveProject()
                } catch {
                    editor.errorMessage = error.localizedDescription
                }
            } label: {
                Label("Save Project", systemImage: "square.and.arrow.down")
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.1), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(editor.project.videoURL == nil)
            .padding(.horizontal, 16)

            #if os(macOS)
            Button {
                exportPortablePackage()
            } label: {
                Label("Export package…", systemImage: "folder.badge.plus")
                    .font(.custom("AvenirNext-DemiBold", size: 13))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(editor.project.videoURL == nil)
            .padding(.horizontal, 16)
            #endif

            if let draftMessage = editor.draftMessage {
                Text(draftMessage)
                    .font(.custom("AvenirNext-Medium", size: 11))
                    .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.8).opacity(0.8))
                    .padding(.horizontal, 16)
            }

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
            editor.ensureDistribution()
        }
    }

    #if os(macOS)
    private func exportPortablePackage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Export Here"
        panel.message = "Choose a folder for the .captionstudio package (project.json + video)."
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            let package = try editor.exportProjectPackage(to: directory)
            editor.draftMessage = "Exported \(package.lastPathComponent)"
        } catch {
            editor.errorMessage = error.localizedDescription
        }
    }
    #endif

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
    @EnvironmentObject private var editor: EditorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var copyFlash: String?
    @State private var isMakingCover = false

    init(url: URL) {
        self.urls = [url]
    }

    init(urls: [URL]) {
        self.urls = urls
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color(red: 0.3, green: 0.92, blue: 0.75))
                        .padding(.top, 24)

                    Text(urls.count > 1 ? "Ready to share (\(urls.count))" : "Ready to share")
                        .font(.custom("AvenirNext-Heavy", size: 24))
                        .foregroundStyle(.white)

                    if let dist = editor.distribution {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Post copy")
                                .font(.custom("AvenirNext-Bold", size: 13))
                                .foregroundStyle(.white.opacity(0.55))

                            copyBlock(label: "Title", value: dist.title)
                            if let hook = dist.hookLine, !hook.isEmpty {
                                copyBlock(label: "Hook", value: hook)
                            }
                            copyBlock(label: "Hashtags", value: dist.hashtagLine)
                            copyBlock(label: "Cover text", value: dist.coverText)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 20)

                        if let flash = copyFlash {
                            Text(flash)
                                .font(.custom("AvenirNext-Medium", size: 12))
                                .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.8))
                        }

                        Button {
                            isMakingCover = true
                            Task {
                                await editor.exportCoverImage()
                                isMakingCover = false
                            }
                        } label: {
                            Label(
                                isMakingCover
                                ? "Making cover…"
                                : (editor.coverURL == nil ? "Export cover PNG" : "Refresh cover PNG"),
                                systemImage: "photo"
                            )
                            .font(.custom("AvenirNext-DemiBold", size: 14))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(red: 1.0, green: 0.92, blue: 0.35), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isMakingCover)
                        .padding(.horizontal, 24)

                        if let coverURL = editor.coverURL {
                            ShareLink(item: coverURL) {
                                Label("Share cover", systemImage: "square.and.arrow.up")
                                    .font(.custom("AvenirNext-DemiBold", size: 14))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(Color.white.opacity(0.12), in: Capsule())
                            }
                            .padding(.horizontal, 24)
                        }
                    }

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
                }
                .padding(.bottom, 32)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.05, green: 0.08, blue: 0.1).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                editor.ensureDistribution()
            }
        }
    }

    @ViewBuilder
    private func copyBlock(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.custom("AvenirNext-Medium", size: 11))
                .foregroundStyle(.white.opacity(0.4))
            HStack(alignment: .top) {
                Text(value)
                    .font(.custom("AvenirNext-DemiBold", size: 14))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    copyToPasteboard(value)
                    copyFlash = "Copied \(label.lowercased())"
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.15, green: 0.9, blue: 0.72))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func copyToPasteboard(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #elseif os(macOS)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(string, forType: .string)
        #endif
    }
}
