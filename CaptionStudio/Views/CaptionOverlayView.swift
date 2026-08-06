import SwiftUI

/// Live caption rendering synced to playback time.
///
/// Coordinate space must match the aspect canvas (export `renderSize`), not the
/// source video's intrinsic frame. Parent should `.frame` this to the fitted canvas.
struct CaptionOverlayView: View {
    @EnvironmentObject private var editor: EditorViewModel

    /// Reference width used by export font scaling (`fontSize * width / 390`).
    static let layoutReferenceWidth: CGFloat = 390

    var body: some View {
        GeometryReader { geo in
            let style = editor.project.captionStyle
            let scale = geo.size.width / Self.layoutReferenceWidth
            if let caption = editor.activeCaption {
                AnimatedCaptionText(
                    caption: caption,
                    style: style,
                    time: editor.currentTime,
                    layoutScale: scale,
                    maxTextWidth: geo.size.width * 0.88
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
    /// Canvas width / 390 — same basis as `VideoExportService` caption font scaling.
    var layoutScale: CGFloat = 1
    var maxTextWidth: CGFloat = 320

    private var fontSize: CGFloat { style.fontSize * layoutScale }

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
        .shadow(color: style.shadowColor.color, radius: style.shadowRadius * layoutScale, y: 2 * layoutScale)
        .padding(.horizontal, style.backgroundColor.a > 0.05 ? 14 * layoutScale : 0)
        .padding(.vertical, style.backgroundColor.a > 0.05 ? 8 * layoutScale : 0)
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
        HStack(spacing: 5 * layoutScale) {
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
        .frame(maxWidth: maxTextWidth)
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
            .frame(maxWidth: maxTextWidth)
    }

    private func strokedText(_ text: String, highlighted: Bool) -> some View {
        let fill = highlighted
            ? Color(red: 1.0, green: 0.92, blue: 0.35)
            : style.textColor.color

        return ZStack {
            if style.strokeWidth > 0 {
                Text(text)
                    .font(.custom(style.fontName, size: fontSize))
                    .foregroundStyle(style.strokeColor.color)
                    .padding(style.strokeWidth * layoutScale)
            }
            Text(text)
                .font(.custom(style.fontName, size: fontSize))
                .foregroundStyle(fill)
        }
    }
}

/// Draggable live overlays on the preview.
/// Parent must `.frame` this to the same aspect canvas as the video player / export.
struct LiveOverlayCanvas: View {
    @EnvironmentObject private var editor: EditorViewModel

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / CaptionOverlayView.layoutReferenceWidth
            ForEach(editor.visibleOverlays) { item in
                overlayView(item, layoutScale: scale)
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
    private func overlayView(_ item: OverlayItem, layoutScale: CGFloat) -> some View {
        switch item.kind {
        case .emoji:
            Text(item.text)
                .font(.system(size: item.fontSize * item.scale * layoutScale))
                .rotationEffect(.degrees(item.rotation))
        case .text, .watermark:
            stylishOrPlainText(item, layoutScale: layoutScale)
                .rotationEffect(.degrees(item.rotation))
        case .wordHit:
            WordHitView(item: item, time: editor.currentTime, layoutScale: layoutScale)
        case .gif:
            if let url = editor.libraryFileURL(for: item) {
                AnimatedGIFView(url: url, time: editor.currentTime, startTime: item.startTime)
                    .frame(width: 90 * item.scale * layoutScale, height: 90 * item.scale * layoutScale)
                    .rotationEffect(.degrees(item.rotation))
            }
        case .png:
            if let url = editor.libraryFileURL(for: item) {
                LibraryImage(url: url)
                    .frame(width: 90 * item.scale * layoutScale, height: 90 * item.scale * layoutScale)
                    .rotationEffect(.degrees(item.rotation))
            }
        case .shape:
            shapeView(item)
                .frame(width: 60 * item.scale * layoutScale, height: 60 * item.scale * layoutScale)
                .rotationEffect(.degrees(item.rotation))
        }
    }

    @ViewBuilder
    private func stylishOrPlainText(_ item: OverlayItem, layoutScale: CGFloat) -> some View {
        if let style = editor.stylishTextStyle(for: item) {
            Text(item.text)
                .font(.custom(style.fontName ?? "AvenirNext-Bold", size: (style.fontSize ?? 28) * item.scale * layoutScale))
                .foregroundStyle(Color(hex: style.textColor ?? "#FFFFFF") ?? .white)
                .shadow(color: .black.opacity(0.45), radius: (style.shadowRadius ?? 4) * layoutScale, y: 2 * layoutScale)
                .padding(.horizontal, (style.backgroundColor != nil) ? 10 * layoutScale : 0)
                .padding(.vertical, (style.backgroundColor != nil) ? 6 * layoutScale : 0)
                .background(
                    (Color(hex: style.backgroundColor ?? "#00000000") ?? .clear),
                    in: RoundedRectangle(cornerRadius: style.cornerRadius ?? 8)
                )
        } else {
            Text(item.text)
                .font(.custom("AvenirNext-Bold", size: item.fontSize * item.scale * layoutScale))
                .foregroundStyle(item.color.color)
                .shadow(color: .black.opacity(0.45), radius: 4 * layoutScale, y: 2 * layoutScale)
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

