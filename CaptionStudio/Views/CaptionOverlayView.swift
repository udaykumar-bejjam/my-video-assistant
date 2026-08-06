import SwiftUI

/// Live caption rendering synced to playback time.
struct CaptionOverlayView: View {
    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        GeometryReader { geo in
            let style = editor.project.captionStyle
            if let caption = editor.activeCaption {
                AnimatedCaptionText(
                    caption: caption,
                    style: style,
                    time: editor.currentTime
                )
                .position(
                    x: geo.size.width * style.positionX,
                    y: geo.size.height * style.positionY
                )
                .transition(transition(for: style.animation))
                .id(caption.id)
            }
        }
        .allowsHitTesting(false)
        .animation(.spring(response: 0.35, dampingFraction: 0.78), value: editor.activeCaption?.id)
    }

    private func transition(for animation: CaptionAnimation) -> AnyTransition {
        switch animation {
        case .none:
            return .identity
        case .fade:
            return .opacity
        case .pop, .bounce:
            return .scale(scale: 0.7).combined(with: .opacity)
        case .karaoke, .typewriter:
            return .opacity
        }
    }
}

struct AnimatedCaptionText: View {
    let caption: CaptionSegment
    let style: CaptionStyle
    let time: TimeInterval

    var body: some View {
        Group {
            switch style.animation {
            case .karaoke where !caption.words.isEmpty:
                karaokeText
            case .typewriter:
                typewriterText
            default:
                plainText(style.textCase.apply(caption.text))
            }
        }
        .shadow(color: style.shadowColor.color, radius: style.shadowRadius, y: 2)
        .padding(.horizontal, style.backgroundColor.a > 0.05 ? 14 : 0)
        .padding(.vertical, style.backgroundColor.a > 0.05 ? 8 : 0)
        .background(
            style.backgroundColor.color,
            in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
        )
        .scaleEffect(bounceScale)
    }

    private var bounceScale: CGFloat {
        guard style.animation == .bounce || style.animation == .pop else { return 1 }
        let local = time - caption.startTime
        if local < 0.18 {
            return 0.85 + CGFloat(local / 0.18) * 0.2
        }
        return 1
    }

    private var karaokeText: some View {
        HStack(spacing: 5) {
            ForEach(caption.words) { word in
                let active = word.contains(time: time) || time >= word.endTime
                strokedText(
                    style.textCase.apply(word.text),
                    highlighted: active && word.contains(time: time)
                )
                .opacity(active ? 1 : 0.35)
                .scaleEffect(word.contains(time: time) ? 1.08 : 1)
                .animation(.easeOut(duration: 0.12), value: word.contains(time: time))
            }
        }
        .frame(maxWidth: 320)
        .multilineTextAlignment(.center)
    }

    private var typewriterText: some View {
        let progress = min(1, max(0, (time - caption.startTime) / max(caption.duration, 0.01)))
        let count = Int(Double(caption.text.count) * progress)
        let visible = String(caption.text.prefix(count))
        return plainText(style.textCase.apply(visible))
    }

    private func plainText(_ text: String) -> some View {
        strokedText(text, highlighted: false)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)
    }

    private func strokedText(_ text: String, highlighted: Bool) -> some View {
        let fill = highlighted
            ? Color(red: 1.0, green: 0.92, blue: 0.35)
            : style.textColor.color

        return ZStack {
            if style.strokeWidth > 0 {
                Text(text)
                    .font(.custom(style.fontName, size: style.fontSize * 0.55))
                    .foregroundStyle(style.strokeColor.color)
                    .padding(style.strokeWidth)
            }
            Text(text)
                .font(.custom(style.fontName, size: style.fontSize * 0.55))
                .foregroundStyle(fill)
        }
    }
}

/// Draggable live overlays on the preview.
struct LiveOverlayCanvas: View {
    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        GeometryReader { geo in
            ForEach(editor.visibleOverlays) { item in
                overlayView(item)
                    .position(x: geo.size.width * item.x, y: geo.size.height * item.y)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                var updated = item
                                updated.x = min(0.95, max(0.05, value.location.x / geo.size.width))
                                updated.y = min(0.95, max(0.05, value.location.y / geo.size.height))
                                editor.updateOverlay(updated)
                            }
                    )
                    .onTapGesture {
                        editor.selectedOverlayID = item.id
                        editor.editorTab = .overlays
                    }
            }
        }
    }

    @ViewBuilder
    private func overlayView(_ item: OverlayItem) -> some View {
        switch item.kind {
        case .emoji:
            Text(item.text)
                .font(.system(size: item.fontSize * item.scale))
                .rotationEffect(.degrees(item.rotation))
        case .text, .watermark:
            stylishOrPlainText(item)
                .rotationEffect(.degrees(item.rotation))
        case .wordHit:
            WordHitView(item: item, time: editor.currentTime)
        case .gif:
            if let url = editor.libraryFileURL(for: item) {
                AnimatedGIFView(url: url, time: editor.currentTime, startTime: item.startTime)
                    .frame(width: 72 * item.scale, height: 72 * item.scale)
                    .rotationEffect(.degrees(item.rotation))
            }
        case .png:
            if let url = editor.libraryFileURL(for: item) {
                LibraryImage(url: url)
                    .frame(width: 72 * item.scale, height: 72 * item.scale)
                    .rotationEffect(.degrees(item.rotation))
            }
        case .shape:
            shapeView(item)
                .frame(width: 48 * item.scale, height: 48 * item.scale)
                .rotationEffect(.degrees(item.rotation))
        }
    }

    @ViewBuilder
    private func stylishOrPlainText(_ item: OverlayItem) -> some View {
        if let style = editor.stylishTextStyle(for: item) {
            Text(item.text)
                .font(.custom(style.fontName ?? "AvenirNext-Bold", size: (style.fontSize ?? 28) * item.scale * 0.55))
                .foregroundStyle(Color(hex: style.textColor ?? "#FFFFFF") ?? .white)
                .shadow(color: .black.opacity(0.45), radius: style.shadowRadius ?? 4, y: 2)
                .padding(.horizontal, (style.backgroundColor != nil) ? 10 : 0)
                .padding(.vertical, (style.backgroundColor != nil) ? 6 : 0)
                .background(
                    (Color(hex: style.backgroundColor ?? "#00000000") ?? .clear),
                    in: RoundedRectangle(cornerRadius: style.cornerRadius ?? 8)
                )
        } else {
            Text(item.text)
                .font(.custom("AvenirNext-Bold", size: item.fontSize * item.scale * 0.7))
                .foregroundStyle(item.color.color)
                .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
        }
    }

    @ViewBuilder
    private func shapeView(_ item: OverlayItem) -> some View {
        let fill = item.color.color.opacity(item.opacity)
        switch item.shape {
        case .circle:
            Circle().fill(fill)
        case .rectangle:
            RoundedRectangle(cornerRadius: 8).fill(fill)
        case .line:
            Rectangle().fill(fill).frame(height: 4)
        case .arrow:
            Image(systemName: "arrow.right")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(fill)
        }
    }
}

/// Significant word rendering lives in `WordHitView.swift`.

